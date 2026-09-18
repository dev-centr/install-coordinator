module installcoordinator.uil.journal;

import installcoordinator.uil.classic_paths;
import installcoordinator.uil.types;
import std.datetime.systime;
import std.json;
import std.stdio : writeln;

enum JournalOpKind
{
    mkdir,
    copyFile,
    claimPathEntry,
    claimStartMenu,
    claimFileAssoc,
    claimService,
    claimDriver,
    claimEnv,
    removeFile,
}

struct JournalOperation
{
    JournalOpKind kind;
    string source;
    string destination;
    string detail;
}

struct InstallJournal
{
    string format = "uil-journal-v1";
    string packageId;
    string packageVersion;
    SysTime startedAt;
    JournalOperation[] forward;
    JournalOperation[] rollback;
}

InstallJournal buildJournal(const ref UilManifest m, const ref ClassicInstallPlan plan)
{
    InstallJournal j;
    j.format = m.journal.format.length ? m.journal.format : "uil-journal-v1";
    j.packageId = m.package_.id;
    j.packageVersion = m.package_.version_;
    j.startedAt = Clock.currTime();

    foreach (f; plan.files)
    {
        JournalOperation mk;
        mk.kind = JournalOpKind.mkdir;
        mk.destination = dirNameOnly(f.destination);
        j.forward ~= mk;

        JournalOperation cp;
        cp.kind = JournalOpKind.copyFile;
        cp.source = f.source;
        cp.destination = f.destination;
        j.forward ~= cp;

        JournalOperation rm;
        rm.kind = JournalOpKind.removeFile;
        rm.destination = f.destination;
        j.rollback ~= rm;
    }

    foreach (note; plan.claimNotes)
    {
        JournalOperation claim;
        claim.detail = note;
        if (note.startsWith("path_entry:"))
            claim.kind = JournalOpKind.claimPathEntry;
        else if (note.startsWith("start_menu:"))
            claim.kind = JournalOpKind.claimStartMenu;
        else if (note.startsWith("file_assoc:"))
            claim.kind = JournalOpKind.claimFileAssoc;
        else if (note.startsWith("service:"))
            claim.kind = JournalOpKind.claimService;
        else if (note.startsWith("driver:"))
            claim.kind = JournalOpKind.claimDriver;
        else if (note.startsWith("env["))
            claim.kind = JournalOpKind.claimEnv;
        else
            continue;
        claim.detail = note;
        j.forward ~= claim;
        j.rollback ~= claim; // MVP: claims reversed in a future apply engine
    }

    return j;
}

void printJournalDryRun(const ref InstallJournal j)
{
    writeln("UIL journal (dry-run) format=", j.format, " package=", j.packageId, "@", j.packageVersion);
    foreach (op; j.forward)
        writeln("  + ", journalOpLabel(op));
}

void printRollbackDryRun(const ref InstallJournal j)
{
    writeln("UIL rollback (dry-run) operations=", j.rollback.length);
    foreach (op; j.rollback)
        writeln("  - ", journalOpLabel(op));
}

ApplyResult applyJournalDryRun(const ref InstallJournal j)
{
    printJournalDryRun(j);
    ApplyResult r;
    r.dryRun = true;
    r.operationsPlanned = j.forward.length;
    return r;
}

struct ApplyResult
{
    bool dryRun;
    size_t operationsPlanned;
    string error;
}

JSONValue journalToJson(const ref InstallJournal j)
{
    JSONValue ops = JSONValue.emptyArray;
    foreach (op; j.forward)
    {
        JSONValue o = JSONValue.emptyObject;
        o["kind"] = JSONValue(journalOpKindLabel(op.kind));
        if (op.source.length)
            o["source"] = JSONValue(op.source);
        if (op.destination.length)
            o["destination"] = JSONValue(op.destination);
        if (op.detail.length)
            o["detail"] = JSONValue(op.detail);
        ops.array ~= o;
    }
    JSONValue root = JSONValue.emptyObject;
    root["format"] = JSONValue(j.format);
    root["packageId"] = JSONValue(j.packageId);
    root["packageVersion"] = JSONValue(j.packageVersion);
    root["startedAt"] = JSONValue(j.startedAt.toISOExtString());
    root["operations"] = ops;
    return root;
}

private string dirNameOnly(string path)
{
    import std.path : dirName;
    return dirName(path);
}

private string journalOpLabel(const ref JournalOperation op)
{
    auto k = journalOpKindLabel(op.kind);
    if (op.kind == JournalOpKind.copyFile)
        return k ~ " " ~ op.source ~ " -> " ~ op.destination;
    if (op.destination.length)
        return k ~ " " ~ op.destination;
    return k ~ " " ~ op.detail;
}

private string journalOpKindLabel(JournalOpKind k) @safe
{
    final switch (k)
    {
    case JournalOpKind.mkdir: return "mkdir";
    case JournalOpKind.copyFile: return "copy";
    case JournalOpKind.claimPathEntry: return "claim.path_entry";
    case JournalOpKind.claimStartMenu: return "claim.start_menu";
    case JournalOpKind.claimFileAssoc: return "claim.file_assoc";
    case JournalOpKind.claimService: return "claim.service";
    case JournalOpKind.claimDriver: return "claim.driver";
    case JournalOpKind.claimEnv: return "claim.env";
    case JournalOpKind.removeFile: return "remove";
    }
}

private import std.algorithm : startsWith;
