module installcoordinator.store;

import installcoordinator.manifest;
import installcoordinator.paths;
import installcoordinator.types;
import std.algorithm : sort;
import std.datetime.systime;
import std.file : exists, mkdirRecurse, readText, write, remove;
import std.json;
import std.stdio : stderr;

struct JobStore
{
    JobRecord[] jobs;

    void ensureDir()
    {
    import std.path : dirName;
    auto p = jobsFile();
        auto d = dirName(p);
        if (!exists(d))
            mkdirRecurse(d);
    }

    void load()
    {
        ensureDir();
        auto path = jobsFile();
        if (!exists(path))
        {
            jobs = [];
            return;
        }
        auto root = parseJSON(readText(path));
        jobs = [];
        if ("jobs" in root)
            foreach (v; root["jobs"].array)
                jobs ~= parseJobJson(v);
    }

    void save()
    {
        ensureDir();
        JSONValue arr = JSONValue.emptyArray;
        foreach (j; jobs)
            arr.array ~= jobToJson(j);
        JSONValue root = JSONValue.emptyObject;
        root["version"] = JSONValue(1);
        root["savedAt"] = JSONValue(Clock.currTime().toISOExtString());
        root["jobs"] = arr;
        write(jobsFile(), root.toPrettyString());
    }

    JobRecord* find(string id)
    {
        foreach (ref j; jobs)
            if (j.id == id)
                return &j;
        return null;
    }

    JobRecord[] activeJobs()
    {
        JobRecord[] out_;
        foreach (j; jobs)
            if (!j.isTerminal())
                out_ ~= j;
        return out_;
    }

    JobRecord[] history()
    {
        JobRecord[] out_;
        foreach (j; jobs)
            if (j.isTerminal())
                out_ ~= j;
        out_.sort!((a, b) => a.finishedAt > b.finishedAt);
        return out_;
    }

    void upsert(JobRecord job)
    {
        auto p = find(job.id);
        if (p !is null)
            *p = job;
        else
            jobs ~= job;
        save();
    }
}

JobRecord parseJobJson(JSONValue v)
{
    JobRecord j;
    j.id = v["id"].str;
    j.displayName = ("displayName" in v) ? v["displayName"].str : "";
    j.publisher = ("publisher" in v) ? v["publisher"].str : "";
    j.productVersion = ("version" in v) ? v["version"].str : "";
    if ("presentation" in v)
        j.presentation = parsePresentationMode(v["presentation"].str);
    if ("state" in v)
        j.state = parseJobState(v["state"].str);
    if ("scope" in v)
        j.installScope = parseInstallScope(v["scope"].str);
    if ("termsAccepted" in v)
        j.termsAccepted = v["termsAccepted"].type == JSONType.true_;
    j.statusMessage = ("statusMessage" in v) ? v["statusMessage"].str : "";
    j.errorMessage = ("errorMessage" in v) ? v["errorMessage"].str : "";
    if ("claims" in v)
        j.claims = parseClaims(v["claims"]);
    if ("steps" in v)
        foreach (s; v["steps"].array)
            j.steps ~= parseStep(s);
    if ("options" in v)
        foreach (string k, ref val; v["options"].object)
            j.options[k] = val.type == JSONType.string ? val.str : val.toString();
    j.sourceManifest = ("sourceManifest" in v) ? v["sourceManifest"].str : "";
    j.stubExecutable = ("stubExecutable" in v) ? v["stubExecutable"].str : "";
    if ("createdAt" in v)
        j.createdAt = SysTime.fromISOExtString(v["createdAt"].str);
    if ("updatedAt" in v)
        j.updatedAt = SysTime.fromISOExtString(v["updatedAt"].str);
    if ("finishedAt" in v)
        j.finishedAt = SysTime.fromISOExtString(v["finishedAt"].str);
    return j;
}

struct SessionStore
{
    SessionState session;

    void load()
    {
        auto path = sessionFile();
        if (!exists(path))
            return;
        auto v = parseJSON(readText(path));
        if ("elevationMode" in v)
            session.elevationMode = v["elevationMode"].str == "lockedForSession"
                ? ElevationMode.lockedForSession : ElevationMode.promptEach;
        if ("elevationGranted" in v)
            session.elevationGranted = v["elevationGranted"].type == JSONType.true_;
        if ("defaultScope" in v)
            session.defaultScope = parseInstallScope(v["defaultScope"].str);
        if ("batchTermsReady" in v)
            session.batchTermsReady = v["batchTermsReady"].type == JSONType.true_;
    }

    void save()
    {
        import std.path : dirName;
        auto path = sessionFile();
        auto d = dirName(path);
        if (!exists(d))
            mkdirRecurse(d);
        JSONValue o = JSONValue.emptyObject;
        o["elevationMode"] = session.elevationMode == ElevationMode.lockedForSession
            ? "lockedForSession" : "promptEach";
        o["elevationGranted"] = JSONValue(session.elevationGranted);
        o["defaultScope"] = session.defaultScope == InstallScope.perMachine ? "perMachine" : "perUser";
        o["batchTermsReady"] = JSONValue(session.batchTermsReady);
        if (session.lockedAt != SysTime.init)
            o["lockedAt"] = JSONValue(session.lockedAt.toISOExtString());
        write(path, o.toPrettyString());
    }

    void clear()
    {
        session = SessionState.init;
        if (exists(sessionFile()))
            remove(sessionFile());
    }
}
