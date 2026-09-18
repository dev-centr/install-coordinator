module installcoordinator.uil;

public import installcoordinator.uil.types;
public import installcoordinator.uil.parse;
public import installcoordinator.uil.validate;
public import installcoordinator.uil.classic_paths;
public import installcoordinator.uil.journal;
public import installcoordinator.uil.plan;
public import installcoordinator.uil.coordinator_emit;

unittest
{
    import std.path : buildPath;
    immutable sample = `{
  "uilVersion": "1.0",
  "package": {
    "id": "dev-centr.demo",
    "name": "Demo",
    "version": "1.0.0"
  },
  "layout": {
    "adapter": "classic-paths",
    "scope": "perUser"
  },
  "payload": {
    "entries": [
      { "source": "bin/demo", "role": "bin", "relativePath": "demo" }
    ]
  },
  "claims": [
    {
      "type": "path_entry",
      "directories": ["${role:bin}"]
    }
  ]
}`;
    auto m = parseUilManifest(sample, buildPath("examples", "uil-classic-demo.uil.json"));
    auto vr = validateUil(m);
    assert(vr.ok);
    auto pr = planUil(m);
    assert(pr.ok);
    assert(pr.classic.files.length == 1);
}
