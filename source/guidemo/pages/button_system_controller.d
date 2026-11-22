/**
 * button_system_controller.d - Page 4 controller for AnimatedHoverButtonSystem.
 */
module guidemo.pages.button_system_controller;

import guidemo.common : PageControllerParams, syncPageShellView,
  syncPageStatus;
import guidemo.model : ButtonSystemPageModel, DemoModel, DemoPage;
import guidemo.pages.button_system_page : ButtonSystemPage,
  sysBtnCountActionEvent, sysBtnCountResetEvent;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker;

/// Parameters for constructing ButtonSystemPageController.
alias ButtonSystemPageControllerParams =
  PageControllerParams!(ButtonSystemPage, ModelTracker!ButtonSystemPageModel);

/// Controller handling Page 4 system-driven button action and reset events.
final class ButtonSystemPageController : DefaultController {
  @disable this();

  /// Constructs the controller from fluent `params`.
  this(ref ButtonSystemPageControllerParams params) {
    assert(params.ui !is null, "ui must not be null");
    assert(params.page !is null, "page must not be null");
    super(params.ui);
    this.demoTracker = ModelTracker!DemoModel.from(params.demoTracker);
    this.page = params.page;
    this.tracker = ModelTracker!ButtonSystemPageModel.from(params.trackers);
    syncPageShellView(
      this.demoTracker.model,
      DemoPage.buttonSystem,
      page.rootWidget()
    );
    syncPageStatus(
      this.demoTracker,
      DemoPage.buttonSystem,
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
      DemoPage.buttonSystem,
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
      DemoPage.buttonSystem,
      page.rootWidget()
    );
    return true;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind != AppEvent.Kind.view) {
      return super.handleEvent(ev);
    }

    const string eventName = ev.view.eventName;
    if (eventName == sysBtnCountActionEvent) {
      auto model = tracker.edit();
      model.buttonClickCount += 1;
      tracker.commit(model);
      return HandleResult(HandleResult.Result.update, true);
    }
    if (eventName == sysBtnCountResetEvent) {
      auto model = tracker.edit();
      model.buttonClickCount = 0;
      tracker.commit(model);
      return HandleResult(HandleResult.Result.update, true);
    }
    return super.handleEvent(ev);
  }

private:
  ModelTracker!DemoModel demoTracker;
  ModelTracker!ButtonSystemPageModel tracker;
  ButtonSystemPage page;
}

unittest {
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  auto ui = new UiSystemImpl(null);
  auto root = new Widget(ui.nextWidgetId());
  auto standaloneDemo = ModelTracker!DemoModel(new DemoModel());
  auto pageTracker = ModelTracker!ButtonSystemPageModel(
    new ButtonSystemPageModel()
  );
  auto page = new ButtonSystemPage(ui, root, pageTracker);
  ButtonSystemPageControllerParams params;
  params.withUi(ui)
    .withDemoTracker(standaloneDemo)
    .withTrackers(pageTracker)
    .withPage(page);
  auto ctrl = new ButtonSystemPageController(params);

  auto evInc = ViewAppEventBuilder(sysBtnCountActionEvent).build();
  auto hrInc = ctrl.handleEvent(evInc);
  assert(hrInc.result == HandleResult.Result.update);
  assert(hrInc.consume);
  assert(pageTracker.model.buttonClickCount == 1);

  auto evReset = ViewAppEventBuilder(sysBtnCountResetEvent).build();
  auto hrReset = ctrl.handleEvent(evReset);
  assert(hrReset.consume);
  assert(pageTracker.model.buttonClickCount == 0);

  // Page 3 event is not consumed
  auto evOther = ViewAppEventBuilder("btnCountAction").build();
  auto hrOther = ctrl.handleEvent(evOther);
  assert(hrOther.result == HandleResult.Result.nothing);
  assert(!hrOther.consume);

  // Phase 2 update() syncs page visibility when activePage changes
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto pageTracker2 = ModelTracker!ButtonSystemPageModel(
    new ButtonSystemPageModel()
  );
  auto page2 = new ButtonSystemPage(ui, root, pageTracker2);
  ButtonSystemPageControllerParams params2;
  params2.withUi(ui)
    .withDemoTracker(demoTracker)
    .withTrackers(pageTracker2)
    .withPage(page2);
  auto ctrl2 = new ButtonSystemPageController(params2);
  assert(!page2.isVisible());
  auto dm = demoTracker.edit();
  dm.activePage = DemoPage.buttonSystem;
  demoTracker.commit(dm);
  assert(ctrl2.update());
  assert(!ctrl2.update());
  ctrl2.updateView();
  assert(page2.isVisible());
}
