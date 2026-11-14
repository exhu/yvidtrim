/**
 * controller.d - Interactive keyboard and event controller for guidemo.
 */
module guidemo.controller;

import yguilib.app : App;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode, Scancode;
import yguilib.model : ModelTracker;
import yguilib.widget : WidgetUpdateScope;
import yguilib.widget.drawing_components : DebugDrawComponent, TextLabel;
import yguilib.widget.layout_components : AlignItems, FlexDirection,
  JustifyContent;

import guidemo.model : DemoModel;
import guidemo.pages.textlabel_page : TextLabelPage;
import guidemo.tabcontrol : TabControlWidgetViewController, TabsModel,
  registerTabControl;
import guidemo.view : DemoView, createHeaderTabsModel, headerTabSwitchEvent;

/// Controller handling keyboard shortcuts, animation ticks, and view updates.
final class DemoController : DefaultController {
  this(App app) {
    assert(app !is null);
    super(app.ui);
    this.app = app;
    tabControlController = registerTabControl(app.ui);
    tracker = ModelTracker!DemoModel(new DemoModel);
    tabsTracker = ModelTracker!TabsModel(createHeaderTabsModel());
    view = new DemoView(tracker, tabsTracker, app.ui);
    app.ui.mainWindow().rootWidget = view.getRootWidget();
  }

  override bool updateView() {
    view.update();
    if (tabControlController !is null) {
      tabControlController.updateView();
    }
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
    if (ev.kind == AppEvent.Kind.view) {
      bool consumeViewEvent = true;
      if (handleViewEvent(ev, consumeViewEvent)) {
        HandleResult res;
        res.result = HandleResult.Result.updateView;
        res.consume = consumeViewEvent;
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
        // timeout will abuse rendering
        //res.timeoutMs = 16;
        return res;
      }
    }

    auto res = super.handleEvent(ev);
    return res;
  }

  DemoView getView() {
    return view;
  }

  TabControlWidgetViewController getTabControlController() {
    return tabControlController;
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
      if (idx < 5) {
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
    } else {
      handled = handlePage5ViewEvent(ev, model, consumeEvent);
    }
    const size_t newPage = model.activePage;
    tracker.commit(model);
    if (newPage != prevPage) {
      syncActiveTab(newPage);
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

  bool handleKeyDownEvent(in AppEvent ev) {
    bool consumed = false;
    auto model = tracker.edit();
    const size_t prevPage = model.activePage;

    if (isKey(ev, Keycode.f12, Scancode.f12)) {
      toggleDebugDraw();
      tracker.commit(model);
      return true;
    }
    if (isKey(ev, Keycode.tab, Scancode.tab)) {
      model.activePage = (model.activePage + 1) % 5;
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
    } else {
      consumed = handlePageShortcutKey(ev, model);
    }

    const size_t newPage = model.activePage;
    tracker.commit(model);
    if (newPage != prevPage) {
      syncActiveTab(newPage);
    }
    return consumed;
  }

  void toggleDebugDraw() {
    auto root = app.ui.mainWindow().rootWidget;
    if (root is null) {
      return;
    }
    if (root.components.debugDraw is null) {
      auto comp = new DebugDrawComponent();
      comp.recursive = true;
      root.components.debugDraw = comp;
    } else {
      const bool debugDrawEnabled = root.components.debugDraw.enabled;
      const bool debugDrawHiddenEnabled = root.components.debugDraw.drawHidden;
      if (debugDrawEnabled && debugDrawHiddenEnabled) {
        root.components.debugDraw.enabled = false;
        root.components.debugDraw.drawHidden = false;
      }
      else if (debugDrawEnabled)
        root.components.debugDraw.drawHidden = true;
      else
        root.components.debugDraw.enabled = true;
    }
    root.update(WidgetUpdateScope.visuals);
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

  App app;
  DemoView view;
  TabControlWidgetViewController tabControlController;
  ModelTracker!DemoModel tracker;
  ModelTracker!TabsModel tabsTracker;
}

unittest {
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.window : Window;

  auto win = new Window(1280, 720, "test_demo_controller");
  auto app = new App(win);
  auto demoCtrl = new DemoController(app);

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
}
