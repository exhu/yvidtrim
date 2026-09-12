module yguilib.widget;

public import yguilib.render_types;


abstract class Component {

}

class Background : Component {
  this(ColorF color) {
    this.color = color;
  }
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
  Background background;
  View view;
  InputEnabled inputEnabled;
  Focus focus;
  DefaultButton defaultButton;
}

class Widget {
  this(Widget parent, RectF rect) {
    this.parent = parent;
    this.rect = rect;
  }

  Widget parent;
  RectF rect;
  WidgetComponents components;
  bool handleInput;
  bool visible = true;
}
