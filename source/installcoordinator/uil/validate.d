module installcoordinator.uil.validate;

import installcoordinator.uil.types;
import std.algorithm : canFind;
import std.conv : to;

struct ValidationIssue
{
    string path;
    string message;
}

struct ValidationResult
{
    ValidationIssue[] issues;

    bool ok() const @safe
    {
        return issues.length == 0;
    }

    void add(string path, string message)
    {
        ValidationIssue i;
        i.path = path;
        i.message = message;
        issues ~= i;
    }
}

ValidationResult validateUil(const ref UilManifest m)
{
    ValidationResult r;
    if (!m.package_.id.length)
        r.add("package.id", "required");
    if (!m.package_.name.length)
        r.add("package.name", "required");
    if (!m.package_.version_.length)
        r.add("package.version", "required");

    if (m.layout.adapter == LayoutAdapter.connectomeFs)
        r.add("layout.adapter", "connectome-fs is documented but not yet implemented in this runtime; use classic-paths");

    if (m.layout.sideBySide.enabled && !m.layout.sideBySide.slot.length)
        r.add("layout.sideBySide.slot", "required when sideBySide.enabled is true");

    if (!m.entries.length)
        r.add("payload.entries", "at least one entry required");

    foreach (i, e; m.entries)
    {
        auto prefix = "payload.entries[" ~ i.to!string ~ "]";
        if (!e.source.length)
            r.add(prefix ~ ".source", "required");
        if (!e.relativePath.length && e.role != PayloadRole.bin)
            r.add(prefix ~ ".relativePath", "recommended for non-bin roles");
    }

    foreach (i, c; m.claims)
    {
        auto prefix = "claims[" ~ i.to!string ~ "]";
        final switch (c.kind)
        {
        case ClaimKind.pathEntry:
            if (!c.pathEntryDirectories.length)
                r.add(prefix, "path_entry requires directories");
            break;
        case ClaimKind.startMenu:
            if (!c.startMenu.name.length || !c.startMenu.targetRelative.length)
                r.add(prefix, "start_menu shortcut incomplete");
            break;
        case ClaimKind.fileAssoc:
            if (!c.fileExtension.length || !c.progid.length)
                r.add(prefix, "file_assoc requires extension and progid");
            break;
        case ClaimKind.service:
            if (!c.serviceName.length)
                r.add(prefix, "service requires serviceName");
            break;
        case ClaimKind.driver:
            if (!c.driverInfRelative.length)
                r.add(prefix, "driver requires infRelative");
            break;
        case ClaimKind.env:
            if (!c.envVariables.length)
                r.add(prefix, "env requires variables");
            break;
        }
    }

    if (m.journal.format.length && m.journal.format != "uil-journal-v1")
        r.add("journal.format", "must be uil-journal-v1 when set");

    // path_entry directories should reference role roots when using relative tokens
    foreach (c; m.claims)
    {
        if (c.kind != ClaimKind.pathEntry)
            continue;
        foreach (d; c.pathEntryDirectories)
        {
            if (d.canFind(".."))
                r.add("claims.path_entry", "directory paths must not contain ..");
        }
    }

    return r;
}
