/**
 * controller.d - Interactive keyboard and event controller for guidemo.
 */
module guidemo.controller;

import yguilib.app : App;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode, Scancode;
import yguilib.model : ModelTracker;
import yguilib.timers : AnimationTimer, AnimationWrapMode, DeltaTimer;
import yguilib.widget.drawing_components : TextLabel;
import yguilib.widget.layout_components : AlignItems, FlexDirection,
  JustifyContent;

import guidemo.model : DebugDrawMode, DemoModel;
import guidemo.pages.scrollbars_page : page6HScrollEvent,
  page6LiveScrollEvent, page6PlaygroundScrollEvent, page6ReleaseScrollEvent,
  page6VScrollEvent;
import guidemo.pages.textlabel_page : TextLabelPage;
import guidemo.tabcontrol : TabsModel;
import guidemo.view : DemoView, createHeaderTabsModel, headerTabSwitchEvent;

/// Controller handling keyboard shortcuts, animation ticks, and view updates.
final class DemoController : DefaultController {
  this(App app) {
    assert(app !is null);
    super(app.ui);
    this.app = app;
    tracker = ModelTracker!DemoModel(new DemoModel);
    tabsTracker = ModelTracker!TabsModel(createHeaderTabsModel());
    alphaTimer.start(1.2f, AnimationWrapMode.pingPong);
    alphaTimer.setPause(false);
    view = new DemoView(tracker, tabsTracker, app.ui);
    app.ui.mainWindow().rootWidget = view.getRootWidget();
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

    if (model.activePage == 0 && !alphaTimer.isPaused()) {
      const float dt = alphaDeltaTimer.step();
      alphaTimer.update(dt);
      model.alphaValue = alphaTimer.map(0.2f, 1.0f);
    }

    tracker.commit(model);
    return tracker.update();
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.view) {
      bool consumeViewEvent = true;
      if (handleViewEvent(ev, consumeViewEvent)) {
        HandleResult res;
        res.result = HandleResult.Result.updateView;
        res.consume = consumeViewEvent;
        res.timeoutMs = animationTimeoutMs();
        return res;
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
      if (handleKeyDownEvent(ev)) {
        HandleResult res;
        res.result = HandleResult.Result.updateView;
        res.consume = true;
        res.timeoutMs = animationTimeoutMs();
        return res;
      }
    }

    auto res = super.handleEvent(ev);
    if (!res.isQuit()) {
      res.timeoutMs = animationTimeoutMs();
    }
    return res;
  }

  DemoView getView() {
    return view;
  }

private:
  bool handleViewEvent(in AppEvent ev, out bool consumeEvent) {
    consumeEvent = true;
    bool handled = false;
    auto model = tracker.edit();
    const size_t prevPage = model.activePage;
    const auto eventName = ev.view.eventName;
    if (eventName == headerTabSwitchEvent) {
      const size_t idx = cast(size_t) ev.view.value[0];
      if (idx < 6) {
        model.activePage = idx;
      }
      consumeEvent = false;
      handled = true;
    } else if (eventName == "btnCountAction") {
      model.buttonClickCount += 1;
      handled = true;
    } else if (eventName == "btnCountReset") {
      model.buttonClickCount = 0;
      handled = true;
    } else if (handlePage5ViewEvent(ev, model, consumeEvent)) {
      handled = true;
    } else {
      handled = handlePage6ViewEvent(ev, model);
    }
    const size_t newPage = model.activePage;
    tracker.commit(model);
    if (newPage != prevPage) {
      syncActiveTab(newPage);
      syncAlphaTimerForPage(newPage);
    }
    return handled;
  }

  bool handlePage5ViewEvent(
    in AppEvent ev,
    DemoModel model,
    out bool consumeEvent
  ) {
    consumeEvent = true;
    const auto eventName = ev.view.eventName;
    const size_t idx = cast(size_t) ev.view.value[0];
    if (eventName == "pageTabSwitch" ||
        eventName == "dynamicTabSwitch" ||
        eventName == "verticalTabSwitch") {
      return handlePage5TabSwitch(eventName, idx, model, consumeEvent);
    }
    return handlePage5Mutation(eventName, model);
  }

  bool handlePage5TabSwitch(
    string eventName,
    size_t idx,
    DemoModel model,
    out bool consumeEvent
  ) {
    consumeEvent = false;
    model.page5LastEventName = eventName;
    model.page5LastEventIndex = idx;
    if (eventName == "pageTabSwitch") {
      model.page5SubTab = idx;
      return true;
    } else if (eventName == "dynamicTabSwitch") {
      model.page5DynamicTab = idx;
      return true;
    } else if (eventName == "verticalTabSwitch") {
      model.page5VerticalTab = idx;
      return true;
    }
    return false;
  }

  bool handlePage5Mutation(string eventName, DemoModel model) {
    auto p5 = view.getTabControlPage();
    if (eventName == "page5AddTab") {
      model.page5DynamicTabCount = p5.addDynamicTab();
      model.page5DynamicTab = p5.getDynamicActiveTab();
    } else if (eventName == "page5RemoveTab") {
      model.page5DynamicTabCount = p5.removeDynamicTab();
      model.page5DynamicTab = p5.getDynamicActiveTab();
    } else if (eventName == "page5ResetTabs") {
      model.page5DynamicTabCount = p5.resetDynamicTabs();
      model.page5DynamicTab = p5.getDynamicActiveTab();
    } else if (eventName == "page5NarrowViewport") {
      model.page5ViewportWidth = p5.narrowDynamicViewport();
    } else if (eventName == "page5WidenViewport") {
      model.page5ViewportWidth = p5.widenDynamicViewport();
    } else {
      return false;
    }
    sendUpdate();
    return true;
  }

  bool handlePage6ViewEvent(in AppEvent ev, DemoModel model) {
    const string eventName = ev.view.eventName;
    const long val = cast(long) ev.view.value[0];
    if (eventName == page6HScrollEvent) {
      model.page6HScroll = val;
      return true;
    } else if (eventName == page6VScrollEvent) {
      model.page6VScroll = val;
      return true;
    } else if (eventName == page6LiveScrollEvent) {
      model.page6LiveValue = val;
      model.page6LiveEventCount += 1;
      return true;
    } else if (eventName == page6ReleaseScrollEvent) {
      model.page6ReleaseValue = val;
      model.page6ReleaseEventCount += 1;
      return true;
    } else if (eventName == page6PlaygroundScrollEvent) {
      model.page6PlaygroundValue = val;
      return true;
    }
    return handlePage6Mutation(eventName, model);
  }

  bool handlePage6Mutation(string eventName, DemoModel model) {
    auto p6 = view.getScrollbarsPage();
    if (eventName == "page6VisDec") {
      p6.shrinkVisibleSize();
    } else if (eventName == "page6VisInc") {
      p6.growVisibleSize();
    } else if (eventName == "page6RangeToggle") {
      p6.togglePlaygroundRange();
      model.page6PlaygroundValue = p6.getPlaygroundValue();
    } else if (eventName == "page6NarrowBar") {
      p6.narrowPlaygroundBar();
    } else if (eventName == "page6WidenBar") {
      p6.widenPlaygroundBar();
    } else if (eventName == "page6ResetBar") {
      p6.resetPlayground();
      model.page6PlaygroundValue = p6.getPlaygroundValue();
    } else {
      return false;
    }
    sendUpdate();
    return true;
  }

  bool handleKeyDownEvent(in AppEvent ev) {
    bool consumed = false;
    auto model = tracker.edit();
    const size_t prevPage = model.activePage;

    if (isKey(ev, Keycode.f12, Scancode.f12)) {
      toggleDebugDraw(model);
      tracker.commit(model);
      return true;
    }
    if (isKey(ev, Keycode.tab, Scancode.tab)) {
      model.activePage = (model.activePage + 1) % 6;
      consumed = true;
    } else if (isKey(ev, Keycode.key1, Scancode.key1)) {
      model.activePage = 0;
      consumed = true;
    } else if (isKey(ev, Keycode.key2, Scancode.key2)) {
      model.activePage = 1;
      consumed = true;
    } else if (isKey(ev, Keycode.key3, Scancode.key3)) {
      model.activePage = 2;
      consumed = true;
    } else if (isKey(ev, Keycode.key4, Scancode.key4)) {
      model.activePage = 3;
      consumed = true;
    } else if (isKey(ev, Keycode.key5, Scancode.key5)) {
      model.activePage = 4;
      consumed = true;
    } else if (isKey(ev, Keycode.key6, Scancode.key6)) {
      model.activePage = 5;
      consumed = true;
    } else {
      consumed = handlePageShortcutKey(ev, model);
    }

    const size_t newPage = model.activePage;
    tracker.commit(model);
    if (newPage != prevPage) {
      syncActiveTab(newPage);
      syncAlphaTimerForPage(newPage);
      sendUpdate();
    }
    return consumed;
  }

  static void toggleDebugDraw(DemoModel model) {
    size_t next = (cast(size_t) model.debugDrawMode + 1) %
      (DebugDrawMode.max + 1);
    model.debugDrawMode = cast(DebugDrawMode) next;
  }

  static bool handlePageShortcutKey(in AppEvent ev, DemoModel model) {
    if (isKey(ev, Keycode.m, Scancode.m)) {
      model.labelMultiline = !model.labelMultiline;
      return true;
    } else if (isKey(ev, Keycode.e, Scancode.e)) {
      model.labelEllipsis = !model.labelEllipsis;
      return true;
    } else if (isKey(ev, Keycode.l, Scancode.l)) {
      size_t nextAlign = (cast(size_t)model.labelAlignment + 1) % 3;
      model.labelAlignment = cast(TextLabel.Alignment)nextAlign;
      return true;
    } else if (isKey(ev, Keycode.t, Scancode.t)) {
      if (model.activePage == 0) {
        model.textSampleIndex = (model.textSampleIndex + 1) % 3;
      } else {
        model.labelSampleIndex = (model.labelSampleIndex + 1) %
          TextLabelPage.labelInteractiveSamples.length;
      }
      return true;
    } else if (isKey(ev, Keycode.d, Scancode.d)) {
      model.direction = model.direction == FlexDirection.row
        ? FlexDirection.column
        : FlexDirection.row;
      return true;
    } else if (isKey(ev, Keycode.j, Scancode.j)) {
      size_t nextJ = (cast(size_t)model.justify + 1) %
        (JustifyContent.max + 1);
      model.justify = cast(JustifyContent)nextJ;
      return true;
    } else if (isKey(ev, Keycode.a, Scancode.a)) {
      size_t nextA = (cast(size_t)model.alignItems + 1) %
        (AlignItems.max + 1);
      model.alignItems = cast(AlignItems)nextA;
      return true;
    } else if (isKey(ev, Keycode.g, Scancode.g)) {
      model.gap = (model.gap >= 24.0f) ? 0.0f : (model.gap + 8.0f);
      return true;
    } else if (isKey(ev, Keycode.v, Scancode.v)) {
      model.child2Visible = !model.child2Visible;
      return true;
    }
    return false;
  }
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

  void syncActiveTab(size_t pageIdx) {
    if (tabsTracker.model.activeTab != pageIdx) {
      auto tabsModel = tabsTracker.edit();
      tabsModel.activeTab = pageIdx;
      tabsTracker.commit(tabsModel);
    }
  }

  void syncAlphaTimerForPage(size_t newPage) {
    alphaDeltaTimer.reset();
    alphaTimer.setPause(newPage != 0);
  }

  int animationTimeoutMs() {
    if (tracker.model.activePage == 0 && !alphaTimer.isPaused()) {
      return 16;
    }
    return -1;
  }

  App app;
  DemoView view;
  ModelTracker!DemoModel tracker;
  ModelTracker!TabsModel tabsTracker;
  AnimationTimer alphaTimer;
  DeltaTimer alphaDeltaTimer;
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

  // Page 5 TabControl switch events must not be consumed by DemoController so
  // TabControlWidgetViewController on the stack also receives them.
  auto evSub = ViewAppEventBuilder("pageTabSwitch").value(2).build();
  auto hrSub = demoCtrl.handleEvent(evSub);
  assert(hrSub.result == HandleResult.Result.updateView);
  assert(!hrSub.consume);
  assert(demoCtrl.tracker.model.page5SubTab == 2);

  auto evDyn = ViewAppEventBuilder("dynamicTabSwitch").value(1).build();
  auto hrDyn = demoCtrl.handleEvent(evDyn);
  assert(hrDyn.result == HandleResult.Result.updateView);
  assert(!hrDyn.consume);
  assert(demoCtrl.tracker.model.page5DynamicTab == 1);

  auto evVert = ViewAppEventBuilder("verticalTabSwitch").value(3).build();
  auto hrVert = demoCtrl.handleEvent(evVert);
  assert(hrVert.result == HandleResult.Result.updateView);
  assert(!hrVert.consume);
  assert(demoCtrl.tracker.model.page5VerticalTab == 3);

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

  // Page 1 alpha pulse animates with 16ms timeout and pauses off Page 1
  auto evKey1 = makeKeyDown(Keycode.key1, Scancode.key1);
  auto hrPage1 = demoCtrl.handleEvent(evKey1);
  assert(hrPage1.timeoutMs == 16);
  const float alphaBefore = demoCtrl.tracker.model.alphaValue;
  auto hrTick = demoCtrl.handleEvent(AppEvent(AppEvent.Kind.update));
  assert(hrTick.result == HandleResult.Result.updateView);
  assert(hrTick.timeoutMs == 16);
  assert(demoCtrl.tracker.model.alphaValue != alphaBefore);

  auto evKey2 = makeKeyDown(Keycode.key2, Scancode.key2);
  auto hrPage2 = demoCtrl.handleEvent(evKey2);
  assert(hrPage2.timeoutMs == -1);

  // Page 6 key switch & scrollbar event handling
  auto evKey6 = makeKeyDown(Keycode.key6, Scancode.key6);
  auto hrPage6 = demoCtrl.handleEvent(evKey6);
  assert(hrPage6.consume);
  assert(demoCtrl.tracker.model.activePage == 5);
  assert(demoCtrl.tabsTracker.model.activeTab == 5);

  auto evHScroll = ViewAppEventBuilder(page6HScrollEvent).value(120).build();
  assert(demoCtrl.handleEvent(evHScroll).consume);
  assert(demoCtrl.tracker.model.page6HScroll == 120);

  auto evLive = ViewAppEventBuilder(page6LiveScrollEvent).value(480).build();
  assert(demoCtrl.handleEvent(evLive).consume);
  assert(demoCtrl.tracker.model.page6LiveValue == 480);
  assert(demoCtrl.tracker.model.page6LiveEventCount == 1);
}
