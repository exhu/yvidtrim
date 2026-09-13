module yvidtrim.app;
import yvidtrim.clibs.sdl3;
import std.stdio;
import yguilib.app;
import yguilib.controller;
import yguilib.events;
import yguilib.uisystem;
import yguilib.widget;
import yguilib.render_types;
import yguilib.window;

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
  auto view = new Widget(null, RectF(10, 10, 200, 200));
  view.components.background = new Background(ColorF(0.5, 0.5, 0, 1));
  window.view = view;
  auto smaller = new Widget(view, RectF(15, 15, 130, 90));
  smaller.components.background = new Background(ColorF(0.5, 1, 0.5, 0.3));
  auto smaller2 = new Widget(view, RectF(35, 45, 150, 190));
  smaller2.components.background = new Background(ColorF(0.0, 1, 0.5, 0.3));
  smaller2.components.textLabel = new TextLabel("Hello-0123456789", ColorF(0,0,1,1));
  auto app = new App(window);

  app.run(new MainController);
}
