module yvidtrim.app;
import yvidtrim.clibs.sdl3;
import std.stdio;
import yguilib.app;
import yguilib.controller;
import yguilib.events;
import yguilib.uisystem;

class MainController : DefaultController {
  override HandleResult handleEvent(in AppEvent ev) {
    writeln("event = %s", ev);
    writeln("Edit source/app.d to start your project.", yvidtrim_sdl3_hello());
    return super.handleEvent(ev);
  }
}

void main()
{
  auto window = new Window(1280, 720, "yvidtrim");
  auto app = new App(window);

  app.run(new MainController);
}
