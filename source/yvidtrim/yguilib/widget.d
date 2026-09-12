module yvidtrim.yguilib.widget;
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

// TODO implement code first approach, without symbolic bindings


/// widgets can have this component to mark a root view
abstract class View : Component {
  //TrackedViewModel[string] params;

  /// exported events, if values are not null/empty then the event is exported
  /// under a new name up the tree
  string[string] events;
  // TODO

  /// must update controls
  abstract void update();
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
