module installcoordinator.ipc;

import installcoordinator.manifest;
import installcoordinator.scheduler;
import installcoordinator.store;
import installcoordinator.types;
import std.algorithm;
import std.conv : to;
import std.datetime.systime;
import std.json;
import std.string : strip, replace;

/// Handle one JSON-line request; returns JSON response string (without newline).
string handleRequest(InstallScheduler scheduler, string line)
{
    line = strip(line);
    if (!line.length)
        return `{"ok":false,"error":"empty request"}`;
    JSONValue req;
    try
        req = parseJSON(line);
    catch (Exception e)
        return `{"ok":false,"error":"invalid json"}`;

    auto cmd = ("cmd" in req) ? req["cmd"].str : "";
    try
    {
        switch (cmd)
        {
        case "ping":
            return `{"ok":true,"cmd":"ping","version":1}`;
        case "submit":
            return ipcSubmit(scheduler, req);
        case "list":
            return ipcList(scheduler, req);
        case "get":
            return ipcGet(scheduler, req);
        case "commit":
            return ipcCommit(scheduler, req);
        case "cancel":
            return ipcCancel(scheduler, req);
        case "session":
            return ipcSession(scheduler, req);
        default:
            return `{"ok":false,"error":"unknown cmd"}`;
        }
    }
    catch (Exception e)
        return (`{"ok":false,"error":"` ~ escapeJson(e.msg) ~ `"`);
}

private string escapeJson(string s)
{
    return replace(replace(s, "\\", "\\\\"), "\"", "\\\"");
}

private string ipcSubmit(InstallScheduler scheduler, JSONValue req)
{
    JobRecord job;
    if ("manifest" in req)
        job = parseManifest(req["manifest"].str);
    else if ("manifestPath" in req)
    {
        job = loadManifestFile(req["manifestPath"].str);
        job.sourceManifest = req["manifestPath"].str;
    }
    else if ("job" in req)
        job = parseJobFromSubmit(req["job"]);
    else
        return `{"ok":false,"error":"manifest required"}`;
    if ("stubExecutable" in req)
        job.stubExecutable = req["stubExecutable"].str;
    job = scheduler.submit(job);
    JSONValue o = JSONValue.emptyObject;
    o["ok"] = JSONValue(true);
    o["cmd"] = JSONValue("submit");
    o["job"] = jobToJson(job);
    return o.toString();
}

private JobRecord parseJobFromSubmit(JSONValue v)
{
    JobRecord j;
    if ("displayName" in v)
        j.displayName = v["displayName"].str;
    if ("presentation" in v)
        j.presentation = parsePresentationMode(v["presentation"].str);
    if ("termsAccepted" in v)
        j.termsAccepted = v["termsAccepted"].type == JSONType.true_;
    if ("scope" in v)
        j.installScope = parseInstallScope(v["scope"].str);
    if ("claims" in v)
        j.claims = parseClaims(v["claims"]);
    if ("steps" in v)
        foreach (s; v["steps"].array)
            j.steps ~= parseStep(s);
    j.id = newJobId();
    j.createdAt = Clock.currTime();
    j.updatedAt = j.createdAt;
    j.state = JobState.collecting;
    return j;
}

private string ipcList(InstallScheduler scheduler, JSONValue req)
{
    string filter = ("filter" in req) ? req["filter"].str : "all";
    JobRecord[] jobs;
    switch (filter)
    {
    case "queue", "active":
        jobs = scheduler.store.activeJobs();
        break;
    case "history":
        jobs = scheduler.store.history();
        break;
    default:
        jobs = scheduler.store.jobs;
        break;
    }
    JSONValue arr = JSONValue.emptyArray;
    foreach (j; jobs)
        arr.array ~= jobToJson(j);
    JSONValue o = JSONValue.emptyObject;
    o["ok"] = JSONValue(true);
    o["cmd"] = JSONValue("list");
    o["jobs"] = arr;
    return o.toString();
}

private string ipcGet(InstallScheduler scheduler, JSONValue req)
{
    if (!("id" in req))
        return `{"ok":false,"error":"id required"}`;
    auto p = scheduler.store.find(req["id"].str);
    if (p is null)
        return `{"ok":false,"error":"not found"}`;
    JSONValue o = JSONValue.emptyObject;
    o["ok"] = JSONValue(true);
    o["cmd"] = JSONValue("get");
    o["job"] = jobToJson(*p);
    return o.toString();
}

private string ipcCommit(InstallScheduler scheduler, JSONValue req)
{
    if (!("id" in req))
        return `{"ok":false,"error":"id required"}`;
    bool terms = ("termsAccepted" in req) && req["termsAccepted"].type == JSONType.true_;
    InstallScope installScope = InstallScope.perUser;
    if ("scope" in req)
        installScope = parseInstallScope(req["scope"].str);
    if (!scheduler.commit(req["id"].str, terms, installScope))
        return `{"ok":false,"error":"commit failed"}`;
    JSONValue o = JSONValue.emptyObject;
    o["ok"] = JSONValue(true);
    o["cmd"] = JSONValue("commit");
    return o.toString();
}

private string ipcCancel(InstallScheduler scheduler, JSONValue req)
{
    if (!("id" in req))
        return `{"ok":false,"error":"id required"}`;
    if (!scheduler.cancel(req["id"].str))
        return `{"ok":false,"error":"cancel failed"}`;
    return `{"ok":true,"cmd":"cancel"}`;
}

private string ipcSession(InstallScheduler scheduler, JSONValue req)
{
    ElevationMode elev = ElevationMode.promptEach;
    if ("elevationMode" in req)
        elev = req["elevationMode"].str == "lockedForSession"
            ? ElevationMode.lockedForSession : ElevationMode.promptEach;
    InstallScope installScope = InstallScope.perUser;
    if ("defaultScope" in req)
        installScope = parseInstallScope(req["defaultScope"].str);
    bool batchTerms = ("batchTermsReady" in req) && req["batchTermsReady"].type == JSONType.true_;
    bool grant = ("grantElevation" in req) && req["grantElevation"].type == JSONType.true_;
    scheduler.setSession(elev, installScope, batchTerms, grant);
    JSONValue o = JSONValue.emptyObject;
    o["ok"] = JSONValue(true);
    o["cmd"] = JSONValue("session");
    return o.toString();
}
