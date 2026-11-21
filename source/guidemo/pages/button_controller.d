/**
 * button_controller.d - Page 3 controller for HoverButton showcase.
 */
module guidemo.pages.button_controller;

import guidemo.common : syncPageShell;
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
    syncPageShell(
      this.demoTracker,
      DemoPage.button,
      page.getRootWidget(),
      page.formatStatus()
    );
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
        DemoPage.button,
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
    if (eventName == btnCountActionEvent) {
      auto model = tracker.edit();
      model.buttonClickCount += 1;
      tracker.commit(model);
      return HandleResult(HandleResult.Result.updateView, true);
    }
    if (eventName == btnCountResetEvent) {
      auto model = tracker.edit();
      model.buttonClickCount = 0;
      tracker.commit(model);
      return HandleResult(HandleResult.Result.updateView, true);
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
  assert(hrInc.result == HandleResult.Result.updateView);
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
  ctrl2.updateView();
  assert(page2.isVisible());
}
