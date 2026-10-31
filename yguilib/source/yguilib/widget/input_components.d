module yguilib.widget.input_components;
import yguilib.widget.component;

/// participates in focus loop
final class Focus : WidgetComponent {
  /// currently in focus, mark one control with true to mark the first focused
  /// item. Only one widget can be focused between focusRoots
  bool focused;
  /// does not participate in focus loop, cannot be focused
  bool skip;
  /// focus is cycling between all the widgets from this root to the next in hierarchy
  bool focusRoot;
}

/// this button is pressed by enter
final class DefaultButton : WidgetComponent {
}

/// convert event press and release to event with parameter
final class KeyboardEvent : WidgetComponent {
  struct Params {
    bool isPressed;
  }
  string[string] keyToViewEvent;
}

import yguilib.events : AppEvent;

final class MouseEvent : WidgetComponent {
  /// Packed value passed in AppEvent.ViewData.value to avoid heap
  /// allocations during frequent mouse events.
  union AppEventViewValue {
    /// Raw 64-bit integer array stored in AppEvent.ViewData.value.
    ulong[AppEvent.ViewData.valueSize] raw;
    struct {
      /// Mouse button index (1=left, 2=middle, 3=right), 0 for motion.
      ubyte buttons;
      /// True if the cursor is inside the widget's hit area.
      bool inside;
      /// Cursor X in widget-local space (origin = widget rect left-top).
      float localX;
      /// Cursor Y in widget-local space (origin = widget rect left-top).
      float localY;
    }

    /// Allows implicit conversion to array for ViewAppEventBuilder.value.
    alias raw this;

    /// Constructs from raw array payload.
    this(in ulong[AppEvent.ViewData.valueSize] raw) {
      this.raw = raw;
    }

    /// Constructs from cursor coordinates, button index, and inside flag.
    this(float localX, float localY, ubyte buttons = 0, bool inside = true) {
      this.raw = 0;
      this.buttons = buttons;
      this.inside = inside;
      this.localX = localX;
      this.localY = localY;
    }
  }

  /// view.value contains button index, inside flag, and local coordinates.
  string mouseDown;
  /// Sent on mouse button release to the widget that previously received
  /// mouseDown.
  string mouseUp;
  /// mouse entered widget abs rect, mouseMove is sent together with enter/leave
  /// events
  string mouseEnter;
  /// mouse was over the widget abs rect and left
  string mouseLeave;
  /// mouse is moving over widget abs rect.
  /// NOTE: mouseMove is not sent when outside the widget even after mouseDown.
  string mouseMove;
}
