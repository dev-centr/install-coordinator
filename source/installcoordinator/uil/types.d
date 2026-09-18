module installcoordinator.uil.types;

import installcoordinator.types : InstallScope;

/// UIL contract revision supported by this library.
enum UilVersion
{
    v1_0,
}

enum LayoutAdapter
{
    classicPaths,
    connectomeFs,
}

enum PlatformFamily
{
    host,
    windows,
    macos,
    linux,
    bsd,
}

enum PayloadRole
{
    bin,
    lib,
    share,
    state,
    cache,
    config,
    logs,
}

enum ClaimKind
{
    pathEntry,
    startMenu,
    fileAssoc,
    service,
    driver,
    env,
}

enum RepairStrategy
{
    reconcilePayload,
    msiRepair,
    custom,
}

enum UninstallStrategy
{
    removePayloadAndClaims,
    msiUninstall,
    custom,
}

struct UilPackage
{
    string id;
    string name;
    string publisher;
    string version_;
    string edition = "default";
}

struct SideBySideLayout
{
    bool enabled;
    string slot;
}

struct UilLayout
{
    LayoutAdapter adapter = LayoutAdapter.classicPaths;
    InstallScope installScope = InstallScope.perUser;
    PlatformFamily platformFamily = PlatformFamily.host;
    SideBySideLayout sideBySide;
    string installRoot;
}

struct PayloadEntry
{
    string source;
    PayloadRole role;
    string relativePath;
}

struct StartMenuShortcut
{
    string name;
    PayloadRole targetRole;
    string targetRelative;
    string arguments;
    PayloadRole iconRole;
    string iconRelative;
}

struct UilClaim
{
    ClaimKind kind;
    string id;
    string description;
    string[] pathEntryDirectories;
    bool pathEntryPrepend = true;
    StartMenuShortcut startMenu;
    string fileExtension;
    string progid;
    PayloadRole openCommandRole;
    string openCommandRelative;
    string serviceName;
    string serviceDisplayName;
    PayloadRole serviceExecutableRole;
    string serviceExecutableRelative;
    PayloadRole driverInfRole;
    string driverInfRelative;
    string envScope = "user";
    string[string] envVariables;
}

struct LifecycleRepair
{
    RepairStrategy strategy = RepairStrategy.reconcilePayload;
    string notes;
}

struct LifecycleUninstall
{
    UninstallStrategy strategy = UninstallStrategy.removePayloadAndClaims;
    bool removeState;
    bool removeCache = true;
}

struct UilLifecycle
{
    LifecycleRepair repair;
    LifecycleUninstall uninstall;
}

struct JournalSpec
{
    string format = "uil-journal-v1";
    string persistPath;
}

struct CoordinatorBridge
{
    string presentation = "thinStub";
    bool termsAccepted;
    string[string] options;
}

struct UilManifest
{
    UilVersion contract = UilVersion.v1_0;
    UilPackage package_;
    UilLayout layout;
    PayloadEntry[] entries;
    UilClaim[] claims;
    UilLifecycle lifecycle;
    JournalSpec journal;
    CoordinatorBridge coordinator;
    string sourcePath;
}

string payloadRoleLabel(PayloadRole r) @safe
{
    final switch (r)
    {
    case PayloadRole.bin: return "bin";
    case PayloadRole.lib: return "lib";
    case PayloadRole.share: return "share";
    case PayloadRole.state: return "state";
    case PayloadRole.cache: return "cache";
    case PayloadRole.config: return "config";
    case PayloadRole.logs: return "logs";
    }
}

PayloadRole parsePayloadRole(string s)
{
    switch (s)
    {
    case "bin": return PayloadRole.bin;
    case "lib": return PayloadRole.lib;
    case "share": return PayloadRole.share;
    case "state": return PayloadRole.state;
    case "cache": return PayloadRole.cache;
    case "config": return PayloadRole.config;
    case "logs": return PayloadRole.logs;
    default: throw new Exception("unknown payload role: " ~ s);
    }
}

ClaimKind parseClaimKind(string s)
{
    switch (s)
    {
    case "path_entry": return ClaimKind.pathEntry;
    case "start_menu": return ClaimKind.startMenu;
    case "file_assoc": return ClaimKind.fileAssoc;
    case "service": return ClaimKind.service;
    case "driver": return ClaimKind.driver;
    case "env": return ClaimKind.env;
    default: throw new Exception("unknown claim type: " ~ s);
    }
}
