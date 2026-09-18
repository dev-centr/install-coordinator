import installcoordinator.client;
import installcoordinator.daemon;
import installcoordinator.manifest;
import installcoordinator.paths;
import installcoordinator.scheduler;
import installcoordinator.shortcuts;
import installcoordinator.store;
import installcoordinator.stub;
import installcoordinator.types;
import installcoordinator.versioninfo;
import installcoordinator.uil_cli;
import std.conv : to;
import std.file : exists, readText, write;
import std.json;
import std.stdio : writeln, stderr;
import std.string : toLower, strip;

int main(string[] args)
{
    if (args.length < 2)
        return usage();

    auto cmd = args[1].toLower;
    try
    {
        switch (cmd)
        {
        case "--version":
        case "version":
            writeln(aboutLine());
            return 0;
        case "daemon":
            return cmdDaemon(args[2 .. $]);
        case "gui":
            if (ensureDaemonStarted() != 0)
                return 1;
            import installcoordinator.http_config : defaultPortFromEnv;
            import installcoordinator.local_shell : openUserShell;
            return openUserShell(defaultPortFromEnv());
        case "submit":
        case "stub":
            return runStub(args[2 .. $]);
        case "queue":
        case "list":
            return cmdList(args[2 .. $]);
        case "status":
            return cmdStatus(args[2 .. $]);
        case "commit":
            return cmdCommit(args[2 .. $]);
        case "cancel":
            return cmdCancel(args[2 .. $]);
        case "session":
            return cmdSession(args[2 .. $]);
        case "ping":
            return cmdPing();
        case "shortcut":
            return cmdShortcut(args[2 .. $]);
        case "new-manifest":
            return cmdNewManifest(args[2 .. $]);
        case "uil":
            return cmdUil(args[2 .. $]);
        case "help":
        case "--help":
        case "-h":
            return usage();
        default:
            stderr.writeln("Unknown command: ", args[1]);
            return usage();
        }
    }
    catch (Exception e)
    {
        stderr.writeln("error: ", e.msg);
        return 1;
    }
}

int usage()
{
    writeln(aboutLine());
    writeln(`
Commands:
  daemon [--remote] [--bind=HOST] [--auth-token=TOKEN] [--port=N]
                             Background service + HTTP surfaces
  gui                        Open local user app window (not a browser tab)
  list [active|history|all]  List jobs
  status <job-id>            Job detail
  commit <job-id> [--terms] [--scope=perUser|perMachine]
  cancel <job-id>
  session [--lock-elevation] [--scope=perMachine] [--batch-terms]
  shortcut <job-id> --desktop|--start-menu
  new-manifest <name> <msi-path> [out.json]
  uil validate|plan|emit-coordinator <manifest.uil.json>
  ping                       Daemon health check

Presentation modes (manifest field presentation):
  thinStub (default)         Hand off to daemon; exit stub process
  detachedCollect            Per-app collect UI, then hand off (reserved)
  embeddedQueue              Not recommended — client keeps queue UI

Examples:
  install-coordinator daemon
  install-coordinator submit examples/sample-msi.json
  install-coordinator session --lock-elevation --batch-terms --scope=perMachine
`);
    return 0;
}

int cmdList(string[] args)
{
    ensureDaemonStarted();
    string filter = args.length ? args[0] : "active";
    JSONValue p = JSONValue.emptyObject;
    p["filter"] = JSONValue(filter);
    auto r = callDaemon("list", p);
    if (!("jobs" in r))
    {
        stderr.writeln(r.toString());
        return 1;
    }
    foreach (j; r["jobs"].array)
        writeln(j["id"].str, "\t", j["state"].str, "\t", j["displayName"].str);
    return 0;
}

int cmdStatus(string[] args)
{
    if (!args.length)
    {
        stderr.writeln("job id required");
        return 1;
    }
    ensureDaemonStarted();
    JSONValue p = JSONValue.emptyObject;
    p["id"] = JSONValue(args[0]);
    auto r = callDaemon("get", p);
    writeln(r.toPrettyString());
    return ("ok" in r && r["ok"].type == JSONType.true_) ? 0 : 1;
}

int cmdCommit(string[] args)
{
    if (!args.length)
    {
        stderr.writeln("job id required");
        return 1;
    }
    bool terms;
    string installScope = "perUser";
    foreach (a; args[1 .. $])
    {
        if (a == "--terms")
            terms = true;
        else if (a.startsWith("--scope="))
            installScope = a[8 .. $];
    }
    ensureDaemonStarted();
    JSONValue p = JSONValue.emptyObject;
    p["id"] = JSONValue(args[0]);
    p["termsAccepted"] = JSONValue(terms);
    p["scope"] = JSONValue(installScope);
    auto r = callDaemon("commit", p);
    writeln(r.toString());
    return ("ok" in r && r["ok"].type == JSONType.true_) ? 0 : 1;
}

int cmdCancel(string[] args)
{
    if (!args.length)
        return 1;
    ensureDaemonStarted();
    JSONValue p = JSONValue.emptyObject;
    p["id"] = JSONValue(args[0]);
    auto r = callDaemon("cancel", p);
    return ("ok" in r && r["ok"].type == JSONType.true_) ? 0 : 1;
}

int cmdSession(string[] args)
{
    bool lockElev;
    bool batchTerms;
    string installScope = "perUser";
    foreach (a; args)
    {
        if (a == "--lock-elevation")
            lockElev = true;
        else if (a == "--batch-terms")
            batchTerms = true;
        else if (a.startsWith("--scope="))
            installScope = a[8 .. $];
    }
    ensureDaemonStarted();
    JSONValue p = JSONValue.emptyObject;
    p["elevationMode"] = JSONValue(lockElev ? "lockedForSession" : "promptEach");
    p["defaultScope"] = JSONValue(installScope);
    p["batchTermsReady"] = JSONValue(batchTerms);
    p["grantElevation"] = JSONValue(lockElev);
    auto r = callDaemon("session", p);
    if (lockElev)
        writeln("Session elevation locked until coordinator GUI/daemon closes. Run daemon elevated for silent admin installs.");
    writeln(r.toString());
    return 0;
}

int cmdPing()
{
    ensureDaemonStarted();
    auto r = callDaemon("ping");
    writeln(r.toString());
    return 0;
}

int cmdShortcut(string[] args)
{
    if (!args.length)
        return 1;
    auto id = args[0];
    ShortcutKind kind = ShortcutKind.desktop;
    foreach (a; args[1 .. $])
    {
        if (a == "--desktop")
            kind = ShortcutKind.desktop;
        else if (a == "--start-menu")
            kind = ShortcutKind.startMenu;
    }
    ensureDaemonStarted();
    JSONValue p = JSONValue.emptyObject;
    p["id"] = JSONValue(id);
    auto r = callDaemon("get", p);
    if (!("job" in r))
        return 1;
    auto job = r["job"];
    auto manifest = ("sourceManifest" in job) ? job["sourceManifest"].str : "";
    if (!manifest.length)
    {
        stderr.writeln("job has no source manifest path");
        return 1;
    }
    import std.file : thisExePath;
    writeln(createShortcut(job["displayName"].str, thisExePath(), manifest, kind));
    return 0;
}

int cmdNewManifest(string[] args)
{
    if (args.length < 2)
    {
        stderr.writeln("usage: new-manifest <displayName> <msi-path> [out.json]");
        return 1;
    }
    auto outPath = args.length >= 3 ? args[2] : "install-manifest.json";
    write(outPath, manifestTemplate(args[0], args[1]));
    writeln("Wrote ", outPath);
    return 0;
}

import std.algorithm : startsWith;
import installcoordinator.http_config;

int cmdDaemon(string[] args)
{
    auto config = HttpConfig.fromEnvironment();
    bool remoteFlag;
    string bindOverride;
    string tokenOverride;
    foreach (a; args)
    {
        if (a == "--remote")
            remoteFlag = true;
        else if (a.startsWith("--bind="))
            bindOverride = a[7 .. $];
        else if (a.startsWith("--auth-token="))
            tokenOverride = a[13 .. $];
        else if (a.startsWith("--port="))
            config.port = cast(ushort) to!int(a[7 .. $]);
    }
    config.applyFlags(bindOverride, tokenOverride, remoteFlag);
    return runDaemonMain(config);
}
