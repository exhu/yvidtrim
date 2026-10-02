module yguilib.events;

import yguilib.events.keyboard : Keycode, Scancode;

/// Current and up the stack controllers decide what events are consumed,
/// which propagated up the controller stack.
struct AppEvent {
  enum Kind {
    /// When this event is received controller should run update logic.
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
    /// Valid when: Kind.windowResized or Kind.windowDisplayScaleChanged.
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
    /// Valid when: Kind.mouseMotion, Kind.mouseButtonDown,
    /// or Kind.mouseButtonUp.
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

  /// User and view custom event payload.
  struct UserData {
    /// Custom event identifier.
    /// Valid when: Kind.user or Kind.view.
    uint eventId = 0;

    /// Custom user payload object.
    /// Valid when: Kind.user or Kind.view.
    Object data = null;
  }

  /// Event type discriminator. Valid for all events.
  Kind kind;

  /// Window event details.
  /// Valid when: Kind.windowClose, Kind.windowResized, Kind.windowExposed,
  /// Kind.windowDisplayScaleChanged, or Kind.windowRedraw.
  @property ref inout(WindowData) window() inout {
    assert(
      kind == Kind.windowClose ||
      kind == Kind.windowResized ||
      kind == Kind.windowExposed ||
      kind == Kind.windowDisplayScaleChanged ||
      kind == Kind.windowRedraw,
      "AppEvent.window accessed for wrong Kind"
    );
    return payload.window;
  }

  /// Mouse event details.
  /// Valid when: Kind.mouseMotion, Kind.mouseButtonDown,
  /// or Kind.mouseButtonUp.
  @property ref inout(MouseData) mouse() inout {
    assert(
      kind == Kind.mouseMotion ||
      kind == Kind.mouseButtonDown ||
      kind == Kind.mouseButtonUp,
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

  /// User and view event details.
  /// Valid when: Kind.user or Kind.view.
  @property ref inout(UserData) user() inout {
    assert(
      kind == Kind.user || kind == Kind.view,
      "AppEvent.user accessed for wrong Kind"
    );
    return payload.user;
  }

  /// Constructs events without data (appQuit, update, windowRedraw).
  this(Kind kind) {
    assert(
      kind == Kind.appQuit ||
      kind == Kind.update ||
      kind == Kind.windowRedraw
    );
    this.kind = kind;
  }

  /// Constructs window events with WindowData payload.
  this(Kind kind, WindowData data) {
    assert(
      kind == Kind.windowClose ||
      kind == Kind.windowDisplayScaleChanged ||
      kind == Kind.windowExposed ||
      kind == Kind.windowRedraw ||
      kind == Kind.windowResized
    );
    this.kind = kind;
    payload.window = data;
  }

  /// Constructs mouse events with MouseData payload.
  this(Kind kind, MouseData data) {
    assert(
      kind == Kind.mouseMotion ||
      kind == Kind.mouseButtonDown ||
      kind == Kind.mouseButtonUp
    );
    this.kind = kind;
    payload.mouse = data;
  }

  /// Constructs mouse wheel events with WheelData payload.
  this(Kind kind, WheelData data) {
    assert(kind == Kind.mouseWheel);
    this.kind = kind;
    payload.wheel = data;
  }

  /// Constructs keyboard events with KeyData payload.
  this(Kind kind, KeyData data) {
    assert(kind == Kind.keyDown || kind == Kind.keyUp);
    this.kind = kind;
    payload.keyData = data;
  }

  /// Constructs text events with TextData payload.
  this(Kind kind, TextData data) {
    assert(kind == Kind.textEditing || kind == Kind.textInput);
    this.kind = kind;
    payload.textData = data;
  }

  /// Constructs custom user/view events with UserData payload.
  this(Kind kind, UserData data) {
    assert(kind == Kind.user || kind == Kind.view);
    this.kind = kind;
    payload.user = data;
  }

  /// Convenience constructor for user and view events.
  this(Kind kind, uint eventId, Object data = null) {
    assert(kind == Kind.user || kind == Kind.view);
    this.kind = kind;
    payload.user = UserData(eventId, data);
  }

private:
  /// Compact C-style union storage for event variants.
  union Payload {
    WindowData window;
    MouseData  mouse;
    WheelData  wheel;
    KeyData    keyData;
    TextData   textData;
    UserData   user;
  }
  Payload payload;
}

unittest {
  AppEvent ev = AppEvent(
    AppEvent.Kind.windowDisplayScaleChanged,
    AppEvent.WindowData(1, 640, 480, 2.0f)
  );
  assert(ev.kind == AppEvent.Kind.windowDisplayScaleChanged);
  assert(ev.window.windowId == 1);
  assert(ev.window.scale == 2.0f);
  assert(ev.window.width == 640);
  assert(ev.window.height == 480);

  AppEvent mouseEv = AppEvent(
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

  AppEvent wheelEv = AppEvent(
    AppEvent.Kind.mouseWheel,
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

  AppEvent keyEv = AppEvent(
    AppEvent.Kind.keyDown,
    AppEvent.KeyData(1, Keycode.return_, Scancode.return_, 0x0001, true)
  );
  assert(keyEv.kind == AppEvent.Kind.keyDown);
  assert(keyEv.keyData.windowId == 1);
  assert((cast(uint)keyEv.keyData.key) == 13);
  assert((cast(uint)keyEv.keyData.scancode) == 40);
  assert(keyEv.keyData.mod == 1);
  assert(keyEv.keyData.repeat);

  AppEvent textEv = AppEvent(
    AppEvent.Kind.textInput,
    AppEvent.TextData(1, "hello")
  );
  assert(textEv.kind == AppEvent.Kind.textInput);
  assert(textEv.textData.windowId == 1);
  assert(textEv.textData.text == "hello");

  AppEvent editEv = AppEvent(
    AppEvent.Kind.textEditing,
    AppEvent.TextData(1, "comp", 2, 1)
  );
  assert(editEv.kind == AppEvent.Kind.textEditing);
  assert(editEv.textData.windowId == 1);
  assert(editEv.textData.text == "comp");
  assert(editEv.textData.editStart == 2);
  assert(editEv.textData.editLength == 1);

  AppEvent userEv = AppEvent(AppEvent.Kind.user, 42);
  assert(userEv.kind == AppEvent.Kind.user);
  assert(userEv.user.eventId == 42);
  assert(userEv.user.data is null);

  AppEvent quitEv = AppEvent(AppEvent.Kind.appQuit);
  assert(quitEv.kind == AppEvent.Kind.appQuit);

  AppEvent updateEv = AppEvent(AppEvent.Kind.update);
  assert(updateEv.kind == AppEvent.Kind.update);

  // Verify compact footprint: size should be 40 bytes instead of 80 bytes.
  static assert(AppEvent.sizeof == 40);
}
