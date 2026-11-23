/**
 * canvas_controller.d - Page 10 controller for the Canvas 2D API showcase.
 *
 * Runs a ~30 fps controller timer only while the page is active and the
 * model is `animating`; [Space] toggles `animating`. Each tick advances
 * `dashOffset` and `rotation`; the page marks its animated widgets dirty.
 * [I] cycles slot 7 through the interop, image, offscreen and patterns
 * sections; [P] shows the offscreen section and requests an
 * `offscreen-<time>.png` save (performed by the page draw on the main
 * thread). `onPop` releases the page GPU resources while the GL context
 * is still alive.
 */
module guidemo.pages.canvas_controller;

import guidemo.common : PageControllerParams, isKey, pngPathFromPrefixTime,
  syncPageShellView, syncPageStatus;
import guidemo.demo_model_helpers : isPageActive;
import guidemo.model : CanvasPageModel, CanvasSlot7, DemoModel, DemoPage;
import guidemo.pages.canvas_page : CanvasPage;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode, Scancode;
import yguilib.model : ModelTracker;
import yguilib.timercontrol : TimerId, invalidTimerId;
import yguilib.timers : TimerMode;

/// Animation timer interval (~30 fps).
enum uint canvasAnimIntervalMs = 33;
/// Dash offset speed in pixels per second.
enum float canvasDashSpeed = 24.0f;
/// Rotation speed in radians per second.
enum float canvasRotationSpeed = 1.2f;

/// Parameters for constructing CanvasPageController.
alias CanvasPageControllerParams =
  PageControllerParams!(CanvasPage, ModelTracker!CanvasPageModel);

/// Controller animating the Canvas page and toggling it with [Space];
/// [I] cycles the slot 7 sections, [P] saves the offscreen image.
final class CanvasPageController : DefaultController {
  @disable this();

  /// Constructs the controller from fluent `params`.
  this(ref CanvasPageControllerParams params) {
    assert(params.ui !is null, "ui must not be null");
    assert(params.page !is null, "page must not be null");
    super(params.ui);
    this.demoTracker = ModelTracker!DemoModel.from(params.demoTracker);
    this.tracker = ModelTracker!CanvasPageModel.from(params.trackers);
    this.page = params.page;
    syncAnimTimer();
    syncPageShellView(
      this.demoTracker.model,
      DemoPage.canvas,
      page.rootWidget()
    );
    syncPageStatus(this.demoTracker, DemoPage.canvas, page.formatStatus());
  }

  invariant {
    assert(page !is null);
  }

  override void onPop() {
    stopTimer(animTimerId);
    page.releaseGpuResources();
  }

  override bool update() {
    const bool demoChanged = demoTracker.update();
    const bool pageChanged = tracker.update();
    syncAnimTimer();
    const bool statusChanged = syncPageStatus(
      demoTracker,
      DemoPage.canvas,
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
      DemoPage.canvas,
      page.rootWidget()
    );
    return true;
  }

  override bool onTimer(TimerId id, float dt) {
    import std.math : PI;

    if (id == invalidTimerId || id != animTimerId) {
      return false;
    }
    syncAnimTimer();
    if (!wantsAnimation()) {
      return false;
    }
    auto m = tracker.edit();
    m.dashOffset = (m.dashOffset + dt * canvasDashSpeed) % 1000.0f;
    m.rotation = (m.rotation + dt * canvasRotationSpeed) % (2 * PI);
    tracker.commit(m);
    return true;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.keyDown
        && isPageActive(demoTracker.model, DemoPage.canvas)
        && isKey(ev, Keycode.space, Scancode.space)) {
      auto m = tracker.edit();
      m.animating = !m.animating;
      tracker.commit(m);
      syncAnimTimer();
      return HandleResult(HandleResult.Result.update, true);
    }
    if (ev.kind == AppEvent.Kind.keyDown
        && isPageActive(demoTracker.model, DemoPage.canvas)
        && isKey(ev, Keycode.i, Scancode.i)) {
      auto m = tracker.edit();
      m.slot7 = nextSlot7(m.slot7);
      tracker.commit(m);
      return HandleResult(HandleResult.Result.update, true);
    }
    if (ev.kind == AppEvent.Kind.keyDown
        && isPageActive(demoTracker.model, DemoPage.canvas)
        && isKey(ev, Keycode.p, Scancode.p)) {
      requestOffscreenSave();
      return HandleResult(HandleResult.Result.update, true);
    }
    return super.handleEvent(ev);
  }

private:
  /// Returns the slot 7 section after `s` in the [I] cycle.
  static CanvasSlot7 nextSlot7(CanvasSlot7 s) {
    return s == CanvasSlot7.max ? CanvasSlot7.min : cast(CanvasSlot7)(s + 1);
  }

  /// Shows the offscreen section and asks its draw to save a PNG.
  void requestOffscreenSave() {
    import std.datetime.systime : Clock;
    import std.logger : tracef;

    const string path = pngPathFromPrefixTime("offscreen", Clock.currTime());
    tracef("[P]: requesting offscreen save %s", path);
    auto m = tracker.edit();
    m.slot7 = CanvasSlot7.offscreen;
    m.offscreenSavePath = path;
    m.offscreenSaveSerial++;
    tracker.commit(m);
  }

  bool wantsAnimation() {
    return tracker.model.animating
      && isPageActive(demoTracker.model, DemoPage.canvas);
  }

  /// Starts the timer when animation is wanted, stops it otherwise.
  void syncAnimTimer() {
    if (wantsAnimation()) {
      if (animTimerId == invalidTimerId) {
        animTimerId = startTimer(canvasAnimIntervalMs, TimerMode.repeat);
      }
    } else {
      stopTimer(animTimerId);
    }
  }

  ModelTracker!DemoModel demoTracker;
  ModelTracker!CanvasPageModel tracker;
  CanvasPage page;
  TimerId animTimerId = invalidTimerId;
}

unittest {
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  auto ui = new UiSystemImpl(null);
  auto root = new Widget(ui.nextWidgetId());
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto pageTracker = ModelTracker!CanvasPageModel(new CanvasPageModel());
  auto page = new CanvasPage(ui, root, pageTracker);
  CanvasPageControllerParams params;
  params.withUi(ui)
    .withDemoTracker(demoTracker)
    .withTrackers(pageTracker)
    .withPage(page);
  auto ctrl = new CanvasPageController(params);

  AppEvent makeKeyDown(Keycode k, Scancode sc) {
    return AppEvent.keyEvent(
      AppEvent.Kind.keyDown,
      AppEvent.KeyData(1, k, sc)
    );
  }

  // Page hidden: no timer, [Space] not consumed
  assert(!page.isVisible());
  assert(!ui.isTimerActive(ctrl.animTimerId));
  auto hrHidden = ctrl.handleEvent(makeKeyDown(Keycode.space, Scancode.space));
  assert(!hrHidden.consume);
  assert(pageTracker.model.animating);

  // Page shown: timer starts and ticks advance the model
  auto dm = demoTracker.edit();
  dm.activePage = DemoPage.canvas;
  demoTracker.commit(dm);
  assert(ctrl.update());
  ctrl.updateView();
  assert(page.isVisible());
  assert(ui.isTimerActive(ctrl.animTimerId));
  assert(ctrl.onTimer(ctrl.animTimerId, 0.5f));
  assert(pageTracker.model.dashOffset > 0);
  assert(pageTracker.model.rotation > 0);
  assert(page.update());

  // [Space] pauses: timer stops, ticks are ignored
  auto hrSpace = ctrl.handleEvent(makeKeyDown(Keycode.space, Scancode.space));
  assert(hrSpace.consume);
  assert(hrSpace.result == HandleResult.Result.update);
  assert(!pageTracker.model.animating);
  assert(!ui.isTimerActive(ctrl.animTimerId));
  const float rot = pageTracker.model.rotation;
  assert(!ctrl.onTimer(ctrl.animTimerId, 0.5f));
  assert(pageTracker.model.rotation == rot);
  assert(ctrl.update());
  assert(demoTracker.model.statusText.length > 0);

  // [Space] resumes
  ctrl.handleEvent(makeKeyDown(Keycode.space, Scancode.space));
  assert(pageTracker.model.animating);
  assert(ui.isTimerActive(ctrl.animTimerId));

  // [I] cycles images -> offscreen -> patterns -> interop -> images
  assert(pageTracker.model.slot7 == CanvasSlot7.images);
  auto hrI = ctrl.handleEvent(makeKeyDown(Keycode.i, Scancode.i));
  assert(hrI.consume);
  assert(pageTracker.model.slot7 == CanvasSlot7.offscreen);
  assert(ctrl.update());
  assert(demoTracker.model.statusText.length > 0);
  ctrl.handleEvent(makeKeyDown(Keycode.i, Scancode.i));
  assert(pageTracker.model.slot7 == CanvasSlot7.patterns);
  ctrl.handleEvent(makeKeyDown(Keycode.i, Scancode.i));
  assert(pageTracker.model.slot7 == CanvasSlot7.interop);
  ctrl.handleEvent(makeKeyDown(Keycode.i, Scancode.i));
  assert(pageTracker.model.slot7 == CanvasSlot7.images);

  // [P] shows the offscreen section and requests a timestamped PNG save
  {
    import std.algorithm.searching : endsWith, startsWith;

    auto hrP = ctrl.handleEvent(makeKeyDown(Keycode.p, Scancode.p));
    assert(hrP.consume);
    assert(pageTracker.model.slot7 == CanvasSlot7.offscreen);
    assert(pageTracker.model.offscreenSaveSerial == 1);
    const string p = pageTracker.model.offscreenSavePath;
    assert(p.length == "offscreen-YYYYMMDD-HHMMSS.png".length);
    assert(p.startsWith("offscreen-") && p.endsWith(".png"));
    ctrl.handleEvent(makeKeyDown(Keycode.p, Scancode.p));
    assert(pageTracker.model.offscreenSaveSerial == 2);
  }

  // Switching away stops the timer
  dm = demoTracker.edit();
  dm.activePage = DemoPage.knob;
  demoTracker.commit(dm);
  assert(ctrl.update());
  assert(!ui.isTimerActive(ctrl.animTimerId));

  // Unrelated event is not consumed
  auto otherEv = ViewAppEventBuilder("btnCountAction").build();
  assert(!ctrl.handleEvent(otherEv).consume);

  dm = demoTracker.edit();
  dm.activePage = DemoPage.canvas;
  demoTracker.commit(dm);
  ctrl.update();
  ctrl.onPop();
  assert(!ui.isTimerActive(ctrl.animTimerId));
}
