module yguilib.widget;
import yguilib.widget.component;
import yguilib.widget.drawing_components;
import yguilib.render.render_types;
import yguilib.widget.layout;
import yguilib.widget.input_components;

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
  // layout
  FlexContainer flexContainer;
  Size size;

  // drawing
  Background background;
  TextLabel textLabel;
  Border border;
  CustomDraw customDraw;

  // action/logic
  View view;
  InputEnabled inputEnabled;
  Focus focus;
  DefaultButton defaultButton;
  KeyboardAction keyboardAction;
}

class Widget {
  this(Widget parent, RectF rect) {
    this.parent = parent;
    this.rect = rect;
    if (parent)
      parent.children ~= this;
  }

  /// must be called after properties have changed
  void markDirty() {
    dirty = true;
  }

  Widget parent;
  RectF rect;
  WidgetComponents components;
  bool handleInput;
  bool visible = true;
  bool clipContents = true;
  bool clipChildren = false;
  Widget[] children;
  bool dirty = true;
}
