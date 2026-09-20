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
      update,
      updateView,
      quit,
    }
    Result result = Result.nothing;
    /// this controller consumes the event
    bool consume;

    /// wait for the next event no longer than (<0 = forever)
    /// useful in case of active video playback
    int timeoutMs = -1;
  }

  /// handleEvent may be called more than once before updateView or update,
  /// and it should be lightweight and quick.
  /// Move complex event handling to `update` method.
  HandleResult handleEvent(AppEvent ev);
  /// called once, and then uisystem is called to recheck models and update
  /// put view model update code (or calls to ui) there
  void updateView();
  /// return true if the view needs update.
  /// put heavy logic into update.
  bool update();
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

  override bool update() {
    return false;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.windowClose ||
        ev.kind == AppEvent.Kind.appQuit)
      return HandleResult(HandleResult.Result.quit);
    if (ev.kind == AppEvent.Kind.windowResized ||
        ev.kind == AppEvent.Kind.windowExposed ||
        ev.kind == AppEvent.Kind.windowDisplayScaleChanged ||
        ev.kind == AppEvent.Kind.windowRedraw)
      return HandleResult(HandleResult.Result.updateView);
    if (ev.kind == AppEvent.Kind.update)
      return HandleResult(update() ? HandleResult.Result.updateView : HandleResult.Result.nothing);

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

  /// request additional update (e.g. when thread updated the model)
  void sendUpdate() {
    sendAppEvent(AppEvent(AppEvent.kind.update));
  }

  void sendQuit() {
    sendAppEvent(AppEvent(AppEvent.kind.appQuit));
  }
private:
  bool isModal_ = false;
  SendAppEventFunc sendAppEventFunc;
}
