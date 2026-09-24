module yvidtrim.app;
import std.stdio;
import yguilib.app;
import yguilib.controller;
import yguilib.events;
import yguilib.events.keyboard;
import yguilib.model;
import yguilib.render;
import yguilib.render.render_types;
import yguilib.uisystem;
import yguilib.widget;
import yguilib.window;

import std.algorithm;

final class MainModel : VersionedModel {
  bool toggleVisible = true;
  float alphaValue = 0.3f;
  bool qPressed;
}


// TODO 1) widgets will not have bindings,
// instead all updates to widgest are performed in code in update()
// 2) a group of widgets may make a subview/composite
// 3) implement a view builder, where the models are accessed via
// introspection, and the update() checks which models changed,
// calls setters on the widgets and calls update() on widgets.
// widgets usually should not update on changing their properties.

final class MainView {
  this(ref ModelTracker!MainModel otherTracker) {
    tracker = ModelTracker!MainModel(otherTracker);

    view = new Widget(null, RectF(10, 10, 200, 200));
    view.components.background = new Background(ColorF(0.5, 0.5, 0, 1));
    auto smaller2 = new Widget(view, RectF(35, 45, 150, 190));
    smaller2.components.background = new Background(ColorF(0.0, 1, 0.5, 0.3));
    smaller2.components.border = new Border(ColorF(0.0, 0, 0.5, 1), Border.style.roundDashed);
    smaller2.components.textLabel = new TextLabel("Hello-0123456789", ColorF(0,0,1,1));
    auto smaller = new Widget(smaller2, RectF(15, 15, 200, 90));
    smaller.components.background = new Background(ColorF(0.5, 1, 0.5, 0.3), Background.Style.round);
    smaller2.clipChildren = true;

    toggleWidget = smaller;
    alphaWidget = smaller2;
  }

  void update() {
    if (tracker.update()) {
      toggleWidget.visible = tracker.model.toggleVisible;
      toggleWidget.markDirty();
      alphaWidget.components.background.color.a = tracker.model.alphaValue;
      alphaWidget.markDirty();
    }
  }

  Widget view;
private:
  ModelTracker!MainModel tracker;

  Widget toggleWidget;
  Widget alphaWidget;
}

final class MainController : DefaultController {
  this(App app) {
    super(&app.ui.sendAppEvent);
    this.app = app;
    view = new MainView(t);
    app.ui.getMainWindow().view = view.view;
  }

  override void updateView() {
    view.update();
  }

  override bool update() {
    auto model = t.edit();
    if (model.qPressed)
      sendQuit();

    model.toggleVisible ^= true;
    model.alphaValue = clamp((model.alphaValue + 0.01)%1.0, 0.1, 1.0);
    t.commit(model);

    return t.update();
  }

  override HandleResult handleEvent(AppEvent ev) {
    bool consume = false;
    writefln("event = %s", ev);

    if (ev.Kind.update)
      return HandleResult(HandleResult.Result.nothing);

    if (ev.kind == AppEvent.Kind.keyUp && ev.key == KeyCode.q) {
      auto model = t.edit();
      model.qPressed = true;
      t.commit(model);
      consume = true;
    }

    auto res = super.handleEvent(ev);
    return res.isQuit() || res.isUpdateView() ? res :
      HandleResult(HandleResult.Result.update, consume);
  }

  App app;
  MainView view;
  ModelTracker!MainModel t = ModelTracker!MainModel(new MainModel);
}

void main()
{
  auto window = new Window(1280, 720, "yvidtrim");
  auto app = new App(window);
  app.run(new MainController(app));
}
