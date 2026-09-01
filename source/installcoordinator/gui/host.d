module installcoordinator.gui.host;

import dlangui;
import installcoordinator.client;
import installcoordinator.paths;
import installcoordinator.shortcuts;
import installcoordinator.types;
import installcoordinator.versioninfo;
import std.array : array;
import std.conv : to;
import std.file : thisExePath;
import std.json;
import std.string : split;

class CoordinatorFrame : Widget
{
    StringListWidget queueList;
    StringListWidget historyList;
    EditBox detailEdit;
    CheckBox lockElevation;
    CheckBox batchTerms;
    ComboBox scopeCombo;
    string selectedJobId;
    string[] queueLines;
    string[] historyLines;

    this()
    {
        ensureDaemonStarted();
        auto topBar = new HorizontalLayout;
        lockElevation = new CheckBox("lock", "Lock admin for session");
        batchTerms = new CheckBox("batch", "Batch policy acceptance");
        scopeCombo = new ComboBox("scope");
        scopeCombo.items.add("perUser");
        scopeCombo.items.add("perMachine");
        auto installAll = new Button("installAll", "Install all ready");
        auto refresh = new Button("refresh", "Refresh");
        topBar.addChild(lockElevation);
        topBar.addChild(batchTerms);
        topBar.addChild(scopeCombo);
        topBar.addChild(installAll);
        topBar.addChild(refresh);

        queueList = new StringListWidget("queue");
        queueList.preferredWidth = 320;
        historyList = new StringListWidget("history");
        historyList.preferredWidth = 320;
        detailEdit = new EditBox("detail");
        detailEdit.readOnly = true;
        detailEdit.multiline = true;

        auto lists = new HorizontalLayout;
        lists.addChild(queueList, 0);
        lists.addChild(historyList, 0);
        lists.addChild(detailEdit, 1);

        auto actions = new HorizontalLayout;
        auto pinDesktop = new Button("pinDesk", "Pin to Desktop");
        auto pinStart = new Button("pinStart", "Add to Start Menu");
        actions.addChild(pinDesktop);
        actions.addChild(pinStart);

        auto title = new TextWidget("title");
        title.text = aboutLine();
        auto mainLayout = new VerticalLayout;
        mainLayout.addChild(title);
        version (Windows)
        {
            if (!isElevated())
            {
                auto elev = new TextWidget("elev");
                elev.text = "Run elevated to lock admin for session.";
                mainLayout.addChild(elev);
            }
        }
        mainLayout.addChild(topBar);
        mainLayout.addChild(lists, 1);
        mainLayout.addChild(actions);
        addChild(mainLayout);

        installAll.onClick = delegate(Widget) { onInstallAll(); };
        refresh.onClick = delegate(Widget) { refreshLists(); };
        lockElevation.onClick = delegate(Widget) { pushSession(); };
        batchTerms.onClick = delegate(Widget) { pushSession(); };
        queueList.itemSelected = delegate(ListWidget, ListWidgetItem item, int index) {
            pickLine(queueLines, index);
        };
        historyList.itemSelected = delegate(ListWidget, ListWidgetItem item, int index) {
            pickLine(historyLines, index);
        };
        pinDesktop.onClick = delegate(Widget) { createSelectedShortcut(ShortcutKind.desktop); };
        pinStart.onClick = delegate(Widget) { createSelectedShortcut(ShortcutKind.startMenu); };

        pushSession();
        refreshLists();
    }

    void pickLine(string[] lines, int index)
    {
        if (index < 0 || index >= cast(int) lines.length)
            return;
        selectJob(lines[index].split("\t")[0]);
    }

    void refreshLists()
    {
        queueLines = [];
        historyLines = [];
        try
        {
            JSONValue pf = JSONValue.emptyObject;
            pf["filter"] = JSONValue("active");
            auto active = callDaemon("list", pf);
            if ("jobs" in active)
                foreach (j; active["jobs"].array)
                    queueLines ~= formatJobLine(j);
            JSONValue hf = JSONValue.emptyObject;
            hf["filter"] = JSONValue("history");
            auto hist = callDaemon("list", hf);
            if ("jobs" in hist)
                foreach (j; hist["jobs"].array)
                    historyLines ~= formatJobLine(j);
            queueList.items = queueLines.map!(l => l.to!dstring).array;
            historyList.items = historyLines.map!(l => l.to!dstring).array;
        }
        catch (Exception e)
        {
            detailEdit.text = "Daemon: " ~ e.msg;
        }
    }

    string formatJobLine(JSONValue j)
    {
        return j["id"].str ~ "\t" ~ j["state"].str ~ "\t" ~ j["displayName"].str;
    }

    void selectJob(string id)
    {
        selectedJobId = id;
        JSONValue p = JSONValue.emptyObject;
        p["id"] = JSONValue(id);
        auto r = callDaemon("get", p);
        detailEdit.text = r.toPrettyString();
    }

    void pushSession()
    {
        JSONValue p = JSONValue.emptyObject;
        p["elevationMode"] = JSONValue(lockElevation.checked ? "lockedForSession" : "promptEach");
        p["defaultScope"] = JSONValue(scopeCombo.selectedItem == 1 ? "perMachine" : "perUser");
        p["batchTermsReady"] = JSONValue(batchTerms.checked);
        p["grantElevation"] = JSONValue(lockElevation.checked);
        callDaemon("session", p);
    }

    void onInstallAll()
    {
        JSONValue pf = JSONValue.emptyObject;
        pf["filter"] = JSONValue("active");
        auto active = callDaemon("list", pf);
        if (!("jobs" in active))
            return;
        foreach (j; active["jobs"].array)
        {
            auto st = j["state"].str;
            if (st == "collecting" || st == "ready")
            {
                JSONValue c = JSONValue.emptyObject;
                c["id"] = j["id"];
                c["termsAccepted"] = JSONValue(true);
                c["scope"] = JSONValue(scopeCombo.selectedItem == 1 ? "perMachine" : "perUser");
                callDaemon("commit", c);
            }
        }
        refreshLists();
    }

    void createSelectedShortcut(ShortcutKind kind)
    {
        if (!selectedJobId.length)
            return;
        JSONValue p = JSONValue.emptyObject;
        p["id"] = JSONValue(selectedJobId);
        auto r = callDaemon("get", p);
        if (!("job" in r))
            return;
        auto job = r["job"];
        auto manifest = ("sourceManifest" in job) ? job["sourceManifest"].str : "";
        if (!manifest.length)
            return;
        import std.stdio : writeln;
        writeln(createShortcut(job["displayName"].str, thisExePath(), manifest, kind));
    }
}

import std.algorithm : map;
