/**
 * tabcontrol_controller.d - Page 5 controller for TabControl showcase.
 */
module guidemo.pages.tabcontrol_controller;

import guidemo.common : syncPageShell;
import guidemo.model : DemoModel, DemoPage, TabControlPageModel;
import guidemo.pages.tabcontrol_page : TabControlPage, dynamicTabSwitchEvent,
  page5AddTabEvent, page5NarrowViewportEvent, page5RemoveTabEvent,
  page5ResetTabsEvent, page5WidenViewportEvent, pageTabSwitchEvent,
  verticalTabSwitchEvent;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;

/// Controller handling Page 5 tab switch and dynamic tab mutation events.
final class TabControlPageController : DefaultController {
  this(
    UiSystem ui,
    ref ModelTracker!DemoModel demoTracker,
    Widget parent
  ) {
    assert(ui !is null, "ui must not be null");
    assert(parent !is null, "parent must not be null");
    this(ui, demoTracker, new TabControlPage(ui, parent, ui));
  }

  this(
    UiSystem ui,
    ref ModelTracker!DemoModel demoTracker,
    TabControlPage page
  ) {
    assert(ui !is null, "ui must not be null");
    assert(page !is null, "page must not be null");
    super(ui);
    this.demoTracker = ModelTracker!DemoModel.from(demoTracker);
    this.page = page;
    this.tracker = ModelTracker!TabControlPageModel.from(page.getTracker());
    syncPageShell(
      this.demoTracker,
      DemoPage.tabControl,
      page.getRootWidget(),
      page.formatStatus()
    );
  }

  this(UiSystem ui, TabControlPage page) {
    auto dm = ModelTracker!DemoModel(new DemoModel());
    this(ui, dm, page);
  }

  invariant {
    assert(page !is null);
  }

  override bool update() {
    return demoTracker.update();
  }

  override bool updateView() {
    page.update();
    if (syncPageShell(
        demoTracker,
        DemoPage.tabControl,
        page.getRootWidget(),
        page.formatStatus()
      )) {
      sendUpdate();
    }
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
        return HandleResult(HandleResult.Result.updateView, false);
      }
      return super.handleEvent(ev);
    }

    if (handleMutation(eventName)) {
      return HandleResult(HandleResult.Result.updateView, true);
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
    auto model = tracker.edit();
    bool handled = true;
    if (eventName == page5AddTabEvent) {
      model.dynamicTabCount = page.addDynamicTab();
      model.dynamicTab = page.getDynamicActiveTab();
    } else if (eventName == page5RemoveTabEvent) {
      model.dynamicTabCount = page.removeDynamicTab();
      model.dynamicTab = page.getDynamicActiveTab();
    } else if (eventName == page5ResetTabsEvent) {
      model.dynamicTabCount = page.resetDynamicTabs();
      model.dynamicTab = page.getDynamicActiveTab();
    } else if (eventName == page5NarrowViewportEvent) {
      model.viewportWidth = page.narrowDynamicViewport();
    } else if (eventName == page5WidenViewportEvent) {
      model.viewportWidth = page.widenDynamicViewport();
    } else {
      handled = false;
    }
    tracker.commit(model);
    if (handled) {
      sendUpdate();
    }
    return handled;
  }

  ModelTracker!DemoModel demoTracker;
  ModelTracker!TabControlPageModel tracker;
  TabControlPage page;
}

unittest {
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  auto ui = new UiSystemImpl(null);
  auto root = new Widget(ui.nextWidgetId());
  auto page = new TabControlPage(ui, root);
  auto ctrl = new TabControlPageController(ui, page);

  // Tab switch events must not be consumed so TabControlWidgetViewController
  // on the stack also receives them.
  auto evSub = ViewAppEventBuilder(pageTabSwitchEvent).value(2).build();
  auto hrSub = ctrl.handleEvent(evSub);
  assert(hrSub.result == HandleResult.Result.updateView);
  assert(!hrSub.consume);
  assert(page.getTracker().model.subTab == 2);

  auto evDyn = ViewAppEventBuilder(dynamicTabSwitchEvent).value(1).build();
  auto hrDyn = ctrl.handleEvent(evDyn);
  assert(hrDyn.result == HandleResult.Result.updateView);
  assert(!hrDyn.consume);
  assert(page.getTracker().model.dynamicTab == 1);

  auto evVert = ViewAppEventBuilder(verticalTabSwitchEvent).value(3).build();
  auto hrVert = ctrl.handleEvent(evVert);
  assert(hrVert.result == HandleResult.Result.updateView);
  assert(!hrVert.consume);
  assert(page.getTracker().model.verticalTab == 3);

  // Mutation events are consumed
  auto evAdd = ViewAppEventBuilder(page5AddTabEvent).build();
  auto hrAdd = ctrl.handleEvent(evAdd);
  assert(hrAdd.result == HandleResult.Result.updateView);
  assert(hrAdd.consume);
  assert(page.getTracker().model.dynamicTabCount == 7);

  // Unrelated event is not consumed
  auto evOther = ViewAppEventBuilder("headerTabSwitch").value(0).build();
  auto hrOther = ctrl.handleEvent(evOther);
  assert(hrOther.result == HandleResult.Result.nothing);
  assert(!hrOther.consume);

  // Phase 2 update() syncs page visibility when activePage changes
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto page2 = new TabControlPage(ui, root);
  auto ctrl2 = new TabControlPageController(ui, demoTracker, page2);
  assert(!page2.isVisible());
  auto dm = demoTracker.edit();
  dm.activePage = DemoPage.tabControl;
  demoTracker.commit(dm);
  assert(ctrl2.update());
  ctrl2.updateView();
  assert(page2.isVisible());
}
