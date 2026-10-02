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

  /// Compact C-style union storage for event variants.
  union {
    /// Window event details.
    /// Valid when: Kind.windowClose, Kind.windowResized, Kind.windowExposed,
    /// Kind.windowDisplayScaleChanged, or Kind.windowRedraw.
    WindowData window;

    /// Mouse event details.
    /// Valid when: Kind.mouseMotion, Kind.mouseButtonDown,
    /// or Kind.mouseButtonUp.
    MouseData mouse;

    /// Keyboard event details.
    /// Valid when: Kind.keyDown or Kind.keyUp.
    KeyData keyData;

    /// Text editing and input details.
    /// Valid when: Kind.textEditing or Kind.textInput.
    TextData textData;

    /// User and view event details.
    /// Valid when: Kind.user or Kind.view.
    UserData user;
  }

  /// constructor for events without data, e.g. appQuit
  this(Kind kind) {
    assert(kind == Kind.appQuit);
    this.kind = kind;
  }

  this(Kind kind, WindowData data) {
    // ensure all window events in assert
    assert(kind == Kind.windowClose ||
      kind == Kind.windowDisplayScaleChanged ||
      kind == Kind.windowExposed ||
      kind == Kind.windowRedraw ||
      kind == Kind.windowResized
    );
    this.kind = kind;
    window = data;
  }
  // TODO implement constructors for MouseData, KeyData, TextData, UserData events

  // TODO refactor external code and remove backward compatibility layer
  // properties after all event constructors are implemented
  // --- Convenience Properties for Ergonomics & Backward Compatibility ---

  /// Window ID.
  /// Valid when: window, mouse, keyboard, or text events.
  @property uint windowId() const {
    switch (kind) {
      case Kind.windowClose:
      case Kind.windowResized:
      case Kind.windowExposed:
      case Kind.windowDisplayScaleChanged:
      case Kind.windowRedraw:
        return window.windowId;
      case Kind.mouseMotion:
      case Kind.mouseButtonDown:
      case Kind.mouseButtonUp:
        return mouse.windowId;
      case Kind.keyDown:
      case Kind.keyUp:
        return keyData.windowId;
      case Kind.textEditing:
      case Kind.textInput:
        return textData.windowId;
      default:
        return 0;
    }
  }

  /// Sets window ID for the active variant.
  @property void windowId(uint id) {
    switch (kind) {
      case Kind.windowClose:
      case Kind.windowResized:
      case Kind.windowExposed:
      case Kind.windowDisplayScaleChanged:
      case Kind.windowRedraw:
        window.windowId = id;
        break;
      case Kind.mouseMotion:
      case Kind.mouseButtonDown:
      case Kind.mouseButtonUp:
        mouse.windowId = id;
        break;
      case Kind.keyDown:
      case Kind.keyUp:
        keyData.windowId = id;
        break;
      case Kind.textEditing:
      case Kind.textInput:
        textData.windowId = id;
        break;
      default:
        break;
    }
  }

  /// Custom event identifier.
  /// Valid when: Kind.user or Kind.view.
  @property uint eventId() const { return user.eventId; }
  /// ditto
  @property void eventId(uint val) { user.eventId = val; }

  /// Custom user payload object.
  /// Valid when: Kind.user or Kind.view.
  @property Object data() { return user.data; }
  /// ditto
  @property void data(Object val) { user.data = val; }

  /// New pixel width of the window.
  /// Valid when: Kind.windowResized, Kind.windowExposed,
  /// or Kind.windowDisplayScaleChanged.
  @property int width() const { return window.width; }
  /// ditto
  @property void width(int val) { window.width = val; }

  /// New pixel height of the window.
  /// Valid when: Kind.windowResized, Kind.windowExposed,
  /// or Kind.windowDisplayScaleChanged.
  @property int height() const { return window.height; }
  /// ditto
  @property void height(int val) { window.height = val; }

  /// Display scale factor.
  /// Valid when: Kind.windowResized or Kind.windowDisplayScaleChanged.
  @property float scale() const { return window.scale; }
  /// ditto
  @property void scale(float val) { window.scale = val; }

  /// Window-relative mouse X coordinate.
  /// Valid when: Kind.mouseMotion, Kind.mouseButtonDown,
  /// or Kind.mouseButtonUp.
  @property float x() const { return mouse.x; }
  /// ditto
  @property void x(float val) { mouse.x = val; }

  /// Window-relative mouse Y coordinate.
  /// Valid when: Kind.mouseMotion, Kind.mouseButtonDown,
  /// or Kind.mouseButtonUp.
  @property float y() const { return mouse.y; }
  /// ditto
  @property void y(float val) { mouse.y = val; }

  /// Layout-dependent virtual key code.
  /// Valid when: Kind.keyDown or Kind.keyUp.
  @property Keycode key() const { return keyData.key; }
  /// ditto
  @property void key(Keycode val) { keyData.key = val; }

  /// Layout-independent hardware scan code.
  /// Valid when: Kind.keyDown or Kind.keyUp.
  @property Scancode scancode() const { return keyData.scancode; }
  /// ditto
  @property void scancode(Scancode val) { keyData.scancode = val; }

  /// Key modifier bitmask.
  /// Valid when: Kind.keyDown or Kind.keyUp.
  @property ushort mod() const { return keyData.mod; }
  /// ditto
  @property void mod(ushort val) { keyData.mod = val; }

  /// True if key down was triggered by automatic keyboard repeat.
  /// Valid when: Kind.keyDown.
  @property bool repeat() const { return keyData.repeat; }
  /// ditto
  @property void repeat(bool val) { keyData.repeat = val; }

  /// UTF-8 entered text or IME composition candidate.
  /// Valid when: Kind.textEditing or Kind.textInput.
  @property string text() const { return textData.text; }
  /// ditto
  @property void text(string val) { textData.text = val; }

  /// Start position of composition selection.
  /// Valid when: Kind.textEditing.
  @property int editStart() const { return textData.editStart; }
  /// ditto
  @property void editStart(int val) { textData.editStart = val; }

  /// Length of composition selection.
  /// Valid when: Kind.textEditing.
  @property int editLength() const { return textData.editLength; }
  /// ditto
  @property void editLength(int val) { textData.editLength = val; }


  // TODO remove constructor, use (Kind, data) constructors instead
  /// Constructs an AppEvent initializing only the fields relevant to kind.
  deprecated
  this(
    Kind kind,
    uint eventId = 0,
    int width = 0,
    int height = 0,
    Object data = null,
    float x = 0.0f,
    float y = 0.0f,
    float scale = 1.0f,
    uint key = 0,
    uint scancode = 0,
    ushort mod = 0,
    bool repeat = false,
    string text = null,
    int editStart = 0,
    int editLength = 0,
    uint windowId = 0
  ) {
    this.kind = kind;
    switch (kind) {
      case Kind.user:
      case Kind.view:
        this.user.eventId = eventId;
        this.user.data = data;
        break;
      case Kind.windowClose:
      case Kind.windowRedraw:
        this.window.windowId = windowId;
        break;
      case Kind.windowResized:
      case Kind.windowExposed:
      case Kind.windowDisplayScaleChanged:
        this.window.windowId = windowId;
        this.window.width = width;
        this.window.height = height;
        this.window.scale = scale;
        break;
      case Kind.mouseMotion:
      case Kind.mouseButtonDown:
      case Kind.mouseButtonUp:
        this.mouse.windowId = windowId;
        this.mouse.x = x;
        this.mouse.y = y;
        break;
      case Kind.keyDown:
      case Kind.keyUp:
        this.keyData.windowId = windowId;
        this.keyData.key = cast(Keycode)key;
        this.keyData.scancode = cast(Scancode)scancode;
        this.keyData.mod = mod;
        this.keyData.repeat = repeat;
        break;
      case Kind.textEditing:
        this.textData.windowId = windowId;
        this.textData.text = text;
        this.textData.editStart = editStart;
        this.textData.editLength = editLength;
        break;
      case Kind.textInput:
        this.textData.windowId = windowId;
        this.textData.text = text;
        break;
      default:
        break;
    }
  }
}

unittest {
  AppEvent ev = AppEvent(AppEvent.Kind.windowDisplayScaleChanged);
  ev.windowId = 1;
  ev.width = 640;
  ev.height = 480;
  ev.scale = 2.0f;
  assert(ev.kind == AppEvent.Kind.windowDisplayScaleChanged);
  assert(ev.windowId == 1);
  assert(ev.scale == 2.0f);
  assert(ev.width == 640);
  assert(ev.height == 480);
  assert(ev.window.width == 640);

  AppEvent mouseEv = AppEvent(AppEvent.Kind.mouseMotion);
  mouseEv.windowId = 1;
  mouseEv.x = 150.5f;
  mouseEv.y = 250.0f;
  assert(mouseEv.kind == AppEvent.Kind.mouseMotion);
  assert(mouseEv.windowId == 1);
  assert(mouseEv.x == 150.5f);
  assert(mouseEv.y == 250.0f);
  assert(mouseEv.mouse.x == 150.5f);

  AppEvent keyEv = AppEvent(AppEvent.Kind.keyDown);
  keyEv.windowId = 1;
  keyEv.key = Keycode.return_;
  keyEv.scancode = Scancode.return_;
  keyEv.mod = 0x0001;
  keyEv.repeat = true;
  assert(keyEv.kind == AppEvent.Kind.keyDown);
  assert(keyEv.windowId == 1);
  assert((cast(uint)keyEv.key) == 13);
  assert((cast(uint)keyEv.scancode) == 40);
  assert(keyEv.mod == 1);
  assert(keyEv.repeat);
  assert(keyEv.keyData.mod == 1);

  AppEvent textEv = AppEvent(AppEvent.Kind.textInput);
  textEv.windowId = 1;
  textEv.text = "hello";
  assert(textEv.kind == AppEvent.Kind.textInput);
  assert(textEv.windowId == 1);
  assert(textEv.text == "hello");
  assert(textEv.textData.text == "hello");

  AppEvent editEv = AppEvent(AppEvent.Kind.textEditing);
  editEv.windowId = 1;
  editEv.text = "comp";
  editEv.editStart = 2;
  editEv.editLength = 1;
  assert(editEv.kind == AppEvent.Kind.textEditing);
  assert(editEv.windowId == 1);
  assert(editEv.text == "comp");
  assert(editEv.editStart == 2);
  assert(editEv.editLength == 1);
  assert(editEv.textData.editStart == 2);

  // Verify compact footprint: size should be 40 bytes instead of 80 bytes.
  static assert(AppEvent.sizeof == 40);
}
