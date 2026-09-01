module installcoordinator.http;

import installcoordinator.ipc;
import installcoordinator.msi_lane : msiLaneBusy;
import installcoordinator.scheduler;
import installcoordinator.types;

import core.thread;
import core.time : msecs;
import std.algorithm : canFind;
import std.array : appender, split;
import std.conv : to;
import std.file : exists, readText, thisExePath;
import std.json;
import std.path : buildPath, dirName;
import std.socket : InternetAddress, Socket, SocketSet, SocketOption, SocketOptionLevel, TcpSocket;
import std.stdio : stderr;
import std.string : strip, startsWith;

ushort defaultHttpPort()
{
    import std.process : environment;

    auto p = environment.get("INSTALL_COORD_HTTP_PORT", "");
    if (p.length)
    {
        try
            return cast(ushort) to!int(p);
        catch (Exception)
        {
        }
    }
    return 17_420;
}

void serveHttp(InstallScheduler scheduler, ushort port, shared bool* stopFlag)
{
    auto addr = new InternetAddress("127.0.0.1", port);
    auto listener = new TcpSocket();
    scope (exit)
        listener.close();
    listener.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
    listener.bind(addr);
    listener.listen(16);
    stderr.writeln("Install Coordinator UI: http://127.0.0.1:", port, "/ui");

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
            handleHttpClient(client, scheduler, port);
        catch (Exception e)
            stderr.writeln("http: ", e.msg);
        finally
            client.close();
    }
}

void startHttpThread(InstallScheduler scheduler, ushort port, shared bool* stopFlag)
{
    auto t = new Thread({
        serveHttp(scheduler, port, stopFlag);
    });
    t.isDaemon = true;
    t.start();
}

private void handleHttpClient(Socket client, InstallScheduler scheduler, ushort port)
{
    char[65536] buf;
    auto n = client.receive(buf[]);
    if (n <= 0)
        return;
    auto req = cast(string) buf[0 .. n];
    auto lines = req.split("\r\n");
    auto parts = lines[0].split(" ");
    string method = parts.length > 0 ? parts[0] : "GET";
    string path = parts.length > 1 ? parts[1] : "/";
    string body;
    if (method == "POST")
    {
        auto chunks = req.split("\r\n\r\n");
        if (chunks.length > 1)
            body = chunks[1].strip;
    }

    if (path.startsWith("/ui"))
    {
        respondHtml(client, loadUiHtml());
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
            JSONValue pf = JSONValue.emptyObject;
            pf["filter"] = JSONValue("active");
            auto parsed = parseJSON(handleRequest(scheduler, (`{"cmd":"list","filter":"active"}`)));
            out_ = JSONValue([
                "port": JSONValue(port),
                "msiBusy": JSONValue(msiLaneBusy()),
                "ui": JSONValue("http://127.0.0.1:" ~ port.to!string ~ "/ui"),
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
            else
                throw new Exception("unknown action");
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
                    line["defaultScope"] = JSONValue(j["installForAllUsers"].boolean ? "perMachine" : "perUser");
                if ("orgPolicyAccepted" in j)
                    line["batchTermsReady"] = j["orgPolicyAccepted"];
                if ("grantElevation" in j)
                {
                    line["grantElevation"] = j["grantElevation"];
                    line["elevationMode"] = JSONValue("lockedForSession");
                }
                if ("lockElevationUntilClose" in j && j["lockElevationUntilClose"].boolean)
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

private string loadUiHtml()
{
    auto exe = dirName(thisExePath());
    string[] candidates = [
        buildPath(exe, "assets", "ui", "index.html"),
        buildPath(exe, "..", "assets", "ui", "index.html"),
        buildPath(exe, "..", "..", "assets", "ui", "index.html"),
    ];
    foreach (c; candidates)
        if (exists(c))
            return readText(c);
    return "<html><body><p>Missing assets/ui/index.html</p></body></html>";
}
