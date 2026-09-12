/// bindings to yguilib-clib-sdl C library
module yguilib.clibs.sdl3;

enum yguilib_sdl3_EventType : int {
  none = 0,
  quit,
  windowClose,
  windowResized,
  windowExposed,
  wake,
  unknown,
}

struct yguilib_sdl3_Event {
  yguilib_sdl3_EventType type;
  uint windowId;
  int width;
  int height;
}

struct yguilib_sdl3_Window;
struct yguilib_sdl3_GLContext;

enum yguilib_sdl3_LogPriority : int {
  verbose = 1,
  debug_ = 2,
  info = 3,
  warn = 4,
  error = 5,
  critical = 6,
}

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
  int yguilib_sdl3_set_window_size(
    yguilib_sdl3_Window* window,
    int width,
    int height
  );
  int yguilib_sdl3_get_window_size_in_pixels(
    const(yguilib_sdl3_Window)* window,
    int* width,
    int* height
  );
  yguilib_sdl3_GLContext* yguilib_sdl3_gl_create_context(
    yguilib_sdl3_Window* window
  );
  void yguilib_sdl3_gl_destroy_context(yguilib_sdl3_GLContext* context);
  int yguilib_sdl3_gl_make_current(
    yguilib_sdl3_Window* window,
    yguilib_sdl3_GLContext* context
  );
  int yguilib_sdl3_gl_swap_window(yguilib_sdl3_Window* window);
  alias yguilib_sdl3_GLProc = extern(C) void function();
  yguilib_sdl3_GLProc yguilib_sdl3_gl_get_proc_address(const(char)* proc);
  int yguilib_sdl3_hello();
  void yguilib_sdl3_log(const(char)* message);
  void yguilib_sdl3_log_priority(
    yguilib_sdl3_LogPriority priority,
    const(char)* message
  );
}

