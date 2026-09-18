module installcoordinator.uil.coordinator_emit;

import installcoordinator.manifest : manifestTemplate;
import installcoordinator.uil.types;
import std.json;
import std.path : absolutePath;

/// Build a thin-stub Install Coordinator job that references a UIL manifest for planning/apply.
string coordinatorJobJson(const ref UilManifest m, string uilPath)
{
    JSONValue root = JSONValue.emptyObject;
    root["displayName"] = JSONValue(m.package_.name);
    root["publisher"] = JSONValue(m.package_.publisher);
    root["version"] = JSONValue(m.package_.version_);
    root["presentation"] = JSONValue(m.coordinator.presentation.length ? m.coordinator.presentation : "thinStub");
    root["termsAccepted"] = JSONValue(m.coordinator.termsAccepted);
    root["scope"] = JSONValue(m.layout.installScope == InstallScope.perMachine ? "perMachine" : "perUser");

    JSONValue claims = JSONValue.emptyObject;
    claims["msi"] = JSONValue(false);
    JSONValue paths = JSONValue.emptyArray;
    paths.array ~= JSONValue("${installRoot}/**");
    claims["paths"] = paths;
    root["claims"] = claims;

    JSONValue steps = JSONValue.emptyArray;
    JSONValue step = JSONValue.emptyObject;
    step["kind"] = JSONValue("exec");
    step["path"] = JSONValue("install-coordinator");
    JSONValue args = JSONValue.emptyArray;
    args.array ~= JSONValue("uil");
    args.array ~= JSONValue("plan");
    args.array ~= JSONValue(absolutePath(uilPath));
    args.array ~= JSONValue("--dry-run");
    step["args"] = args;
    steps.array ~= step;
    root["steps"] = steps;

    JSONValue opts = JSONValue.emptyObject;
    opts["uilManifest"] = JSONValue(absolutePath(uilPath));
    opts["uilPackageId"] = JSONValue(m.package_.id);
    opts["uilEdition"] = JSONValue(m.package_.edition);
    foreach (k, v; m.coordinator.options)
        opts[k] = JSONValue(v);
    root["options"] = opts;

    return root.toPrettyString();
}

/// MSI thin-stub job (queue plane only).
string msiThinStubJobJson(string displayName, string msiPath, string publisher = "", string version_ = "")
{
    return manifestTemplate(displayName, msiPath);
}

private import installcoordinator.types : InstallScope;
