module yguilib.events;

import yguilib.events.keyboard : Keycode, Scancode;
import yguilib.widget : Widget;

/// Current and up the stack controllers decide what events are consumed,
/// which propagated up the controller stack.
struct AppEvent {
  enum Kind {
    /// Triggers a Phase 2 Controller.update() model-sync pass.
    update,
    /// User defined global events.
    user,
    /// Events that are produced by uisystem controls.
    view,
    /// Window close requested.
    windowClose,
    /// Window size changed.
    windowResized,
    /// Window damaged or exposed.
    windowExposed,
    /// Window DPI or display scale factor changed.
    windowDisplayScaleChanged,
    /// Mouse cursor entered window bounds.
    windowMouseEnter,
    /// Mouse cursor left window bounds.
    windowMouseLeave,
    /// Synthetic window redraw trigger.
    windowRedraw,
    /// Mouse moved within window bounds.
    mouseMotion,
    /// Mouse button pressed.
    mouseButtonDown,
    /// Mouse button released.
    mouseButtonUp,
    /// Mouse wheel scrolled.
    mouseWheel,
    /// Keyboard key pressed.
    keyDown,
    /// Keyboard key released.
    keyUp,
    /// Candidate text editing in progress (IME).
    textEditing,
    /// Text input entered.
    textInput,
    /// Application quit requested.
    appQuit,
  }

  bool isWindowEvent() const nothrow @safe {
    return isWindowKind(fKind);
  }

  bool isWindowRedrawEvent() const nothrow @safe {
    return isWindowRedrawKind(fKind);
  }

  bool isKeyboardEvent() const nothrow @safe {
    switch (fKind) {
      case Kind.keyDown, Kind.keyUp, Kind.textEditing, Kind.textInput:
        return true;
      default:
        return false;
    }
  }

  bool isMouseEvent() const nothrow @safe {
    switch (fKind) {
      case Kind.mouseMotion, Kind.mouseButtonDown, Kind.mouseButtonUp,
        Kind.mouseWheel:
        return true;
      default:
        return false;
    }
  }

  /// Window event payload.
  struct WindowData {
    /// SDL window ID (0 for all/any window).
    /// Valid when: window events.
    uint windowId = 0;

    /// New pixel width of the window.
    /// Valid when: Kind.windowResized, Kind.windowExposed,
    /// or Kind.windowDisplayScaleChanged.
    int width = 0;

    /// New pixel height of the window.
    /// Valid when: Kind.windowResized, Kind.windowExposed,
    /// or Kind.windowDisplayScaleChanged.
    int height = 0;

    /// Display scaling factor (e.g. 1.0, 2.0).
    /// Valid when: Kind.windowResized, Kind.windowExposed,
    /// or Kind.windowDisplayScaleChanged.
    float scale = 1.0f;
  }

  /// Mouse event payload.
  struct MouseData {
    /// SDL window ID.
    /// Valid when: Kind.mouseMotion, Kind.mouseButtonDown,
    /// or Kind.mouseButtonUp.
    uint windowId = 0;

    /// Window-relative mouse X coordinate.
    /// Valid when: Kind.mouseMotion, Kind.mouseButtonDown,
    /// or Kind.mouseButtonUp.
    float x = 0.0f;

    /// Window-relative mouse Y coordinate.
    /// Valid when: Kind.mouseMotion, Kind.mouseButtonDown,
    /// or Kind.mouseButtonUp.
    float y = 0.0f;

    /// Bitmask of currently pressed mouse buttons (SDL_MouseButtonFlags).
    /// Valid when: Kind.mouseMotion (0 for button events).
    uint state = 0;

    /// Relative X motion since last mouse event.
    /// Valid when: Kind.mouseMotion.
    float xrel = 0.0f;

    /// Relative Y motion since last mouse event.
    /// Valid when: Kind.mouseMotion.
    float yrel = 0.0f;

    /// Mouse button index (1=left, 2=middle, 3=right, ...).
    /// Valid when: Kind.mouseButtonDown or Kind.mouseButtonUp.
    ubyte button = 0;

    /// True when the button is pressed (down), false when released.
    /// Valid when: Kind.mouseButtonDown or Kind.mouseButtonUp.
    bool down = false;

    /// Number of clicks (1=single, 2=double, ...).
    /// Valid when: Kind.mouseButtonDown or Kind.mouseButtonUp.
    ubyte clicks = 0;

  private:
    ubyte padding = 0;
  }

  /// Mouse wheel event payload.
  struct WheelData {
    /// SDL window ID.
    /// Valid when: Kind.mouseWheel.
    uint windowId = 0;

    /// Horizontal scroll delta (positive = right).
    /// Valid when: Kind.mouseWheel.
    float x = 0.0f;

    /// Vertical scroll delta (positive = up in natural direction).
    /// Valid when: Kind.mouseWheel.
    float y = 0.0f;

    /// Mouse cursor X position at scroll time.
    /// Valid when: Kind.mouseWheel.
    float mouseX = 0.0f;

    /// Mouse cursor Y position at scroll time.
    /// Valid when: Kind.mouseWheel.
    float mouseY = 0.0f;

    /// Scroll direction: 1=normal, -1=flipped/natural.
    /// Valid when: Kind.mouseWheel.
    int direction = 0;

    /// Raw integer horizontal scroll (platform-specific).
    /// Valid when: Kind.mouseWheel.
    int integerX = 0;

    /// Raw integer vertical scroll (platform-specific).
    /// Valid when: Kind.mouseWheel.
    int integerY = 0;
  }

  /// Keyboard event payload.
  struct KeyData {
    /// SDL window ID.
    /// Valid when: Kind.keyDown or Kind.keyUp.
    uint windowId = 0;

    /// Layout-dependent virtual key code.
    /// Valid when: Kind.keyDown or Kind.keyUp.
    Keycode key;

    /// Layout-independent hardware scan code.
    /// Valid when: Kind.keyDown or Kind.keyUp.
    Scancode scancode;

    /// Modifier bitmask (Shift, Ctrl, Alt, Gui).
    /// Valid when: Kind.keyDown or Kind.keyUp.
    ushort mod = 0;

    /// True if key down was triggered by automatic keyboard repeat.
    /// Valid when: Kind.keyDown.
    bool repeat = false;
  }

  /// Text input and IME composition payload.
  struct TextData {
    /// SDL window ID.
    /// Valid when: Kind.textEditing or Kind.textInput.
    uint windowId = 0;

    /// UTF-8 entered text or IME composition candidate.
    /// Valid when: Kind.textEditing or Kind.textInput.
    string text = null;

    /// Start position of composition selection.
    /// Valid when: Kind.textEditing.
    int editStart = 0;

    /// Length of composition selection.
    /// Valid when: Kind.textEditing.
    int editLength = 0;
  }

  /// User custom event payload.
  struct UserData {
    /// Custom event identifier.
    /// Valid when: Kind.user.
    uint eventId = 0;

    /// Custom user payload object. Allowed to be null.
    /// Valid when: Kind.user.
    Object data = null;
  }

  /// View event payload.
  struct ViewData {
    enum valueSize = 4;

    /// Event name identifying the view action. Allowed to be null.
    string eventName;
    /// Originating widget. Allowed to be null.
    Widget widget;
    /// Nearest view widget ancestor. Allowed to be null.
    Widget viewWidget;
    /// Opaque value to be used to manage
    /// data either by integer or object instance, or both.
    ulong[valueSize] value;
    /// Custom user payload object. Allowed to be null.
    Object data;
  }

  /// Event type discriminator. Valid for all events.
  @property Kind kind() const nothrow @safe {
    return fKind;
  }

  /// Do not push event if there's already the same in the queue
  @property bool noRepeat() inout {
    return fnoRepeat;
  }

  /// Window event details.
  /// Valid when: Kind.windowClose, Kind.windowResized, Kind.windowExposed,
  /// Kind.windowDisplayScaleChanged, Kind.windowMouseEnter,
  /// Kind.windowMouseLeave, or Kind.windowRedraw.
  @property ref inout(WindowData) window() inout {
    assert(isWindowEvent(), "AppEvent.window accessed for wrong Kind");
    return payload.window;
  }

  /// Mouse event details.
  /// Valid when: Kind.mouseMotion, Kind.mouseButtonDown,
  /// or Kind.mouseButtonUp.
  @property ref inout(MouseData) mouse() inout {
    assert(
      isMousePointerKind(fKind),
      "AppEvent.mouse accessed for wrong Kind"
    );
    return payload.mouse;
  }

  /// Mouse wheel event details.
  /// Valid when: Kind.mouseWheel.
  @property ref inout(WheelData) wheel() inout {
    assert(
      kind == Kind.mouseWheel,
      "AppEvent.wheel accessed for wrong Kind"
    );
    return payload.wheel;
  }

  /// Keyboard event details.
  /// Valid when: Kind.keyDown or Kind.keyUp.
  @property ref inout(KeyData) keyData() inout {
    assert(
      kind == Kind.keyDown || kind == Kind.keyUp,
      "AppEvent.keyData accessed for wrong Kind"
    );
    return payload.keyData;
  }

  /// Text editing and input details.
  /// Valid when: Kind.textEditing or Kind.textInput.
  @property ref inout(TextData) textData() inout {
    assert(
      kind == Kind.textEditing || kind == Kind.textInput,
      "AppEvent.textData accessed for wrong Kind"
    );
    return payload.textData;
  }

  /// User event details.
  /// Valid when: Kind.user.
  @property ref inout(UserData) user() inout {
    assert(
      kind == Kind.user,
      "AppEvent.user accessed for wrong Kind"
    );
    return payload.user;
  }

  @property ref inout(ViewData) view() inout {
    assert(
      kind == Kind.view,
      "AppEvent.view accessed for wrong Kind"
    );
    return payload.view;
  }

  /// Constructs events with kind discriminator.
  this(Kind kind) {
    fKind = kind;
  }

  static AppEvent makeNoRepeat(Kind kind) {
    auto ev = AppEvent(kind);
    ev.fnoRepeat = true;
    return ev;
  }

  /// Constructs window events with WindowData payload.
  static AppEvent windowEvent(Kind kind, WindowData data) {
    assert(isWindowKind(kind));
    auto ev = AppEvent(kind);
    ev.payload.window = data;
    return ev;
  }

  /// Constructs mouse events with MouseData payload.
  static AppEvent mouseEvent(Kind kind, MouseData data) {
    assert(isMousePointerKind(kind));
    auto ev = AppEvent(kind);
    ev.payload.mouse = data;
    return ev;
  }

  /// Constructs mouse wheel events with WheelData payload.
  static AppEvent wheelEvent(WheelData data) {
    auto ev = AppEvent(Kind.mouseWheel);
    ev.payload.wheel = data;
    return ev;
  }

  /// Constructs keyboard events with KeyData payload.
  static AppEvent keyEvent(Kind kind, KeyData data) {
    assert(kind == Kind.keyDown || kind == Kind.keyUp);
    auto ev = AppEvent(kind);
    ev.payload.keyData = data;
    return ev;
  }

  /// Constructs text events with TextData payload.
  static AppEvent textEvent(Kind kind, TextData data) {
    assert(kind == Kind.textEditing || kind == Kind.textInput);
    auto ev = AppEvent(kind);
    ev.payload.textData = data;
    return ev;
  }

  static AppEvent userEvent(UserData data) {
    auto ev = AppEvent(Kind.user);
    ev.payload.user = data;
    return ev;
  }

  static AppEvent viewEvent(ViewData data) {
    auto ev = AppEvent(Kind.view);
    ev.payload.view = data;
    return ev;
  }

package(yguilib):
  bool equalsContent(in AppEvent other) const {
    if (kind != other.kind) {
      return false;
    }
    final switch (kind) {
    case Kind.update, Kind.appQuit:
      return true;
    case Kind.user:
      return payload.user.eventId == other.payload.user.eventId &&
        payload.user.data is other.payload.user.data;
    case Kind.view:
      return payload.view.eventName == other.payload.view.eventName &&
        payload.view.widget is other.payload.view.widget &&
        payload.view.viewWidget is other.payload.view.viewWidget &&
        payload.view.value == other.payload.view.value &&
        payload.view.data is other.payload.view.data;
    case Kind.windowClose, Kind.windowResized, Kind.windowExposed,
        Kind.windowDisplayScaleChanged, Kind.windowMouseEnter,
        Kind.windowMouseLeave, Kind.windowRedraw:
      return payload.window == other.payload.window;
    case Kind.mouseMotion, Kind.mouseButtonDown, Kind.mouseButtonUp:
      return payload.mouse == other.payload.mouse;
    case Kind.mouseWheel:
      return payload.wheel == other.payload.wheel;
    case Kind.keyDown, Kind.keyUp:
      return payload.keyData == other.payload.keyData;
    case Kind.textEditing, Kind.textInput:
      return payload.textData == other.payload.textData;
    }
  }

private:
  static bool isWindowKind(Kind k) nothrow @safe {
    switch (k) {
      case Kind.windowClose, Kind.windowMouseEnter, Kind.windowMouseLeave:
        return true;
      default:
        return isWindowRedrawKind(k);
    }
  }

  static bool isWindowRedrawKind(Kind k) nothrow @safe {
    switch (k) {
      case Kind.windowDisplayScaleChanged, Kind.windowExposed,
        Kind.windowRedraw, Kind.windowResized:
        return true;
      default:
        return false;
    }
  }

  static bool isMousePointerKind(Kind k) nothrow @safe {
    return k == Kind.mouseMotion ||
      k == Kind.mouseButtonDown ||
      k == Kind.mouseButtonUp;
  }

  /// Compact C-style union storage for event variants.
  union Payload {
    WindowData window;
    MouseData mouse;
    WheelData wheel;
    KeyData keyData;
    TextData textData;
    UserData user;
    ViewData view;
  }
  Kind fKind;
  Payload payload;
  bool fnoRepeat = false;
}

unittest {
  AppEvent ev = AppEvent.windowEvent(
    AppEvent.Kind.windowDisplayScaleChanged,
    AppEvent.WindowData(1, 640, 480, 2.0f)
  );
  assert(ev.kind == AppEvent.Kind.windowDisplayScaleChanged);
  assert(ev.window.windowId == 1);
  assert(ev.window.scale == 2.0f);
  assert(ev.window.width == 640);
  assert(ev.window.height == 480);

  AppEvent mouseEv = AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 150.5f, 250.0f, 0x01, -2.5f, 3.5f, 1, true, 2)
  );
  assert(mouseEv.kind == AppEvent.Kind.mouseMotion);
  assert(mouseEv.mouse.windowId == 1);
  assert(mouseEv.mouse.x == 150.5f);
  assert(mouseEv.mouse.y == 250.0f);
  assert(mouseEv.mouse.state == 0x01);
  assert(mouseEv.mouse.xrel == -2.5f);
  assert(mouseEv.mouse.yrel == 3.5f);
  assert(mouseEv.mouse.button == 1);
  assert(mouseEv.mouse.down);
  assert(mouseEv.mouse.clicks == 2);

  AppEvent wheelEv = AppEvent.wheelEvent(
    AppEvent.WheelData(1, 0.0f, 1.5f, 100.0f, 200.0f, 1, 0, 1)
  );
  assert(wheelEv.kind == AppEvent.Kind.mouseWheel);
  assert(wheelEv.wheel.windowId == 1);
  assert(wheelEv.wheel.x == 0.0f);
  assert(wheelEv.wheel.y == 1.5f);
  assert(wheelEv.wheel.mouseX == 100.0f);
  assert(wheelEv.wheel.mouseY == 200.0f);
  assert(wheelEv.wheel.direction == 1);
  assert(wheelEv.wheel.integerX == 0);
  assert(wheelEv.wheel.integerY == 1);

  AppEvent keyEv = AppEvent.keyEvent(
    AppEvent.Kind.keyDown,
    AppEvent.KeyData(1, Keycode.return_, Scancode.return_, 0x0001, true)
  );
  assert(keyEv.kind == AppEvent.Kind.keyDown);
  assert(keyEv.keyData.windowId == 1);
  assert((cast(uint)keyEv.keyData.key) == 13);
  assert((cast(uint)keyEv.keyData.scancode) == 40);
  assert(keyEv.keyData.mod == 1);
  assert(keyEv.keyData.repeat);

  AppEvent textEv = AppEvent.textEvent(
    AppEvent.Kind.textInput,
    AppEvent.TextData(1, "hello")
  );
  assert(textEv.kind == AppEvent.Kind.textInput);
  assert(textEv.textData.windowId == 1);
  assert(textEv.textData.text == "hello");

  AppEvent editEv = AppEvent.textEvent(
    AppEvent.Kind.textEditing,
    AppEvent.TextData(1, "comp", 2, 1)
  );
  assert(editEv.kind == AppEvent.Kind.textEditing);
  assert(editEv.textData.windowId == 1);
  assert(editEv.textData.text == "comp");
  assert(editEv.textData.editStart == 2);
  assert(editEv.textData.editLength == 1);

  AppEvent userEv = AppEvent.userEvent(AppEvent.UserData(42));
  assert(userEv.kind == AppEvent.Kind.user);
  assert(userEv.user.eventId == 42);
  assert(userEv.user.data is null);

  AppEvent quitEv = AppEvent(AppEvent.Kind.appQuit);
  assert(quitEv.kind == AppEvent.Kind.appQuit);

  AppEvent updateEv = AppEvent(AppEvent.Kind.update);
  assert(updateEv.kind == AppEvent.Kind.update);

  AppEvent enterEv = AppEvent.windowEvent(
    AppEvent.Kind.windowMouseEnter,
    AppEvent.WindowData(7)
  );
  assert(enterEv.kind == AppEvent.Kind.windowMouseEnter);
  assert(enterEv.isWindowEvent());
  assert(!enterEv.isWindowRedrawEvent());
  assert(enterEv.window.windowId == 7);

  AppEvent leaveEv = AppEvent.windowEvent(
    AppEvent.Kind.windowMouseLeave,
    AppEvent.WindowData(7)
  );
  assert(leaveEv.kind == AppEvent.Kind.windowMouseLeave);
  assert(leaveEv.isWindowEvent());
  assert(!leaveEv.isWindowRedrawEvent());
  assert(leaveEv.window.windowId == 7);

  // makeNoRepeat sets noRepeat flag
  AppEvent nrUpdate = AppEvent.makeNoRepeat(AppEvent.Kind.update);
  assert(nrUpdate.kind == AppEvent.Kind.update);
  assert(nrUpdate.noRepeat);
  assert(!updateEv.noRepeat);

  // equalsContent compares kind, value payloads, and object identity
  assert(quitEv.equalsContent(AppEvent(AppEvent.Kind.appQuit)));
  assert(!quitEv.equalsContent(updateEv));
  assert(ev.equalsContent(AppEvent.windowEvent(
    AppEvent.Kind.windowDisplayScaleChanged,
    AppEvent.WindowData(1, 640, 480, 2.0f)
  )));
  assert(!ev.equalsContent(AppEvent.windowEvent(
    AppEvent.Kind.windowDisplayScaleChanged,
    AppEvent.WindowData(2, 640, 480, 2.0f)
  )));
  assert(mouseEv.equalsContent(mouseEv));
  assert(wheelEv.equalsContent(wheelEv));
  assert(keyEv.equalsContent(keyEv));
  assert(textEv.equalsContent(textEv));

  Object objA = new Object;
  Object objB = new Object;
  AppEvent uA1 = AppEvent.userEvent(AppEvent.UserData(10, objA));
  AppEvent uA2 = AppEvent.userEvent(AppEvent.UserData(10, objA));
  AppEvent uB = AppEvent.userEvent(AppEvent.UserData(10, objB));
  assert(uA1.equalsContent(uA2));
  assert(!uA1.equalsContent(uB));
}
