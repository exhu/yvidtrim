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

import yguilib.events : AppEvent;

final class MouseEvent : Component {
  /// Packed value passed in AppEvent.ViewData.value to avoid heap
  /// allocations during frequent mouse events.
  union AppEventViewValue {
    /// Raw 64-bit integer array stored in AppEvent.ViewData.value.
    ulong[AppEvent.ViewData.valueSize] raw;
    struct {
      /// Mouse button index (1=left, 2=middle, 3=right).
      ubyte buttons;
      /// Absolute cursor X coordinate in window coordinates.
      float absX;
      /// Absolute cursor Y coordinate in window coordinates.
      float absY;
    }

    /// Allows implicit conversion to array for ViewAppEventBuilder.value.
    alias raw this;

    /// Constructs from raw array payload.
    this(in ulong[AppEvent.ViewData.valueSize] raw) {
      this.raw = raw;
    }

    /// Constructs from cursor coordinates and optional button index.
    this(float absX, float absY, ubyte buttons = 0) {
      this.raw = 0;
      this.buttons = buttons;
      this.absX = absX;
      this.absY = absY;
    }
  }

  /// view.value contains button index and cursor coordinates
  string mouseDown;
  string mouseUp;
  /// mouse entered widget abs rect, mouseMove is sent together with enter/leave
  /// events
  string mouseEnter;
  /// mouse was over the widget abs rect and left
  string mouseLeave;
  /// mouse is moving over widget abs rect
  string mouseMove;
}
