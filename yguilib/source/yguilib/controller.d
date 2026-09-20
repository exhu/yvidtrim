module yguilib.controller;
import yguilib.events;

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
      consume,
      quit,
      /// do not consume, but still force updateView
      updateView,
    }
    Result result = Result.nothing;

    /// wait for the next event no longer than (<0 = forever)
    /// useful in case of active video playback
    int timeoutMs = -1;
  }

  /// handleEvent may be called more than once before updateView
  HandleResult handleEvent(in AppEvent ev);
  /// called once, and then uisystem is called to recheck models and update
  void updateView();
  void onPush();
  void onPop();
  void onSuspendByModal();
  void onResumeByModal();
  @property bool isModal() const;
  @property void isModal(bool value);

  void sendAppEvent(AppEvent ev);
}

class DefaultController : Controller {
  alias SendAppEventFunc = void delegate(AppEvent ev);

  @disable this();

  this(SendAppEventFunc sendAppEventFunc) {
    this.sendAppEventFunc = sendAppEventFunc;
  }

  override HandleResult handleEvent(in AppEvent ev) {
    if (ev.kind == AppEvent.Kind.windowClose ||
        ev.kind == AppEvent.Kind.appQuit)
      return HandleResult(HandleResult.Result.quit);
    if (ev.kind == AppEvent.Kind.windowResized ||
        ev.kind == AppEvent.Kind.windowExposed ||
        ev.kind == AppEvent.Kind.windowDisplayScaleChanged ||
        ev.kind == AppEvent.Kind.windowRedraw)
      return HandleResult(HandleResult.Result.updateView);
    return HandleResult(HandleResult.Result.nothing);
  }
  override void updateView() {
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
  @property override void isModal(bool value) {
    isModal_ = value;
  }

  override void sendAppEvent(AppEvent ev) {
    assert(sendAppEventFunc !is null);
    sendAppEventFunc(ev);
  }
private:
  bool isModal_ = false;
  SendAppEventFunc sendAppEventFunc;
}
