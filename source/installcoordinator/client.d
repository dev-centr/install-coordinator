module installcoordinator.client;

import core.thread;
import installcoordinator.ipc;
import installcoordinator.paths;
import std.file : exists, readText, write;
import std.json;
import std.process : environment;
import std.stdio : stderr;
import std.string : strip;

version (Windows)
{
    import core.sys.windows.windows;
}

/// Send one request to the daemon; returns parsed JSON response.
JSONValue callDaemon(string cmd, JSONValue payload = JSONValue.emptyObject)
{
    JSONValue req = JSONValue.emptyObject;
    req["cmd"] = JSONValue(cmd);
    foreach (string k, ref v; payload.object)
        req[k] = v;
    auto line = req.toString();
    auto respText = transport(line);
    return parseJSON(respText);
}

private string transport(string line)
{
    version (Windows)
        return pipeRoundTripWindows(line);
    else
        return pipeRoundTripUnix(line);
}

version (Windows)
private string pipeRoundTripWindows(string line)
{
    import core.sys.windows.windows;
    import std.utf : toUTF16z;
    enum maxAttempts = 40;
    foreach (i; 0 .. maxAttempts)
    {
        auto h = CreateFileW(
            pipeName().toUTF16z(),
            GENERIC_READ | GENERIC_WRITE,
            0,
            null,
            OPEN_EXISTING,
            0,
            null);
        if (h != INVALID_HANDLE_VALUE)
        {
            scope (exit) CloseHandle(h);
            line ~= "\n";
            auto bytes = cast(const(ubyte)[]) line;
            DWORD written;
            WriteFile(h, bytes.ptr, cast(DWORD) bytes.length, &written, null);
            ubyte[65536] buf;
            DWORD read;
            ReadFile(h, buf.ptr, cast(DWORD) buf.length, &read, null);
            auto got = cast(string) buf[0 .. read].idup;
            return got.strip();
        }
        Sleep(125);
    }
    throw new Exception("Install Coordinator daemon is not running. Start it with: install-coordinator daemon");
}

version (Posix)
private string pipeRoundTripUnix(string line)
{
    import std.socket;
    auto sockPath = pipeName();
    if (!exists(sockPath))
        throw new Exception("daemon socket missing — run install-coordinator daemon");
    auto addr = new UnixAddress(sockPath);
    auto sock = new Socket(AddressFamily.UNIX, SocketType.STREAM);
    scope (exit) sock.close();
    sock.connect(addr);
    line ~= "\n";
    sock.send(line);
    char[65536] buf;
    auto n = sock.receive(buf);
    string s = cast(string) buf[0 .. n].idup;
    return s.strip();
}

bool daemonRunning()
{
    version (Windows)
    {
        import std.conv : to;
        auto pidPath = daemonPidFile();
        if (!exists(pidPath))
            return false;
        auto pid = to!uint(strip(readText(pidPath)));
        return isProcessRunning(pid);
    }
    else version (Posix)
    {
        if (!exists(pipeName()))
            return false;
        try
        {
            auto r = callDaemon("ping");
            return "ok" in r && r["ok"].type == JSONType.true_;
        }
        catch (Exception e)
            return false;
    }
}

int ensureDaemonStarted()
{
    if (daemonRunning())
    {
        try
        {
            auto r = callDaemon("ping");
            if ("ok" in r && r["ok"].type == JSONType.true_)
                return 0;
        }
        catch (Exception e)
        {
        }
    }
    import std.file : thisExePath;
    import std.process : spawnProcess, Config;
    auto exe = thisExePath();
    spawnProcess([exe, "daemon"], cast(const(string[string])) null, Config.detached);
    foreach (i; 0 .. 40)
    {
        Thread.sleep(125.msecs);
        if (daemonRunning())
            return 0;
    }
    return 1;
}
