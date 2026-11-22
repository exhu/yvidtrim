/**
 * button_controller.d - Page 3 controller for HoverButton showcase.
 */
module guidemo.pages.button_controller;

import guidemo.common : syncPageShellView, syncPageStatus;
import guidemo.model : ButtonPageModel, DemoModel, DemoPage;
import guidemo.pages.button_page : ButtonPage, btnCountActionEvent,
  btnCountResetEvent;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker;
import yguilib.uisystem : UiSystem;

/// Controller handling Page 3 button action and reset events.
final class ButtonPageController : DefaultController {
  static ButtonPageController createStandalone(
    UiSystem ui,
    ButtonPage page
  ) {
    auto dm = ModelTracker!DemoModel(new DemoModel());
    return new ButtonPageController(ui, dm, page);
  }

  @disable this();

  this(
    UiSystem ui,
    ref ModelTracker!DemoModel demoTracker,
    ButtonPage page
  ) {
    assert(ui !is null, "ui must not be null");
    assert(page !is null, "page must not be null");
    super(ui);
    this.demoTracker = ModelTracker!DemoModel.from(demoTracker);
    this.page = page;
    this.tracker = ModelTracker!ButtonPageModel.from(page.getTracker());
    syncPageShellView(
      this.demoTracker.model,
      DemoPage.button,
      page.getRootWidget()
    );
    syncPageStatus(
      this.demoTracker,
      DemoPage.button,
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
      DemoPage.button,
      page.formatStatus()
    );
    if (statusChanged) {
      demoTracker.update();
    }
    return demoChanged || pageChanged || statusChanged;
  }

  override bool updateView() {
    page.update();
    syncPageShellView(
      demoTracker.model,
      DemoPage.button,
      page.getRootWidget()
    );
    return true;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind != AppEvent.Kind.view) {
      return super.handleEvent(ev);
    }

    const string eventName = ev.view.eventName;
    if (eventName == btnCountActionEvent) {
      auto model = tracker.edit();
      model.buttonClickCount += 1;
      tracker.commit(model);
      return HandleResult(HandleResult.Result.update, true);
    }
    if (eventName == btnCountResetEvent) {
      auto model = tracker.edit();
      model.buttonClickCount = 0;
      tracker.commit(model);
      return HandleResult(HandleResult.Result.update, true);
    }
    return super.handleEvent(ev);
  }

private:
  ModelTracker!DemoModel demoTracker;
  ModelTracker!ButtonPageModel tracker;
  ButtonPage page;
}

unittest {
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  auto ui = new UiSystemImpl(null);
  auto root = new Widget(ui.nextWidgetId());
  auto page = new ButtonPage(ui, root);
  auto ctrl = ButtonPageController.createStandalone(ui, page);

  auto evInc = ViewAppEventBuilder(btnCountActionEvent).build();
  auto hrInc = ctrl.handleEvent(evInc);
  assert(hrInc.result == HandleResult.Result.update);
  assert(hrInc.consume);
  assert(page.getTracker().model.buttonClickCount == 1);

  auto evReset = ViewAppEventBuilder(btnCountResetEvent).build();
  auto hrReset = ctrl.handleEvent(evReset);
  assert(hrReset.consume);
  assert(page.getTracker().model.buttonClickCount == 0);

  // Unrelated event is not consumed
  auto evOther = ViewAppEventBuilder("sysBtnCountAction").build();
  auto hrOther = ctrl.handleEvent(evOther);
  assert(hrOther.result == HandleResult.Result.nothing);
  assert(!hrOther.consume);

  // Phase 2 update() syncs page visibility when activePage changes
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto page2 = new ButtonPage(ui, root);
  auto ctrl2 = new ButtonPageController(ui, demoTracker, page2);
  assert(!page2.isVisible());
  auto dm = demoTracker.edit();
  dm.activePage = DemoPage.button;
  demoTracker.commit(dm);
  assert(ctrl2.update());
  assert(!ctrl2.update());
  ctrl2.updateView();
  assert(page2.isVisible());
}

// End-to-end App test: verifies single-pass update (no update-after-update)
// and same-frame DemoView status bar sync when DemoController is below page.
unittest {
  import std.algorithm.searching : canFind;
  import guidemo.controller : DemoController, DemoControllerParams;
  import guidemo.view : DemoView, createHeaderTabsModel;
  import yguilib.app : App;
  import yguilib.controls.tabcontrol : TabsModel;
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.model : ModelTracker;
  import yguilib.timercontrol : TimerId, invalidTimerId;
  import yguilib.timers : TimerMode;
  import yguilib.widget : Widget;

  Widget findByName(Widget root, string targetName) {
    if (root is null) {
      return null;
    }
    if (root.name == targetName) {
      return root;
    }
    foreach (child; root.children) {
      if (auto found = findByName(child, targetName)) {
        return found;
      }
    }
    return null;
  }

  auto app = App.makeAppWithTitleWh("button_controller_test", 640, 480);
  auto ui = app.ui;
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto dmInit = demoTracker.edit();
  dmInit.activePage = DemoPage.button;
  demoTracker.commit(dmInit);

  auto tabsTracker = ModelTracker!TabsModel(createHeaderTabsModel());
  auto demoView = new DemoView(ui, demoTracker, tabsTracker);
  auto root = demoView.getRootWidget();
  ui.mainWindow().rootWidget = root;

  DemoControllerParams params;
  params.withUi(ui)
    .withTracker(demoTracker)
    .withView(demoView)
    .withTabsTracker(tabsTracker);
  auto demoCtrl = new DemoController(params);

  auto page = new ButtonPage(ui, root);
  auto btnCtrl = new ButtonPageController(ui, demoTracker, page);

  final class HarnessController : DefaultController {
    int updateCount = 0;
    TimerId checkTimer = invalidTimerId;
    bool passed = false;

    this(UiSystem sys) {
      assert(sys !is null, "sys must not be null");
      super(sys);
    }

    override void onPush() {
      sendAppEvent(ViewAppEventBuilder(btnCountActionEvent).build());
      checkTimer = startTimer(20, TimerMode.repeat);
    }

    override void onPop() {
      stopTimer(checkTimer);
    }

    override bool update() {
      updateCount++;
      return false;
    }

    override bool onTimer(TimerId id, float dt) {
      if (id == invalidTimerId || id != checkTimer) {
        return false;
      }
      if (updateCount >= 1) {
        passed = true;
        stopTimer(checkTimer);
        sendQuit();
      }
      return false;
    }
  }

  ui.pushController(demoCtrl);
  scope (exit) ui.popController();
  ui.pushController(btnCtrl);
  scope (exit) ui.popController();

  auto harness = new HarnessController(ui);
  app.run(harness);

  assert(harness.passed);
  assert(harness.updateCount == 1);
  auto statusLbl = findByName(root, "statusLabel");
  assert(statusLbl !is null && statusLbl.components.textLabel !is null);
  assert(statusLbl.components.textLabel.caption.canFind("Clicks: 1"));
}
