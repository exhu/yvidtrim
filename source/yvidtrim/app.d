module yvidtrim.app;
import std.stdio;
import yguilib.app;
import yguilib.controller;
import yguilib.events;
import yguilib.uisystem;
import yguilib.widget;
import yguilib.render_types;
import yguilib.window;
import yguilib.model;
import yguilib.keyboard;

import std.algorithm;

class MainController : DefaultController {
  this(App app, Widget toggleWidget, Widget alphaWidget) {
    this.app = app;
    this.toggleWidget = toggleWidget;
    this.alphaWidget = alphaWidget;
  }
  override HandleResult handleEvent(in AppEvent ev) {
    writeln("event = %s", ev);

    toggleWidget.visible ^= true;
    alphaWidget.components.background.color.a =
      clamp((alphaWidget.components.background.color.a + 0.01)%1.0, 0.1, 1.0);

    if (ev.kind == AppEvent.Kind.keyUp && ev.key == KeyCode.q)
      return HandleResult(HandleResult.Result.quit);

    auto res = super.handleEvent(ev);
    return res.isQuit() ? res : HandleResult(HandleResult.Result.updateView);
  }

  App app;
  Widget toggleWidget;
  Widget alphaWidget;
}

void main()
{
  auto window = new Window(1280, 720, "yvidtrim");
  auto view = new Widget(null, RectF(10, 10, 200, 200));
  view.components.background = new Background(ColorF(0.5, 0.5, 0, 1));
  window.view = view;
  auto smaller2 = new Widget(view, RectF(35, 45, 150, 190));
  smaller2.components.background = new Background(ColorF(0.0, 1, 0.5, 0.3));
  smaller2.components.border = new Border(ColorF(0.0, 0, 0.5, 1), Border.style.roundDashed);
  smaller2.components.textLabel = new TextLabel("Hello-0123456789", ColorF(0,0,1,1));
  auto smaller = new Widget(smaller2, RectF(15, 15, 200, 90));
  smaller.components.background = new Background(ColorF(0.5, 1, 0.5, 0.3), Background.Style.round);
  auto app = new App(window);
  smaller2.clipChildren = true;

  app.run(new MainController(app, smaller, smaller2));
}
