module installcoordinator.uil_cli;

import installcoordinator.uil.coordinator_emit;
import installcoordinator.uil.journal;
import installcoordinator.uil.parse;
import installcoordinator.uil.plan;
import installcoordinator.uil.validate;
import std.file : write;
import std.path : absolutePath, dirName;
import std.stdio : writeln, stderr;
import std.string : toLower;

int cmdUil(string[] args)
{
    if (!args.length)
        return uilUsage();
    auto sub = args[0].toLower;
    auto rest = args[1 .. $];
    switch (sub)
    {
    case "validate":
        return uilValidate(rest);
    case "plan":
        return uilPlan(rest);
    case "emit-coordinator":
        return uilEmitCoordinator(rest);
    case "help":
        return uilUsage();
    default:
        stderr.writeln("Unknown uil subcommand: ", args[0]);
        return uilUsage();
    }
}

int uilUsage()
{
    writeln(`UIL (Unity Install Layout) commands:
  uil validate <manifest.uil.json>
  uil plan <manifest.uil.json> [--dry-run] [--json-journal]
  uil emit-coordinator <manifest.uil.json> [out.job.json]
`);
    return 0;
}

int uilValidate(string[] args)
{
    if (!args.length)
    {
        stderr.writeln("manifest path required");
        return 1;
    }
    auto m = loadUilFile(absolutePath(args[0]));
    auto vr = validateUil(m);
    if (!vr.ok)
    {
        foreach (i; vr.issues)
            stderr.writeln(i.path, ": ", i.message);
        return 1;
    }
    writeln("OK ", m.package_.id, " ", m.package_.version_, " (", m.entries.length, " payload entries, ",
        m.claims.length, " claims)");
    return 0;
}

int uilPlan(string[] args)
{
    if (!args.length)
    {
        stderr.writeln("manifest path required");
        return 1;
    }
    bool dryRun;
    bool jsonJournal;
    string path = args[0];
    foreach (a; args[1 .. $])
    {
        if (a == "--dry-run")
            dryRun = true;
        else if (a == "--json-journal")
            jsonJournal = true;
    }
    auto m = loadUilFile(absolutePath(path));
    auto pr = planUil(m);
    if (!pr.ok)
    {
        foreach (i; pr.validation.issues)
            stderr.writeln(i.path, ": ", i.message);
        return 1;
    }
    printClassicPlan(pr.classic);
    if (jsonJournal)
        writeln(journalToJson(pr.journal).toPrettyString());
    else if (dryRun)
        applyJournalDryRun(pr.journal);
    else
        applyJournalDryRun(pr.journal); // MVP: apply engine not wired; journal preview only
    return 0;
}

int uilEmitCoordinator(string[] args)
{
    if (!args.length)
    {
        stderr.writeln("manifest path required");
        return 1;
    }
    auto abs = absolutePath(args[0]);
    auto m = loadUilFile(abs);
    auto vr = validateUil(m);
    if (!vr.ok)
    {
        foreach (i; vr.issues)
            stderr.writeln(i.path, ": ", i.message);
        return 1;
    }
    auto jobPath = args.length >= 2 ? args[1] : dirName(abs) ~ "/coordinator.job.json";
    write(jobPath, coordinatorJobJson(m, abs));
    writeln("Wrote ", jobPath);
    return 0;
}
