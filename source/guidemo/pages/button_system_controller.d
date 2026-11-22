/**
 * button_system_controller.d - Page 4 controller for AnimatedHoverButtonSystem.
 */
module guidemo.pages.button_system_controller;

import guidemo.common : syncPageShellView, syncPageStatus;
import guidemo.model : ButtonSystemPageModel, DemoModel, DemoPage;
import guidemo.pages.button_system_page : ButtonSystemPage,
  sysBtnCountActionEvent, sysBtnCountResetEvent;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker;
import yguilib.uisystem : UiSystem;

/// Controller handling Page 4 system-driven button action and reset events.
final class ButtonSystemPageController : DefaultController {
  static ButtonSystemPageController createStandalone(
    UiSystem ui,
    ButtonSystemPage page
  ) {
    auto dm = ModelTracker!DemoModel(new DemoModel());
    return new ButtonSystemPageController(ui, dm, page);
  }

  @disable this();

  this(
    UiSystem ui,
    ref ModelTracker!DemoModel demoTracker,
    ButtonSystemPage page
  ) {
    assert(ui !is null, "ui must not be null");
    assert(page !is null, "page must not be null");
    super(ui);
    this.demoTracker = ModelTracker!DemoModel.from(demoTracker);
    this.page = page;
    this.tracker = ModelTracker!ButtonSystemPageModel.from(page.getTracker());
    syncPageShellView(
      this.demoTracker.model,
      DemoPage.buttonSystem,
      page.getRootWidget()
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
      sendUpdate();
    }
    return demoChanged || pageChanged || statusChanged;
  }

  override bool updateView() {
    page.update();
    syncPageShellView(
      demoTracker.model,
      DemoPage.buttonSystem,
      page.getRootWidget()
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
  auto page = new ButtonSystemPage(ui, root);
  auto ctrl = ButtonSystemPageController.createStandalone(ui, page);

  auto evInc = ViewAppEventBuilder(sysBtnCountActionEvent).build();
  auto hrInc = ctrl.handleEvent(evInc);
  assert(hrInc.result == HandleResult.Result.update);
  assert(hrInc.consume);
  assert(page.getTracker().model.buttonClickCount == 1);

  auto evReset = ViewAppEventBuilder(sysBtnCountResetEvent).build();
  auto hrReset = ctrl.handleEvent(evReset);
  assert(hrReset.consume);
  assert(page.getTracker().model.buttonClickCount == 0);

  // Page 3 event is not consumed
  auto evOther = ViewAppEventBuilder("btnCountAction").build();
  auto hrOther = ctrl.handleEvent(evOther);
  assert(hrOther.result == HandleResult.Result.nothing);
  assert(!hrOther.consume);

  // Phase 2 update() syncs page visibility when activePage changes
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto page2 = new ButtonSystemPage(ui, root);
  auto ctrl2 = new ButtonSystemPageController(ui, demoTracker, page2);
  assert(!page2.isVisible());
  auto dm = demoTracker.edit();
  dm.activePage = DemoPage.buttonSystem;
  demoTracker.commit(dm);
  assert(ctrl2.update());
  ctrl2.updateView();
  assert(page2.isVisible());
}
