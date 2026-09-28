/**
 * controller.d - Interactive keyboard and event controller for guidemo.
 */
module guidemo.controller;

import yguilib.app : App;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : KeyCode, ScanCode;
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
    super(&app.ui.sendAppEvent);
    this.app = app;
    tracker = ModelTracker!DemoModel(new DemoModel);
    view = new DemoView(tracker);
    app.ui.getMainWindow().view = view.getRootWidget();
  }

  override void updateView() {
    view.update();
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
    if (ev.kind == AppEvent.Kind.mouseButtonDown) {
      auto model = tracker.edit();
      if (ev.y >= 20.0f && ev.y <= 52.0f) {
        if (ev.x >= 840.0f && ev.x <= 1025.0f) {
          model.activePage = 0;
          consumed = true;
        } else if (ev.x >= 1035.0f && ev.x <= 1245.0f) {
          model.activePage = 1;
          consumed = true;
        }
      }
      tracker.commit(model);

      if (consumed) {
        HandleResult res;
        res.result = HandleResult.Result.updateView;
        res.consume = true;
        res.timeoutMs = 16;
        return res;
      }
    }

    if (ev.kind == AppEvent.Kind.keyDown) {
      auto model = tracker.edit();

      if (isKey(ev, KeyCode.q, ScanCode.q) ||
          isKey(ev, KeyCode.escape, ScanCode.escape)) {
        model.quitRequested = true;
        tracker.commit(model);
        sendQuit();
        return HandleResult(HandleResult.Result.quit, true);
      } else if (isKey(ev, KeyCode.tab, ScanCode.tab)) {
        model.activePage = (model.activePage + 1) % 2;
        consumed = true;
      } else if (isKey(ev, KeyCode.key1, ScanCode.key1)) {
        model.activePage = 0;
        consumed = true;
      } else if (isKey(ev, KeyCode.key2, ScanCode.key2)) {
        model.activePage = 1;
        consumed = true;
      } else if (isKey(ev, KeyCode.m, ScanCode.m)) {
        model.labelMultiline = !model.labelMultiline;
        consumed = true;
      } else if (isKey(ev, KeyCode.e, ScanCode.e)) {
        model.labelEllipsis = !model.labelEllipsis;
        consumed = true;
      } else if (isKey(ev, KeyCode.l, ScanCode.l)) {
        size_t nextAlign = (cast(size_t)model.labelAlignment + 1) % 3;
        model.labelAlignment = cast(TextLabel.Alignment)nextAlign;
        consumed = true;
      } else if (isKey(ev, KeyCode.t, ScanCode.t)) {
        if (model.activePage == 0) {
          model.textSampleIndex = (model.textSampleIndex + 1) % 3;
        } else {
          model.labelSampleIndex = (model.labelSampleIndex + 1) %
            TextLabelPage.labelInteractiveSamples.length;
        }
        consumed = true;
      } else if (isKey(ev, KeyCode.d, ScanCode.d)) {
        model.direction = model.direction == FlexDirection.row
          ? FlexDirection.column
          : FlexDirection.row;
        consumed = true;
      } else if (isKey(ev, KeyCode.j, ScanCode.j)) {
        size_t nextJ = (cast(size_t)model.justify + 1) %
          (JustifyContent.max + 1);
        model.justify = cast(JustifyContent)nextJ;
        consumed = true;
      } else if (isKey(ev, KeyCode.a, ScanCode.a)) {
        size_t nextA = (cast(size_t)model.alignItems + 1) %
          (AlignItems.max + 1);
        model.alignItems = cast(AlignItems)nextA;
        consumed = true;
      } else if (isKey(ev, KeyCode.g, ScanCode.g)) {
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
      } else if (isKey(ev, KeyCode.v, ScanCode.v)) {
        model.child2Visible = !model.child2Visible;
        consumed = true;
      }

      tracker.commit(model);

      if (consumed) {
        HandleResult res;
        res.result = HandleResult.Result.updateView;
        res.consume = true;
        res.timeoutMs = 16;
        return res;
      }
    }

    auto res = super.handleEvent(ev);
    res.timeoutMs = 16;
    return res;
  }

private:
  static bool isKey(in AppEvent ev, KeyCode targetKey, ScanCode targetScan) {
    if (ev.scancode == targetScan) {
      return true;
    }
    if (ev.key == targetKey) {
      return true;
    }
    // Handle potential uppercase ASCII keycode
    if (targetKey >= 'a' && targetKey <= 'z') {
      if (ev.key == (targetKey - 32)) {
        return true;
      }
    }
    return false;
  }

  App app;
  DemoView view;
  ModelTracker!DemoModel tracker;
}
