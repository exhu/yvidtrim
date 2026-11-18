/**
 * button_system_controller.d - Page 4 controller for AnimatedHoverButtonSystem.
 */
module guidemo.pages.button_system_controller;

import guidemo.model : ButtonSystemPageModel;
import guidemo.pages.button_system_page : ButtonSystemPage,
  sysBtnCountActionEvent, sysBtnCountResetEvent;
import guidemo.view : DemoView;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker;
import yguilib.uisystem : UiSystem;

/// Controller handling Page 4 system-driven button action and reset events.
final class ButtonSystemPageController : DefaultController {
  this(UiSystem ui, ButtonSystemPage page, DemoView demoView = null) {
    assert(ui !is null, "ui must not be null");
    assert(page !is null, "page must not be null");
    super(ui);
    this.page = page;
    this.tracker = ModelTracker!ButtonSystemPageModel.from(page.getTracker());
    this.demoView = demoView;
  }

  invariant {
    assert(page !is null);
  }

  override bool updateView() {
    page.update();
    if (demoView !is null) {
      demoView.updateStatusBar();
    }
    return true;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind != AppEvent.Kind.view) {
      return HandleResult(HandleResult.Result.nothing);
    }

    const string eventName = ev.view.eventName;
    if (eventName == sysBtnCountActionEvent) {
      auto model = tracker.edit();
      model.buttonClickCount += 1;
      tracker.commit(model);
      return HandleResult(HandleResult.Result.updateView, true);
    }
    if (eventName == sysBtnCountResetEvent) {
      auto model = tracker.edit();
      model.buttonClickCount = 0;
      tracker.commit(model);
      return HandleResult(HandleResult.Result.updateView, true);
    }
    return HandleResult(HandleResult.Result.nothing);
  }

private:
  ModelTracker!ButtonSystemPageModel tracker;
  ButtonSystemPage page;
  DemoView demoView;
}

unittest {
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  auto ui = new UiSystemImpl(null);
  auto root = new Widget(ui.nextWidgetId());
  auto page = new ButtonSystemPage(ui, root);
  auto ctrl = new ButtonSystemPageController(ui, page);

  auto evInc = ViewAppEventBuilder(sysBtnCountActionEvent).build();
  auto hrInc = ctrl.handleEvent(evInc);
  assert(hrInc.result == HandleResult.Result.updateView);
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
}
