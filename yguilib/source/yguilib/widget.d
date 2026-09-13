module yguilib.widget;

import yguilib.render_types;
import yguilib.render;

abstract class Component {

}

class CustomDraw : Component {
  void delegate(in Renderer r, in Widget w) drawFunc;
}

class TextLabel : Component {
  this(string caption, ColorF color) {
    this.caption = caption;
    this.color = color;
  }
  string font;
  uint fontSize = 16;
  string caption = "TextLabel";
  ColorF color = ColorF(1,1,1,1);
}

class Background : Component {
  enum Style {
    rect,
    round,
    none,
  }
  this(ColorF color, Style style = Style.rect) {
    this.color = color;
    this.style = style;
  }
  ColorF color;
  Style style;
}

class Border : Component {
  enum Style {
    rect,
    round,
    roundDashed,
    none,
  }
  this(ColorF color, Style style = Style.rect) {
    this.color = color;
    this.style = style;
  }
  ColorF color;
  Style style;
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
  TextLabel textLabel;
  View view;
  InputEnabled inputEnabled;
  Focus focus;
  DefaultButton defaultButton;
  CustomDraw customDraw;
  Border border;
}

class Widget {
  this(Widget parent, RectF rect) {
    this.parent = parent;
    this.rect = rect;
    if (parent)
      parent.children ~= this;
  }

  Widget parent;
  RectF rect;
  WidgetComponents components;
  bool handleInput;
  bool visible = true;
  bool clipContents = true;
  bool clipChildren = false;
  Widget[] children;
}
