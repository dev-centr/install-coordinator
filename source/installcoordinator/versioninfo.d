module installcoordinator.versioninfo;

enum AppVersion = "0.1.0";

string aboutLine() @safe
{
    return "Install Coordinator v" ~ AppVersion ~ " — DevCentr";
}
