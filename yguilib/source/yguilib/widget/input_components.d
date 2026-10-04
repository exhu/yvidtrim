module yguilib.widget.input_components;
import yguilib.widget.component;

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
final class KeyboardEvent : Component {
  struct Params {
    bool isPressed;
  }
  string[string] keyToViewEvent;
}

final class MouseEvent : Component {
  // TODO need to reuse some storage for events
  // because allocating new instance on each mouse movement is expensive
  // use releaseData delegate
  /*
  final class MouseEventData {
    ubyte button;
    float x;
    float y;
  }
  */
  union AppEventViewValue {
    ubyte buttons;
    float absX;
    float absY;
  }
  /// view.value contains button index
  string mouseDown;
  string mouseUp;
  string mouseEnter;
  string mouseLeave;
  string mouseMove;
}
