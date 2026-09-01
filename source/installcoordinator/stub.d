module installcoordinator.stub;

import installcoordinator.client;
import installcoordinator.http;
import installcoordinator.manifest;
import installcoordinator.types;
import installcoordinator.versioninfo;
import std.file : readText, thisExePath;
import std.json;
import std.stdio : writeln, stderr;
import std.string : toLower;

/// Thin stub entry: submit manifest to daemon and exit (default presentation).
int runStub(string[] args)
{
    string manifestPath;
    PresentationMode mode = PresentationMode.thinStub;
    bool autoStartDaemon = true;
    foreach (a; args)
    {
        if (a.startsWith("--presentation="))
            mode = parsePresentationMode(a[15 .. $]);
        else if (a == "--no-daemon-start")
            autoStartDaemon = false;
        else if (!a.startsWith("-"))
            manifestPath = a;
    }
    if (!manifestPath.length)
    {
        stderr.writeln("manifest path required");
        return 1;
    }
    if (mode == PresentationMode.embeddedQueue)
        stderr.writeln("warning: embeddedQueue is discouraged — use thinStub or detachedCollect");

    if (autoStartDaemon)
        ensureDaemonStarted();

    auto job = loadManifestFile(manifestPath);
    job.presentation = mode;
    job.stubExecutable = thisExePath();

    JSONValue payload = JSONValue.emptyObject;
    payload["manifestPath"] = JSONValue(manifestPath);
    payload["stubExecutable"] = JSONValue(job.stubExecutable);
    auto resp = callDaemon("submit", payload);
    if (!("ok" in resp) || resp["ok"].type != JSONType.true_)
    {
        stderr.writeln("submit failed: ", resp.toString());
        return 1;
    }
    auto id = resp["job"]["id"].str;
    writeln(aboutLine());
    writeln("Submitted ", job.displayName, " (", id, ")");
    writeln("Open Install Coordinator to configure, queue, and track installs:");
    import installcoordinator.http_config : defaultPortFromEnv;
    writeln("  http://127.0.0.1:", defaultPortFromEnv(), "/ui/user");
    writeln("  install-coordinator gui");
    if ("job" in resp && resp["job"]["state"].str == "collecting")
    {
        writeln("Job is collecting options — commit terms/scope in the GUI or:");
        writeln("  install-coordinator commit ", id, " --terms --scope=perUser");
    }
    return 0;
}

import std.algorithm : startsWith;
