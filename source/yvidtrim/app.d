module yvidtrim.app;
import yvidtrim.clibs.sdl3;
import std.stdio;
import yguilib.app;
import yguilib.controller;
import yguilib.events;
import yguilib.uisystem;
import yguilib.widget;
import yguilib.render_types;

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
  auto widget = new Widget(null, RectF(10, 10, 200, 200));
  widget.components.background = new Background(ColorF(0.5, 0.5, 0, 1));
  window.view = widget;
  auto app = new App(window);

  app.run(new MainController);
}
