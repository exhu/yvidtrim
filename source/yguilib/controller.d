module yguilib.controller;
import yguilib.events;

interface Controller {
  struct HandleResult {
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
}

class DefaultController : Controller {
  override HandleResult handleEvent(in AppEvent ev) {
    if (ev.kind == AppEvent.Kind.windowClose ||
        ev.kind == AppEvent.Kind.appQuit)
      return HandleResult(HandleResult.Result.quit);
    if (ev.kind == AppEvent.Kind.windowResized ||
        ev.kind == AppEvent.Kind.windowExposed)
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

}
