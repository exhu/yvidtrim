/**
 * controller.d - Shared application controller for guidemo.
 */
module guidemo.controller;

import yguilib.app : App;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode, Scancode;
import yguilib.model : ModelTracker;

import guidemo.common : isKey;
import guidemo.demo_model_helpers : pageCount;
import guidemo.model : DebugDrawMode, DemoModel;
import guidemo.tabcontrol : TabsModel;
import guidemo.view : DemoView, createHeaderTabsModel, headerTabSwitchEvent;

/// Shared controller handling quit, F12 debug draw cycling, and page
/// switching across guidemo.
final class DemoController : DefaultController {
  this(App app) {
    assert(app !is null);
    super(app.ui);
    this.app = app;
    tracker = ModelTracker!DemoModel(new DemoModel);
    tabsTracker = ModelTracker!TabsModel(createHeaderTabsModel());
    view = new DemoView(tracker, tabsTracker, app.ui);
    app.ui.mainWindow().rootWidget = view.getRootWidget();
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
        return HandleResult(HandleResult.Result.updateView, false);
      }
    }

    if (ev.kind == AppEvent.Kind.keyDown) {
      if (isKey(ev, Keycode.q, Scancode.q) ||
          isKey(ev, Keycode.escape, Scancode.escape)) {
        auto model = tracker.edit();
        model.quitRequested = true;
        tracker.commit(model);
        sendQuit();
        return HandleResult(HandleResult.Result.quit, true);
      }
      if (handleGlobalKeyDown(ev)) {
        return HandleResult(HandleResult.Result.updateView, true);
      }
    }

    return super.handleEvent(ev);
  }

  ref ModelTracker!DemoModel getTracker() return {
    return tracker;
  }

  DemoView getView() {
    return view;
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
      sendUpdate();
    }
    return true;
  }

  bool handleGlobalKeyDown(in AppEvent ev) {
    bool consumed = false;
    auto model = tracker.edit();
    const size_t prevPage = model.activePage;

    if (isKey(ev, Keycode.f12, Scancode.f12)) {
      toggleDebugDraw(model);
      tracker.commit(model);
      sendUpdate();
      return true;
    }
    if (isKey(ev, Keycode.tab, Scancode.tab)) {
      model.activePage = (model.activePage + 1) % pageCount();
      consumed = true;
    } else {
      static immutable Keycode[9] keycodes = [
        Keycode.key1, Keycode.key2, Keycode.key3,
        Keycode.key4, Keycode.key5, Keycode.key6,
        Keycode.key7, Keycode.key8, Keycode.key9,
      ];
      static immutable Scancode[9] scancodes = [
        Scancode.key1, Scancode.key2, Scancode.key3,
        Scancode.key4, Scancode.key5, Scancode.key6,
        Scancode.key7, Scancode.key8, Scancode.key9,
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
      sendUpdate();
    }
    return consumed;
  }

  static void toggleDebugDraw(DemoModel model) {
    size_t next = (cast(size_t) model.debugDrawMode + 1) %
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

  App app;
  DemoView view;
  ModelTracker!DemoModel tracker;
  ModelTracker!TabsModel tabsTracker;
}

unittest {
  import yguilib.events.builder : ViewAppEventBuilder;

  auto app = App.makeAppWithTitleWh("test_demo_controller", 1280, 720);
  auto demoCtrl = new DemoController(app);

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
  assert(hrHeader.result == HandleResult.Result.updateView);
  assert(!hrHeader.consume);
  assert(demoCtrl.tracker.model.activePage == 3);
  assert(demoCtrl.tabsTracker.model.activeTab == 3);

  // F12 cycles DebugDrawMode through all 5 states
  assert(demoCtrl.tracker.model.debugDrawMode == DebugDrawMode.off);
  DebugDrawMode[5] expectedModes = [
    DebugDrawMode.allVisible,
    DebugDrawMode.allWithHidden,
    DebugDrawMode.activePageVisible,
    DebugDrawMode.activePageWithHidden,
    DebugDrawMode.off,
  ];
  foreach (expected; expectedModes) {
    auto evF12 = makeKeyDown(Keycode.f12, Scancode.f12);
    auto hrF12 = demoCtrl.handleEvent(evF12);
    assert(hrF12.result == HandleResult.Result.updateView);
    assert(hrF12.consume);
    assert(demoCtrl.tracker.model.debugDrawMode == expected);
  }

  // Page 6 key switch
  auto evKey6 = makeKeyDown(Keycode.key6, Scancode.key6);
  auto hrPage6 = demoCtrl.handleEvent(evKey6);
  assert(hrPage6.consume);
  assert(demoCtrl.tracker.model.activePage == 5);
  assert(demoCtrl.tabsTracker.model.activeTab == 5);
}
