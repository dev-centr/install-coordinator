module installcoordinator.types;

import std.datetime.systime;
import std.uuid;

/// How the installer client presents itself to the user before handoff.
enum PresentationMode
{
    /// Submit manifest to daemon and exit — default.
    thinStub,
    /// Per-app collect window; commits to daemon on Install (future-friendly).
    detachedCollect,
    /// Deprecated: client keeps a queue UI. Not recommended.
    embeddedQueue,
}

/// Job lifecycle states (collect → queue → execute → terminal).
enum JobState
{
    collecting,
    ready,
    queued,
    blocked,
    executing,
    done,
    failed,
    cancelled,
}

enum StepKind
{
    msiexec,
    exec,
}

enum InstallScope
{
    perUser,
    perMachine,
}

enum ElevationMode
{
    /// Prompt (or fail) before each elevated step.
    promptEach,
    /// User granted admin once for this daemon session; reuse until GUI closes.
    lockedForSession,
}

struct InstallStep
{
    StepKind kind;
    string path;
    string[] args;
    string blockedReason;
}

struct JobClaims
{
    bool msi;
    string[] paths;
    string[] mutexNames;
}

struct JobRecord
{
    string id;
    string displayName;
    string publisher;
    string productVersion;
    PresentationMode presentation = PresentationMode.thinStub;
    JobState state = JobState.collecting;
    InstallScope installScope = InstallScope.perUser;
    bool termsAccepted;
    JobClaims claims;
    InstallStep[] steps;
    string[string] options;
    string statusMessage;
    string errorMessage;
    SysTime createdAt;
    SysTime updatedAt;
    SysTime finishedAt;
    /// Original manifest or stub path for relaunch shortcuts.
    string sourceManifest;
    string stubExecutable;

    bool isTerminal() const @safe
    {
        return state == JobState.done || state == JobState.failed || state == JobState.cancelled;
    }

    bool needsMsiLane() const @safe
    {
        if (claims.msi)
            return true;
        foreach (s; steps)
            if (s.kind == StepKind.msiexec)
                return true;
        return false;
    }
}

struct SessionState
{
    ElevationMode elevationMode = ElevationMode.promptEach;
    bool elevationGranted;
    InstallScope defaultScope = InstallScope.perUser;
    bool batchTermsReady;
    SysTime lockedAt;
}

string newJobId()
{
    return randomUUID().toString();
}

string stateLabel(JobState s) @safe
{
    final switch (s)
    {
    case JobState.collecting: return "collecting";
    case JobState.ready: return "ready";
    case JobState.queued: return "queued";
    case JobState.blocked: return "blocked";
    case JobState.executing: return "executing";
    case JobState.done: return "done";
    case JobState.failed: return "failed";
    case JobState.cancelled: return "cancelled";
    }
}

string presentationLabel(PresentationMode m) @safe
{
    final switch (m)
    {
    case PresentationMode.thinStub: return "thinStub";
    case PresentationMode.detachedCollect: return "detachedCollect";
    case PresentationMode.embeddedQueue: return "embeddedQueue";
    }
}

PresentationMode parsePresentationMode(string s)
{
    switch (s)
    {
    case "thinStub", "thin-stub", "stub": return PresentationMode.thinStub;
    case "detachedCollect", "detached-collect", "detached": return PresentationMode.detachedCollect;
    case "embeddedQueue", "embedded-queue", "embedded": return PresentationMode.embeddedQueue;
    default: return PresentationMode.thinStub;
    }
}

JobState parseJobState(string s)
{
    switch (s)
    {
    case "collecting": return JobState.collecting;
    case "ready": return JobState.ready;
    case "queued": return JobState.queued;
    case "blocked": return JobState.blocked;
    case "executing": return JobState.executing;
    case "done": return JobState.done;
    case "failed": return JobState.failed;
    case "cancelled": return JobState.cancelled;
    default: throw new Exception("unknown job state: " ~ s);
    }
}

InstallScope parseInstallScope(string s)
{
    switch (s)
    {
    case "perMachine", "machine", "allUsers", "all-users": return InstallScope.perMachine;
    default: return InstallScope.perUser;
    }
}
