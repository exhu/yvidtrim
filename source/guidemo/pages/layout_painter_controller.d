/**
 * layout_painter_controller.d - Page 1 controller for Layout & Painter demo.
 */
module guidemo.pages.layout_painter_controller;

import guidemo.common : isKey, syncPageShell;
import guidemo.demo_model_helpers : isPageActive;
import guidemo.model : DemoModel, DemoPage, LayoutPainterPageModel;
import guidemo.pages.layout_painter_page : LayoutPainterPage;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode, Scancode;
import yguilib.model : ModelTracker;
import yguilib.timers : AnimationTimer, AnimationWrapMode, TimerId,
  TimerIntervalMs, TimerMode, invalidTimerId;
import yguilib.uisystem : UiSystem;
import yguilib.widget.layout_components : AlignItems, FlexDirection,
  JustifyContent;

/// Controller handling Page 1 keyboard shortcuts and alpha pulse animation.
final class LayoutPainterPageController : DefaultController {
  @disable this();

  this(
    UiSystem ui,
    ref ModelTracker!DemoModel demoTracker,
    LayoutPainterPage page
  ) {
    assert(ui !is null, "ui must not be null");
    assert(page !is null, "page must not be null");
    super(ui);
    this.demoTracker = ModelTracker!DemoModel.from(demoTracker);
    this.page = page;
    this.tracker = ModelTracker!LayoutPainterPageModel.from(page.getTracker());
    alphaTimer.start(1.2f, AnimationWrapMode.pingPong);
    const bool onPage = isPageActive(
      this.demoTracker.model,
      DemoPage.layoutPainter
    );
    alphaTimer.setPause(!onPage);
    wasOnPage1 = onPage;
    syncAlphaTimer();
    syncPageShell(
      this.demoTracker,
      DemoPage.layoutPainter,
      page.getRootWidget(),
      page.formatStatus()
    );
  }

  invariant {
    assert(page !is null);
  }

  override void onPop() {
    stopTickTimer(alphaTimerId);
  }

  override bool updateView() {
    page.update();
    if (syncPageShell(
        demoTracker,
        DemoPage.layoutPainter,
        page.getRootWidget(),
        page.formatStatus()
      )) {
      sendUpdate();
    }
    return true;
  }

  override bool update() {
    const bool demoChanged = demoTracker.update();
    syncAlphaTimer();
    return demoChanged;
  }

  override bool tick(float dt) {
    syncAlphaTimer();
    if (!isPageActive(demoTracker.model, DemoPage.layoutPainter) ||
        alphaTimer.isPaused()) {
      return false;
    }

    alphaTimer.update(dt);
    auto model = tracker.edit();
    model.alphaValue = alphaTimer.map(0.2f, 1.0f);
    tracker.commit(model);
    return tracker.update();
  }

  override HandleResult handleEvent(AppEvent ev) {
    const bool onPage1 = isPageActive(
      demoTracker.model,
      DemoPage.layoutPainter
    );

    if (ev.kind == AppEvent.Kind.keyDown && onPage1) {
      if (handlePageKey(ev)) {
        return HandleResult(HandleResult.Result.updateView, true);
      }
    }

    return super.handleEvent(ev);
  }

private:
  bool handlePageKey(in AppEvent ev) {
    auto model = tracker.edit();
    bool handled = true;
    if (isKey(ev, Keycode.t, Scancode.t)) {
      model.textSampleIndex = (model.textSampleIndex + 1) % 3;
    } else if (isKey(ev, Keycode.d, Scancode.d)) {
      model.direction = model.direction == FlexDirection.row
        ? FlexDirection.column
        : FlexDirection.row;
    } else if (isKey(ev, Keycode.j, Scancode.j)) {
      size_t nextJ = (cast(size_t) model.justify + 1) %
        (JustifyContent.max + 1);
      model.justify = cast(JustifyContent) nextJ;
    } else if (isKey(ev, Keycode.a, Scancode.a)) {
      size_t nextA = (cast(size_t) model.alignItems + 1) %
        (AlignItems.max + 1);
      model.alignItems = cast(AlignItems) nextA;
    } else if (isKey(ev, Keycode.g, Scancode.g)) {
      model.gap = (model.gap >= 24.0f) ? 0.0f : (model.gap + 8.0f);
    } else if (isKey(ev, Keycode.v, Scancode.v)) {
      model.child2Visible = !model.child2Visible;
    } else {
      handled = false;
    }
    tracker.commit(model);
    return handled;
  }

  void syncAlphaTimer() {
    const bool onPage1 = isPageActive(
      demoTracker.model,
      DemoPage.layoutPainter
    );
    if (onPage1 != wasOnPage1) {
      alphaTimer.setPause(!onPage1);
      wasOnPage1 = onPage1;
    }
    if (onPage1 && !alphaTimer.isPaused()) {
      if (alphaTimerId == invalidTimerId) {
        alphaTimerId = startTickTimer(
          TimerIntervalMs.fps60,
          TimerMode.repeat
        );
      }
    } else {
      stopTickTimer(alphaTimerId);
    }
  }

  ModelTracker!DemoModel demoTracker;
  ModelTracker!LayoutPainterPageModel tracker;
  LayoutPainterPage page;
  AnimationTimer alphaTimer;
  TimerId alphaTimerId = invalidTimerId;
  bool wasOnPage1 = true;
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  auto ui = new UiSystemImpl(null);
  auto demoModel = new DemoModel();
  auto demoTracker = ModelTracker!DemoModel(demoModel);
  auto root = new Widget(ui.nextWidgetId());
  auto page = new LayoutPainterPage(ui, root);
  auto ctrl = new LayoutPainterPageController(ui, demoTracker, page);

  AppEvent makeKeyDown(Keycode k, Scancode sc) {
    return AppEvent.keyEvent(
      AppEvent.Kind.keyDown,
      AppEvent.KeyData(1, k, sc)
    );
  }

  assert(ui.isTimerActive(ctrl.alphaTimerId));

  // Page 1 active: [D] toggles FlexDirection and consumes event
  auto hrD = ctrl.handleEvent(makeKeyDown(Keycode.d, Scancode.d));
  assert(hrD.result == HandleResult.Result.updateView);
  assert(hrD.consume);
  assert(page.getTracker().model.direction == FlexDirection.column);

  // Page 1 active: [M] is unrelated and must not be consumed or trigger update
  auto hrM = ctrl.handleEvent(makeKeyDown(Keycode.m, Scancode.m));
  assert(hrM.result == HandleResult.Result.nothing);
  assert(!hrM.consume);

  // Page 1 alpha pulse animates on tick(dt)
  const float alphaBefore = page.getTracker().model.alphaValue;
  assert(ctrl.tick(0.016f));
  assert(page.getTracker().model.alphaValue != alphaBefore);

  // Switch away from Page 1: shortcuts ignored and timer stopped
  auto dm = demoTracker.edit();
  dm.activePage = 1;
  demoTracker.commit(dm);
  assert(!ctrl.tick(0.016f));
  assert(!ui.isTimerActive(ctrl.alphaTimerId));

  auto hrD2 = ctrl.handleEvent(makeKeyDown(Keycode.d, Scancode.d));
  assert(hrD2.result == HandleResult.Result.nothing);
  assert(!hrD2.consume);
  assert(page.getTracker().model.direction == FlexDirection.column);

  // Switch back to Page 1: update() restarts timer
  dm = demoTracker.edit();
  dm.activePage = 0;
  demoTracker.commit(dm);
  assert(ctrl.update());
  assert(ui.isTimerActive(ctrl.alphaTimerId));

  ctrl.onPop();
  assert(!ui.isTimerActive(ctrl.alphaTimerId));
}
