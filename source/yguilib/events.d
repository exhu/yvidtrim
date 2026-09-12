module yguilib.events;

struct AppEvent {
  enum Kind {
    /// user defined global events
    user,
    /// events that are produced by uisystem controls
    view,
    windowClose,
    windowResized,
    appQuit,
  }

  Kind kind;
  uint eventId = 0;
  int width = 0;
  int height = 0;
  Object data = null;

  this(
    Kind kind,
    uint eventId = 0,
    int width = 0,
    int height = 0,
    Object data = null
  ) {
    this.kind = kind;
    this.eventId = eventId;
    this.width = width;
    this.height = height;
    this.data = data;
  }
}

