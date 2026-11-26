/**
 * tabcontrol_controller.d - Page 5 controller for TabControl showcase.
 */
module guidemo.pages.tabcontrol_controller;

import guidemo.common : PageControllerParams, syncPageShellView,
  syncPageStatus;
import guidemo.model : DemoModel, DemoPage, TabControlPageModel;
import guidemo.pages.tabcontrol_page : TabControlPage, TabControlPageTrackers,
  defaultDynamicTabNames, dynamicTabSwitchEvent, page5AddTabEvent,
  page5NarrowViewportEvent, page5RemoveTabEvent, page5ResetTabsEvent,
  page5WidenViewportEvent, pageTabSwitchEvent, verticalTabSwitchEvent;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.controls.tabcontrol : TabsModel;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker;

/// Parameters for constructing TabControlPageController.
alias TabControlPageControllerParams =
  PageControllerParams!(TabControlPage, TabControlPageTrackers);

/// Maximum number of dynamic tabs.
enum size_t maxDynamicTabs = 10;
/// Minimum dynamic tab viewport width in pixels.
enum float minViewportWidth = 300.0f;
/// Maximum dynamic tab viewport width in pixels.
enum float maxViewportWidth = 580.0f;
/// Dynamic tab viewport width change per narrow/widen click.
enum float viewportWidthStep = 70.0f;

/// Controller handling Page 5 tab switch and dynamic tab mutation events.
final class TabControlPageController : DefaultController {
  @disable this();

  /// Constructs the controller from fluent `params`.
  this(ref TabControlPageControllerParams params) {
    assert(params.ui !is null, "ui must not be null");
    assert(params.page !is null, "page must not be null");
    super(params.ui);
    this.demoTracker = ModelTracker!DemoModel.from(params.demoTracker);
    this.tracker = ModelTracker!TabControlPageModel.from(
      params.trackers.page
    );
    this.dynamicTabsTracker = ModelTracker!TabsModel.from(
      params.trackers.dynamicTabs
    );
    this.page = params.page;
    syncPageShellView(
      this.demoTracker.model,
      DemoPage.tabControl,
      page.rootWidget()
    );
    syncPageStatus(
      this.demoTracker,
      DemoPage.tabControl,
      page.formatStatus()
    );
  }

  invariant {
    assert(page !is null);
  }

  override bool update() {
    const bool demoChanged = demoTracker.update();
    const bool pageChanged = tracker.update();
    const bool tabsChanged = dynamicTabsTracker.update();
    const bool statusChanged = syncPageStatus(
      demoTracker,
      DemoPage.tabControl,
      page.formatStatus()
    );
    if (statusChanged) {
      demoTracker.update();
    }
    return demoChanged || pageChanged || tabsChanged || statusChanged;
  }

  override bool updateView() {
    page.update();
    syncPageShellView(
      demoTracker.model,
      DemoPage.tabControl,
      page.rootWidget()
    );
    return true;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind != AppEvent.Kind.view) {
      return super.handleEvent(ev);
    }

    const string eventName = ev.view.eventName;
    const size_t idx = cast(size_t) ev.view.value[0];
    if (eventName == pageTabSwitchEvent ||
        eventName == dynamicTabSwitchEvent ||
        eventName == verticalTabSwitchEvent) {
      if (handleTabSwitch(eventName, idx)) {
        return HandleResult(HandleResult.Result.update, false);
      }
      return super.handleEvent(ev);
    }

    if (handleMutation(eventName)) {
      return HandleResult(HandleResult.Result.update, true);
    }
    return super.handleEvent(ev);
  }

private:
  bool handleTabSwitch(string eventName, size_t idx) {
    auto model = tracker.edit();
    model.lastEventName = eventName;
    model.lastEventIndex = idx;
    bool handled = true;
    if (eventName == pageTabSwitchEvent) {
      model.subTab = idx;
    } else if (eventName == dynamicTabSwitchEvent) {
      model.dynamicTab = idx;
    } else if (eventName == verticalTabSwitchEvent) {
      model.verticalTab = idx;
    } else {
      handled = false;
    }
    tracker.commit(model);
    return handled;
  }

  bool handleMutation(string eventName) {
    if (eventName == page5AddTabEvent) {
      addDynamicTab();
    } else if (eventName == page5RemoveTabEvent) {
      removeDynamicTab();
    } else if (eventName == page5ResetTabsEvent) {
      resetDynamicTabs();
    } else if (eventName == page5NarrowViewportEvent) {
      commitViewportWidth(narrowedWidth(tracker.model.viewportWidth));
    } else if (eventName == page5WidenViewportEvent) {
      commitViewportWidth(widenedWidth(tracker.model.viewportWidth));
    } else {
      return false;
    }
    return true;
  }

  /// Appends a new tab to the dynamic TabsModel (up to 10 tabs).
  void addDynamicTab() {
    import std.format : format;

    auto m = dynamicTabsTracker.edit();
    if (m.tabNames.length < maxDynamicTabs) {
      const size_t nextNum = m.tabNames.length + 1;
      m.tabNames ~= format("Clip %d", nextNum);
      m.activeTab = m.tabNames.length - 1;
    }
    dynamicTabsTracker.commit(m);
    syncDynamicTabs();
  }

  /// Removes the last tab from the dynamic TabsModel (down to 1 tab).
  void removeDynamicTab() {
    auto m = dynamicTabsTracker.edit();
    if (m.tabNames.length > 1) {
      m.tabNames = m.tabNames[0 .. $ - 1];
      if (m.activeTab >= m.tabNames.length) {
        m.activeTab = m.tabNames.length - 1;
      }
    }
    dynamicTabsTracker.commit(m);
    syncDynamicTabs();
  }

  /// Resets the dynamic TabsModel back to 6 tabs.
  void resetDynamicTabs() {
    auto m = dynamicTabsTracker.edit();
    m.tabNames = defaultDynamicTabNames();
    m.activeTab = 0;
    dynamicTabsTracker.commit(m);
    syncDynamicTabs();
  }

  /// Copies the dynamic tab count and active tab into the page model.
  void syncDynamicTabs() {
    const auto dm = dynamicTabsTracker.model;
    auto model = tracker.edit();
    model.dynamicTabCount = dm.tabNames.length;
    model.dynamicTab = dm.activeTab;
    tracker.commit(model);
  }

  /// Stores the dynamic tab viewport `width` in the page model.
  void commitViewportWidth(float width) {
    auto model = tracker.edit();
    model.viewportWidth = width;
    tracker.commit(model);
  }

  /// Returns `width` narrowed by one step (min `minViewportWidth`).
  static float narrowedWidth(float width) {
    if (width <= minViewportWidth) {
      return width;
    }
    const float w = width - viewportWidthStep;
    return (w < minViewportWidth) ? minViewportWidth : w;
  }

  /// Returns `width` widened by one step (max `maxViewportWidth`).
  static float widenedWidth(float width) {
    if (width >= maxViewportWidth) {
      return width;
    }
    const float w = width + viewportWidthStep;
    return (w > maxViewportWidth) ? maxViewportWidth : w;
  }

  ModelTracker!DemoModel demoTracker;
  ModelTracker!TabControlPageModel tracker;
  ModelTracker!TabsModel dynamicTabsTracker;
  TabControlPage page;
}

unittest {
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  TabControlPageController makeController(
    UiSystemImpl ui,
    Widget root,
    ref ModelTracker!DemoModel demoTracker,
    ref TabControlPageTrackers trackers
  ) {
    auto page = new TabControlPage(ui, root, trackers);
    TabControlPageControllerParams params;
    params.withUi(ui)
      .withDemoTracker(demoTracker)
      .withTrackers(trackers)
      .withPage(page);
    return new TabControlPageController(params);
  }

  auto ui = new UiSystemImpl(null);
  auto root = new Widget(ui.nextWidgetId());
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto trackers = TabControlPageTrackers.make();
  auto ctrl = makeController(ui, root, demoTracker, trackers);

  // Tab switch events must not be consumed so TabControlWidgetViewController
  // on the stack also receives them.
  auto evSub = ViewAppEventBuilder(pageTabSwitchEvent).value(2).build();
  auto hrSub = ctrl.handleEvent(evSub);
  assert(hrSub.result == HandleResult.Result.update);
  assert(!hrSub.consume);
  assert(trackers.page.model.subTab == 2);

  auto evDyn = ViewAppEventBuilder(dynamicTabSwitchEvent).value(1).build();
  auto hrDyn = ctrl.handleEvent(evDyn);
  assert(hrDyn.result == HandleResult.Result.update);
  assert(!hrDyn.consume);
  assert(trackers.page.model.dynamicTab == 1);

  auto evVert = ViewAppEventBuilder(verticalTabSwitchEvent).value(3).build();
  auto hrVert = ctrl.handleEvent(evVert);
  assert(hrVert.result == HandleResult.Result.update);
  assert(!hrVert.consume);
  assert(trackers.page.model.verticalTab == 3);

  // Mutation events are consumed
  auto evAdd = ViewAppEventBuilder(page5AddTabEvent).build();
  auto hrAdd = ctrl.handleEvent(evAdd);
  assert(hrAdd.result == HandleResult.Result.update);
  assert(hrAdd.consume);
  assert(trackers.page.model.dynamicTabCount == 7);
  assert(trackers.dynamicTabs.model.tabNames.length == 7);
  assert(trackers.page.model.dynamicTab == 6);

  auto evRem = ViewAppEventBuilder(page5RemoveTabEvent).build();
  assert(ctrl.handleEvent(evRem).consume);
  assert(trackers.page.model.dynamicTabCount == 6);
  assert(trackers.page.model.dynamicTab == 5);

  auto evNarrow = ViewAppEventBuilder(page5NarrowViewportEvent).build();
  assert(ctrl.handleEvent(evNarrow).consume);
  assert(trackers.page.model.viewportWidth == 510.0f);
  auto evWiden = ViewAppEventBuilder(page5WidenViewportEvent).build();
  assert(ctrl.handleEvent(evWiden).consume);
  assert(trackers.page.model.viewportWidth == maxViewportWidth);

  auto evReset = ViewAppEventBuilder(page5ResetTabsEvent).build();
  assert(ctrl.handleEvent(evReset).consume);
  assert(trackers.page.model.dynamicTabCount == 6);
  assert(trackers.page.model.dynamicTab == 0);

  // Unrelated event is not consumed
  auto evOther = ViewAppEventBuilder("headerTabSwitch").value(0).build();
  auto hrOther = ctrl.handleEvent(evOther);
  assert(hrOther.result == HandleResult.Result.nothing);
  assert(!hrOther.consume);

  // Phase 2 update() syncs page visibility when activePage changes
  auto demoTracker2 = ModelTracker!DemoModel(new DemoModel());
  auto trackers2 = TabControlPageTrackers.make();
  auto ctrl2 = makeController(ui, root, demoTracker2, trackers2);
  assert(!ctrl2.page.visible());
  auto dm = demoTracker2.edit();
  dm.activePage = DemoPage.tabControl;
  demoTracker2.commit(dm);
  assert(ctrl2.update());
  assert(!ctrl2.update());
  ctrl2.updateView();
  assert(ctrl2.page.visible());
}
