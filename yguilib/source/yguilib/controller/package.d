module yguilib.controller;
import yguilib.events : AppEvent;
import yguilib.uisystem : UiSystem;

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

    /// wait for the next event no longer than (<0 = forever)
    /// useful in case of active video playback
    int timeoutMs = -1;
  }

  /// handleEvent may be called more than once before updateView or update,
  /// and it should be lightweight and quick.
  /// Move complex event handling to `update` method.
  HandleResult handleEvent(AppEvent ev);

  /// Called once, and then uisystem is called to recheck models and update if true.
  /// Put view model update code (or calls to ui) there.
  /// Returns true if ui layer should be redrawn.
  bool updateView();

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

  @disable this();

  this(UiSystem uiSystem) {
    this.uiSystem = uiSystem;
  }

  override bool update() {
    return false;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.windowClose ||
        ev.kind == AppEvent.Kind.appQuit)
      return HandleResult(HandleResult.Result.quit);
    if (ev.isWindowRedrawEvent())
      return HandleResult(HandleResult.Result.updateView);
    if (ev.kind == AppEvent.Kind.update) {
      return HandleResult(
        update() ?
          HandleResult.Result.updateView :
          HandleResult.Result.nothing
      );
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
  @property override bool isModal() const {
    return isModal_;
  }
  @property override void isModal(bool value) {
    isModal_ = value;
  }

  override void sendAppEvent(AppEvent ev) {
    uiSystem.sendAppEvent(ev);
  }

  /// request additional update (e.g. when thread updated the model)
  void sendUpdate() {
    sendAppEvent(AppEvent(AppEvent.Kind.update));
  }

  void sendQuit() {
    sendAppEvent(AppEvent(AppEvent.Kind.appQuit));
  }
private:
  bool isModal_ = false;
  UiSystem uiSystem;
}
