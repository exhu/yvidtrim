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
import yguilib.clibs.sdl3;

class MainController : DefaultController {
  this(App app) {
    this.app = app;
  }
  override HandleResult handleEvent(in AppEvent ev) {
    writeln("event = %s", ev);

    app.ui.getMainWindow().view.children[0].visible ^= true;
    if (ev.kind == AppEvent.Kind.keyUp && ev.key == SDL_Keycode.q)
      return HandleResult(HandleResult.Result.quit);

    auto res = super.handleEvent(ev);
    return res.isQuit() ? res : HandleResult(HandleResult.Result.updateView);
  }

  App app;
}

void main()
{
  auto window = new Window(1280, 720, "yvidtrim");
  auto view = new Widget(null, RectF(10, 10, 200, 200));
  view.components.background = new Background(ColorF(0.5, 0.5, 0, 1));
  window.view = view;
  auto smaller = new Widget(view, RectF(15, 15, 130, 90));
  smaller.components.background = new Background(ColorF(0.5, 1, 0.5, 0.3), Background.Style.round);
  auto smaller2 = new Widget(view, RectF(35, 45, 150, 190));
  smaller2.components.background = new Background(ColorF(0.0, 1, 0.5, 0.3));
  smaller2.components.border = new Border(ColorF(0.0, 0, 0.5, 1), Border.style.roundDashed);
  smaller2.components.textLabel = new TextLabel("Hello-0123456789", ColorF(0,0,1,1));
  auto app = new App(window);

  app.run(new MainController(app));
}
