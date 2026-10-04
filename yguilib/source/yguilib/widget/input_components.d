module yguilib.widget.input_components;
import yguilib.widget.component;

final class InputEnabled : Component {
  bool enabled;
}

/// participates in focus loop
final class Focus : Component {
  /// currently in focus, mark one control with true to mark the first focused
  /// item. Only one widget can be focused between focusRoots
  bool focused;
  /// does not participate in focus loop, cannot be focused
  bool skip;
  /// focus is cycling between all the widgets from this root to the next in hierarchy
  bool focusRoot;
}

/// this button is pressed by enter
final class DefaultButton : Component {
}

/// convert event press and release to event with parameter
final class KeyboardAction : Component {
  struct Params {
    bool isPressed;
  }
  string[string] keyToViewEvent;
}

final class MouseAction : Component {
  final class MouseActionEventData {
    ubyte button;
    float x;
    float y;
  }
  string mouseDown;
  string mouseUp;
  string mouseEnter;
  string mouseLeave;
  string mouseMove;
}
