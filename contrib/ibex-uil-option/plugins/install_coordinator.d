module easyinstaller.plugins.install_coordinator;

import easyinstaller.plugin;
import easyinstaller.project : InstallerProject, extra, extraFlag;
import std.file : exists, mkdirRecurse, write;
import std.json;
import std.path : buildPath;
import std.string : format;

/// Emit UIL manifests and Install Coordinator job JSON (queue plane handoff).
final class InstallCoordinatorPlugin : InstallerPlugin
{
    string id() { return "install-coordinator"; }
    string displayName() { return "Install Coordinator (UIL)"; }
    string[] targets() { return ["all"]; }
    bool canBuild() { return true; }
    string detectTool() { return "install-coordinator"; }
    string guiName() { return "Install Coordinator"; }
    string guiInstallUrl() { return "https://github.com/dev-centr/install-coordinator"; }
    string guiDetectHint() { return "install-coordinator on PATH"; }
    string detectGui() { return ""; }
    string installPlaybook() { return ""; }

    ExtraField[] extrasSchema()
    {
        return [
            ExtraField("uilScope", "string", "perUser", "perUser or perMachine layout.scope"),
            ExtraField("sideBySide", "bool", "false", "Enable UIL side-by-side slot directory"),
            ExtraField("emitCoordinatorJob", "bool", "true", "Also write dist/<name>.coordinator.json"),
        ];
    }

    string designerSource(const ref InstallerProject project, string outDir)
    {
        return buildPath(outDir, project.name ~ ".uil.json");
    }

    string emitSources(const ref InstallerProject project, string outDir)
    {
        if (!exists(outDir))
            mkdirRecurse(outDir);
        auto uilPath = buildPath(outDir, project.name ~ ".uil.json");
        write(uilPath, emitUilJson(project));
        return "Wrote " ~ uilPath;
    }

    string build(const ref InstallerProject project, string outDir)
    {
        if (!exists(outDir))
            mkdirRecurse(outDir);
        auto uilPath = buildPath(outDir, project.name ~ ".uil.json");
        write(uilPath, emitUilJson(project));
        string[] notes = ["Wrote " ~ uilPath];
        if (extraFlag(project, "emitCoordinatorJob", true))
        {
            auto jobPath = buildPath(outDir, project.name ~ ".coordinator.json");
            write(jobPath, emitCoordinatorJob(project, uilPath));
            notes ~= "Wrote " ~ jobPath;
        }
        return notes.join("\n");
    }

    private string emitUilJson(const ref InstallerProject project)
    {
        string installScope = extra(project, "uilScope", "perUser");
        bool sxs = extraFlag(project, "sideBySide", false);
        JSONValue root = JSONValue.emptyObject;
        root["uilVersion"] = JSONValue("1.0");
        JSONValue pkg = JSONValue.emptyObject;
        pkg["id"] = JSONValue(project.id);
        pkg["name"] = JSONValue(project.name);
        pkg["publisher"] = JSONValue(project.publisher);
        pkg["version"] = JSONValue(project.version_);
        root["package"] = pkg;
        JSONValue layout = JSONValue.emptyObject;
        layout["adapter"] = JSONValue("classic-paths");
        layout.object["scope"] = JSONValue(installScope);
        if (sxs)
        {
            JSONValue s = JSONValue.emptyObject;
            s["enabled"] = JSONValue(true);
            s["slot"] = JSONValue(project.version_);
            layout["sideBySide"] = s;
        }
        root["layout"] = layout;
        JSONValue entries = JSONValue.emptyArray;
        JSONValue bin = JSONValue.emptyObject;
        bin["source"] = JSONValue(project.exe.length ? project.exe : "dist/");
        bin["role"] = JSONValue("bin");
        if (project.exe.length)
            bin["relativePath"] = JSONValue(project.exe);
        entries.array ~= bin;
        JSONValue payload = JSONValue.emptyObject;
        payload["entries"] = entries;
        root["payload"] = payload;
        if (project.addToPath)
        {
            JSONValue claims = JSONValue.emptyArray;
            JSONValue pe = JSONValue.emptyObject;
            pe["type"] = JSONValue("path_entry");
            JSONValue dirs = JSONValue.emptyArray;
            dirs.array ~= JSONValue("${role:bin}");
            pe["directories"] = dirs;
            claims.array ~= pe;
            root["claims"] = claims;
        }
        JSONValue coord = JSONValue.emptyObject;
        coord["presentation"] = JSONValue("thinStub");
        coord["termsAccepted"] = JSONValue(true);
        root["coordinator"] = coord;
        return root.toPrettyString();
    }

    private string emitCoordinatorJob(const ref InstallerProject project, string uilPath)
    {
        JSONValue root = JSONValue.emptyObject;
        root["displayName"] = JSONValue(project.name);
        root["publisher"] = JSONValue(project.publisher);
        root["version"] = JSONValue(project.version_);
        root["presentation"] = JSONValue("thinStub");
        root["termsAccepted"] = JSONValue(true);
        root.object["scope"] = JSONValue(extra(project, "uilScope", "perUser"));
        JSONValue claims = JSONValue.emptyObject;
        claims["msi"] = JSONValue(false);
        root["claims"] = claims;
        JSONValue steps = JSONValue.emptyArray;
        JSONValue step = JSONValue.emptyObject;
        step["kind"] = JSONValue("exec");
        step["path"] = JSONValue("install-coordinator");
        JSONValue args = JSONValue.emptyArray;
        args.array ~= JSONValue("uil");
        args.array ~= JSONValue("plan");
        args.array ~= JSONValue(uilPath);
        args.array ~= JSONValue("--dry-run");
        step["args"] = args;
        steps.array ~= step;
        root["steps"] = steps;
        JSONValue opts = JSONValue.emptyObject;
        opts["uilManifest"] = JSONValue(uilPath);
        opts["uilPackageId"] = JSONValue(project.id);
        root["options"] = opts;
        return root.toPrettyString();
    }
}

/// Alias plugin id `uil` for documentation and installer.kdl ergonomics.
final class UilPlugin : InstallerPlugin
{
    private InstallCoordinatorPlugin inner;
    this() { inner = new InstallCoordinatorPlugin(); }
    string id() { return "uil"; }
    string displayName() { return "Unity Install Layout (UIL)"; }
    string[] targets() { return inner.targets(); }
    bool canBuild() { return inner.canBuild(); }
    string detectTool() { return inner.detectTool(); }
    string guiName() { return inner.guiName(); }
    string guiInstallUrl() { return inner.guiInstallUrl(); }
    string guiDetectHint() { return inner.guiDetectHint(); }
    string detectGui() { return inner.detectGui(); }
    string installPlaybook() { return inner.installPlaybook(); }
    ExtraField[] extrasSchema() { return inner.extrasSchema(); }
    string designerSource(const ref InstallerProject project, string outDir) { return inner.designerSource(project, outDir); }
    string emitSources(const ref InstallerProject project, string outDir) { return inner.emitSources(project, outDir); }
    string build(const ref InstallerProject project, string outDir) { return inner.build(project, outDir); }
}

shared static this()
{
    registerBuiltin(new InstallCoordinatorPlugin());
    registerBuiltin(new UilPlugin());
}

private import std.array : join;
