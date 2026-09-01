module installcoordinator.daemon;

import installcoordinator.client;
import installcoordinator.http;
import installcoordinator.http_config;
import installcoordinator.ipc;
import installcoordinator.paths;
import installcoordinator.scheduler;
import std.conv : to;
import std.file : exists, mkdirRecurse, write, remove;
import std.path : dirName;
import std.stdio : stderr, writeln;

version (Windows)
{
    import core.sys.windows.windows;
    import std.utf : toUTF16z;
}

final class CoordinatorDaemon
{
    InstallScheduler scheduler;
    shared bool stopHttp;

    this(HttpConfig httpConfig)
    {
        scheduler = new InstallScheduler();
        scheduler.start();
        stopHttp = false;
        startHttpThread(scheduler, httpConfig, &stopHttp);
    }

    void shutdown()
    {
        stopHttp = true;
        scheduler.stop();
        scheduler.sessionStore.clear();
    }

    int runForever()
    {
        ensureDataDir();
        writePid();
        scope (exit) cleanupPid();
        version (Windows)
            return runPipeServerWindows();
        else
            return runUnixSocketServer();
    }

    private void ensureDataDir()
    {
        auto d = dataRoot();
        if (!exists(d))
            mkdirRecurse(d);
    }

    private void writePid()
    {
        version (Windows)
        {
            import core.sys.windows.windows;
            write(daemonPidFile(), to!string(GetCurrentProcessId()));
        }
        else
        {
            import std.process : getpid;
            write(daemonPidFile(), to!string(getpid()));
        }
    }

    private void cleanupPid()
    {
        if (exists(daemonPidFile()))
            remove(daemonPidFile());
    }
}

private __gshared CoordinatorDaemon gDaemon;

version (Windows)
private int runPipeServerWindows()
{
    import std.utf : toUTF16z;
    enum bufSize = 65536;
    enum maxInstances = 8;
    while (true)
    {
        auto h = CreateNamedPipeW(
            pipeName().toUTF16z(),
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
            maxInstances,
            bufSize,
            bufSize,
            0,
            null);
        if (h == INVALID_HANDLE_VALUE)
        {
            stderr.writeln("CreateNamedPipe failed");
            return 1;
        }
        if (ConnectNamedPipe(h, null) == 0 && GetLastError() != ERROR_PIPE_CONNECTED)
        {
            CloseHandle(h);
            continue;
        }
        ubyte[bufSize] buf;
        DWORD read;
        ReadFile(h, buf.ptr, bufSize, &read, null);
        auto req = cast(string) buf[0 .. read];
        auto resp = handleRequest(gDaemon.scheduler, req) ~ "\n";
        DWORD written;
        WriteFile(h, cast(const(void)*) resp.ptr, cast(DWORD) resp.length, &written, null);
        FlushFileBuffers(h);
        DisconnectNamedPipe(h);
        CloseHandle(h);
    }
}

version (Posix)
private int runUnixSocketServer()
{
    import std.socket;
    import std.file : remove;
    auto sockPath = pipeName();
    if (exists(sockPath))
        remove(sockPath);
    auto addr = new UnixAddress(sockPath);
    auto listener = socket(PF_LOCAL, SocketType.STREAM, 0);
    scope (exit) listener.close();
    listener.bind(addr);
    listener.listen(8);
    while (true)
    {
        auto client = listener.accept();
        scope (exit) client.close();
        char[65536] buf;
        auto n = client.receive(buf);
        auto req = cast(string) buf[0 .. n];
        auto resp = handleRequest(gDaemon.scheduler, req) ~ "\n";
        client.send(resp);
    }
}

int runDaemonMain(HttpConfig config)
{
    config.validate();
    gDaemon = new CoordinatorDaemon(config);
    return gDaemon.runForever();
}

void stopDaemonMain()
{
    if (gDaemon !is null)
        gDaemon.shutdown();
}
