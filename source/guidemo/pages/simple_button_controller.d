/**
 * simple_button_controller.d - Page 9 controller for the plain push
 * button showcase.
 */
module guidemo.pages.simple_button_controller;

import guidemo.common : PageControllerParams, syncPageShellView,
  syncPageStatus;
import guidemo.model : DemoModel, DemoPage, SimpleButtonPageModel;
import guidemo.pages.simple_button_page : SimpleButtonPage,
  simpleBtnAutoEvent, simpleBtnDangerEvent, simpleBtnFixedEvent,
  simpleBtnPrimaryEvent, simpleBtnSecondaryEvent, simpleBtnTargetEvent,
  simpleBtnToggleEvent;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker;

/// Parameters for constructing SimpleButtonPageController.
alias SimpleButtonPageControllerParams =
  PageControllerParams!(SimpleButtonPage, ModelTracker!SimpleButtonPageModel);

/// Controller counting button clicks and toggling the target button.
final class SimpleButtonPageController : DefaultController {
  @disable this();

  /// Constructs the controller from fluent `params`.
  this(ref SimpleButtonPageControllerParams params) {
    assert(params.ui !is null, "ui must not be null");
    assert(params.page !is null, "page must not be null");
    super(params.ui);
    this.demoTracker = ModelTracker!DemoModel.from(params.demoTracker);
    this.tracker = ModelTracker!SimpleButtonPageModel.from(params.trackers);
    this.page = params.page;
    syncPageShellView(
      this.demoTracker.model,
      DemoPage.simpleButton,
      page.rootWidget()
    );
    syncPageStatus(
      this.demoTracker,
      DemoPage.simpleButton,
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
      DemoPage.simpleButton,
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
      DemoPage.simpleButton,
      page.rootWidget()
    );
    return true;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind != AppEvent.Kind.view) {
      return super.handleEvent(ev);
    }

    const string eventName = ev.view.eventName;
    if (eventName == simpleBtnToggleEvent) {
      auto m = tracker.edit();
      m.targetEnabled = !m.targetEnabled;
      m.lastAction = m.targetEnabled ? "enable" : "disable";
      tracker.commit(m);
      return HandleResult(HandleResult.Result.update, true);
    }
    const string action = actionFromEventName(eventName);
    if (action.length == 0) {
      return super.handleEvent(ev);
    }
    auto m = tracker.edit();
    m.clickCount++;
    m.lastAction = action;
    tracker.commit(m);
    return HandleResult(HandleResult.Result.update, true);
  }

private:
  /// Returns the action label of a counting button event, or empty.
  static string actionFromEventName(string eventName) {
    switch (eventName) {
    case simpleBtnPrimaryEvent:
      return "primary";
    case simpleBtnSecondaryEvent:
      return "secondary";
    case simpleBtnDangerEvent:
      return "danger";
    case simpleBtnTargetEvent:
      return "target";
    case simpleBtnFixedEvent:
      return "fixed";
    case simpleBtnAutoEvent:
      return "auto";
    default:
      return null;
    }
  }

  ModelTracker!DemoModel demoTracker;
  ModelTracker!SimpleButtonPageModel tracker;
  SimpleButtonPage page;
}

unittest {
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  auto ui = new UiSystemImpl(null);
  auto root = new Widget(ui.nextWidgetId());
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto pageTracker =
    ModelTracker!SimpleButtonPageModel(new SimpleButtonPageModel());
  auto page = new SimpleButtonPage(ui, root, pageTracker);
  SimpleButtonPageControllerParams params;
  params.withUi(ui)
    .withDemoTracker(demoTracker)
    .withTrackers(pageTracker)
    .withPage(page);
  auto ctrl = new SimpleButtonPageController(params);
  assert(page.primaryButton().inputEnabled);
  assert(page.targetButton().inputEnabled);
  assert(page.toggleButton().inputEnabled);

  // Style buttons count clicks and record the last action.
  auto primaryEv = ViewAppEventBuilder(simpleBtnPrimaryEvent).build();
  assert(ctrl.handleEvent(primaryEv).consume);
  auto dangerEv = ViewAppEventBuilder(simpleBtnDangerEvent).build();
  const hrDanger = ctrl.handleEvent(dangerEv);
  assert(hrDanger.result == HandleResult.Result.update);
  assert(hrDanger.consume);
  assert(pageTracker.model.clickCount == 2);
  assert(pageTracker.model.lastAction == "danger");

  // Toggle disables the target button after updateView.
  auto toggleEv = ViewAppEventBuilder(simpleBtnToggleEvent).build();
  assert(ctrl.handleEvent(toggleEv).consume);
  assert(!pageTracker.model.targetEnabled);
  assert(ctrl.update());
  ctrl.updateView();
  assert(!page.targetButton().inputEnabled);
  assert(page.formatTargetState() == "Target button: disabled");
  assert(page.formatStatus() ==
    "Clicks: 2 | Last: disable | Target: disabled");

  // Toggling again re-enables it; target clicks count.
  ctrl.handleEvent(toggleEv);
  ctrl.update();
  ctrl.updateView();
  assert(page.targetButton().inputEnabled);
  auto targetEv = ViewAppEventBuilder(simpleBtnTargetEvent).build();
  assert(ctrl.handleEvent(targetEv).consume);
  assert(pageTracker.model.clickCount == 3);
  assert(page.formatStats() == "Clicks: 3 | Last action: target");

  // Unrelated event is not consumed.
  auto otherEv = ViewAppEventBuilder("btnCountAction").build();
  auto hrOther = ctrl.handleEvent(otherEv);
  assert(hrOther.result == HandleResult.Result.nothing);
  assert(!hrOther.consume);

  // Page visibility follows DemoModel.activePage.
  assert(!page.isVisible());
  auto dm = demoTracker.edit();
  dm.activePage = DemoPage.simpleButton;
  demoTracker.commit(dm);
  assert(ctrl.update());
  ctrl.updateView();
  assert(page.isVisible());
}
