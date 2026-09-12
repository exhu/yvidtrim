/** see ./documentation/gui-overview.adoc

 */
module yvidtrim.yguilib.app;

struct AppEvent {
  enum Kind {
    /// user defined global events
    user,
    /// events that are produced by uisystem controls
    view,
    windowClose,
    appQuit,
  }

  Kind kind;
  uint eventId;
  Object data;
}

struct RectF {
  float x = 0;
  float y = 0;
  float w = 1;
  float h = 1;
}

struct ColorF {
  float r, g, b, a = 1.0f;
}

abstract class Component {

}

class Background : Component {
  ColorF color;
}

class InputEnabled : Component {
  bool enabled;
}

/// participates in focus loop
class Focus : Component {
  /// currently in focus, mark one control with true to mark the first focused
  /// item
  bool focused;
}

/// convert event press and release to event with parameter
class KeyboardAction : Component {
  struct Params {
    bool isPressed;
  }
  string[string] keyToAction;
}

/// this button is pressed by enter
class DefaultButton : Component {
}

struct WidgetComponents {
  View view;
  InputEnabled inputEnabled;
  Focus focus;
  DefaultButton defaultButton;
}

class Widget {
  RectF rect;
  WidgetComponents components;
  bool handleInput;
  bool visible;
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

  Widget view;
}

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

class App {
  // TODO controller stack, windows, systems

  /// entry point
  void run(Controller mainController) {

  }

  UiSystem ui;
}

abstract class Model {
  @property uint modelVersion() {
    return version_;
  }

  void mutate(void delegate(Model m) func) {
    func(this);
    version_ += 1;
  }

private:
  uint version_ = 1;
}

struct TrackedModel {
  Model model;
  uint lastSeenVersion;

  bool isChanged() {
    bool changed = model.modelVersion != lastSeenVersion;
    if (changed)
      lastSeenVersion = model.modelVersion;

    return changed;
  }
}

version(none) {
  abstract class BindingExpression {
    enum ReturnType {
      floatValue,
      integerValue,
      boolValue,
      stringValue,
      arrayValue,
      mapValue,
      modelReference,
    }
  }

  final class BindingValue : BindingExpression {
  }
}

// TODO implement code first approach, without symbolic bindings


/// widgets can have this component to mark a root view
abstract class View : Component {
  //TrackedViewModel[string] params;

  /// exported events, if values are not null/empty then the event is exported
  /// under a new name up the tree
  string[string] events;
  // TODO

  /// must update controls
  abstract void update(UiSystem s, Widget w);
}

class UiSystem {

  void pushController(Controller c) {
    controllersStack ~= c;
    // TODO
  }

  void pushModalController(Controller c) {
    controllersStack ~= c;
    // TODO
  }

  void popController() {
    controllersStack = controllersStack[0..$-1];
    // TODO
  }

  void pushFocusRoot(Widget w) {
  }
  void popFocuseRoot() {
  }

  Controller[] controllersStack;
}
