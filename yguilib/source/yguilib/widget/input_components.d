module yguilib.widget.input_components;
import yguilib.widget.component;

class InputEnabled : Component {
  bool enabled;
}

/// participates in focus loop
class Focus : Component {
  /// currently in focus, mark one control with true to mark the first focused
  /// item. Only one widget can be focused between focusRoots
  bool focused;
  /// does not participate in focus loop, cannot be focused
  bool skip;
  /// focus is cycling between all the widgets from this root to the next in hierarchy
  bool focusRoot;
}

/// this button is pressed by enter
class DefaultButton : Component {
}

/// convert event press and release to event with parameter
class KeyboardAction : Component {
  struct Params {
    bool isPressed;
  }
  string[string] keyToAction;
}
