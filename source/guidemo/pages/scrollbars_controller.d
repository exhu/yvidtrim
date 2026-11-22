/**
 * scrollbars_controller.d - Page 6 controller for Scrollbars showcase.
 */
module guidemo.pages.scrollbars_controller;

import guidemo.common : syncPageShellView, syncPageStatus;
import guidemo.model : DemoModel, DemoPage, ScrollbarsPageModel;
import guidemo.pages.scrollbars_page : ScrollbarsPage, page6HorizScrollEvent,
  page6LiveScrollEvent, page6NarrowBarEvent, page6PlaygroundScrollEvent,
  page6RangeToggleEvent, page6ReleaseScrollEvent, page6ResetBarEvent,
  page6VertScrollEvent, page6VisDecEvent, page6VisIncEvent, page6WidenBarEvent;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker;
import yguilib.uisystem : UiSystem;

/// Controller handling Page 6 scrollbar position and playground events.
final class ScrollbarsPageController : DefaultController {
  static ScrollbarsPageController createStandalone(
    UiSystem ui,
    ScrollbarsPage page
  ) {
    auto dm = ModelTracker!DemoModel(new DemoModel());
    return new ScrollbarsPageController(ui, dm, page);
  }

  @disable this();

  this(
    UiSystem ui,
    ref ModelTracker!DemoModel demoTracker,
    ScrollbarsPage page
  ) {
    assert(ui !is null, "ui must not be null");
    assert(page !is null, "page must not be null");
    super(ui);
    this.demoTracker = ModelTracker!DemoModel.from(demoTracker);
    this.page = page;
    this.tracker = ModelTracker!ScrollbarsPageModel.from(page.getTracker());
    syncPageShellView(
      this.demoTracker.model,
      DemoPage.scrollbars,
      page.getRootWidget()
    );
    syncPageStatus(
      this.demoTracker,
      DemoPage.scrollbars,
      page.formatStatus()
    );
  }

  invariant {
    assert(page !is null);
  }

  override bool update() {
    const bool demoChanged = demoTracker.update();
    const bool pageChanged = tracker.update();
    const bool statusChanged = syncPageStatus(
      demoTracker,
      DemoPage.scrollbars,
      page.formatStatus()
    );
    if (statusChanged) {
      sendUpdate();
    }
    return demoChanged || pageChanged || statusChanged;
  }

  override bool updateView() {
    page.update();
    syncPageShellView(
      demoTracker.model,
      DemoPage.scrollbars,
      page.getRootWidget()
    );
    return true;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind != AppEvent.Kind.view) {
      return super.handleEvent(ev);
    }

    const string eventName = ev.view.eventName;
    const long val = cast(long) ev.view.value[0];
    if (handleScrollEvent(eventName, val) || handleMutation(eventName)) {
      return HandleResult(HandleResult.Result.update, true);
    }
    return super.handleEvent(ev);
  }

private:
  bool handleScrollEvent(string eventName, long val) {
    auto model = tracker.edit();
    bool handled = true;
    if (eventName == page6HorizScrollEvent) {
      model.hScroll = val;
    } else if (eventName == page6VertScrollEvent) {
      model.vScroll = val;
    } else if (eventName == page6LiveScrollEvent) {
      model.liveValue = val;
      model.liveEventCount += 1;
    } else if (eventName == page6ReleaseScrollEvent) {
      model.releaseValue = val;
      model.releaseEventCount += 1;
    } else if (eventName == page6PlaygroundScrollEvent) {
      model.playgroundValue = val;
    } else {
      handled = false;
    }
    tracker.commit(model);
    return handled;
  }

  bool handleMutation(string eventName) {
    auto model = tracker.edit();
    bool handled = true;
    if (eventName == page6VisDecEvent) {
      page.shrinkVisibleSize();
    } else if (eventName == page6VisIncEvent) {
      page.growVisibleSize();
    } else if (eventName == page6RangeToggleEvent) {
      page.togglePlaygroundRange();
      model.playgroundValue = page.getPlaygroundValue();
    } else if (eventName == page6NarrowBarEvent) {
      page.narrowPlaygroundBar();
    } else if (eventName == page6WidenBarEvent) {
      page.widenPlaygroundBar();
    } else if (eventName == page6ResetBarEvent) {
      page.resetPlayground();
      model.playgroundValue = page.getPlaygroundValue();
    } else {
      handled = false;
    }
    tracker.commit(model);
    return handled;
  }

  ModelTracker!DemoModel demoTracker;
  ModelTracker!ScrollbarsPageModel tracker;
  ScrollbarsPage page;
}

unittest {
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  auto ui = new UiSystemImpl(null);
  auto root = new Widget(ui.nextWidgetId());
  auto page = new ScrollbarsPage(ui, root, ui);
  auto ctrl = ScrollbarsPageController.createStandalone(ui, page);

  auto evHScroll = ViewAppEventBuilder(page6HorizScrollEvent)
    .value(120)
    .build();
  assert(ctrl.handleEvent(evHScroll).consume);
  assert(page.getTracker().model.hScroll == 120);

  auto evLive = ViewAppEventBuilder(page6LiveScrollEvent).value(480).build();
  assert(ctrl.handleEvent(evLive).consume);
  assert(page.getTracker().model.liveValue == 480);
  assert(page.getTracker().model.liveEventCount == 1);

  // Unrelated event is not consumed
  auto evOther = ViewAppEventBuilder("btnCountAction").build();
  auto hrOther = ctrl.handleEvent(evOther);
  assert(hrOther.result == HandleResult.Result.nothing);
  assert(!hrOther.consume);

  // Phase 2 update() syncs page visibility when activePage changes
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto page2 = new ScrollbarsPage(ui, root, ui);
  auto ctrl2 = new ScrollbarsPageController(ui, demoTracker, page2);
  assert(!page2.isVisible());
  auto dm = demoTracker.edit();
  dm.activePage = DemoPage.scrollbars;
  demoTracker.commit(dm);
  assert(ctrl2.update());
  ctrl2.updateView();
  assert(page2.isVisible());
}
