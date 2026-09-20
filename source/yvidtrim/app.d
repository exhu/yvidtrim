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

final class MainModel : VersionedModel {
  bool toggleVisible = true;
  float alphaValue = 0.3f;
  bool shouldQuit;
  bool qPressed;
}


final class MainView {
  this(ref ModelTracker!MainModel otherTracker, Widget toggleWidget, Widget alphaWidget) {
    this.tracker = ModelTracker!MainModel(otherTracker);
    this.toggleWidget = toggleWidget;
    this.alphaWidget = alphaWidget;
  }

  void update() {
    if (tracker.update()) {
      toggleWidget.visible = tracker.model.toggleVisible;
      alphaWidget.components.background.color.a = tracker.model.alphaValue;
    }
  }

  ModelTracker!MainModel tracker;

  Widget toggleWidget;
  Widget alphaWidget;
}

final class MainController : DefaultController {
  this(App app, Widget toggleWidget, Widget alphaWidget) {
    super(&app.ui.sendAppEvent);
    this.app = app;
    this.view = new MainView(t, toggleWidget, alphaWidget);
  }

  override void updateView() {
    view.update();
  }

  void update() {
    auto model = t.edit();
    if (model.qPressed)
      model.shouldQuit = true;

    model.toggleVisible ^= true;
    model.alphaValue = clamp((model.alphaValue + 0.01)%1.0, 0.1, 1.0);
    t.commit(model);
  }

  override HandleResult handleEvent(in AppEvent ev) {
    bool shouldUpdateView = false;
    writeln("event = %s", ev);

    if (ev.kind == AppEvent.Kind.keyUp && ev.key == KeyCode.q) {
      auto model = t.edit();
      model.qPressed = true;
      t.commit(model);
      sendAppEvent(AppEvent(AppEvent.Kind.update));
    } else if (ev.kind == AppEvent.Kind.update) {
      update();
      shouldUpdateView = t.update();
    } else
      sendAppEvent(AppEvent(AppEvent.Kind.update));


    if (t.model.shouldQuit)
      return HandleResult(HandleResult.Result.quit);

    // TODO make bool update() virtual, update event handling to default handleEvent

    auto res = super.handleEvent(ev);
    return res.isQuit() || res.isUpdateView() ? res :
      HandleResult(shouldUpdateView ? HandleResult.Result.consume :
      HandleResult.Result.nothing);
  }

  App app;
  MainView view;
  ModelTracker!MainModel t = ModelTracker!MainModel(new MainModel);
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
