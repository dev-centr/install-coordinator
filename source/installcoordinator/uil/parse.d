module installcoordinator.uil.parse;

import installcoordinator.types : InstallScope, parseInstallScope;
import installcoordinator.uil.types;
import std.file : readText;
import std.json;

UilManifest parseUilManifest(string text, string sourcePath = "")
{
    auto root = parseJSON(text);
    UilManifest m;
    m.sourcePath = sourcePath;

    if ("uilVersion" !in root)
        throw new Exception("missing uilVersion");
    if (root["uilVersion"].str != "1.0")
        throw new Exception("unsupported uilVersion: " ~ root["uilVersion"].str);
    m.contract = UilVersion.v1_0;

    if ("package" !in root)
        throw new Exception("missing package");
    parsePackage(root["package"], m.package_);

    if ("layout" !in root)
        throw new Exception("missing layout");
    parseLayout(root["layout"], m.layout);

    if ("payload" !in root || "entries" !in root["payload"])
        throw new Exception("missing payload.entries");
    foreach (e; root["payload"]["entries"].array)
        m.entries ~= parsePayloadEntry(e);

    if ("claims" in root)
        foreach (c; root["claims"].array)
            m.claims ~= parseClaim(c);

    if ("lifecycle" in root)
        parseLifecycle(root["lifecycle"], m.lifecycle);

    if ("journal" in root)
        parseJournal(root["journal"], m.journal);

    if ("coordinator" in root)
        parseCoordinator(root["coordinator"], m.coordinator);

    return m;
}

UilManifest loadUilFile(string path)
{
    return parseUilManifest(readText(path), path);
}

private void parsePackage(JSONValue v, ref UilPackage p)
{
    if ("id" !in v)
        throw new Exception("package.id required");
    p.id = v["id"].str;
    if ("name" !in v)
        throw new Exception("package.name required");
    p.name = v["name"].str;
    if ("version" !in v)
        throw new Exception("package.version required");
    p.version_ = v["version"].str;
    if ("publisher" in v)
        p.publisher = v["publisher"].str;
    if ("edition" in v)
        p.edition = v["edition"].str;
}

private void parseLayout(JSONValue v, ref UilLayout l)
{
    if ("adapter" !in v)
        throw new Exception("layout.adapter required");
    switch (v["adapter"].str)
    {
    case "classic-paths":
        l.adapter = LayoutAdapter.classicPaths;
        break;
    case "connectome-fs":
        l.adapter = LayoutAdapter.connectomeFs;
        break;
    default:
        throw new Exception("unknown layout.adapter: " ~ v["adapter"].str);
    }
    if ("scope" in v)
        l.installScope = parseInstallScope(v["scope"].str);
    if ("platformFamily" in v)
        l.platformFamily = parsePlatformFamily(v["platformFamily"].str);
    if ("sideBySide" in v)
    {
        auto s = v["sideBySide"];
        if ("enabled" in s)
            l.sideBySide.enabled = s["enabled"].type == JSONType.true_;
        if ("slot" in s)
            l.sideBySide.slot = s["slot"].str;
    }
    if ("installRoot" in v)
        l.installRoot = v["installRoot"].str;
}

private PlatformFamily parsePlatformFamily(string s)
{
    switch (s)
    {
    case "auto": return PlatformFamily.host;
    case "windows": return PlatformFamily.windows;
    case "macos": return PlatformFamily.macos;
    case "linux": return PlatformFamily.linux;
    case "bsd": return PlatformFamily.bsd;
    default: throw new Exception("unknown platformFamily: " ~ s);
    }
}

private PayloadEntry parsePayloadEntry(JSONValue v)
{
    PayloadEntry e;
    if ("source" !in v)
        throw new Exception("payload entry missing source");
    if ("role" !in v)
        throw new Exception("payload entry missing role");
    e.source = v["source"].str;
    e.role = parsePayloadRole(v["role"].str);
    if ("relativePath" in v)
        e.relativePath = v["relativePath"].str;
    return e;
}

private UilClaim parseClaim(JSONValue v)
{
    if ("type" !in v)
        throw new Exception("claim missing type");
    UilClaim c;
    c.kind = parseClaimKind(v["type"].str);
    if ("id" in v)
        c.id = v["id"].str;
    if ("description" in v)
        c.description = v["description"].str;

    final switch (c.kind)
    {
    case ClaimKind.pathEntry:
        if ("directories" !in v)
            throw new Exception("path_entry claim requires directories");
        foreach (d; v["directories"].array)
            c.pathEntryDirectories ~= d.str;
        if ("prepend" in v)
            c.pathEntryPrepend = v["prepend"].type == JSONType.true_;
        break;
    case ClaimKind.startMenu:
        if ("shortcut" !in v)
            throw new Exception("start_menu claim requires shortcut");
        parseShortcut(v["shortcut"], c.startMenu);
        break;
    case ClaimKind.fileAssoc:
        if ("extension" !in v || "progid" !in v)
            throw new Exception("file_assoc requires extension and progid");
        c.fileExtension = v["extension"].str;
        c.progid = v["progid"].str;
        if ("openCommandRole" in v)
            c.openCommandRole = parsePayloadRole(v["openCommandRole"].str);
        if ("openCommandRelative" in v)
            c.openCommandRelative = v["openCommandRelative"].str;
        break;
    case ClaimKind.service:
        if ("serviceName" !in v)
            throw new Exception("service claim requires serviceName");
        c.serviceName = v["serviceName"].str;
        if ("displayName" in v)
            c.serviceDisplayName = v["displayName"].str;
        if ("executableRole" in v)
            c.serviceExecutableRole = parsePayloadRole(v["executableRole"].str);
        if ("executableRelative" in v)
            c.serviceExecutableRelative = v["executableRelative"].str;
        break;
    case ClaimKind.driver:
        if ("infRole" !in v || "infRelative" !in v)
            throw new Exception("driver claim requires infRole and infRelative");
        c.driverInfRole = parsePayloadRole(v["infRole"].str);
        c.driverInfRelative = v["infRelative"].str;
        break;
    case ClaimKind.env:
        if ("variables" !in v)
            throw new Exception("env claim requires variables");
        if ("scope" in v)
            c.envScope = v["scope"].str;
        foreach (string k, ref val; v["variables"].object)
            c.envVariables[k] = val.str;
        break;
    }
    return c;
}

private void parseShortcut(JSONValue v, ref StartMenuShortcut s)
{
    if ("name" !in v || "targetRole" !in v || "targetRelative" !in v)
        throw new Exception("shortcut requires name, targetRole, targetRelative");
    s.name = v["name"].str;
    s.targetRole = parsePayloadRole(v["targetRole"].str);
    s.targetRelative = v["targetRelative"].str;
    if ("arguments" in v)
        s.arguments = v["arguments"].str;
    if ("iconRole" in v)
        s.iconRole = parsePayloadRole(v["iconRole"].str);
    if ("iconRelative" in v)
        s.iconRelative = v["iconRelative"].str;
}

private void parseLifecycle(JSONValue v, ref UilLifecycle l)
{
    if ("repair" in v)
    {
        auto r = v["repair"];
        if ("strategy" in r)
            l.repair.strategy = parseRepairStrategy(r["strategy"].str);
        if ("notes" in r)
            l.repair.notes = r["notes"].str;
    }
    if ("uninstall" in v)
    {
        auto u = v["uninstall"];
        if ("strategy" in u)
            l.uninstall.strategy = parseUninstallStrategy(u["strategy"].str);
        if ("removeState" in u)
            l.uninstall.removeState = u["removeState"].type == JSONType.true_;
        if ("removeCache" in u)
            l.uninstall.removeCache = u["removeCache"].type == JSONType.true_;
    }
}

private RepairStrategy parseRepairStrategy(string s)
{
    switch (s)
    {
    case "reconcile-payload": return RepairStrategy.reconcilePayload;
    case "msi-repair": return RepairStrategy.msiRepair;
    case "custom": return RepairStrategy.custom;
    default: throw new Exception("unknown repair strategy: " ~ s);
    }
}

private UninstallStrategy parseUninstallStrategy(string s)
{
    switch (s)
    {
    case "remove-payload-and-claims": return UninstallStrategy.removePayloadAndClaims;
    case "msi-uninstall": return UninstallStrategy.msiUninstall;
    case "custom": return UninstallStrategy.custom;
    default: throw new Exception("unknown uninstall strategy: " ~ s);
    }
}

private void parseJournal(JSONValue v, ref JournalSpec j)
{
    if ("format" in v)
        j.format = v["format"].str;
    if ("persistPath" in v)
        j.persistPath = v["persistPath"].str;
}

private void parseCoordinator(JSONValue v, ref CoordinatorBridge c)
{
    if ("presentation" in v)
        c.presentation = v["presentation"].str;
    if ("termsAccepted" in v)
        c.termsAccepted = v["termsAccepted"].type == JSONType.true_;
    if ("options" in v)
        foreach (string k, ref val; v["options"].object)
            c.options[k] = val.str;
}
