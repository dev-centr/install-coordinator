module installcoordinator.manifest;

import installcoordinator.types;
import std.datetime.systime;
import std.file : readText;
import std.json;

InstallStep parseStep(JSONValue v)
{
    InstallStep s;
    auto kind = "exec";
    if ("kind" in v)
        kind = v["kind"].str;
    s.kind = kind == "msiexec" ? StepKind.msiexec : StepKind.exec;
    if ("path" in v)
        s.path = v["path"].str;
    if ("command" in v)
        s.path = v["command"].str;
    if ("args" in v)
        foreach (a; v["args"].array)
            s.args ~= a.str;
    return s;
}

JobClaims parseClaims(JSONValue v)
{
    JobClaims c;
    if ("msi" in v)
        c.msi = v["msi"].type == JSONType.true_;
    if ("paths" in v)
        foreach (p; v["paths"].array)
            c.paths ~= p.str;
    if ("mutex" in v)
        foreach (m; v["mutex"].array)
            c.mutexNames ~= m.str;
    return c;
}

JobRecord parseManifest(string text, string sourcePath = "")
{
    auto root = parseJSON(text);
    JobRecord job;
    job.id = ("id" in root) ? root["id"].str : newJobId();
    job.displayName = ("displayName" in root) ? root["displayName"].str : "Installer";
    if ("display" in root)
        job.displayName = root["display"].str;
    if ("publisher" in root)
        job.publisher = root["publisher"].str;
    if ("version" in root)
        job.productVersion = root["version"].str;
    if ("presentation" in root)
        job.presentation = parsePresentationMode(root["presentation"].str);
    if ("scope" in root)
        job.installScope = parseInstallScope(root["scope"].str);
    if ("termsAccepted" in root)
        job.termsAccepted = root["termsAccepted"].type == JSONType.true_;
    if ("claims" in root)
        job.claims = parseClaims(root["claims"]);
    if ("steps" in root)
        foreach (s; root["steps"].array)
            job.steps ~= parseStep(s);
    if ("options" in root)
        foreach (string k, ref v; root["options"].object)
            job.options[k] = v.type == JSONType.string ? v.str : v.toString();
    job.sourceManifest = sourcePath;
    job.createdAt = Clock.currTime();
    job.updatedAt = job.createdAt;
    job.state = JobState.collecting;
    return job;
}

JobRecord loadManifestFile(string path)
{
    return parseManifest(readText(path), path);
}

JSONValue jobToJson(const JobRecord job)
{
    JSONValue steps = JSONValue.emptyArray;
    foreach (s; job.steps)
    {
        JSONValue o = JSONValue.emptyObject;
        o["kind"] = s.kind == StepKind.msiexec ? "msiexec" : "exec";
        o["path"] = JSONValue(s.path);
        JSONValue args = JSONValue.emptyArray;
        foreach (a; s.args)
            args.array ~= JSONValue(a);
        o["args"] = args;
        steps.array ~= o;
    }
    JSONValue opts = JSONValue.emptyObject;
    foreach (k, v; job.options)
        opts[k] = JSONValue(v);
    JSONValue claims = JSONValue.emptyObject;
    claims["msi"] = JSONValue(job.claims.msi);
    JSONValue paths = JSONValue.emptyArray;
    foreach (p; job.claims.paths)
        paths.array ~= JSONValue(p);
    claims["paths"] = paths;
    JSONValue mutex = JSONValue.emptyArray;
    foreach (m; job.claims.mutexNames)
        mutex.array ~= JSONValue(m);
    claims["mutex"] = mutex;

    JSONValue o = JSONValue.emptyObject;
    o["id"] = JSONValue(job.id);
    o["displayName"] = JSONValue(job.displayName);
    o["publisher"] = JSONValue(job.publisher);
    o["version"] = JSONValue(job.productVersion);
    o["presentation"] = JSONValue(presentationLabel(job.presentation));
    o["scope"] = JSONValue(job.installScope == InstallScope.perMachine ? "perMachine" : "perUser");
    o["termsAccepted"] = JSONValue(job.termsAccepted);
    o["state"] = JSONValue(stateLabel(job.state));
    o["statusMessage"] = JSONValue(job.statusMessage);
    o["errorMessage"] = JSONValue(job.errorMessage);
    o["claims"] = claims;
    o["steps"] = steps;
    o["options"] = opts;
    o["sourceManifest"] = JSONValue(job.sourceManifest);
    o["stubExecutable"] = JSONValue(job.stubExecutable);
    o["createdAt"] = JSONValue(job.createdAt.toISOExtString());
    o["updatedAt"] = JSONValue(job.updatedAt.toISOExtString());
    if (job.finishedAt != SysTime.init)
        o["finishedAt"] = JSONValue(job.finishedAt.toISOExtString());
    return o;
}

string manifestTemplate(string displayName, string msiPath)
{
    return `{
  "displayName": "` ~ displayName ~ `",
  "presentation": "thinStub",
  "termsAccepted": true,
  "scope": "perUser",
  "claims": { "msi": true },
  "steps": [
    { "kind": "msiexec", "path": "` ~ msiPath ~ `", "args": ["/passive", "/norestart"] }
  ]
}`;
}
