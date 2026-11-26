/**
 * virtlist_controller.d - Page 7 controller for VirtList showcase.
 */
module guidemo.pages.virtlist_controller;

import guidemo.common : PageControllerParams, syncPageShellView,
  syncPageStatus;
import guidemo.demo_model_helpers : isPageActive;
import guidemo.model : DemoModel, DemoPage, VirtListPageModel;
import guidemo.pages.virtlist_items : HorizontalItemsModel,
  VerticalItemsModel;
import guidemo.pages.virtlist_page : VirtListPage, VirtListPageTrackers,
  hListDefaultCount, hViewportDefaultWidth, page7ExpandRowEvent,
  page7HorizChangedEvent, page7HorizInsertEvent, page7HorizNarrowEvent,
  page7HorizRemoveEvent, page7HorizResetEvent, page7HorizResizeEvent,
  page7HorizWidenEvent, page7InsertAboveEvent, page7InsertHereEvent,
  page7Jump5000Event, page7RemoveHereEvent, page7ToggleCountEvent,
  page7VertChangedEvent, vListDefaultCount;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.controls.virtlist : VirtListModel;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker;
import yguilib.timercontrol : TimerId, invalidTimerId;
import yguilib.timers : TimerMode;
import yguilib.uisystem : UiSystem;

/// Parameters for constructing VirtListPageController.
alias VirtListPageControllerParams =
  PageControllerParams!(VirtListPage, VirtListPageTrackers);

/// Minimum horizontal VirtList viewport width in pixels.
enum float hViewportMinWidth = 300.0f;
/// Horizontal viewport width change per narrow/widen click.
enum float hViewportWidthStep = 70.0f;
/// Vertical item count used by the 10K / 50 toggle's small dataset.
enum size_t vListSmallCount = 50;

/// Controller handling Page 7 VirtList actions, metrics sync, and video pulse
/// animation timer lifecycle.
final class VirtListPageController : DefaultController {
  @disable this();

  /// Constructs the controller from fluent `params`.
  this(ref VirtListPageControllerParams params) {
    assert(params.ui !is null, "ui must not be null");
    assert(params.page !is null, "page must not be null");
    super(params.ui);
    this.demoTracker = ModelTracker!DemoModel.from(params.demoTracker);
    this.tracker = ModelTracker!VirtListPageModel.from(params.trackers.page);
    this.vListTracker = ModelTracker!VirtListModel.from(
      params.trackers.vList
    );
    this.hListTracker = ModelTracker!VirtListModel.from(
      params.trackers.hList
    );
    this.vItemsTracker = ModelTracker!VerticalItemsModel.from(
      params.trackers.vItems
    );
    this.hItemsTracker = ModelTracker!HorizontalItemsModel.from(
      params.trackers.hItems
    );
    this.page = params.page;
    syncAnimTimer();
    syncPageShellView(
      this.demoTracker.model,
      DemoPage.virtList,
      page.rootWidget()
    );
    syncPageStatus(
      this.demoTracker,
      DemoPage.virtList,
      page.formatStatus()
    );
  }

  invariant {
    assert(page !is null);
  }

  override void onPop() {
    stopTimer(animTimerId);
  }

  override bool update() {
    const bool demoChanged = demoTracker.update();
    const bool telemetryChanged = page.syncTelemetry();
    const bool pageChanged = tracker.update();
    const bool itemsChanged = vItemsTracker.update() |
      hItemsTracker.update();
    syncAnimTimer();
    const bool statusChanged = syncPageStatus(
      demoTracker,
      DemoPage.virtList,
      page.formatStatus()
    );
    if (statusChanged) {
      demoTracker.update();
    }
    return demoChanged || pageChanged || telemetryChanged ||
      itemsChanged || statusChanged;
  }

  override bool updateView() {
    page.update();
    syncPageShellView(
      demoTracker.model,
      DemoPage.virtList,
      page.rootWidget()
    );
    return true;
  }

  override bool onTimer(TimerId id, float dt) {
    if (id == invalidTimerId || id != animTimerId) {
      return false;
    }
    syncAnimTimer();
    if (!isPageActive(demoTracker.model, DemoPage.virtList) ||
        !page.hasActiveVideos()) {
      return false;
    }
    return page.tickAnimations(dt);
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind != AppEvent.Kind.view) {
      return super.handleEvent(ev);
    }

    const string eventName = ev.view.eventName;
    if (eventName == page7VertChangedEvent ||
        eventName == page7HorizChangedEvent) {
      return HandleResult(HandleResult.Result.update, false);
    }

    if (handleVerticalAction(eventName) || handleHorizontalAction(eventName)) {
      return HandleResult(HandleResult.Result.update, true);
    }
    return super.handleEvent(ev);
  }

private:
  bool handleVerticalAction(string eventName) {
    if (eventName == page7ExpandRowEvent) {
      expandVisibleRow();
    } else if (eventName == page7InsertAboveEvent) {
      insertAboveViewport();
    } else if (eventName == page7InsertHereEvent) {
      insertAtCurrent();
    } else if (eventName == page7RemoveHereEvent) {
      removeAtCurrent();
    } else if (eventName == page7ToggleCountEvent) {
      toggleVerticalCount();
    } else if (eventName == page7Jump5000Event) {
      jumpToMiddle();
    } else {
      return false;
    }
    return true;
  }

  bool handleHorizontalAction(string eventName) {
    if (eventName == page7HorizResizeEvent) {
      resizeHorizontalItem();
    } else if (eventName == page7HorizInsertEvent) {
      insertHorizontalClip();
    } else if (eventName == page7HorizRemoveEvent) {
      removeHorizontalClip();
    } else if (eventName == page7HorizNarrowEvent) {
      commitHorizontalViewportWidth(
        narrowedWidth(tracker.model.hViewportWidth)
      );
    } else if (eventName == page7HorizWidenEvent) {
      commitHorizontalViewportWidth(
        widenedWidth(tracker.model.hViewportWidth)
      );
    } else if (eventName == page7HorizResetEvent) {
      resetHorizontalList();
    } else {
      return false;
    }
    return true;
  }

  /// Toggles expanded/oversized dimensions on a visible vertical row.
  void expandVisibleRow() {
    const auto vm = vListTracker.model;
    auto items = vItemsTracker.edit();
    const size_t targetIdx = items.toggleExpandNear(
      vm.firstVisibleIndex, vm.visibleItemsCount
    );
    vItemsTracker.commit(items);
    if (targetIdx == size_t.max) {
      return;
    }
    auto m = vListTracker.edit();
    m.updateItem(targetIdx);
    vListTracker.commit(m);
  }

  /// Inserts a new video row at index 0 to test anchor stability above view.
  void insertAboveViewport() {
    insertVerticalAt(0);
  }

  /// Inserts a new video row at the current first visible index.
  void insertAtCurrent() {
    insertVerticalAt(vListTracker.model.firstVisibleIndex);
  }

  /// Inserts a new video row at `idx` into the items and list models.
  void insertVerticalAt(size_t idx) {
    auto items = vItemsTracker.edit();
    items.insertItemAt(idx);
    vItemsTracker.commit(items);
    auto m = vListTracker.edit();
    m.insertItems(idx, 1);
    vListTracker.commit(m);
  }

  /// Removes the item at the current first visible index.
  void removeAtCurrent() {
    const auto vm = vListTracker.model;
    if (vm.itemsCount == 0) {
      return;
    }
    const size_t idx = vm.firstVisibleIndex < vm.itemsCount
      ? vm.firstVisibleIndex
      : vm.itemsCount - 1;
    auto items = vItemsTracker.edit();
    items.removeItemAt(idx);
    vItemsTracker.commit(items);
    auto m = vListTracker.edit();
    m.removeItems(idx, 1);
    vListTracker.commit(m);
  }

  /// Toggles vertical dataset size between 10,000 and 50 items.
  void toggleVerticalCount() {
    const size_t target = (vListTracker.model.itemsCount > vListSmallCount)
      ? vListSmallCount
      : vListDefaultCount;
    auto items = vItemsTracker.edit();
    items.resetItems(target);
    vItemsTracker.commit(items);
    auto m = vListTracker.edit();
    m.itemsCount = target;
    m.requestScrollToIndex(0);
    vListTracker.commit(m);
  }

  /// Jumps the vertical list directly to index 5000 (or last item).
  void jumpToMiddle() {
    const size_t count = vListTracker.model.itemsCount;
    if (count == 0) {
      return;
    }
    const size_t target = (count > 5000) ? 5000 : (count / 2);
    auto m = vListTracker.edit();
    m.requestScrollToIndex(target);
    vListTracker.commit(m);
  }

  /// Toggles resized/oversized dimensions on a visible horizontal clip card.
  void resizeHorizontalItem() {
    const auto hm = hListTracker.model;
    auto items = hItemsTracker.edit();
    const size_t targetIdx = items.toggleResizeNear(
      hm.firstVisibleIndex, hm.visibleItemsCount
    );
    hItemsTracker.commit(items);
    if (targetIdx == size_t.max) {
      return;
    }
    auto m = hListTracker.edit();
    m.updateItem(targetIdx);
    hListTracker.commit(m);
  }

  /// Inserts a wide GOP segment card at the first visible horizontal index.
  void insertHorizontalClip() {
    const size_t idx = hListTracker.model.firstVisibleIndex;
    auto items = hItemsTracker.edit();
    items.insertItemAt(idx);
    hItemsTracker.commit(items);
    auto m = hListTracker.edit();
    m.insertItems(idx, 1);
    hListTracker.commit(m);
  }

  /// Removes the card at the first visible horizontal index.
  void removeHorizontalClip() {
    const auto hm = hListTracker.model;
    if (hm.itemsCount == 0) {
      return;
    }
    const size_t idx = hm.firstVisibleIndex < hm.itemsCount
      ? hm.firstVisibleIndex
      : hm.itemsCount - 1;
    auto items = hItemsTracker.edit();
    items.removeItemAt(idx);
    hItemsTracker.commit(items);
    auto m = hListTracker.edit();
    m.removeItems(idx, 1);
    hListTracker.commit(m);
  }

  /// Resets horizontal filmstrip items and viewport width.
  void resetHorizontalList() {
    auto items = hItemsTracker.edit();
    items.resetItems(hListDefaultCount);
    hItemsTracker.commit(items);
    auto m = hListTracker.edit();
    m.itemsCount = hListDefaultCount;
    m.updateItems(0, hListDefaultCount);
    m.requestScrollToIndex(0);
    hListTracker.commit(m);
    commitHorizontalViewportWidth(hViewportDefaultWidth);
  }

  /// Stores the horizontal viewport `width` in the page model.
  void commitHorizontalViewportWidth(float width) {
    auto model = tracker.edit();
    model.hViewportWidth = width;
    tracker.commit(model);
  }

  /// Returns `width` narrowed by one step (min `hViewportMinWidth`).
  static float narrowedWidth(float width) {
    if (width <= hViewportMinWidth) {
      return width;
    }
    const float w = width - hViewportWidthStep;
    return (w < hViewportMinWidth) ? hViewportMinWidth : w;
  }

  /// Returns `width` widened by one step (max `hViewportDefaultWidth`).
  static float widenedWidth(float width) {
    if (width >= hViewportDefaultWidth) {
      return width;
    }
    const float w = width + hViewportWidthStep;
    return (w > hViewportDefaultWidth) ? hViewportDefaultWidth : w;
  }

  void syncAnimTimer() {
    const bool onPage = isPageActive(demoTracker.model, DemoPage.virtList);
    const bool active = onPage && page.hasActiveVideos();
    if (active) {
      if (animTimerId == invalidTimerId) {
        animTimerId = startTimer(33, TimerMode.repeat);
      }
    } else {
      stopTimer(animTimerId);
    }
  }

  ModelTracker!DemoModel demoTracker;
  ModelTracker!VirtListPageModel tracker;
  ModelTracker!VirtListModel vListTracker;
  ModelTracker!VirtListModel hListTracker;
  ModelTracker!VerticalItemsModel vItemsTracker;
  ModelTracker!HorizontalItemsModel hItemsTracker;
  VirtListPage page;
  TimerId animTimerId = invalidTimerId;
}

unittest {
  import yguilib.controls.scrollbars : registerScrollbars;
  import yguilib.controls.virtlist : registerVirtList;
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  VirtListPageController makeController(
    UiSystem ui,
    Widget root,
    ref ModelTracker!DemoModel demoTracker,
    ref VirtListPageTrackers trackers
  ) {
    auto page = new VirtListPage(ui, root, trackers);
    VirtListPageControllerParams params;
    params.withUi(ui)
      .withDemoTracker(demoTracker)
      .withTrackers(trackers)
      .withPage(page);
    return new VirtListPageController(params);
  }

  auto ui = new UiSystemImpl(null);
  ui.pushController(registerScrollbars(ui));
  auto vlCtrl = registerVirtList(ui);
  ui.pushController(vlCtrl);

  auto root = new Widget(ui.nextWidgetId());
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto trackers = VirtListPageTrackers.make();
  auto ctrl = makeController(ui, root, demoTracker, trackers);
  auto page = ctrl.page;

  // Initially inactive (Page 1 active): page hidden and timer stopped
  assert(!page.visible());
  assert(!ui.isTimerActive(ctrl.animTimerId));
  assert(trackers.page.model.vItemsCount == 10000);
  assert(trackers.page.model.hItemsCount == 1200);

  // Insert, remove, expand, and horizontal mutations update counts
  assert(
    ctrl.handleEvent(ViewAppEventBuilder(page7InsertAboveEvent).build()).consume
  );
  assert(ctrl.update());
  assert(trackers.page.model.vItemsCount == 10001);

  assert(
    ctrl.handleEvent(ViewAppEventBuilder(page7InsertHereEvent).build()).consume
  );
  assert(ctrl.update());
  assert(trackers.page.model.vItemsCount == 10002);

  assert(
    ctrl.handleEvent(ViewAppEventBuilder(page7RemoveHereEvent).build()).consume
  );
  assert(ctrl.update());
  assert(trackers.page.model.vItemsCount == 10001);

  assert(
    ctrl.handleEvent(ViewAppEventBuilder(page7ExpandRowEvent).build()).consume
  );
  assert(vlCtrl.updateView());

  assert(
    ctrl.handleEvent(
      ViewAppEventBuilder(page7HorizInsertEvent).build()
    ).consume
  );
  assert(ctrl.update());
  assert(trackers.page.model.hItemsCount == 1201);

  assert(
    ctrl.handleEvent(
      ViewAppEventBuilder(page7HorizRemoveEvent).build()
    ).consume
  );
  assert(ctrl.update());
  assert(trackers.page.model.hItemsCount == 1200);

  assert(
    ctrl.handleEvent(ViewAppEventBuilder(page7HorizNarrowEvent).build()).consume
  );
  assert(trackers.page.model.hViewportWidth == 513.0f);
  ctrl.update();
  ctrl.updateView();
  assert(page.horizontalListRoot().rect.width == 513.0f);

  assert(
    ctrl.handleEvent(ViewAppEventBuilder(page7HorizResetEvent).build()).consume
  );
  assert(trackers.hItems.model.itemsLength == hListDefaultCount);
  ctrl.update();
  ctrl.updateView();
  assert(page.horizontalListRoot().rect.width == hViewportDefaultWidth);

  // Toggle count resets the vertical items model
  assert(
    ctrl.handleEvent(ViewAppEventBuilder(page7ToggleCountEvent).build()).consume
  );
  assert(trackers.vItems.model.itemsLength == vListSmallCount);
  assert(trackers.vList.model.itemsCount == vListSmallCount);
  assert(ctrl.update());
  assert(trackers.page.model.vItemsCount == vListSmallCount);

  // Unrelated event is not consumed
  auto hrOther = ctrl.handleEvent(
    ViewAppEventBuilder("btnCountAction").build()
  );
  assert(hrOther.result == HandleResult.Result.nothing);
  assert(!hrOther.consume);

  // Switching activePage to DemoPage.virtList syncs visibility
  auto dm = demoTracker.edit();
  dm.activePage = DemoPage.virtList;
  demoTracker.commit(dm);
  assert(ctrl.update());
  assert(!ctrl.update());
  ctrl.updateView();
  assert(page.visible());

  // Popping controller stops timer cleanly
  ctrl.onPop();
  assert(!ui.isTimerActive(ctrl.animTimerId));
}

// End-to-end App pipeline test: verifies Page 7 activation, 10,000-item
// layout, video animation timer lifecycle, and Jump 5000 recycling.
unittest {
  import yguilib.controls.scrollbars : registerScrollbars;
  import yguilib.controls.virtlist : registerVirtList;
  import yguilib.app : App;
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.widget : Widget;

  auto app = App.makeAppWithTitleWh("virtlist_page_test", 1280, 720);
  auto ui = app.ui;
  ui.pushController(registerScrollbars(ui));
  ui.pushController(registerVirtList(ui));

  auto root = new Widget(ui.nextWidgetId());
  root.name = "testDemoRoot";
  app.withRootWidget(root);

  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto trackers = VirtListPageTrackers.make();
  auto page = new VirtListPage(ui, root, trackers);
  VirtListPageControllerParams params;
  params.withUi(ui)
    .withDemoTracker(demoTracker)
    .withTrackers(trackers)
    .withPage(page);
  auto pageCtrl = new VirtListPageController(params);

  final class Page7HarnessController : DefaultController {
    VirtListPageController target;
    ModelTracker!VirtListPageModel pageTracker;
    int step = 0;
    TimerId pollId = invalidTimerId;
    bool passed = false;

    @disable this();

    this(
      UiSystem sys,
      VirtListPageController targetCtrl,
      ref ModelTracker!VirtListPageModel targetTracker
    ) {
      assert(sys !is null, "sys must not be null");
      assert(targetCtrl !is null, "targetCtrl must not be null");
      super(sys);
      target = targetCtrl;
      pageTracker = ModelTracker!VirtListPageModel.from(targetTracker);
      pollId = startTimer(10, TimerMode.repeat);
    }

    override void onPop() {
      stopTimer(pollId);
    }

    override bool onTimer(TimerId id, float dt) {
      if (id == invalidTimerId || id != pollId) {
        return false;
      }
      if (step == 0) {
        auto dm = target.demoTracker.edit();
        dm.activePage = DemoPage.virtList;
        target.demoTracker.commit(dm);
        sendUpdate();
        step = 1;
        return false;
      }
      if (step == 1) {
        const auto m = trackers.page.model;
        if (m.activeVideosCount > 0 &&
            uiSystem.isTimerActive(target.animTimerId)) {
          assert(target.onTimer(target.animTimerId, 0.05f));
          uiSystem.sendAppEvent(
            ViewAppEventBuilder(page7Jump5000Event).build()
          );
          step = 2;
        }
        return false;
      }
      if (step == 2) {
        const auto m = trackers.page.model;
        if (m.vFirstVisible >= 4900) {
          assert(m.recycledStopsCount > 0);
          auto dm = target.demoTracker.edit();
          dm.activePage = DemoPage.layoutPainter;
          target.demoTracker.commit(dm);
          sendUpdate();
          step = 3;
        }
        return false;
      }
      if (step == 3 && !uiSystem.isTimerActive(target.animTimerId)) {
        passed = true;
        stopTimer(pollId);
        sendQuit();
      }
      return false;
    }
  }

  ui.pushController(pageCtrl);
  auto harness = new Page7HarnessController(
    ui, pageCtrl, trackers.page
  );
  ui.pushController(harness);
  app.run();
  assert(harness.passed);
}
