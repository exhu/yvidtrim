module yvidtrim.app;

import std.stdio : writefln, writeln;
import yguilib.app : App;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode;
import yguilib.model : ModelTracker, VersionedModel;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.layout_components : AlignItems, FlexContainer;
import yguilib.window : Window;
import yvidtrim.uitree.mainview;

import std.logger;

final class MainModel : VersionedModel {
  bool toggleVisible = true;
  float alphaValue = 0.3f;
  bool qPressed;
  bool aPressed;
  AlignItems alignItems;
}

final class MainView {
public:
  this(UiSystem ui, ref ModelTracker!MainModel otherTracker) {
    assert(ui !is null, "UiSystem must not be null");
    this.ui = ui;
    tracker = ModelTracker!MainModel.from(otherTracker);

    widgets = makeMainViewWidgets(ui);
    fc = widgets.container.components.flexContainer;
    assert(fc !is null);
    fc.alignItems = tracker.model.alignItems;

    infof("tree = %s", widgets.root.dumpTree());
  }

  void update() {
    if (tracker.update()) {
      if (widgets.toggle.visible != tracker.model.toggleVisible) {
        widgets.toggle.visible = tracker.model.toggleVisible;
        widgets.toggle.update(WidgetUpdateScope.layout);
      }
      if (widgets.alpha.components.background !is null &&
          widgets.alpha.components.background.color.a !=
          tracker.model.alphaValue) {
        widgets.alpha.components.background.color.a =
          tracker.model.alphaValue;
        widgets.alpha.update(WidgetUpdateScope.visuals);
      }
      if (fc.alignItems != tracker.model.alignItems) {
        fc.alignItems = tracker.model.alignItems;
        widgets.container.update(WidgetUpdateScope.layout);
        writeln("alignItems=", fc.alignItems);
      }
    }
  }

package(yvidtrim):
  Widget rootWidget() {
    return widgets.root;
  }

private:
  UiSystem ui;
  ModelTracker!MainModel tracker;
  MainViewWidgets widgets;
  FlexContainer fc;
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
  // TODO parse cmdline arguments
  auto app = App.makeAppWithTitleWh("yvidtrim", 1280, 720);
  app.run(new MainController(app));
}
