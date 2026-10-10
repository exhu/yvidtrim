module yvidtrim.app;

import std.stdio : writefln, writeln;
import yguilib.app : App;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode;
import yguilib.model : ModelTracker, VersionedModel;
import colors = yguilib.render.colors;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Background, Border;
import yguilib.widget.layout_components : AlignItems, Anchor, FlexContainer,
  JustifyContent;
import yguilib.window : Window;

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
public:
  this(ref ModelTracker!MainModel otherTracker) {
    tracker = ModelTracker!MainModel(otherTracker);

    view = WidgetBuilder(RectF(10, 10, 200, 200))
      .view()
      .background(ColorF(0.5f, 0.5f, 0.0f, 1.0f))
      .build();

    alphaWidget = WidgetBuilder(view, RectF(35, 45, 150, 190))
      .background(ColorF(0.0f, 1.0f, 0.5f, 0.3f))
      .border(ColorF(0.0f, 0.0f, 0.5f, 1.0f), 2.0f, Border.Style.roundDashed)
      .text("Hello-0123456789", ColorF(0.0f, 0.0f, 1.0f, 1.0f))
      .autoSize()
      .clipChildren(true)
      .build();

    toggleWidget = WidgetBuilder(view, RectF(15, 15, 300, 90))
      .background(ColorF(0.5f, 1.0f, 0.5f, 0.3f), Background.Style.round)
      .build();

    // --- layout testing ---
    container = WidgetBuilder(view, RectF(35, 250, 400, 300))
      .background(colors.darkGray)
      .border(colors.brightWhite, 3.0f, Border.Style.dashed)
      .flexRow(8.0f, JustifyContent.start, tracker.model.alignItems)
      .child(RectF(5, 8, 1, 1), (ref WidgetBuilder b) {
        b.background(colors.yellow)
          .fixedSize(100.0f, 40.0f);
      })
      .child(RectF(15, 18, 1, 1), (ref WidgetBuilder b) {
        b.background(colors.brown)
          .margin(10.0f, 10.0f, 14.0f, 15.0f)
          .fixedSize(110.0f, 50.0f);
      })
      .build();
    fc = container.components.flexContainer;

    // TODO demo all other supported flex etc.
    addRightTopAnchor();
    addLeftBottomAnchor();
    addRightBottomAnchor();
  }

  void addRightTopAnchor() {
    WidgetBuilder(view, RectF(0, 0, 30, 30))
      .background(colors.red)
      .anchor(new Anchor().withRight(0.0f).withTop(3.0f))
      .build();
  }

  void addLeftBottomAnchor() {
    WidgetBuilder(view, RectF(0, 0, 30, 30))
      .background(colors.brightRed)
      .anchor(new Anchor().withLeft(3.0f).withBottom(7.0f))
      .build();
  }

  void addRightBottomAnchor() {
    WidgetBuilder(view, RectF(0, 0, 30, 30))
      .background(colors.magenta)
      .anchor(new Anchor().withRight(5.0f).withBottom(2.0f))
      .build();
  }

  void update() {
    if (tracker.update()) {
      if (toggleWidget.visible != tracker.model.toggleVisible) {
        toggleWidget.visible = tracker.model.toggleVisible;
        toggleWidget.update();
      }
      if (alphaWidget.components.background !is null &&
          alphaWidget.components.background.color.a !=
          tracker.model.alphaValue) {
        alphaWidget.components.background.color.a = tracker.model.alphaValue;
        alphaWidget.update();
      }
      if (fc.alignItems != tracker.model.alignItems) {
        fc.alignItems = tracker.model.alignItems;
        container.update();
        writeln("alignItems=", fc.alignItems);
      }
    }
  }

package(yvidtrim):
  Widget view;

private:
  ModelTracker!MainModel tracker;
  Widget toggleWidget;
  Widget alphaWidget;
  FlexContainer fc;
  Widget container;
}

final class MainController : DefaultController {
  this(App app) {
    assert(app !is null);
    super(app.ui);
    this.app = app;
    view = new MainView(t);
    app.ui.mainWindow().view = view.view;
  }

  override bool updateView() {
    view.update();
    return true;
  }

  override bool update() {
    import std.algorithm.comparison : clamp;

    auto model = t.edit();
    if (model.qPressed) {
      sendQuit();
    }

    if (model.aPressed) {
      size_t e = cast(size_t)model.alignItems;
      e += 1;
      e = e % AlignItems.max;

      model.alignItems = cast(AlignItems)e;
      model.aPressed = false;
    }

    model.toggleVisible ^= true;
    model.alphaValue = clamp((model.alphaValue + 0.01f) % 1.0f, 0.1f, 1.0f);
    t.commit(model);

    return t.update();
  }

  override HandleResult handleEvent(AppEvent ev) {
    bool consume = false;
    writefln("event = %s", ev);

    if (ev.kind == AppEvent.Kind.updateUiLayer) {
      return HandleResult(HandleResult.Result.nothing);
    }

    if (ev.kind == AppEvent.Kind.keyUp) {
      if (ev.keyData.key == Keycode.q) {
        auto model = t.edit();
        model.qPressed = true;
        t.commit(model);
        consume = true;
      } else if (ev.keyData.key == Keycode.a) {
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

private:
  App app;
  MainView view;
  ModelTracker!MainModel t = ModelTracker!MainModel(new MainModel);
}

void main() {
  auto window = new Window(1280, 720, "yvidtrim");
  auto app = new App(window);
  app.run(new MainController(app));
}
