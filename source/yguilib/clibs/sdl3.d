/// bindings to yguilib-clib-sdl C library
module yguilib.clibs.sdl3;

enum yguilib_sdl3_EventType : int {
  none = 0,
  quit,
  windowClose,
  wake,
  unknown,
}

struct yguilib_sdl3_Event {
  yguilib_sdl3_EventType type;
  uint windowId;
}

extern(C) {
  int yguilib_sdl3_init();
  void yguilib_sdl3_quit();
  uint yguilib_sdl3_register_wake_event();
  int yguilib_sdl3_send_wake_event();
  int yguilib_sdl3_wait_event(yguilib_sdl3_Event* event, int timeoutMs);
  int yguilib_sdl3_poll_event(yguilib_sdl3_Event* event);
  int yguilib_sdl3_hello();
}
