module yvidtrim.app;

import std.stdio : writefln, writeln;
import yguilib.app : App;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode;
import yguilib.model : ModelTracker, VersionedModel;
import colors = yguilib.render.colors;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Border;
import yguilib.widget.layout_components : AlignItems, FlexContainer, Insets,
  JustifyContent;
import yguilib.window : Window;

import std.logger;

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
  this(UiSystem ui, ref ModelTracker!MainModel otherTracker) {
    assert(ui !is null, "UiSystem must not be null");
    this.ui = ui;
    tracker = ModelTracker!MainModel.from(otherTracker);

    rootWidget = WidgetBuilder.make(ui)
      .name("root")
      .bounds(10, 10, 200, 200)
      .view()
      .bg(ColorF(0.5f, 0.5f, 0.0f, 1.0f))
      .build();

    alphaWidget = WidgetBuilder.make(ui)
      .parent(rootWidget)
      .name("alphaWidget")
      .bounds(35, 45, 150, 190)
      .bg(ColorF(0.0f, 1.0f, 0.5f, 0.3f))
      .border(ColorF(0.0f, 0.0f, 0.5f, 1.0f))
      .borderWidth(2.0f)
      .borderStyle(Border.Style.roundDashed)
      .borderRadius(10.0f)
      .text("Hello-0123456789")
      .textColor(ColorF(0.0f, 0.0f, 1.0f, 1.0f))
      .autoSize()
      .clipChildren(true)
      .build();

    toggleWidget = WidgetBuilder.make(ui)
      .parent(rootWidget)
      .name("toggleWidget")
      .bounds(15, 15, 300, 90)
      .roundBg(ColorF(0.5f, 1.0f, 0.5f, 0.3f))
      .bgRadius(15.0f)
      .build();

    // --- layout testing ---
    container = WidgetBuilder.make(ui)
      .parent(rootWidget)
      .name("container")
      .pos(35, 250)
      .size(400, 300)
      .bg(colors.darkGray)
      .border(colors.brightWhite)
      .borderWidth(3.0f)
      .borderStyle(Border.Style.dashed)
      .flexRow()
      .gap(8.0f)
      .justify(JustifyContent.start)
      .alignItems(tracker.model.alignItems)
      .children(
        WidgetBuilder.make(ui)
          .name("yellowBox")
          .pos(5, 8)
          .fixedSize(100.0f, 40.0f)
          .bg(colors.yellow)
          .build(),
        WidgetBuilder.make(ui)
          .name("brownBox")
          .pos(15, 18)
          .fixedSize(110.0f, 50.0f)
          .bg(colors.brown)
          .margin(Insets.horizontal(10.0f).withTop(14.0f).withBottom(15.0f))
          .build()
      )
      .build();
    fc = container.components.flexContainer;

    // TODO demo all other supported flex etc.
    addRightTopAnchor();
    addLeftBottomAnchor();
    addRightBottomAnchor();

    infof("tree = %s", rootWidget.dumpTree());

  }

  void addRightTopAnchor() {
    WidgetBuilder.make(ui)
      .parent(rootWidget)
      .name("rightTopAnchor")
      .size(30, 30)
      .bg(colors.red)
      .anchorRight(0.0f)
      .anchorTop(3.0f)
      .build();
  }

  void addLeftBottomAnchor() {
    WidgetBuilder.make(ui)
      .parent(rootWidget)
      .name("leftBottomAnchor")
      .size(30, 30)
      .bg(colors.brightRed)
      .anchorLeft(3.0f)
      .anchorBottom(7.0f)
      .build();
  }

  void addRightBottomAnchor() {
    WidgetBuilder.make(ui)
      .parent(rootWidget)
      .name("rightBottomAnchor")
      .size(30, 30)
      .bg(colors.magenta)
      .anchorRight(5.0f)
      .anchorBottom(2.0f)
      .build();
  }

  void update() {
    if (tracker.update()) {
      if (toggleWidget.visible != tracker.model.toggleVisible) {
        toggleWidget.visible = tracker.model.toggleVisible;
        toggleWidget.update(WidgetUpdateScope.layout);
      }
      if (alphaWidget.components.background !is null &&
          alphaWidget.components.background.color.a !=
          tracker.model.alphaValue) {
        alphaWidget.components.background.color.a = tracker.model.alphaValue;
        alphaWidget.update(WidgetUpdateScope.visuals);
      }
      if (fc.alignItems != tracker.model.alignItems) {
        fc.alignItems = tracker.model.alignItems;
        container.update(WidgetUpdateScope.layout);
        writeln("alignItems=", fc.alignItems);
      }
    }
  }

package(yvidtrim):
  Widget rootWidget;

private:
  UiSystem ui;
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
    view = new MainView(app.ui, t);
    app.ui.mainWindow().rootWidget = view.rootWidget;
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
