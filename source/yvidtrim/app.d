module yvidtrim.app;
import yvidtrim.clibs.sdl3;
import std.stdio;
import yguilib.app;
import yguilib.controller;
import yguilib.events;

class MainController : DefaultController {
  override HandleResult handleEvent(in AppEvent ev) {
    writeln("Edit source/app.d to start your project.", yvidtrim_sdl3_hello());
    return super.handleEvent(ev);
  }
}

void main()
{
  auto app = new App;
  app.run(new MainController);
}
