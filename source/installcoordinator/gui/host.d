module installcoordinator.gui.host;

import dlangui;
import installcoordinator.client;
import installcoordinator.paths;
import installcoordinator.shortcuts;
import installcoordinator.types;
import installcoordinator.versioninfo;
import std.conv : to;
import std.file : thisExePath;
import std.json;
import std.string : split;

class CoordinatorFrame : Widget
{
    ListView queueList;
    ListView historyList;
    TextEdit detailEdit;
    CheckBox lockElevation;
    CheckBox batchTerms;
    ComboBox scopeCombo;
    string selectedJobId;

    this()
    {
        ensureDaemonStarted();
        auto topBar = new HorizontalLayout;
        lockElevation = new CheckBox("Lock admin for session");
        batchTerms = new CheckBox("Batch policy acceptance");
        scopeCombo = new ComboBox;
        scopeCombo.items.add("perUser");
        scopeCombo.items.add("perMachine");
        auto installAll = new Button("Install all ready");
        auto refresh = new Button("Refresh");
        topBar.addChild(lockElevation);
        topBar.addChild(batchTerms);
        topBar.addChild(scopeCombo);
        topBar.addChild(installAll);
        topBar.addChild(refresh);

        queueList = new ListView;
        queueList.preferredWidth = 320;
        historyList = new ListView;
        historyList.preferredWidth = 320;
        detailEdit = new TextEdit;
        detailEdit.readOnly = true;
        detailEdit.multiline = true;

        auto lists = new HorizontalLayout;
        lists.addChild(queueList, 0);
        lists.addChild(historyList, 0);
        lists.addChild(detailEdit, 1);

        auto actions = new HorizontalLayout;
        auto pinDesktop = new Button("Pin to Desktop");
        auto pinStart = new Button("Add to Start Menu");
        actions.addChild(pinDesktop);
        actions.addChild(pinStart);

        auto mainLayout = new VerticalLayout;
        auto title = new TextWidget(aboutLine());
        mainLayout.addChild(title);
        version (Windows)
        {
            if (!isElevated())
                mainLayout.addChild(new TextWidget("Run elevated to lock admin for session."));
        }
        mainLayout.addChild(topBar);
        mainLayout.addChild(lists, 1);
        mainLayout.addChild(actions);
        addChild(mainLayout);

        installAll.onClick = delegate(Widget) { onInstallAll(); };
        refresh.onClick = delegate(Widget) { refreshLists(); };
        lockElevation.onClick = delegate(Widget) { pushSession(); };
        batchTerms.onClick = delegate(Widget) { pushSession(); };
        queueList.onItemSelected = delegate(int index) {
            if (index >= 0 && index < cast(int) queueList.items.length)
                selectJob(queueList.items[index].split("\t")[0]);
        };
        historyList.onItemSelected = delegate(int index) {
            if (index >= 0 && index < cast(int) historyList.items.length)
                selectJob(historyList.items[index].split("\t")[0]);
        };
        pinDesktop.onClick = delegate(Widget) { createSelectedShortcut(ShortcutKind.desktop); };
        pinStart.onClick = delegate(Widget) { createSelectedShortcut(ShortcutKind.startMenu); };

        pushSession();
        refreshLists();
    }

    void refreshLists()
    {
        queueList.items.clear;
        historyList.items.clear;
        try
        {
            JSONValue pf = JSONValue.emptyObject;
            pf["filter"] = JSONValue("active");
            auto active = callDaemon("list", pf);
            if ("jobs" in active)
                foreach (j; active["jobs"].array)
                    queueList.items ~= formatJobLine(j);
            JSONValue hf = JSONValue.emptyObject;
            hf["filter"] = JSONValue("history");
            auto hist = callDaemon("list", hf);
            if ("jobs" in hist)
                foreach (j; hist["jobs"].array)
                    historyList.items ~= formatJobLine(j);
            queueList.updateItems();
            historyList.updateItems();
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
