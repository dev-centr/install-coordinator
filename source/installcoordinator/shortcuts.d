module installcoordinator.shortcuts;

import installcoordinator.paths;
import std.conv : to;
import std.string : replace;
import std.file : exists, mkdirRecurse;
import std.path : buildPath;
import std.process : execute, environment;

version (Windows)
{
    /// Create a .lnk on Desktop or Start Menu that re-submits a manifest or relaunches stub.
    string createShortcut(string jobDisplayName, string targetExe, string manifestPath, ShortcutKind kind)
    {
        import std.process : environment;
        string folder;
        final switch (kind)
        {
        case ShortcutKind.desktop:
            folder = buildPath(environment.get("USERPROFILE", ""), "Desktop");
            break;
        case ShortcutKind.startMenu:
            folder = buildPath(
                environment.get("APPDATA", ""),
                "Microsoft", "Windows", "Start Menu", "Programs", "Install Coordinator");
            break;
        }
        if (!folder.length)
            return "Could not resolve shortcut folder";
        import std.file : mkdirRecurse;
        if (!exists(folder))
            mkdirRecurse(folder);
        string safe = replace(jobDisplayName, " ", "-");
        auto lnk = buildPath(folder, safe ~ ".lnk");
        string args = "submit \"" ~ manifestPath ~ "\"";
        auto ps = `
$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut('` ~ replace(lnk, "'", "''") ~ `')
$s.TargetPath = '` ~ replace(targetExe, "'", "''") ~ `'
$s.Arguments = 'submit "` ~ replace(manifestPath, "'", "''") ~ `"'
$s.WorkingDirectory = '` ~ replace(dataRoot(), "'", "''") ~ `'
$s.Description = 'Re-run install via Install Coordinator'
$s.Save()
`;
        auto r = execute(["powershell", "-NoProfile", "-Command", ps]);
        return r.status == 0 ? "Created " ~ lnk : "Shortcut failed (exit " ~ r.status.to!string ~ ")";
    }
}
else
{
    string createShortcut(string, string, string, ShortcutKind)
    {
        return "Shortcuts are supported on Windows in this release";
    }
}

enum ShortcutKind
{
    desktop,
    startMenu,
}
