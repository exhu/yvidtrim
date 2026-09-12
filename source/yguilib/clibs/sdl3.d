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

struct yguilib_sdl3_Window;
struct yguilib_sdl3_GLContext;

extern(C) {
  int yguilib_sdl3_init();
  void yguilib_sdl3_quit();
  uint yguilib_sdl3_register_wake_event();
  int yguilib_sdl3_send_wake_event();
  int yguilib_sdl3_wait_event(yguilib_sdl3_Event* event, int timeoutMs);
  int yguilib_sdl3_poll_event(yguilib_sdl3_Event* event);
  yguilib_sdl3_Window* yguilib_sdl3_create_window(
    const(char)* title,
    int w,
    int h
  );
  void yguilib_sdl3_destroy_window(yguilib_sdl3_Window* window);
  uint yguilib_sdl3_get_window_id(const(yguilib_sdl3_Window)* window);
  yguilib_sdl3_GLContext* yguilib_sdl3_gl_create_context(
    yguilib_sdl3_Window* window
  );
  void yguilib_sdl3_gl_destroy_context(yguilib_sdl3_GLContext* context);
  int yguilib_sdl3_gl_make_current(
    yguilib_sdl3_Window* window,
    yguilib_sdl3_GLContext* context
  );
  int yguilib_sdl3_gl_swap_window(yguilib_sdl3_Window* window);
  int yguilib_sdl3_gl_clear(float r, float g, float b, float a);
  int yguilib_sdl3_hello();
}

