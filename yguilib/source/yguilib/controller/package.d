module yguilib.controller;
import yguilib.events : AppEvent;
import yguilib.timers : TimerId, TimerMode, invalidTimerId;
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
  @property bool isModal() const;
  void setModal(bool value);

  void sendAppEvent(AppEvent ev);

  /// Called when a widget is released so controllers can clean up references.
  void onWidgetReleased(Widget w);
}

/// Base controller implementing default quit and redraw handling.
class DefaultController : Controller {

  @disable this();

  this(UiSystem uiSystem) {
    assert(uiSystem !is null, "uiSystem must not be null");
    this.uiSystem = uiSystem;
  }

  override bool update() {
    return false;
  }

  override bool onTimer(TimerId id, float dt) {
    return false;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.windowClose ||
        ev.kind == AppEvent.Kind.appQuit)
      return HandleResult(HandleResult.Result.quit);
    if (ev.isWindowRedrawEvent())
      return HandleResult(HandleResult.Result.updateView);

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
  @property override bool isModal() const {
    return isModal_;
  }
  override void setModal(bool value) {
    isModal_ = value;
  }

  override void onWidgetReleased(Widget w) {
  }

  override void sendAppEvent(AppEvent ev) {
    uiSystem.sendAppEvent(ev);
  }

  /// request additional update (e.g. when thread updated the model, or there's
  /// shared model in controllers)
  void sendUpdate() {
    sendAppEvent(AppEvent.makeNoRepeat(AppEvent.Kind.update));
  }

  void sendQuit() {
    sendAppEvent(AppEvent(AppEvent.Kind.appQuit));
  }
protected:
  TimerId startTimer(
    uint intervalMs,
    TimerMode mode
  ) {
    if (uiSystem is null) {
      return invalidTimerId;
    }
    return uiSystem.startTimer(this, intervalMs, mode);
  }

  void stopTimer(ref TimerId id) {
    if (id != invalidTimerId && uiSystem !is null) {
      uiSystem.stopTimer(id);
    }
    id = invalidTimerId;
  }

  UiSystem uiSystem;
private:
  bool isModal_ = false;
}
