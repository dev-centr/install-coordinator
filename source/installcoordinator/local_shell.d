module installcoordinator.local_shell;

import installcoordinator.http_config;
import std.conv : to;
import std.process : execute, environment;
import std.stdio : stderr, writeln;

/// Lay-user surface: framed app window on localhost (not a browser tab).
int openUserShell(ushort port)
{
    auto url = "http://127.0.0.1:" ~ port.to!string ~ "/ui/user";
    version (Windows)
        return openUserShellWindows(url);
    else version (OSX)
        return openUserShellPosix(["open", "-a", "Google Chrome", "--args", "--app=" ~ url]);
    else
        return openUserShellPosix(["xdg-open", url]);
}

version (Windows)
private int openUserShellWindows(string url)
{
    // Prefer Edge/Chrome app mode — frameless window, still localhost → native daemon does work.
    string[] browsers = [
        "msedge", "chrome", "brave", "firefox",
    ];
    foreach (b; browsers)
    {
        if (b == "firefox")
        {
            auto r = execute(["cmd", "/c", "start", "", "firefox", "-new-window", url]);
            if (r.status == 0)
            {
                writeln("Opened Install Coordinator (user window).");
                return 0;
            }
            continue;
        }
        auto r = execute(["cmd", "/c", "start", "", b, "--app=" ~ url]);
        if (r.status == 0)
        {
            writeln("Opened Install Coordinator (user window).");
            return 0;
        }
    }
    stderr.writeln("Could not find Edge/Chrome for app window; falling back to default browser.");
    import std.process : browse;
    browse(url);
    return 0;
}

version (Posix)
private int openUserShellPosix(string[] cmd)
{
    import std.process : spawnProcess, wait;
    auto pid = spawnProcess(cmd);
    wait(pid);
    writeln("Opened Install Coordinator (user window).");
    return 0;
}
