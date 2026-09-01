module app_gui;

import dlangui;
import installcoordinator.client;
import installcoordinator.gui.host;
import std.conv : to;

mixin APP_ENTRY_POINT;

extern (C) int UIAppMain(string[] args)
{
    ensureDaemonStarted();
    FontManager.fontGamma = 0.8;
    auto window = Platform.instance.createWindow("Install Coordinator"d, null, WindowFlag.Resizable, 960, 640);
    window.mainWidget = new CoordinatorFrame;
    window.show();
    return Platform.instance.enterMessageLoop();
}
