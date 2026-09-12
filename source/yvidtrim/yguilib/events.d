module yvidtrim.yguilib.events;
struct AppEvent {
  enum Kind {
    /// user defined global events
    user,
    /// events that are produced by uisystem controls
    view,
    windowClose,
    appQuit,
  }

  Kind kind;
  uint eventId;
  Object data;
}
