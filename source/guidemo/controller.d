/**
 * controller.d - Shared application controller for guidemo.
 */
module guidemo.controller;

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

  ref DemoControllerParams withUi(UiSystem ui) return {
    this.ui = ui;
    return this;
  }

  ref DemoControllerParams withTracker(
    ref ModelTracker!DemoModel otherTracker
  ) return {
    this.tracker = ModelTracker!DemoModel.from(otherTracker);
    return this;
  }

  ref DemoControllerParams withView(DemoView view) return {
    this.view = view;
    return this;
  }

  ref DemoControllerParams withTabsTracker(
    ref ModelTracker!TabsModel otherTabsTracker
  ) return {
    this.tabsTracker = ModelTracker!TabsModel.from(otherTabsTracker);
    return this;
  }
}

/// Shared controller handling quit, F12 debug draw cycling, and page
/// switching across guidemo.
final class DemoController : DefaultController {
  @disable this();

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
      if (isKey(ev, Keycode.q, Scancode.q) ||
          isKey(ev, Keycode.escape, Scancode.escape)) {
        auto model = tracker.edit();
        model.quitRequested = true;
        tracker.commit(model);
        sendQuit();
        return HandleResult(HandleResult.Result.quit, true);
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

    if (isKey(ev, Keycode.f12, Scancode.f12)) {
      toggleDebugDraw(model);
      tracker.commit(model);
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

  DemoView view;
  ModelTracker!DemoModel tracker;
  ModelTracker!TabsModel tabsTracker;
}

unittest {
  import guidemo.view : createHeaderTabsModel;
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto ui = new UiSystemImpl(null);
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
    assert(hrF12.result == HandleResult.Result.update);
    assert(hrF12.consume);
    assert(demoCtrl.tracker.model.debugDrawMode == expected);
    assert(demoCtrl.update());
    assert(demoCtrl.updateView());
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
}
