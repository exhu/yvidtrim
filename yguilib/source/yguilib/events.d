module yguilib.events;
import yguilib.keyboard;

struct AppEvent {
  enum Kind {
    /// when this event is received controller should run update logic
    update,
    /// user defined global events
    user,
    /// events that are produced by uisystem controls
    view,
    windowClose,
    windowResized,
    windowExposed,
    windowDisplayScaleChanged,
    windowRedraw,
    mouseMotion,
    mouseButtonDown,
    mouseButtonUp,
    keyDown,
    keyUp,
    textEditing,
    textInput,
    appQuit,
  }

  Kind kind;
  uint eventId = 0;
  int width = 0;
  int height = 0;
  Object data = null;
  float x = 0.0f;
  float y = 0.0f;
  float scale = 1.0f;
  KeyCode key;
  ScanCode scancode;
  ushort mod = 0;
  bool repeat = false;
  string text = null;
  int editStart = 0;
  int editLength = 0;

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
    int editLength = 0
  ) {
    this.kind = kind;
    this.eventId = eventId;
    this.width = width;
    this.height = height;
    this.data = data;
    this.x = x;
    this.y = y;
    this.scale = scale;
    this.key = cast(KeyCode)key;
    this.scancode = cast(ScanCode)scancode;
    this.mod = mod;
    this.repeat = repeat;
    this.text = text;
    this.editStart = editStart;
    this.editLength = editLength;
  }
}

unittest {
  AppEvent ev = AppEvent(AppEvent.Kind.windowDisplayScaleChanged, 1, 640, 480);
  ev.scale = 2.0f;
  assert(ev.kind == AppEvent.Kind.windowDisplayScaleChanged);
  assert(ev.scale == 2.0f);
  assert(ev.width == 640);
  assert(ev.height == 480);

  AppEvent mouseEv = AppEvent(
    AppEvent.Kind.mouseMotion,
    1,
    0,
    0,
    null,
    150.5f,
    250.0f
  );
  assert(mouseEv.kind == AppEvent.Kind.mouseMotion);
  assert(mouseEv.x == 150.5f);
  assert(mouseEv.y == 250.0f);

  AppEvent keyEv = AppEvent(AppEvent.Kind.keyDown, 1);
  keyEv.key = KeyCode.return_;
  keyEv.scancode = ScanCode.return_;
  keyEv.mod = 0x0001;
  keyEv.repeat = true;
  assert(keyEv.kind == AppEvent.Kind.keyDown);
  assert((cast(uint)keyEv.key) == 13);
  assert((cast(uint)keyEv.scancode) == 40);
  assert(keyEv.mod == 1);
  assert(keyEv.repeat);

  AppEvent textEv = AppEvent(AppEvent.Kind.textInput, 1);
  textEv.text = "hello";
  assert(textEv.kind == AppEvent.Kind.textInput);
  assert(textEv.text == "hello");

  AppEvent editEv = AppEvent(AppEvent.Kind.textEditing, 1);
  editEv.text = "comp";
  editEv.editStart = 2;
  editEv.editLength = 1;
  assert(editEv.kind == AppEvent.Kind.textEditing);
  assert(editEv.text == "comp");
  assert(editEv.editStart == 2);
  assert(editEv.editLength == 1);
}
