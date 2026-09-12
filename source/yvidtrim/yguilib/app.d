/** see ./documentation/gui-overview.adoc

 */
module yvidtrim.yguilib.app;



struct AppEvent {
  enum Kind {
    /// user defined global events
    user,
    /// events that are produced by uisystem controls
    ui,
    windowClose,
    appQuit,
  }

  Kind kind;
  uint eventId;
  Object data;
}

class Widget {

}

class Window {
  this(int w, int h, string title) {
    this.w = w;
    this.h = h;
    this.title = title;
  }

  int w;
  int h;
  string title;

  Widget contents;
}

interface Controller {
  enum HandleResult {
    nothing,
    consume,
    quit,
  }

  /// handleEvent may be called more than once before updateView
  HandleResult handleEvent(AppEvent ev);
  void updateView();
  void onPush();
  void onPop();
  void onSuspendByModal();
  void onResumeByModal();
}

class App {
  // TODO controller stack, windows, systems

  /// entry point
  void run(Controller mainController) {

  }

  UiSystem ui;
}

class ViewModel {
    // TODO
}

/// widgets can have this component to mark a root view
class UiEmbeddedController {
  ViewModel[string] params;
  /// exported events, if values are not null/empty then the event is exported
  /// under a new name up the tree
  string[string] events;
  // TODO
}

class UiSystem {

  void pushController(Controller c) {
    // TODO
  }

  void pushModalController(Controller c) {
    // TODO
  }

  void popController() {
    // TODO
  }


}
