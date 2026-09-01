module installcoordinator.statemachine;

import installcoordinator.types;
import std.datetime.systime;

/// Validates and applies a state transition. Updates statusMessage on success.
bool transition(ref JobRecord job, JobState to, string reason = "") @safe
{
    if (!canTransition(job.state, to))
        return false;
    job.state = to;
    job.updatedAt = Clock.currTime();
    if (reason.length)
        job.statusMessage = reason;
    if (job.isTerminal())
        job.finishedAt = job.updatedAt;
    return true;
}

bool canTransition(JobState from, JobState to) @safe
{
    if (from == to)
        return true;
    final switch (from)
    {
    case JobState.collecting:
        return to == JobState.ready || to == JobState.cancelled || to == JobState.queued;
    case JobState.ready:
        return to == JobState.queued || to == JobState.cancelled;
    case JobState.queued:
        return to == JobState.blocked || to == JobState.executing || to == JobState.cancelled;
    case JobState.blocked:
        return to == JobState.queued || to == JobState.cancelled || to == JobState.failed;
    case JobState.executing:
        return to == JobState.done || to == JobState.failed || to == JobState.blocked;
    case JobState.done:
    case JobState.failed:
    case JobState.cancelled:
        return false;
    }
}

/// After submit: if manifest is complete, advance toward queue.
void autoAdvanceCollecting(ref JobRecord job) @safe
{
    if (job.state != JobState.collecting)
        return;
    if (!job.termsAccepted)
        return;
    if (job.steps.length == 0)
        return;
    transition(job, JobState.ready, "Options complete");
    transition(job, JobState.queued, "Queued for coordinator");
}

void markBlocked(ref JobRecord job, string reason) @safe
{
    job.statusMessage = reason;
    transition(job, JobState.blocked, reason);
}

void markFailed(ref JobRecord job, string err) @safe
{
    job.errorMessage = err;
    job.statusMessage = err;
    transition(job, JobState.failed, err);
}

void markDone(ref JobRecord job, string msg = "Completed") @safe
{
    transition(job, JobState.done, msg);
}
