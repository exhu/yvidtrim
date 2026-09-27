module yvidtrim.app;
import std.stdio;
import yguilib.app;
import yguilib.controller;
import yguilib.events;
import yguilib.events.keyboard;
import yguilib.model;
import yguilib.render;
import colors = yguilib.render.colors;
import yguilib.render.render_types;
import yguilib.uisystem;
import yguilib.widget;
import yguilib.widget.drawing_components;
import yguilib.widget.layout_components;
import yguilib.window;

import std.algorithm;

final class MainModel : VersionedModel {
  bool toggleVisible = true;
  float alphaValue = 0.3f;
  bool qPressed;
  bool aPressed;
  AlignItems alignItems;
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
    smaller2.components.size = new Size;
    smaller2.components.size.width = Dimension(0, SizingMode.auto_);
    smaller2.components.size.height = Dimension(0, SizingMode.auto_);
    auto smaller = new Widget(view, RectF(15, 15, 300, 90));
    smaller.components.background = new Background(ColorF(0.5, 1, 0.5, 0.3), Background.Style.round);
    smaller2.clipChildren = true;

    toggleWidget = smaller;
    alphaWidget = smaller2;

    // --- layout testing ---
    container = makeBox(view, RectF(35, 250, 400, 300), colors.darkGray);
    container.components.border = new Border(colors.brightWhite, Border.style.dashed);
    container.components.border.width = 3;
    fc = new FlexContainer;
    fc.direction = FlexDirection.row;
    fc.gap = 8;
    fc.justify = JustifyContent.start;
    fc.alignItems = tracker.model.alignItems; //AlignItems.center;
    container.components.flexContainer = fc;
    auto c1 = makeBox(container, RectF(5, 8, 1, 1), colors.yellow);
    auto sz = new Size;
    sz.width = Dimension(100, SizingMode.fixed);
    sz.height = Dimension(40, SizingMode.fixed);
    c1.components.size = sz;
    auto c2 = makeBox(container, RectF(15, 18, 1, 1), colors.brown);
    auto sz2 =new Size;
    c2.components.size = sz2;
    sz2.margin.left = 15;
    sz2.margin.right = 10;
    sz2.margin.bottom = 14;
    sz2.margin.top = 10;
    sz2.width = Dimension(110, SizingMode.fixed);
    sz2.height = Dimension(50, SizingMode.fixed);

    // TODO demo all other supported flex etc.
  }

  void update() {
    if (tracker.update()) {
      toggleWidget.visible = tracker.model.toggleVisible;
      toggleWidget.markDirty();
      alphaWidget.components.background.color.a = tracker.model.alphaValue;
      alphaWidget.markDirty();
      fc.alignItems = tracker.model.alignItems;
      container.markDirty();
      writeln("alignItems=", fc.alignItems);
    }
  }

private:
  static Widget makeBox(Widget parent, RectF rect, ColorF color) {
    auto w = new Widget(parent, rect);
    w.components.background = new Background(color);
    return w;
  }


  Widget view;
  ModelTracker!MainModel tracker;
  Widget toggleWidget;
  Widget alphaWidget;
  FlexContainer fc;
  Widget container;
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

    if (model.aPressed) {
      size_t e = cast(size_t)model.alignItems;
      e += 1;
      e = e % AlignItems.max;

      model.alignItems = cast(AlignItems)e;
      model.aPressed = false;
    }

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

    if (ev.kind == AppEvent.Kind.keyUp) {
      if (ev.key == KeyCode.q) {
        auto model = t.edit();
        model.qPressed = true;
        t.commit(model);
        consume = true;
      } else if (ev.key == KeyCode.a) {
        auto model = t.edit();
        model.aPressed = true;
        t.commit(model);
        consume = true;
      }
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
