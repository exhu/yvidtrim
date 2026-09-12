module yvidtrim.yguilib.controller;
import yvidtrim.yguilib.events;

interface Controller {
  struct HandleResult {
    enum Result {
      nothing,
      consume,
      quit,
      /// do not consume, but still force updateView
      updateView,
    }
    Result result;

    /// wait for the next event no longer than (<0 = forever)
    /// useful in case of active video playback
    int timeoutMs = -1;
  }

  /// handleEvent may be called more than once before updateView
  HandleResult handleEvent(AppEvent ev);
  /// called once, and then uisystem is called to recheck models and update
  void updateView();
  void onPush();
  void onPop();
  void onSuspendByModal();
  void onResumeByModal();
}
