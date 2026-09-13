module yguilib.events;

struct AppEvent {
  enum Kind {
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

  this(
    Kind kind,
    uint eventId = 0,
    int width = 0,
    int height = 0,
    Object data = null,
    float x = 0.0f,
    float y = 0.0f,
    float scale = 1.0f
  ) {
    this.kind = kind;
    this.eventId = eventId;
    this.width = width;
    this.height = height;
    this.data = data;
    this.x = x;
    this.y = y;
    this.scale = scale;
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
}

