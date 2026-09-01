module installcoordinator.paths;

import std.file : getcwd, exists;
import std.path : buildPath, dirName;
import std.process : environment;

version (Windows)
{
    import core.sys.windows.windows;
}

string dataRoot() @safe
{
    version (Windows)
    {
        auto local = environment.get("LOCALAPPDATA", "");
        if (local.length)
            return buildPath(local, "DevCentr", "InstallCoordinator");
    }
    else version (linux)
    {
        auto xdg = environment.get("XDG_DATA_HOME", "");
        if (xdg.length)
            return buildPath(xdg, "install-coordinator");
        auto home = environment.get("HOME", "");
        if (home.length)
            return buildPath(home, ".local", "share", "install-coordinator");
    }
    else version (OSX)
    {
        auto home = environment.get("HOME", "");
        if (home.length)
            return buildPath(home, "Library", "Application Support", "InstallCoordinator");
    }
    return buildPath(getcwd(), ".install-coordinator");
}

string jobsFile()
{
    return buildPath(dataRoot(), "jobs.json");
}

string sessionFile()
{
    return buildPath(dataRoot(), "session.json");
}

string daemonPidFile()
{
    return buildPath(dataRoot(), "daemon.pid");
}

string pipeName()
{
    version (Windows)
        return `\\.\pipe\dev-centr-install-coordinator`;
    else
        return buildPath(dataRoot(), "daemon.sock");
}

version (Windows)
bool isProcessRunning(uint pid)
{
    if (pid == 0)
        return false;
    auto h = OpenProcess(0x1000, 0, pid); // PROCESS_QUERY_LIMITED_INFORMATION
    if (h == null)
        return false;
    DWORD code;
    bool ok = GetExitCodeProcess(h, &code) != 0 && code == STILL_ACTIVE;
    CloseHandle(h);
    return ok;
}

version (Windows)
bool isElevated()
{
    HANDLE token;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
        return false;
    scope (exit) CloseHandle(token);
    TOKEN_ELEVATION elev;
    DWORD ret;
    if (!GetTokenInformation(token, TOKEN_INFORMATION_CLASS.TokenElevation, &elev, TOKEN_ELEVATION.sizeof, &ret))
        return false;
    return elev.TokenIsElevated != 0;
}
