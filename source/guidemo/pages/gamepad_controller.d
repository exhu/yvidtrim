/**
 * gamepad_controller.d - Page 11 controller for the Canvas 2D gamepad showcase.
 */
module guidemo.pages.gamepad_controller;

import guidemo.common : PageControllerParams, syncPageShellView,
  syncPageStatus;
import guidemo.model : DemoModel, DemoPage, GamepadPageModel;
import guidemo.pages.gamepad_page : GamepadPage;
import yguilib.controller : DefaultController;
import yguilib.model : ModelTracker;

/// Parameters for constructing GamepadPageController.
alias GamepadPageControllerParams =
  PageControllerParams!(GamepadPage, ModelTracker!GamepadPageModel);

/// Controller synchronizing Page 11 visibility and status bar text.
final class GamepadPageController : DefaultController {
  @disable this();

  /// Constructs the controller from fluent `params`.
  this(ref GamepadPageControllerParams params) {
    assert(params.ui !is null, "ui must not be null");
    assert(params.page !is null, "page must not be null");
    super(params.ui);
    this.demoTracker = ModelTracker!DemoModel.from(params.demoTracker);
    this.tracker = ModelTracker!GamepadPageModel.from(params.trackers);
    this.page = params.page;
    syncPageShellView(
      this.demoTracker.model,
      DemoPage.gamepad,
      page.rootWidget()
    );
    syncPageStatus(
      this.demoTracker,
      DemoPage.gamepad,
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
      DemoPage.gamepad,
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
      DemoPage.gamepad,
      page.rootWidget()
    );
    return true;
  }

private:
  ModelTracker!DemoModel demoTracker;
  ModelTracker!GamepadPageModel tracker;
  GamepadPage page;
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  auto ui = new UiSystemImpl(null);
  auto root = new Widget(ui.nextWidgetId());
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto pageTracker = ModelTracker!GamepadPageModel(new GamepadPageModel());
  auto page = new GamepadPage(ui, root, pageTracker);
  GamepadPageControllerParams params;
  params.withUi(ui)
    .withDemoTracker(demoTracker)
    .withTrackers(pageTracker)
    .withPage(page);
  auto ctrl = new GamepadPageController(params);

  assert(!page.visible());
  assert(demoTracker.model.statusText == "");

  auto dm = demoTracker.edit();
  dm.activePage = DemoPage.gamepad;
  demoTracker.commit(dm);
  assert(ctrl.update());
  assert(demoTracker.model.statusText ==
    "Page 11: Gamepad | Path2d SVG & color helpers (600x400)");
  ctrl.updateView();
  assert(page.visible());

  dm = demoTracker.edit();
  dm.activePage = DemoPage.canvas;
  demoTracker.commit(dm);
  assert(ctrl.update());
  ctrl.updateView();
  assert(!page.visible());
}
