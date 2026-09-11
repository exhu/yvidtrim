module yvidtrim.yguilib.app;

struct AppEvent {
  enum Kind {
    user,
    windowClose,
    appQuit,
  }

  Kind kind;
  int userEvent;
  Object userData;
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
  void onEnter();
  void onLeave();
}

class App {
  // TODO controller stack, windows, systems

  /// entry point
  void run(Controller mainController) {

  }

  UiSystem ui;
}

class UiView {
  Widget root; // = Window.contents

  void update();
}

class UiSystem {


}
