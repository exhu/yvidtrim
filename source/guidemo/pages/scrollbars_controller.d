/**
 * scrollbars_controller.d - Page 6 controller for Scrollbars showcase.
 */
module guidemo.pages.scrollbars_controller;

import guidemo.common : PageControllerParams, syncPageShellView,
  syncPageStatus;
import guidemo.model : DemoModel, DemoPage, ScrollbarsPageModel;
import guidemo.pages.scrollbars_page : ScrollbarsPage, ScrollbarsPageTrackers,
  page6HorizScrollEvent, page6LiveScrollEvent, page6NarrowBarEvent,
  page6PlaygroundScrollEvent, page6RangeToggleEvent, page6ReleaseScrollEvent,
  page6ResetBarEvent, page6VertScrollEvent, page6VisDecEvent,
  page6VisIncEvent, page6WidenBarEvent, playgroundDefaultWidth;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.controls.scrollbars : ScrollbarModel;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker;

/// Parameters for constructing ScrollbarsPageController.
alias ScrollbarsPageControllerParams =
  PageControllerParams!(ScrollbarsPage, ScrollbarsPageTrackers);

/// Minimum playground scrollbar width in pixels.
enum float playgroundMinWidth = 260.0f;
/// Playground scrollbar width change per narrow/widen click.
enum float playgroundWidthStep = 75.0f;

/// Controller handling Page 6 scrollbar position and playground events.
final class ScrollbarsPageController : DefaultController {
  @disable this();

  /// Constructs the controller from fluent `params`.
  this(ref ScrollbarsPageControllerParams params) {
    assert(params.ui !is null, "ui must not be null");
    assert(params.page !is null, "page must not be null");
    super(params.ui);
    this.demoTracker = ModelTracker!DemoModel.from(params.demoTracker);
    this.tracker = ModelTracker!ScrollbarsPageModel.from(
      params.trackers.page
    );
    this.playgroundTracker = ModelTracker!ScrollbarModel.from(
      params.trackers.playground
    );
    this.page = params.page;
    syncPageShellView(
      this.demoTracker.model,
      DemoPage.scrollbars,
      page.rootWidget()
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
    const bool playgroundChanged = playgroundTracker.update();
    const bool statusChanged = syncPageStatus(
      demoTracker,
      DemoPage.scrollbars,
      page.formatStatus()
    );
    if (statusChanged) {
      demoTracker.update();
    }
    return demoChanged || pageChanged || playgroundChanged ||
      statusChanged;
  }

  override bool updateView() {
    page.update();
    syncPageShellView(
      demoTracker.model,
      DemoPage.scrollbars,
      page.rootWidget()
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
    if (eventName == page6VisDecEvent) {
      shrinkVisibleSize();
    } else if (eventName == page6VisIncEvent) {
      growVisibleSize();
    } else if (eventName == page6RangeToggleEvent) {
      togglePlaygroundRange();
    } else if (eventName == page6NarrowBarEvent) {
      commitBarWidth(narrowedWidth(tracker.model.playgroundBarWidth));
    } else if (eventName == page6WidenBarEvent) {
      commitBarWidth(widenedWidth(tracker.model.playgroundBarWidth));
    } else if (eventName == page6ResetBarEvent) {
      resetPlayground();
    } else {
      return false;
    }
    return true;
  }

  /// Halves the playground visible size (min 20).
  void shrinkVisibleSize() {
    auto m = playgroundTracker.edit();
    if (m.visibleSize > 20) {
      m.visibleSize = (m.visibleSize > 100) ? (m.visibleSize / 2) : 20;
    }
    playgroundTracker.commit(m);
  }

  /// Doubles the playground visible size (max 1000).
  void growVisibleSize() {
    auto m = playgroundTracker.edit();
    if (m.visibleSize < 1000) {
      m.visibleSize = (m.visibleSize < 500) ? (m.visibleSize * 2) : 1000;
    }
    playgroundTracker.commit(m);
  }

  /// Toggles the playground range max between 1000 and 10000.
  void togglePlaygroundRange() {
    auto m = playgroundTracker.edit();
    m.max = (m.max <= 1000) ? 10000 : 1000;
    if (m.value > m.max) {
      m.value = m.max;
    }
    playgroundTracker.commit(m);
    syncPlaygroundValue();
  }

  /// Resets the playground scrollbar model and width to defaults.
  void resetPlayground() {
    auto m = playgroundTracker.edit();
    m.min = 0;
    m.max = 1000;
    m.value = 200;
    m.visibleSize = 200;
    m.stepSize = 50;
    playgroundTracker.commit(m);
    commitBarWidth(playgroundDefaultWidth);
    syncPlaygroundValue();
  }

  /// Copies the playground scrollbar value into the page model.
  void syncPlaygroundValue() {
    auto model = tracker.edit();
    model.playgroundValue = playgroundTracker.model.value;
    tracker.commit(model);
  }

  /// Stores the playground bar `width` in the page model.
  void commitBarWidth(float width) {
    auto model = tracker.edit();
    model.playgroundBarWidth = width;
    tracker.commit(model);
  }

  /// Returns `width` narrowed by one step (min `playgroundMinWidth`).
  static float narrowedWidth(float width) {
    if (width <= playgroundMinWidth) {
      return width;
    }
    const float w = width - playgroundWidthStep;
    return (w < playgroundMinWidth) ? playgroundMinWidth : w;
  }

  /// Returns `width` widened by one step (max `playgroundDefaultWidth`).
  static float widenedWidth(float width) {
    if (width >= playgroundDefaultWidth) {
      return width;
    }
    const float w = width + playgroundWidthStep;
    return (w > playgroundDefaultWidth) ? playgroundDefaultWidth : w;
  }

  ModelTracker!DemoModel demoTracker;
  ModelTracker!ScrollbarsPageModel tracker;
  ModelTracker!ScrollbarModel playgroundTracker;
  ScrollbarsPage page;
}

unittest {
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.uisystem : UiSystem, makeHeadlessUiSystem;
  import yguilib.widget : Widget;

  ScrollbarsPageController makeController(
    UiSystem ui,
    Widget root,
    ref ModelTracker!DemoModel demoTracker,
    ref ScrollbarsPageTrackers trackers
  ) {
    auto page = new ScrollbarsPage(ui, root, trackers);
    ScrollbarsPageControllerParams params;
    params.withUi(ui)
      .withDemoTracker(demoTracker)
      .withTrackers(trackers)
      .withPage(page);
    return new ScrollbarsPageController(params);
  }

  auto ui = makeHeadlessUiSystem();
  auto root = new Widget(ui.nextWidgetId());
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto trackers = ScrollbarsPageTrackers.make();
  auto ctrl = makeController(ui, root, demoTracker, trackers);

  auto evHScroll = ViewAppEventBuilder(page6HorizScrollEvent)
    .value(120)
    .build();
  assert(ctrl.handleEvent(evHScroll).consume);
  assert(trackers.page.model.hScroll == 120);

  auto evLive = ViewAppEventBuilder(page6LiveScrollEvent).value(480).build();
  assert(ctrl.handleEvent(evLive).consume);
  assert(trackers.page.model.liveValue == 480);
  assert(trackers.page.model.liveEventCount == 1);

  // Playground mutations edit the shared trackers
  auto evVisDec = ViewAppEventBuilder(page6VisDecEvent).build();
  assert(ctrl.handleEvent(evVisDec).consume);
  assert(trackers.playground.model.visibleSize == 100);
  auto evRange = ViewAppEventBuilder(page6RangeToggleEvent).build();
  assert(ctrl.handleEvent(evRange).consume);
  assert(trackers.playground.model.max == 10000);
  auto evNarrow = ViewAppEventBuilder(page6NarrowBarEvent).build();
  assert(ctrl.handleEvent(evNarrow).consume);
  assert(trackers.page.model.playgroundBarWidth == 495.0f);
  auto evReset = ViewAppEventBuilder(page6ResetBarEvent).build();
  assert(ctrl.handleEvent(evReset).consume);
  assert(trackers.playground.model.max == 1000);
  assert(trackers.playground.model.visibleSize == 200);
  assert(trackers.page.model.playgroundBarWidth == playgroundDefaultWidth);
  assert(trackers.page.model.playgroundValue == 200);

  // Unrelated event is not consumed
  auto evOther = ViewAppEventBuilder("btnCountAction").build();
  auto hrOther = ctrl.handleEvent(evOther);
  assert(hrOther.result == HandleResult.Result.nothing);
  assert(!hrOther.consume);

  // Phase 2 update() syncs page visibility when activePage changes
  auto demoTracker2 = ModelTracker!DemoModel(new DemoModel());
  auto trackers2 = ScrollbarsPageTrackers.make();
  auto ctrl2 = makeController(ui, root, demoTracker2, trackers2);
  assert(!ctrl2.page.visible());
  auto dm = demoTracker2.edit();
  dm.activePage = DemoPage.scrollbars;
  demoTracker2.commit(dm);
  assert(ctrl2.update());
  assert(!ctrl2.update());
  ctrl2.updateView();
  assert(ctrl2.page.visible());
}
