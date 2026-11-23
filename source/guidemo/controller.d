/**
 * controller.d - Shared application controller for guidemo.
 */
module guidemo.controller;

import std.datetime.systime : Clock, SysTime;
import std.logger : tracef, warningf;

import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode, Scancode;
import yguilib.model : ModelTracker;
import yguilib.uisystem : UiSystem;

import guidemo.common : isKey;
import guidemo.demo_model_helpers : pageCount;
import guidemo.model : DebugDrawMode, DemoModel;
import yguilib.controls.tabcontrol : TabsModel;
import guidemo.view : DemoView, headerTabSwitchEvent;

/// Parameters for constructing DemoController.
struct DemoControllerParams {
  UiSystem ui;
  ModelTracker!DemoModel tracker;
  DemoView view;
  ModelTracker!TabsModel tabsTracker;

  /// Sets the UI system.
  ref DemoControllerParams withUi(UiSystem ui) return {
    this.ui = ui;
    return this;
  }

  /// Sets the shared demo model tracker.
  ref DemoControllerParams withTracker(
    ref ModelTracker!DemoModel otherTracker
  ) return {
    this.tracker = ModelTracker!DemoModel.from(otherTracker);
    return this;
  }

  /// Sets the demo shell view.
  ref DemoControllerParams withView(DemoView view) return {
    this.view = view;
    return this;
  }

  /// Sets the header tab control model tracker.
  ref DemoControllerParams withTabsTracker(
    ref ModelTracker!TabsModel otherTabsTracker
  ) return {
    this.tabsTracker = ModelTracker!TabsModel.from(otherTabsTracker);
    return this;
  }
}

/// Shared controller handling quit, F1 debug draw cycling, F12
/// screenshots, and page switching across guidemo.
final class DemoController : DefaultController {
  @disable this();

  /// Constructs DemoController from fluent `params`.
  this(ref DemoControllerParams params) {
    assert(params.ui !is null, "UiSystem must not be null");
    assert(params.view !is null, "DemoView must not be null");
    super(params.ui);
    this.view = params.view;
    this.tracker = ModelTracker!DemoModel.from(params.tracker);
    this.tabsTracker = ModelTracker!TabsModel.from(params.tabsTracker);
  }

  invariant {
    assert(view !is null);
  }

  override bool updateView() {
    view.update();
    return true;
  }

  override bool update() {
    if (tracker.model.quitRequested) {
      sendQuit();
      return false;
    }
    return tracker.update();
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.view) {
      if (handleHeaderTabEvent(ev)) {
        return HandleResult(HandleResult.Result.update, false);
      }
    }

    if (ev.kind == AppEvent.Kind.keyDown) {
      tracef("DemoController keyDown: key=0x%x scancode=%d",
        cast(uint) ev.keyData.key, cast(int) ev.keyData.scancode);
      if (isKey(ev, Keycode.q, Scancode.q) ||
          isKey(ev, Keycode.escape, Scancode.escape)) {
        auto model = tracker.edit();
        model.quitRequested = true;
        tracker.commit(model);
        sendQuit();
        return HandleResult(HandleResult.Result.quit, true);
      }
      if (isKey(ev, Keycode.f12, Scancode.f12)) {
        const string path = screenshotPathFromTime(Clock.currTime());
        tracef("F12: requesting screenshot %s", path);
        uiSystem.requestScreenshot(path);
        return HandleResult(HandleResult.Result.nothing, true);
      }
      if (handleGlobalKeyDown(ev)) {
        return HandleResult(HandleResult.Result.update, true);
      }
    }

    return super.handleEvent(ev);
  }

private:
  bool handleHeaderTabEvent(in AppEvent ev) {
    if (ev.view.eventName != headerTabSwitchEvent) {
      return false;
    }
    auto model = tracker.edit();
    const size_t prevPage = model.activePage;
    const size_t idx = cast(size_t) ev.view.value[0];
    if (idx < pageCount()) {
      model.activePage = idx;
    }
    const size_t newPage = model.activePage;
    tracker.commit(model);
    if (newPage != prevPage) {
      syncActiveTab(newPage);
    }
    return true;
  }

  bool handleGlobalKeyDown(in AppEvent ev) {
    bool consumed = false;
    auto model = tracker.edit();
    const size_t prevPage = model.activePage;

    if (isKey(ev, Keycode.f1, Scancode.f1)) {
      const DebugDrawMode prevMode = model.debugDrawMode;
      toggleDebugDraw(model);
      tracef("F1: debug draw mode %s -> %s", prevMode,
        model.debugDrawMode);
      debug {
      } else {
        warningf("F1: debug draw is not available in release builds "
          ~ "(rebuild with buildtype debug or debugoptimized)");
      }
      tracker.commit(model);
      return true;
    }
    if (isKey(ev, Keycode.tab, Scancode.tab)) {
      model.activePage = (model.activePage + 1) % pageCount();
      consumed = true;
    } else {
      // [0] selects page 10
      static immutable Keycode[10] keycodes = [
        Keycode.key1, Keycode.key2, Keycode.key3,
        Keycode.key4, Keycode.key5, Keycode.key6,
        Keycode.key7, Keycode.key8, Keycode.key9,
        Keycode.key0,
      ];
      static immutable Scancode[10] scancodes = [
        Scancode.key1, Scancode.key2, Scancode.key3,
        Scancode.key4, Scancode.key5, Scancode.key6,
        Scancode.key7, Scancode.key8, Scancode.key9,
        Scancode.key0,
      ];
      const size_t count = pageCount() < keycodes.length
        ? pageCount()
        : keycodes.length;
      foreach (i; 0 .. count) {
        if (isKey(ev, keycodes[i], scancodes[i])) {
          model.activePage = i;
          consumed = true;
          break;
        }
      }
    }

    const size_t newPage = model.activePage;
    tracker.commit(model);
    if (newPage != prevPage) {
      syncActiveTab(newPage);
    }
    return consumed;
  }

  static void toggleDebugDraw(DemoModel model) {
    const size_t next = (cast(size_t) model.debugDrawMode + 1) %
      (DebugDrawMode.max + 1);
    model.debugDrawMode = cast(DebugDrawMode) next;
  }

  void syncActiveTab(size_t pageIdx) {
    if (tabsTracker.model.activeTab != pageIdx) {
      auto tabsModel = tabsTracker.edit();
      tabsModel.activeTab = pageIdx;
      tabsTracker.commit(tabsModel);
    }
  }

  DemoView view;
  ModelTracker!DemoModel tracker;
  ModelTracker!TabsModel tabsTracker;
}

/// Returns the screenshot file name `screenshot-YYYYMMDD-HHMMSS.png` (in the
/// current directory) for the time `t`.
string screenshotPathFromTime(SysTime t) {
  import std.format : format;

  return format(
    "screenshot-%04d%02d%02d-%02d%02d%02d.png",
    t.year, cast(int) t.month, t.day, t.hour, t.minute, t.second
  );
}

unittest {
  import std.datetime.date : DateTime;

  const SysTime t = SysTime(DateTime(2026, 3, 7, 9, 5, 4));
  assert(screenshotPathFromTime(t) == "screenshot-20260307-090504.png");
}

unittest {
  import guidemo.view : createHeaderTabsModel;
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  // Records screenshot requests instead of forwarding them to a window.
  static final class RecordingUiSystem : UiSystemImpl {
    this() {
      super(null);
    }

    override void requestScreenshot(string path) {
      paths ~= path;
    }

    string[] paths;
  }

  auto ui = new RecordingUiSystem();
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto tabsTracker = ModelTracker!TabsModel(createHeaderTabsModel());
  auto demoView = new DemoView(ui, demoTracker, tabsTracker);

  DemoControllerParams params;
  params.withUi(ui)
    .withTracker(demoTracker)
    .withView(demoView)
    .withTabsTracker(tabsTracker);
  auto demoCtrl = new DemoController(params);

  AppEvent makeKeyDown(Keycode k, Scancode sc) {
    return AppEvent.keyEvent(
      AppEvent.Kind.keyDown,
      AppEvent.KeyData(1, k, sc)
    );
  }

  // Page-specific view events must not be consumed by DemoController
  auto evSub = ViewAppEventBuilder("pageTabSwitch").value(2).build();
  auto hrSub = demoCtrl.handleEvent(evSub);
  assert(hrSub.result == HandleResult.Result.nothing);
  assert(!hrSub.consume);

  // Page-specific key events must not be consumed by DemoController
  auto hrD = demoCtrl.handleEvent(makeKeyDown(Keycode.d, Scancode.d));
  assert(hrD.result == HandleResult.Result.nothing);
  assert(!hrD.consume);

  // Header TabControl switch event verification
  auto evHeader = ViewAppEventBuilder(headerTabSwitchEvent).value(3).build();
  auto hrHeader = demoCtrl.handleEvent(evHeader);
  assert(hrHeader.result == HandleResult.Result.update);
  assert(!hrHeader.consume);
  assert(demoCtrl.tracker.model.activePage == 3);
  assert(demoCtrl.tabsTracker.model.activeTab == 3);
  assert(demoCtrl.update());
  assert(!demoCtrl.update());

  // F1 cycles DebugDrawMode through all 5 states
  assert(demoCtrl.tracker.model.debugDrawMode == DebugDrawMode.off);
  DebugDrawMode[5] expectedModes = [
    DebugDrawMode.allVisible,
    DebugDrawMode.allWithHidden,
    DebugDrawMode.activePageVisible,
    DebugDrawMode.activePageWithHidden,
    DebugDrawMode.off,
  ];
  foreach (expected; expectedModes) {
    const evF1 = makeKeyDown(Keycode.f1, Scancode.f1);
    const hrF1 = demoCtrl.handleEvent(evF1);
    assert(hrF1.result == HandleResult.Result.update);
    assert(hrF1.consume);
    assert(demoCtrl.tracker.model.debugDrawMode == expected);
    assert(demoCtrl.update());
    assert(demoCtrl.updateView());
  }

  // F12 requests a screenshot-YYYYMMDD-HHMMSS.png in the current directory
  const hrF12 = demoCtrl.handleEvent(makeKeyDown(Keycode.f12, Scancode.f12));
  assert(hrF12.consume);
  assert(demoCtrl.tracker.model.debugDrawMode == DebugDrawMode.off);
  assert(ui.paths.length == 1);
  {
    import std.ascii : isDigit;
    import std.algorithm.searching : all, endsWith, startsWith;

    const string p = ui.paths[0];
    assert(p.length == "screenshot-YYYYMMDD-HHMMSS.png".length);
    assert(p.startsWith("screenshot-"));
    assert(p.endsWith(".png"));
    assert(p[11 .. 19].all!isDigit);
    assert(p[19] == '-');
    assert(p[20 .. 26].all!isDigit);
  }

  // Page 6 key switch
  auto evKey6 = makeKeyDown(Keycode.key6, Scancode.key6);
  auto hrPage6 = demoCtrl.handleEvent(evKey6);
  assert(hrPage6.consume);
  assert(demoCtrl.tracker.model.activePage == 5);
  assert(demoCtrl.tabsTracker.model.activeTab == 5);

  // Page 7 key switch
  auto evKey7 = makeKeyDown(Keycode.key7, Scancode.key7);
  auto hrPage7 = demoCtrl.handleEvent(evKey7);
  assert(hrPage7.consume);
  assert(demoCtrl.tracker.model.activePage == 6);
  assert(demoCtrl.tabsTracker.model.activeTab == 6);

  // [0] selects page 10
  auto evKey0 = makeKeyDown(Keycode.key0, Scancode.key0);
  assert(demoCtrl.handleEvent(evKey0).consume);
  assert(demoCtrl.tracker.model.activePage == 9);
  assert(demoCtrl.tabsTracker.model.activeTab == 9);
}
