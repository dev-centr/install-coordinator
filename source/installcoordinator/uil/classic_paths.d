module installcoordinator.uil.classic_paths;

import installcoordinator.types : InstallScope;
import installcoordinator.uil.types;
import std.algorithm.searching : startsWith;
import std.string : indexOf;
import std.path : buildPath, dirName, baseName;
import std.process : environment;

struct RoleRoots
{
    string[PayloadRole.max + 1] roots;
}

struct ResolvedPayload
{
    PayloadRole role;
    string source;
    string destination;
}

struct ClassicInstallPlan
{
    PlatformFamily platform;
    InstallScope installScope;
    string installPrefix;
    RoleRoots roles;
    ResolvedPayload[] files;
    string[] claimNotes;
}

PlatformFamily hostPlatformFamily()
{
    version (Windows)
        return PlatformFamily.windows;
    else version (OSX)
        return PlatformFamily.macos;
    else version (linux)
        return PlatformFamily.linux;
    else version (BSD)
        return PlatformFamily.bsd;
    else
        return PlatformFamily.linux;
}

PlatformFamily effectivePlatform(const ref UilLayout layout)
{
    if (layout.platformFamily != PlatformFamily.host)
        return layout.platformFamily;
    return hostPlatformFamily();
}

string defaultInstallPrefix(const ref UilManifest m, PlatformFamily pf)
{
    if (m.layout.installRoot.length)
        return m.layout.installRoot;

    string slot = m.layout.sideBySide.enabled ? m.layout.sideBySide.slot : m.package_.version_;
    if (!slot.length)
        slot = m.package_.edition;

    auto idTail = sanitizePackageId(m.package_.id);

    final switch (pf)
    {
    case PlatformFamily.windows:
        if (m.layout.installScope == InstallScope.perMachine)
            return buildPath(environment.get("ProgramFiles", "C:/Program Files"), idTail, slot);
        return buildPath(environment.get("LOCALAPPDATA", ""), "Programs", idTail, slot);
    case PlatformFamily.macos:
        if (m.layout.installScope == InstallScope.perMachine)
            return buildPath("/Library/Application Support", idTail, slot);
        return buildPath(environment.get("HOME", ""), "Applications", idTail, slot);
    case PlatformFamily.linux, PlatformFamily.bsd, PlatformFamily.host:
        if (m.layout.installScope == InstallScope.perMachine)
            return buildPath("/opt", idTail, slot);
        return buildPath(environment.get("HOME", ""), ".local", "opt", idTail, slot);
    }
}

RoleRoots roleRootsFor(string prefix, PlatformFamily pf)
{
    RoleRoots r;
    final switch (pf)
    {
    case PlatformFamily.windows:
        r.roots[PayloadRole.bin] = buildPath(prefix, "bin");
        r.roots[PayloadRole.lib] = buildPath(prefix, "lib");
        r.roots[PayloadRole.share] = buildPath(prefix, "share");
        r.roots[PayloadRole.state] = buildPath(prefix, "state");
        r.roots[PayloadRole.cache] = buildPath(prefix, "cache");
        r.roots[PayloadRole.config] = buildPath(prefix, "config");
        r.roots[PayloadRole.logs] = buildPath(prefix, "logs");
        break;
    case PlatformFamily.macos:
        r.roots[PayloadRole.bin] = buildPath(prefix, "bin");
        r.roots[PayloadRole.lib] = buildPath(prefix, "lib");
        r.roots[PayloadRole.share] = buildPath(prefix, "share");
        r.roots[PayloadRole.state] = buildPath(prefix, "Library", "Application Support", "state");
        r.roots[PayloadRole.cache] = buildPath(prefix, "Library", "Caches");
        r.roots[PayloadRole.config] = buildPath(prefix, "Library", "Preferences");
        r.roots[PayloadRole.logs] = buildPath(prefix, "Library", "Logs");
        break;
    case PlatformFamily.linux, PlatformFamily.bsd, PlatformFamily.host:
        r.roots[PayloadRole.bin] = buildPath(prefix, "bin");
        r.roots[PayloadRole.lib] = buildPath(prefix, "lib");
        r.roots[PayloadRole.share] = buildPath(prefix, "share");
        r.roots[PayloadRole.state] = buildPath(prefix, "var", "state");
        r.roots[PayloadRole.cache] = buildPath(prefix, "var", "cache");
        r.roots[PayloadRole.config] = buildPath(prefix, "etc");
        r.roots[PayloadRole.logs] = buildPath(prefix, "var", "log");
        break;
    }
    return r;
}

ClassicInstallPlan planClassicPaths(const ref UilManifest m, string manifestDir = "")
{
    ClassicInstallPlan plan;
    plan.platform = effectivePlatform(m.layout);
    plan.installScope = m.layout.installScope;
    plan.installPrefix = defaultInstallPrefix(m, plan.platform);
    plan.roles = roleRootsFor(plan.installPrefix, plan.platform);

    foreach (e; m.entries)
    {
        ResolvedPayload rp;
        rp.role = e.role;
        rp.source = resolveSourcePath(e.source, manifestDir, m.sourcePath);
        auto rel = e.relativePath.length ? e.relativePath : baseName(e.source);
        rp.destination = buildPath(plan.roles.roots[e.role], rel);
        plan.files ~= rp;
    }

    foreach (c; m.claims)
    {
        final switch (c.kind)
        {
        case ClaimKind.pathEntry:
            foreach (d; c.pathEntryDirectories)
                plan.claimNotes ~= "path_entry: " ~ expandClaimPath(d, plan) ~ (c.pathEntryPrepend ? " (prepend)" : "");
            break;
        case ClaimKind.startMenu:
            auto target = buildPath(plan.roles.roots[c.startMenu.targetRole], c.startMenu.targetRelative);
            plan.claimNotes ~= "start_menu: " ~ c.startMenu.name ~ " -> " ~ target;
            break;
        case ClaimKind.fileAssoc:
            plan.claimNotes ~= "file_assoc: ." ~ c.fileExtension ~ " (" ~ c.progid ~ ")";
            break;
        case ClaimKind.service:
            plan.claimNotes ~= "service: " ~ c.serviceName;
            break;
        case ClaimKind.driver:
            plan.claimNotes ~= "driver: " ~ buildPath(plan.roles.roots[c.driverInfRole], c.driverInfRelative);
            break;
        case ClaimKind.env:
            foreach (k, v; c.envVariables)
                plan.claimNotes ~= "env[" ~ c.envScope ~ "]: " ~ k ~ "=" ~ v;
            break;
        }
    }
    return plan;
}

string sanitizePackageId(string id)
{
    char[] buf = id.dup;
    foreach (ref c; buf)
    {
        if (c == '.' || c == '/' || c == '\\')
            c = '-';
    }
    return cast(string) buf;
}

string resolveSourcePath(string source, string manifestDir, string manifestPath)
{
    import std.path : isAbsolute;
    if (isAbsolute(source))
        return source;
    if (manifestDir.length)
        return buildPath(manifestDir, source);
    if (manifestPath.length)
        return buildPath(dirName(manifestPath), source);
    return source;
}

string expandClaimPath(string token, const ref ClassicInstallPlan plan)
{
    if (token == "${prefix}" || token == "${installRoot}")
        return plan.installPrefix;
    if (token.startsWith("${role:"))
    {
        auto end = indexOf(token, '}');
        if (end > 6)
        {
            auto roleName = token[7 .. end];
            auto role = parsePayloadRole(roleName);
            return plan.roles.roots[role];
        }
    }
    if (token.startsWith("${bin}"))
        return plan.roles.roots[PayloadRole.bin];
    return token;
}
