module installcoordinator.http_config;

import std.algorithm : startsWith;
import std.process : environment;
import std.string : strip;

/// HTTP listen + auth policy for the admin remote-control surface.
struct HttpConfig
{
    string bindHost = "127.0.0.1";
    ushort port = 17_420;
    string authToken;
    bool remoteAdmin;

    bool isLocalOnly() const @safe
    {
        return bindHost == "127.0.0.1" || bindHost == "localhost" || bindHost == "::1";
    }

    static HttpConfig fromEnvironment()
    {
        HttpConfig c;
        c.port = defaultPortFromEnv();
        auto bind = environment.get("INSTALL_COORD_BIND", "");
        if (bind.length)
            c.bindHost = bind;
        c.authToken = environment.get("INSTALL_COORD_AUTH_TOKEN", "");
        auto remote = environment.get("INSTALL_COORD_REMOTE", "");
        c.remoteAdmin = remote == "1" || remote == "true" || remote == "yes";
        if (c.remoteAdmin && c.bindHost == "127.0.0.1")
            c.bindHost = "0.0.0.0";
        return c;
    }

    void applyFlags(string bindHostOverride, string authTokenOverride, bool remoteFlag)
    {
        if (bindHostOverride.length)
            bindHost = bindHostOverride;
        if (authTokenOverride.length)
            authToken = authTokenOverride;
        if (remoteFlag)
        {
            remoteAdmin = true;
            if (bindHost == "127.0.0.1")
                bindHost = "0.0.0.0";
        }
        validate();
    }

    void validate()
    {
        if (!isLocalOnly() && !authToken.length)
            throw new Exception("remote admin requires --auth-token or INSTALL_COORD_AUTH_TOKEN");
    }
}

ushort defaultPortFromEnv()
{
    import std.conv : to;
    import std.process : environment;
    auto p = environment.get("INSTALL_COORD_HTTP_PORT", "");
    if (p.length)
        return cast(ushort) to!int(p);
    return 17_420;
}

bool isLoopbackAddress(string ip)
{
    ip = strip(ip);
    if (ip == "127.0.0.1" || ip == "::1" || ip == "localhost")
        return true;
    if (ip.startsWith("127."))
        return true;
    return false;
}
