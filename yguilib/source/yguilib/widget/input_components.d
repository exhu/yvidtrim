module yguilib.widget.input_components;
import yguilib.widget.component : AppEventViewValueMixin, WidgetComponent;

/// participates in focus loop
final class Focus : WidgetComponent {
  /// currently in focus, mark one control with true to mark the first focused
  /// item. Only one widget can be focused between focusRoots
  bool focused;
  /// does not participate in focus loop, cannot be focused
  bool skip;
  /// focus is cycling between all the widgets from this root to the next
  /// in hierarchy
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

/// Cursor capture mode applied while a button pressed on a widget is held.
enum CursorCapture {
  /// No capture: drag/release outside the window are not tracked.
  none,
  /// Captures the mouse to the window (SDL_CaptureMouse) while pressed so
  /// drag and release events are tracked outside window bounds.
  capture,
  /// Hides the cursor and enables relative mouse mode while pressed: drag
  /// events carry unbounded deltas in relX/relY while local/window
  /// coordinates stay at the press point; the cursor is warped back to the
  /// press point on release. Implies `capture`.
  lock,
}

final class MouseEvent : WidgetComponent {
  /// Parameter struct for `AppEventViewValue.pack`.
  struct PackParams {
    float localX = 0.0f;
    float localY = 0.0f;
    ubyte buttons = 0;
    bool inside = false;
    float relX = 0.0f;
    float relY = 0.0f;
    float windowX = 0.0f;
    float windowY = 0.0f;

    PackParams* withLocalPos(float x, float y) {
      localX = x;
      localY = y;
      return &this;
    }

    PackParams* withButtons(ubyte b) {
      buttons = b;
      return &this;
    }

    PackParams* withInside(bool v) {
      inside = v;
      return &this;
    }

    PackParams* withRelPos(float x, float y) {
      relX = x;
      relY = y;
      return &this;
    }

    PackParams* withWindowPos(float x, float y) {
      windowX = x;
      windowY = y;
      return &this;
    }
  }

  /// Packed value passed in AppEvent.ViewData.value to avoid heap
  /// allocations during frequent mouse events.
  union AppEventViewValue {
    mixin AppEventViewValueMixin!();
    struct {
      /// Mouse button index (1=left, 2=middle, 3=right), 0 for motion.
      ubyte buttons;
      /// True if the cursor is inside the widget's hit area.
      bool inside;
      /// Cursor X in widget-local space (origin = widget rect left-top).
      float localX;
      /// Cursor Y in widget-local space (origin = widget rect left-top).
      float localY;
      /// Relative X motion since last mouse event.
      float relX;
      /// Relative Y motion since last mouse event.
      float relY;
      /// Cursor X in window space.
      float windowX;
      /// Cursor Y in window space.
      float windowY;
    }

    /// Constructs from cursor coordinates and button state.
    static AppEventViewValue packLocal(
      float localX,
      float localY,
      ubyte buttons,
      bool inside
    ) {
      PackParams p;
      p.localX = localX;
      p.localY = localY;
      p.buttons = buttons;
      p.inside = inside;
      return pack(p);
    }

    /// Constructs from `PackParams`.
    static AppEventViewValue pack(in PackParams p) {
      AppEventViewValue val;
      val.raw = 0;
      val.buttons = p.buttons;
      val.inside = p.inside;
      val.localX = p.localX;
      val.localY = p.localY;
      val.relX = p.relX;
      val.relY = p.relY;
      val.windowX = p.windowX;
      val.windowY = p.windowY;
      return val;
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
  /// Sent on mouse motion while a button pressed on this widget is held down
  /// (continues firing even when cursor moves outside the widget).
  string mouseDrag;
  /// Cursor capture mode while a button pressed on this widget is held
  /// down; see `CursorCapture`.
  CursorCapture cursorCapture = CursorCapture.none;
}

unittest {
  // packLocal
  auto localVal = MouseEvent.AppEventViewValue.packLocal(12.5f, 34.0f, 1, true);
  assert(localVal.localX == 12.5f);
  assert(localVal.localY == 34.0f);
  assert(localVal.buttons == 1);
  assert(localVal.inside);
  assert(localVal.relX == 0.0f);
  assert(localVal.relY == 0.0f);
  assert(localVal.windowX == 0.0f);
  assert(localVal.windowY == 0.0f);

  // pack with PackParams fluent builder and round-trip via fromRaw
  MouseEvent.PackParams params;
  params.withLocalPos(10.0f, 20.0f)
    .withButtons(2)
    .withInside(false)
    .withRelPos(-3.5f, 4.5f)
    .withWindowPos(100.0f, 200.0f);
  auto packed = MouseEvent.AppEventViewValue.pack(params);
  auto unpacked = MouseEvent.AppEventViewValue.fromRaw(packed.raw);
  assert(unpacked.localX == 10.0f);
  assert(unpacked.localY == 20.0f);
  assert(unpacked.buttons == 2);
  assert(!unpacked.inside);
  assert(unpacked.relX == -3.5f);
  assert(unpacked.relY == 4.5f);
  assert(unpacked.windowX == 100.0f);
  assert(unpacked.windowY == 200.0f);

  // Focus, DefaultButton, KeyboardEvent defaults
  auto focus = new Focus();
  assert(!focus.focused && !focus.skip && !focus.focusRoot);
  auto defBtn = new DefaultButton();
  assert(defBtn !is null);
  auto kb = new KeyboardEvent();
  assert(kb.keyToViewEvent.length == 0);
}
