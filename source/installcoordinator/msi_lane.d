module installcoordinator.msi_lane;

import core.sync.mutex;
import std.process : execute, spawnProcess, wait;
import std.algorithm;
import std.string : toLower, replace;
import std.utf : toUTF16z;

version (Windows)
{
    import core.sys.windows.windows;
}

private __gshared Mutex gMsiLaneMutex;
private shared bool gMsiLaneInitialized;

void initMsiLane()
{
    if (!gMsiLaneInitialized)
    {
        gMsiLaneMutex = new Mutex();
        gMsiLaneInitialized = true;
    }
}

/// Wait until the global Windows Installer execute mutex is available.
bool waitForMsiExecute(uint timeoutMs = 600_000)
{
    version (Windows)
    {
        enum mutexName = "Global\\_MSIExecute";
        uint waited;
        while (waited < timeoutMs)
        {
            auto h = OpenMutexW(0x00100000, 0, mutexName.toUTF16z());
            if (h == null)
            {
                if (GetLastError() == 2)
                    return true;
            }
            else
            {
                CloseHandle(h);
            }
            Sleep(250);
            waited += 250;
        }
        return false;
    }
    else
        return true;
}

bool msiLaneBusy()
{
    version (Windows)
    {
        import core.sys.windows.windows;
        import std.utf : toUTF16z;

        enum mutexName = "Global\\_MSIExecute";
        auto h = OpenMutexW(0x00100000, 0, mutexName.toUTF16z());
        if (h is null)
            return GetLastError() != 2;
        CloseHandle(h);
        return true;
    }
    return false;
}

/// Serialize MSI-class work inside this process.
int runMsiStep(string msiPath, string[] args, bool requireElevation)
{
    initMsiLane();
    synchronized (gMsiLaneMutex)
    {
        if (!waitForMsiExecute())
            return -1618;
        string[] cmd = ["msiexec", "/i", msiPath];
        cmd ~= args;
        version (Windows)
        {
            if (requireElevation)
            {
                import installcoordinator.paths : isElevated;
                if (!isElevated())
                {
                    auto ps = "Start-Process msiexec -ArgumentList '/i \""
                        ~ msiPath ~ "\" " ~ joinArgs(args) ~ "' -Wait -Verb RunAs";
                    auto result = execute(["powershell", "-NoProfile", "-Command", ps]);
                    return result.status;
                }
            }
        }
        auto pid = spawnProcess(cmd);
        return wait(pid);
    }
}

private string joinArgs(string[] args)
{
    string s;
    foreach (a; args)
        s ~= (s.length ? "," : "") ~ "'" ~ replace(a, "'", "''") ~ "'";
    return s;
}

int runExecStep(string command, string[] args)
{
    string[] cmd = [command];
    cmd ~= args;
    auto pid = spawnProcess(cmd);
    return wait(pid);
}
