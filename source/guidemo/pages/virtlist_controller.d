/**
 * virtlist_controller.d - Page 7 controller for VirtList showcase.
 */
module guidemo.pages.virtlist_controller;

import guidemo.common : syncPageShellView, syncPageStatus;
import guidemo.demo_model_helpers : isPageActive;
import guidemo.model : DemoModel, DemoPage, VirtListPageModel;
import guidemo.pages.virtlist_page : VirtListPage, page7ExpandRowEvent,
  page7HorizChangedEvent, page7HorizInsertEvent, page7HorizNarrowEvent,
  page7HorizRemoveEvent, page7HorizResetEvent, page7HorizResizeEvent,
  page7HorizWidenEvent, page7InsertAboveEvent, page7InsertHereEvent,
  page7Jump5000Event, page7RemoveHereEvent, page7ToggleCountEvent,
  page7VertChangedEvent;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker;
import yguilib.timercontrol : TimerId, invalidTimerId;
import yguilib.timers : TimerMode;
import yguilib.uisystem : UiSystem;

/// Controller handling Page 7 VirtList actions, metrics sync, and video pulse
/// animation timer lifecycle.
final class VirtListPageController : DefaultController {
  static VirtListPageController createStandalone(
    UiSystem ui,
    VirtListPage page
  ) {
    auto dm = ModelTracker!DemoModel(new DemoModel());
    return new VirtListPageController(ui, dm, page);
  }

  @disable this();

  this(
    UiSystem ui,
    ref ModelTracker!DemoModel demoTracker,
    VirtListPage page
  ) {
    assert(ui !is null, "ui must not be null");
    assert(page !is null, "page must not be null");
    super(ui);
    this.demoTracker = ModelTracker!DemoModel.from(demoTracker);
    this.page = page;
    this.tracker = ModelTracker!VirtListPageModel.from(page.getTracker());
    syncAnimTimer();
    syncPageShellView(
      this.demoTracker.model,
      DemoPage.virtList,
      page.getRootWidget()
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
    syncAnimTimer();
    const bool statusChanged = syncPageStatus(
      demoTracker,
      DemoPage.virtList,
      page.formatStatus()
    );
    if (statusChanged) {
      demoTracker.update();
    }
    return demoChanged || pageChanged || telemetryChanged || statusChanged;
  }

  override bool updateView() {
    page.update();
    syncPageShellView(
      demoTracker.model,
      DemoPage.virtList,
      page.getRootWidget()
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
      page.expandVisibleRow();
    } else if (eventName == page7InsertAboveEvent) {
      page.insertAboveViewport();
    } else if (eventName == page7InsertHereEvent) {
      page.insertAtCurrent();
    } else if (eventName == page7RemoveHereEvent) {
      page.removeAtCurrent();
    } else if (eventName == page7ToggleCountEvent) {
      page.toggleVerticalCount();
    } else if (eventName == page7Jump5000Event) {
      page.jumpToMiddle();
    } else {
      return false;
    }
    return true;
  }

  bool handleHorizontalAction(string eventName) {
    if (eventName == page7HorizResizeEvent) {
      page.resizeHorizontalItem();
    } else if (eventName == page7HorizInsertEvent) {
      page.insertHorizontalClip();
    } else if (eventName == page7HorizRemoveEvent) {
      page.removeHorizontalClip();
    } else if (eventName == page7HorizNarrowEvent) {
      page.narrowHorizontalViewport();
    } else if (eventName == page7HorizWidenEvent) {
      page.widenHorizontalViewport();
    } else if (eventName == page7HorizResetEvent) {
      page.resetHorizontalList();
    } else {
      return false;
    }
    return true;
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
  VirtListPage page;
  TimerId animTimerId = invalidTimerId;
}

unittest {
  import yguilib.controls.scrollbars : registerScrollbars;
  import yguilib.controls.virtlist : registerVirtList;
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  auto ui = new UiSystemImpl(null);
  ui.pushController(registerScrollbars(ui));
  auto vlCtrl = registerVirtList(ui);
  ui.pushController(vlCtrl);

  auto root = new Widget(ui.nextWidgetId());
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto page = new VirtListPage(ui, root, ui);
  auto ctrl = new VirtListPageController(ui, demoTracker, page);

  // Initially inactive (Page 1 active): page hidden and timer stopped
  assert(!page.isVisible());
  assert(!ui.isTimerActive(ctrl.animTimerId));
  assert(page.getTracker().model.vItemsCount == 10000);
  assert(page.getTracker().model.hItemsCount == 1200);

  // Insert, remove, expand, and horizontal mutations update counts
  assert(
    ctrl.handleEvent(ViewAppEventBuilder(page7InsertAboveEvent).build()).consume
  );
  assert(ctrl.update());
  assert(page.getTracker().model.vItemsCount == 10001);

  assert(
    ctrl.handleEvent(ViewAppEventBuilder(page7InsertHereEvent).build()).consume
  );
  assert(ctrl.update());
  assert(page.getTracker().model.vItemsCount == 10002);

  assert(
    ctrl.handleEvent(ViewAppEventBuilder(page7RemoveHereEvent).build()).consume
  );
  assert(ctrl.update());
  assert(page.getTracker().model.vItemsCount == 10001);

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
  assert(page.getTracker().model.hItemsCount == 1201);

  assert(
    ctrl.handleEvent(
      ViewAppEventBuilder(page7HorizRemoveEvent).build()
    ).consume
  );
  assert(ctrl.update());
  assert(page.getTracker().model.hItemsCount == 1200);

  assert(
    ctrl.handleEvent(ViewAppEventBuilder(page7HorizNarrowEvent).build()).consume
  );
  assert(page.getHorizontalListRoot().rect.width < 583.0f);

  assert(
    ctrl.handleEvent(ViewAppEventBuilder(page7HorizResetEvent).build()).consume
  );
  assert(page.getHorizontalListRoot().rect.width == 583.0f);

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
  assert(page.isVisible());

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
  auto page = new VirtListPage(ui, root, ui);
  auto pageCtrl = new VirtListPageController(ui, demoTracker, page);

  final class Page7HarnessController : DefaultController {
    VirtListPageController target;
    VirtListPage page;
    int step = 0;
    TimerId pollId = invalidTimerId;
    bool passed = false;

    this(
      UiSystem sys,
      VirtListPageController targetCtrl,
      VirtListPage targetPage
    ) {
      assert(sys !is null, "sys must not be null");
      assert(targetCtrl !is null, "targetCtrl must not be null");
      assert(targetPage !is null, "targetPage must not be null");
      super(sys);
      target = targetCtrl;
      page = targetPage;
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
        const auto m = page.getTracker().model;
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
        const auto m = page.getTracker().model;
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
  auto harness = new Page7HarnessController(ui, pageCtrl, page);
  ui.pushController(harness);
  app.run();
  assert(harness.passed);
}
