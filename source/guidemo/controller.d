/**
 * controller.d - Interactive keyboard and event controller for guidemo.
 */
module guidemo.controller;

import yguilib.app : App;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode, Scancode;
import yguilib.model : ModelTracker;
import yguilib.widget.drawing_components : TextLabel;
import yguilib.widget.layout_components : AlignItems, FlexDirection,
  JustifyContent;

import guidemo.model : DemoModel;
import guidemo.pages.textlabel_page : TextLabelPage;
import guidemo.view : DemoView;

/// Controller handling keyboard shortcuts, animation ticks, and view updates.
final class DemoController : DefaultController {
  this(App app) {
    super(app.ui);
    this.app = app;
    tracker = ModelTracker!DemoModel(new DemoModel);
    view = new DemoView(tracker);
    app.ui.mainWindow().view = view.getRootWidget();
  }

  override bool updateView() {
    view.update();
    return true;
  }

  override bool update() {
    auto model = tracker.edit();

    if (model.quitRequested) {
      sendQuit();
      return false;
    }

    // Smoothly animate alpha pulse
    model.alphaValue += model.alphaStep;
    if (model.alphaValue >= 1.0f) {
      model.alphaValue = 1.0f;
      model.alphaStep = -model.alphaStep;
    } else if (model.alphaValue <= 0.2f) {
      model.alphaValue = 0.2f;
      model.alphaStep = -model.alphaStep;
    }

    tracker.commit(model);
    return tracker.update();
  }

  override HandleResult handleEvent(AppEvent ev) {
    bool consumed = false;

    // Mouse click on header tab buttons
    if (ev.kind == AppEvent.Kind.view) {
      import std.logger;
      warning(ev.view.eventName);
      auto model = tracker.edit();
      auto eventName = ev.view.eventName;
      if (eventName == "tab1Btn") {
          model.activePage = 0;
          consumed = true;
          warning(model.activePage);
      } else if (eventName == "tab2Btn") {
          model.activePage = 1;
          consumed = true;
          warning(model.activePage);
      }
      tracker.commit(model);

      if (consumed) {
        HandleResult res;
        res.result = HandleResult.Result.updateView;
        res.consume = true;
        // res.timeoutMs = 16;
        return res;
      }
    }

    if (ev.kind == AppEvent.Kind.keyDown) {
      auto model = tracker.edit();

      if (isKey(ev, Keycode.q, Scancode.q) ||
          isKey(ev, Keycode.escape, Scancode.escape)) {
        model.quitRequested = true;
        tracker.commit(model);
        sendQuit();
        return HandleResult(HandleResult.Result.quit, true);
      } else if (isKey(ev, Keycode.tab, Scancode.tab)) {
        model.activePage = (model.activePage + 1) % 2;
        consumed = true;
      } else if (isKey(ev, Keycode.key1, Scancode.key1)) {
        model.activePage = 0;
        consumed = true;
      } else if (isKey(ev, Keycode.key2, Scancode.key2)) {
        model.activePage = 1;
        consumed = true;
      } else if (isKey(ev, Keycode.m, Scancode.m)) {
        model.labelMultiline = !model.labelMultiline;
        consumed = true;
      } else if (isKey(ev, Keycode.e, Scancode.e)) {
        model.labelEllipsis = !model.labelEllipsis;
        consumed = true;
      } else if (isKey(ev, Keycode.l, Scancode.l)) {
        size_t nextAlign = (cast(size_t)model.labelAlignment + 1) % 3;
        model.labelAlignment = cast(TextLabel.Alignment)nextAlign;
        consumed = true;
      } else if (isKey(ev, Keycode.t, Scancode.t)) {
        if (model.activePage == 0) {
          model.textSampleIndex = (model.textSampleIndex + 1) % 3;
        } else {
          model.labelSampleIndex = (model.labelSampleIndex + 1) %
            TextLabelPage.labelInteractiveSamples.length;
        }
        consumed = true;
      } else if (isKey(ev, Keycode.d, Scancode.d)) {
        model.direction = model.direction == FlexDirection.row
          ? FlexDirection.column
          : FlexDirection.row;
        consumed = true;
      } else if (isKey(ev, Keycode.j, Scancode.j)) {
        size_t nextJ = (cast(size_t)model.justify + 1) %
          (JustifyContent.max + 1);
        model.justify = cast(JustifyContent)nextJ;
        consumed = true;
      } else if (isKey(ev, Keycode.a, Scancode.a)) {
        size_t nextA = (cast(size_t)model.alignItems + 1) %
          (AlignItems.max + 1);
        model.alignItems = cast(AlignItems)nextA;
        consumed = true;
      } else if (isKey(ev, Keycode.g, Scancode.g)) {
        if (model.gap == 0.0f) {
          model.gap = 8.0f;
        } else if (model.gap == 8.0f) {
          model.gap = 16.0f;
        } else if (model.gap == 16.0f) {
          model.gap = 24.0f;
        } else {
          model.gap = 0.0f;
        }
        consumed = true;
      } else if (isKey(ev, Keycode.v, Scancode.v)) {
        model.child2Visible = !model.child2Visible;
        consumed = true;
      }

      tracker.commit(model);

      if (consumed) {
        HandleResult res;
        res.result = HandleResult.Result.updateView;
        res.consume = true;
        // timeout will abuse rendering
        //res.timeoutMs = 16;
        return res;
      }
    }

    auto res = super.handleEvent(ev);
    // timeout will abuse rendering
    //res.timeoutMs = 16;
    return res;
  }

private:
  static bool isKey(in AppEvent ev, Keycode targetKey, Scancode targetScan) {
    if (ev.keyData.scancode == targetScan) {
      return true;
    }
    if (ev.keyData.key == targetKey) {
      return true;
    }
    // Handle potential uppercase ASCII keycode
    if (targetKey >= 'a' && targetKey <= 'z') {
      if (ev.keyData.key == (targetKey - 32)) {
        return true;
      }
    }
    return false;
  }

  App app;
  DemoView view;
  ModelTracker!DemoModel tracker;
}
