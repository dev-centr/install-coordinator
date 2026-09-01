module installcoordinator.http;

import installcoordinator.http_config;
import installcoordinator.ipc;
import installcoordinator.msi_lane : msiLaneBusy;
import installcoordinator.scheduler;
import installcoordinator.shortcuts;
import installcoordinator.types;

import core.thread;
import core.time : msecs;
import std.algorithm : canFind, endsWith;
import std.array : appender, split;
import std.conv : to;
import std.file : exists, readText, thisExePath;
import std.json;
import std.path : buildPath, dirName;
import std.socket : Address, InternetAddress, Socket, SocketSet, SocketOption, SocketOptionLevel, TcpSocket;
import std.stdio : stderr;
import std.string : strip, toLower, startsWith;

void serveHttp(InstallScheduler scheduler, HttpConfig config, shared bool* stopFlag)
{
    auto addr = new InternetAddress(config.bindHost, config.port);
    auto listener = new TcpSocket();
    scope (exit)
        listener.close();
    listener.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
    listener.bind(addr);
    listener.listen(16);
    stderr.writeln("Install Coordinator HTTP on http://", config.bindHost, ":", config.port);
    stderr.writeln("  User surface (local): http://127.0.0.1:", config.port, "/ui/user");
    stderr.writeln("  Admin surface:        http://127.0.0.1:", config.port, "/ui/admin");
    if (!config.isLocalOnly())
        stderr.writeln("  Remote admin enabled — Bearer token required for non-local clients");

    while (!*stopFlag)
    {
        auto set = new SocketSet();
        set.add(listener);
        if (Socket.select(set, null, null, 400.msecs) <= 0)
            continue;
        Socket client;
        try
            client = listener.accept();
        catch (Exception)
            continue;
        if (client is null)
            continue;
        try
            handleHttpClient(client, scheduler, config);
        catch (Exception e)
            stderr.writeln("http: ", e.msg);
        finally
            client.close();
    }
}

void startHttpThread(InstallScheduler scheduler, HttpConfig config, shared bool* stopFlag)
{
    auto t = new Thread({
        serveHttp(scheduler, config, stopFlag);
    });
    t.isDaemon = true;
    t.start();
}

private void handleHttpClient(Socket client, InstallScheduler scheduler, HttpConfig config)
{
    char[65536] buf;
    auto n = client.receive(buf[]);
    if (n <= 0)
        return;
    auto req = cast(string) buf[0 .. n];
    auto headerBody = req.split("\r\n\r\n");
    auto headerBlock = headerBody[0];
    auto lines = headerBlock.split("\r\n");
    auto parts = lines[0].split(" ");
    string method = parts.length > 0 ? parts[0] : "GET";
    string path = parts.length > 1 ? parts[1] : "/";
    string body = headerBody.length > 1 ? headerBody[1].strip : "";
    auto clientIp = extractClientIp(client);
    auto localClient = isLoopbackAddress(clientIp);

    if (path.startsWith("/ui"))
    {
        if (path == "/ui" || path == "/ui/")
        {
            if (localClient)
                respondRedirect(client, "/ui/user");
            else
                respondRedirect(client, "/ui/admin");
            return;
        }
        if (path == "/ui/user" || path == "/ui/user/")
        {
            if (!localClient)
            {
                respondText(client, 403, "User surface is local-only. Use install-coordinator gui on this PC.");
                return;
            }
            respondHtml(client, loadUiAsset("user.html"));
            return;
        }
        if (path == "/ui/admin" || path == "/ui/admin/")
        {
            respondHtml(client, loadUiAsset("admin.html"));
            return;
        }
        if (path.startsWith("/ui/"))
        {
            auto asset = path[4 .. $];
            if (asset.canFind(".."))
            {
                respondText(client, 404, "not found");
                return;
            }
            auto content = loadUiAsset(asset);
            if (content.length)
            {
                respondStatic(client, asset, content);
                return;
            }
        }
        respondText(client, 404, "not found");
        return;
    }

    if (!localClient && !checkAuth(config, req))
    {
        respondJson(client, JSONValue(["error": JSONValue("auth required")]), 401);
        return;
    }

    JSONValue out_;
    int code = 200;
    try
    {
        if (path == "/health")
            out_ = JSONValue(["ok": JSONValue(true)]);
        else if (path == "/status")
        {
            auto parsed = parseJSON(handleRequest(scheduler, (`{"cmd":"list","filter":"active"}`)));
            out_ = JSONValue([
                "port": JSONValue(config.port),
                "msiBusy": JSONValue(msiLaneBusy()),
                "uiUser": JSONValue("http://127.0.0.1:" ~ config.port.to!string ~ "/ui/user"),
                "uiAdmin": JSONValue("http://127.0.0.1:" ~ config.port.to!string ~ "/ui/admin"),
                "remoteAdmin": JSONValue(!config.isLocalOnly()),
                "jobs": ("jobs" in parsed) ? parsed["jobs"] : JSONValue.emptyArray,
            ]);
        }
        else if (path == "/jobs" && method == "GET")
            out_ = parseJSON(handleRequest(scheduler, `{"cmd":"list","filter":"all"}`));
        else if (path == "/jobs/submit" && method == "POST")
        {
            auto j = parseJSON(body);
            JSONValue line = JSONValue.emptyObject;
            line["cmd"] = JSONValue("submit");
            if ("job" in j)
                line["job"] = j["job"];
            else if ("displayName" in j)
                line["job"] = j;
            else
                line.object = j.object;
            out_ = parseJSON(handleRequest(scheduler, line.toString()));
        }
        else if (path.startsWith("/jobs/") && method == "POST")
        {
            auto rest = path[6 .. $];
            auto pathParts = rest.split("/");
            auto id = pathParts.length ? pathParts[0] : "";
            auto action = pathParts.length > 1 ? pathParts[1] : "";
            JSONValue line = JSONValue.emptyObject;
            line["id"] = JSONValue(id);
            if (action == "commit")
            {
                line["cmd"] = JSONValue("commit");
                if (body.length)
                {
                    auto j = parseJSON(body);
                    foreach (k, v; j.object)
                        line[k] = v;
                }
                if (!("termsAccepted" in line))
                    line["termsAccepted"] = JSONValue(true);
            }
            else if (action == "cancel")
                line["cmd"] = JSONValue("cancel");
            else if (action == "configure")
            {
                line["cmd"] = JSONValue("commit");
                auto j = parseJSON(body);
                foreach (k, v; j.object)
                    line[k] = v;
            }
            else if (action == "shortcut")
            {
                auto j = body.length ? parseJSON(body) : JSONValue.emptyObject;
                auto kindStr = ("kind" in j) ? j["kind"].str : "desktop";
                auto getLine = JSONValue(["cmd": JSONValue("get"), "id": JSONValue(id)]);
                auto got = parseJSON(handleRequest(scheduler, getLine.toString()));
                if (!("job" in got))
                    throw new Exception("job not found");
                auto job = got["job"];
                auto manifest = ("sourceManifest" in job) ? job["sourceManifest"].str : "";
                if (!manifest.length)
                    throw new Exception("job has no source manifest path");
                auto kind = kindStr == "startMenu" ? ShortcutKind.startMenu : ShortcutKind.desktop;
                auto msg = createShortcut(job["displayName"].str, thisExePath(), manifest, kind);
                out_ = JSONValue(["ok": JSONValue(true), "message": JSONValue(msg)]);
            }
            else
                throw new Exception("unknown action");
            if (action != "shortcut")
                out_ = parseJSON(handleRequest(scheduler, line.toString()));
        }
        else if (path == "/session")
        {
            JSONValue line = JSONValue.emptyObject;
            line["cmd"] = JSONValue("session");
            if (method == "POST" && body.length)
            {
                auto j = parseJSON(body);
                if ("installForAllUsers" in j)
                    line["defaultScope"] = JSONValue(j["installForAllUsers"].type == JSONType.true_ ? "perMachine" : "perUser");
                if ("orgPolicyAccepted" in j)
                    line["batchTermsReady"] = j["orgPolicyAccepted"];
                if ("grantElevation" in j)
                {
                    line["grantElevation"] = j["grantElevation"];
                    line["elevationMode"] = JSONValue("lockedForSession");
                }
                if ("lockElevationUntilClose" in j && j["lockElevationUntilClose"].type == JSONType.true_)
                    line["elevationMode"] = JSONValue("lockedForSession");
            }
            out_ = parseJSON(handleRequest(scheduler, line.toString()));
        }
        else if (path == "/catalog" && method == "GET")
        {
            auto parsed = parseJSON(handleRequest(scheduler, `{"cmd":"list","filter":"history"}`));
            out_ = JSONValue(["catalog": ("jobs" in parsed) ? parsed["jobs"] : JSONValue.emptyArray]);
        }
        else
            throw new Exception("not found");
    }
    catch (Exception e)
    {
        code = 404;
        out_ = JSONValue(["error": JSONValue(e.msg)]);
    }
    respondJson(client, out_, code);
}

private bool checkAuth(HttpConfig config, string req)
{
    if (!config.authToken.length)
        return false;
    foreach (line; req.split("\r\n"))
    {
        if (line.toLower.startsWith("authorization:"))
        {
            auto val = strip(line[14 .. $]);
            if (val.toLower.startsWith("bearer "))
                return strip(val[7 .. $]) == config.authToken;
        }
    }
    return false;
}

private string extractClientIp(Socket client)
{
    try
    {
        Address addr = client.remoteAddress();
        auto s = addr.toString();
        for (size_t i = s.length; i > 0; --i)
        {
            if (s[i - 1] == ':')
            {
                auto host = s[0 .. i - 1];
                if (host.canFind('.'))
                    return host;
                break;
            }
        }
        return s;
    }
    catch (Exception)
    {
        return "127.0.0.1";
    }
}

private void respondJson(Socket client, JSONValue body, int code)
{
    auto payload = body.toString();
    auto resp = appender!string;
    resp.put("HTTP/1.1 ");
    resp.put(code.to!string);
    resp.put(" OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n");
    resp.put("Content-Length: ");
    resp.put(payload.length.to!string);
    resp.put("\r\nConnection: close\r\n\r\n");
    resp.put(payload);
    client.send(resp.data);
}

private void respondHtml(Socket client, string html)
{
    auto resp = appender!string;
    resp.put("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n");
    resp.put("Content-Length: ");
    resp.put(html.length.to!string);
    resp.put("\r\nConnection: close\r\n\r\n");
    resp.put(html);
    client.send(resp.data);
}

private void respondStatic(Socket client, string asset, string content)
{
    string ctype = "application/octet-stream";
    if (asset.endsWith(".css"))
        ctype = "text/css; charset=utf-8";
    else if (asset.endsWith(".js"))
        ctype = "application/javascript; charset=utf-8";
    auto resp = appender!string;
    resp.put("HTTP/1.1 200 OK\r\nContent-Type: ");
    resp.put(ctype);
    resp.put("\r\nContent-Length: ");
    resp.put(content.length.to!string);
    resp.put("\r\nConnection: close\r\n\r\n");
    resp.put(content);
    client.send(resp.data);
}

private void respondRedirect(Socket client, string location)
{
    auto resp = "HTTP/1.1 302 Found\r\nLocation: " ~ location ~ "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
    client.send(resp);
}

private void respondText(Socket client, int code, string message)
{
    auto resp = appender!string;
    resp.put("HTTP/1.1 ");
    resp.put(code.to!string);
    resp.put(" OK\r\nContent-Type: text/plain\r\nContent-Length: ");
    resp.put(message.length.to!string);
    resp.put("\r\nConnection: close\r\n\r\n");
    resp.put(message);
    client.send(resp.data);
}

private string loadUiAsset(string name)
{
    auto exe = dirName(thisExePath());
    string[] candidates = [
        buildPath(exe, "assets", "ui", name),
        buildPath(exe, "..", "assets", "ui", name),
        buildPath(exe, "..", "..", "assets", "ui", name),
    ];
    foreach (c; candidates)
        if (exists(c))
            return readText(c);
    return "";
}
