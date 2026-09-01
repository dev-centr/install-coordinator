module installcoordinator.scheduler;

import installcoordinator.msi_lane;
import installcoordinator.paths;
import installcoordinator.statemachine;
import installcoordinator.store;
import installcoordinator.types;
import core.sync.mutex;
import core.thread;
import std.datetime.systime : Clock;
import std.algorithm : canFind, startsWith;
import std.conv : to;
import std.string : replace, toLower;

final class InstallScheduler
{
    JobStore store;
    SessionStore sessionStore;
    Mutex lock;
    Thread worker;
    shared bool running;
    void delegate() onChange;

    this()
    {
        store.load();
        sessionStore.load();
        lock = new Mutex();
        initMsiLane();
    }

    void start()
    {
        running = true;
        worker = new Thread(&runLoop);
        worker.isDaemon = true;
        worker.start();
    }

    void stop()
    {
        running = false;
        if (worker !is null)
            worker.join();
    }

    void notifyChange()
    {
        if (onChange !is null)
            onChange();
    }

    JobRecord submit(JobRecord job)
    {
        synchronized (lock)
        {
            if (job.installScope == InstallScope.perUser && sessionStore.session.defaultScope == InstallScope.perMachine)
                job.installScope = InstallScope.perMachine;
            if (sessionStore.session.batchTermsReady)
                job.termsAccepted = true;
            autoAdvanceCollecting(job);
            store.upsert(job);
            notifyChange();
            return job;
        }
    }

    bool commit(string id, bool termsAccepted, InstallScope installScope)
    {
        synchronized (lock)
        {
            auto p = store.find(id);
            if (p is null)
                return false;
            p.termsAccepted = termsAccepted;
            p.installScope = installScope;
            transition(*p, JobState.ready, "User committed options");
            transition(*p, JobState.queued, "Queued");
            store.save();
            notifyChange();
            return true;
        }
    }

    bool cancel(string id)
    {
        synchronized (lock)
        {
            auto p = store.find(id);
            if (p is null)
                return false;
            transition(*p, JobState.cancelled, "Cancelled by user");
            store.save();
            notifyChange();
            return true;
        }
    }

    void setSession(ElevationMode elev, InstallScope installScope, bool batchTerms, bool grantElevation)
    {
        synchronized (lock)
        {
            sessionStore.session.elevationMode = elev;
            sessionStore.session.defaultScope = installScope;
            sessionStore.session.batchTermsReady = batchTerms;
            if (grantElevation)
            {
                sessionStore.session.elevationGranted = true;
                sessionStore.session.lockedAt = Clock.currTime();
            }
            sessionStore.save();
            notifyChange();
        }
    }

    private void runLoop()
    {
        while (running)
        {
            try
                tick();
            catch (Exception e)
            {
                // keep daemon alive
            }
            Thread.sleep(200.msecs);
        }
    }

    private void tick()
    {
        synchronized (lock)
        {
            JobRecord* next;
            foreach (ref j; store.jobs)
            {
                if (j.state == JobState.queued)
                {
                    if (hasClaimConflict(j, store.jobs))
                        continue;
                    next = &j;
                    break;
                }
            }
            if (next is null)
                return;
            executeJob(next);
            store.save();
            notifyChange();
        }
    }

    private bool hasClaimConflict(const JobRecord candidate, const JobRecord[] all)
    {
        foreach (j; all)
        {
            if (j.id == candidate.id || j.state != JobState.executing)
                continue;
            foreach (cp; candidate.claims.paths)
                foreach (ep; j.claims.paths)
                    if (pathsOverlap(cp, ep))
                        return true;
        }
        return false;
    }

    private bool pathsOverlap(string a, string b)
    {
        a = a.toLower.replace("\\", "/");
        b = b.toLower.replace("\\", "/");
        return startsWith(a, b) || startsWith(b, a);
    }

    private void executeJob(JobRecord* job)
    {
        transition(*job, JobState.executing, "Running install steps");
        bool needElev = job.installScope == InstallScope.perMachine;
        bool sessionElev = sessionStore.session.elevationMode == ElevationMode.lockedForSession
            && sessionStore.session.elevationGranted;
        version (Windows)
        {
            if (needElev && sessionElev && !isElevated())
            {
                markBlocked(*job, "Session elevation locked but daemon is not elevated — restart coordinator as admin");
                return;
            }
        }
        foreach (ref step; job.steps)
        {
            int code;
            if (step.kind == StepKind.msiexec)
            {
                if (!waitForMsiExecute(1000))
                {
                    markBlocked(*job, "Waiting for another Windows Installer session (_MSIExecute)");
                    transition(*job, JobState.queued, "Re-queued after MSI wait");
                    return;
                }
                code = runMsiStep(step.path, step.args, needElev && !sessionElev);
            }
            else
                code = runExecStep(step.path, step.args);
            if (code != 0)
            {
                markFailed(*job, "Step failed with exit code " ~ code.to!string);
                return;
            }
        }
        markDone(*job, "Install completed");
    }
}
