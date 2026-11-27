module yguilib.controller;
import yguilib.events : AppEvent;
import yguilib.timercontrol : TimerId, invalidTimerId;
import yguilib.timers : TimerMode;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;

alias HandleResult = Controller.HandleResult;

interface Controller {
  struct HandleResult {
    bool isQuit() const {
      return result == Result.quit;
    }
    bool isUpdateView() const {
      return result == Result.updateView;
    }
    enum Result {
      nothing,
      update,
      updateView,
      quit,
    }
    Result result = Result.nothing;
    /// this controller consumes the event
    bool consume;
  }

  /// handleEvent may be called more than once before updateView or update,
  /// and it should be lightweight and quick.
  /// Move complex event handling to `update` method.
  HandleResult handleEvent(AppEvent ev);

  /// Called once, and then uisystem is called to recheck models and update if
  /// true.
  /// Put view model update code (or calls to ui) there.
  /// Returns true if ui layer should be redrawn.
  bool updateView();

  /// Called in Phase 2 when a model-sync update is requested (`Result.update`
  /// or `sendUpdate()`). Returns true if the view needs updating.
  bool update();

  /**
   * Called independently in Phase 2b for each due timer owned by this
   * controller.
   *
   * May call `sendUpdate()` if model/logic recalculation or view sync is
   * needed, or return `true` to request `updateView()` immediately during
   * the current update step (e.g., preemptive animations regardless of
   * event queue depth). Usually only `Controller.update()` is meant to
   * schedule `updateView()`.
   */
  bool onTimer(TimerId id, float dt);

  void onPush();
  void onPop();
  void onSuspendByModal();
  void onResumeByModal();
  @property bool modal() const;

  void sendAppEvent(AppEvent ev);

  /// Called when a widget is released so controllers can clean up references.
  void onWidgetReleased(Widget w);
}

/// Base controller implementing default quit and redraw handling.
class DefaultController : Controller {

  @disable this();

  this(UiSystem uiSystem) {
    assert(uiSystem !is null, "uiSystem must not be null");
    fUiSystem = uiSystem;
  }

  override bool update() {
    return false;
  }

  override bool onTimer(TimerId id, float dt) {
    return false;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.windowClose ||
        ev.kind == AppEvent.Kind.appQuit) {
      return HandleResult(HandleResult.Result.quit);
    }
    if (ev.isWindowRedrawEvent()) {
      return HandleResult(HandleResult.Result.updateView);
    }

    return HandleResult(HandleResult.Result.nothing);
  }

  override bool updateView() {
    return true;
  }

  override void onPush() {
  }

  override void onPop() {
  }

  override void onSuspendByModal() {
  }

  override void onResumeByModal() {
  }

  @property override bool modal() const {
    return fModal;
  }

  override void onWidgetReleased(Widget w) {
  }

  override void sendAppEvent(AppEvent ev) {
    fUiSystem.sendAppEvent(ev);
  }

  /// Request update for when thread updated the model, or onTimer, or there's
  /// shared model in controllers, usually should not be called from
  /// Controller.update.
  void sendUpdate() {
    sendAppEvent(AppEvent.makeNoRepeat(AppEvent.Kind.update));
  }

  void sendQuit() {
    sendAppEvent(AppEvent(AppEvent.Kind.appQuit));
  }

protected:
  UiSystem uiSystem() {
    return fUiSystem;
  }

  TimerId startTimer(
    uint intervalMs,
    TimerMode mode
  ) {
    return fUiSystem.startControllerTimer(this, intervalMs, mode);
  }

  void stopTimer(ref TimerId id) {
    if (id != invalidTimerId) {
      fUiSystem.stopTimer(id);
      id = invalidTimerId;
    }
  }

private:
  invariant {
    assert(fUiSystem !is null);
  }

  UiSystem fUiSystem;
  bool fModal = false;
}

// Verifies HandleResult helpers and DefaultController fallbacks and timers.
unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto quitRes = HandleResult(HandleResult.Result.quit);
  assert(quitRes.isQuit());
  assert(!quitRes.isUpdateView());

  auto redrawRes = HandleResult(HandleResult.Result.updateView);
  assert(!redrawRes.isQuit());
  assert(redrawRes.isUpdateView());

  auto nothingRes = HandleResult(HandleResult.Result.nothing);
  assert(!nothingRes.isQuit());
  assert(!nothingRes.isUpdateView());

  class TestCtrl : DefaultController {
    this(UiSystem ui) {
      assert(ui !is null);
      super(ui);
    }

    TimerId beginTimer(uint ms, TimerMode mode) {
      return startTimer(ms, mode);
    }

    void endTimer(ref TimerId id) {
      stopTimer(id);
    }

    UiSystem host() {
      return uiSystem();
    }
  }

  auto ui = new UiSystemImpl(null);
  auto ctrl = new TestCtrl(ui);
  assert(ctrl.host() is ui);
  assert(!ctrl.update());
  assert(!ctrl.onTimer(invalidTimerId, 0.016f));
  assert(ctrl.updateView());
  assert(!ctrl.modal());

  assert(ctrl.handleEvent(AppEvent(AppEvent.Kind.windowClose)).isQuit());
  assert(ctrl.handleEvent(AppEvent(AppEvent.Kind.appQuit)).isQuit());
  assert(
    ctrl.handleEvent(
      AppEvent.windowEvent(
        AppEvent.Kind.windowExposed,
        AppEvent.WindowData(0, 0, 0)
      )
    ).isUpdateView()
  );
  auto userRes = ctrl.handleEvent(AppEvent.userEvent(AppEvent.UserData(1)));
  assert(userRes.result == HandleResult.Result.nothing);

  TimerId tid = ctrl.beginTimer(50, TimerMode.oneShot);
  assert(tid != invalidTimerId);
  assert(ui.isTimerActive(tid));
  ctrl.endTimer(tid);
  assert(tid == invalidTimerId);

  ctrl.sendUpdate();
  ctrl.sendQuit();
}
