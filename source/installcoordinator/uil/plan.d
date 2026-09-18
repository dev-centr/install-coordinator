module installcoordinator.uil.plan;

import installcoordinator.uil.classic_paths;
import installcoordinator.uil.journal;
import installcoordinator.uil.types;
import installcoordinator.uil.validate;
import std.path : dirName;
import std.stdio : writeln;

struct UilPlanResult
{
    ValidationResult validation;
    ClassicInstallPlan classic;
    InstallJournal journal;
    bool ok;
}

UilPlanResult planUil(const ref UilManifest m)
{
    UilPlanResult r;
    r.validation = validateUil(m);
    if (!r.validation.ok)
    {
        r.ok = false;
        return r;
    }
    if (m.layout.adapter != LayoutAdapter.classicPaths)
    {
        r.validation.add("layout.adapter", "only classic-paths planning is implemented");
        r.ok = false;
        return r;
    }
    auto manifestDir = m.sourcePath.length ? dirName(m.sourcePath) : "";
    r.classic = planClassicPaths(m, manifestDir);
    r.journal = buildJournal(m, r.classic);
    r.ok = true;
    return r;
}

void printClassicPlan(const ref ClassicInstallPlan plan)
{
    writeln("UIL classic-path plan");
    writeln("  platform: ", platformLabel(plan.platform));
    writeln("  scope: ", plan.installScope == InstallScope.perMachine ? "perMachine" : "perUser");
    writeln("  installPrefix: ", plan.installPrefix);
    writeln("  role roots:");
    foreach (r; [PayloadRole.bin, PayloadRole.lib, PayloadRole.share, PayloadRole.state,
            PayloadRole.cache, PayloadRole.config, PayloadRole.logs])
        writeln("    ", payloadRoleLabel(r), ": ", plan.roles.roots[r]);
    writeln("  payload:");
    foreach (f; plan.files)
        writeln("    ", payloadRoleLabel(f.role), ": ", f.source, " -> ", f.destination);
    if (plan.claimNotes.length)
    {
        writeln("  claims (orientation / shell refresh):");
        foreach (n; plan.claimNotes)
            writeln("    ", n);
    }
}

private string platformLabel(PlatformFamily pf) @safe
{
    final switch (pf)
    {
    case PlatformFamily.host: return "auto";
    case PlatformFamily.windows: return "windows";
    case PlatformFamily.macos: return "macos";
    case PlatformFamily.linux: return "linux";
    case PlatformFamily.bsd: return "bsd";
    }
}

private import installcoordinator.types : InstallScope;
