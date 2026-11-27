#include "yguilib_sdl3.h"
#include <SDL3/SDL.h>
#include <assert.h>
#include <stddef.h>
#include <string.h>

_Static_assert(sizeof(yguilib_sdl3_Rect) == 16, "Rect size");
_Static_assert(offsetof(yguilib_sdl3_Rect, h) == 12, "Rect.h offset");
_Static_assert(sizeof(yguilib_sdl3_WindowEvent) == 20, "WindowEvent size");
_Static_assert(
  offsetof(yguilib_sdl3_WindowEvent, scale) == 16,
  "WindowEvent.scale offset"
);
_Static_assert(
  sizeof(yguilib_sdl3_MouseMotionEvent) == 28,
  "MouseMotionEvent size"
);
_Static_assert(
  offsetof(yguilib_sdl3_MouseMotionEvent, yrel) == 24,
  "MouseMotionEvent.yrel offset"
);
_Static_assert(
  sizeof(yguilib_sdl3_MouseButtonEvent) == 20,
  "MouseButtonEvent size"
);
_Static_assert(
  offsetof(yguilib_sdl3_MouseButtonEvent, padding) == 19,
  "MouseButtonEvent.padding offset"
);
_Static_assert(
  sizeof(yguilib_sdl3_MouseWheelEvent) == 36,
  "MouseWheelEvent size"
);
_Static_assert(
  offsetof(yguilib_sdl3_MouseWheelEvent, integer_y) == 32,
  "MouseWheelEvent.integer_y offset"
);
_Static_assert(sizeof(yguilib_sdl3_KeyEvent) == 20, "KeyEvent size");
_Static_assert(
  offsetof(yguilib_sdl3_KeyEvent, padding) == 19,
  "KeyEvent.padding offset"
);
_Static_assert(
  sizeof(yguilib_sdl3_TextEditingEvent) == (sizeof(void *) == 8 ? 24 : 20),
  "TextEditingEvent size"
);
_Static_assert(
  offsetof(yguilib_sdl3_TextEditingEvent, text) == 8,
  "TextEditingEvent.text offset"
);
_Static_assert(
  sizeof(yguilib_sdl3_TextInputEvent) == (sizeof(void *) == 8 ? 16 : 12),
  "TextInputEvent size"
);
_Static_assert(
  offsetof(yguilib_sdl3_TextInputEvent, text) == 8,
  "TextInputEvent.text offset"
);
_Static_assert(
  sizeof(yguilib_sdl3_Event) == (sizeof(void *) == 8 ? 40 : 36),
  "Event union size"
);

/* Boundary SDL3 enum checks matching sdl3.d. */
_Static_assert(SDL_SCANCODE_UNKNOWN == 0, "Scancode.unknown");
_Static_assert(SDL_SCANCODE_A == 4, "Scancode.a");
_Static_assert(SDL_SCANCODE_RETURN == 40, "Scancode.return_");
_Static_assert(SDL_SCANCODE_SPACE == 44, "Scancode.space");
_Static_assert(SDL_SCANCODE_ENDCALL == 290, "Scancode.endcall");
_Static_assert(SDL_SCANCODE_RESERVED == 400, "Scancode.reserved");
_Static_assert(SDL_SCANCODE_COUNT == 512, "Scancode.count");

_Static_assert(SDLK_UNKNOWN == 0, "Keycode.unknown");
_Static_assert(SDLK_RETURN == 13, "Keycode.return_");
_Static_assert(SDLK_ESCAPE == 27, "Keycode.escape");
_Static_assert(SDLK_A == 'a', "Keycode.a");
_Static_assert(SDLK_F1 == 0x4000003au, "Keycode.f1");
_Static_assert(SDLK_ENDCALL == 0x40000122u, "Keycode.endcall");
_Static_assert(SDLK_RHYPER == 0x20000007u, "Keycode.rhyper");

_Static_assert(SDL_KMOD_NONE == 0x0000u, "Keymod.none");
_Static_assert(SDL_KMOD_LSHIFT == 0x0001u, "Keymod.lshift");
_Static_assert(SDL_KMOD_RSHIFT == 0x0002u, "Keymod.rshift");
_Static_assert(SDL_KMOD_LCTRL == 0x0040u, "Keymod.lctrl");
_Static_assert(SDL_KMOD_RCTRL == 0x0080u, "Keymod.rctrl");
_Static_assert(SDL_KMOD_SCROLL == 0x8000u, "Keymod.scroll");
_Static_assert(
  SDL_KMOD_CTRL == (SDL_KMOD_LCTRL | SDL_KMOD_RCTRL),
  "Keymod.ctrl"
);
_Static_assert(
  SDL_KMOD_SHIFT == (SDL_KMOD_LSHIFT | SDL_KMOD_RSHIFT),
  "Keymod.shift"
);

int main(void) {
  int init_res = yguilib_sdl3_init();
  assert(init_res == 0);
  assert(YGUILIB_SDL3_EVENT_WINDOW_EXPOSED > 0);

  yguilib_sdl3_Event ev;
  // Drain any startup device events (e.g. SDL_EVENT_MOUSE_ADDED).
  while (yguilib_sdl3_poll_event(&ev) == 1) {
  }

  int send_res = yguilib_sdl3_send_wake_event();
  assert(send_res == 0);

  int wait_res = yguilib_sdl3_wait_event(&ev, 1000);
  assert(wait_res == 1);
  assert(ev.type == YGUILIB_SDL3_EVENT_WAKE);

  int timeout_res = yguilib_sdl3_wait_event(&ev, 10);
  assert(timeout_res == 0);
  assert(ev.type == YGUILIB_SDL3_EVENT_NONE);

  yguilib_sdl3_Window *win =
    yguilib_sdl3_create_window("test_window", 320, 240);
  assert(win != NULL);

  uint32_t wid = yguilib_sdl3_get_window_id(win);
  assert(wid > 0);

  yguilib_sdl3_GLContext *ctx = yguilib_sdl3_gl_create_context(win);
  assert(ctx != NULL);

  int make_curr_res = yguilib_sdl3_gl_make_current(win, ctx);
  assert(make_curr_res == 0);

  yguilib_sdl3_GLProc proc = yguilib_sdl3_gl_get_proc_address("glClear");
  assert(proc != NULL);

  int swap_res = yguilib_sdl3_gl_swap_window(win);
  assert(swap_res == 0);

  int set_size_res = yguilib_sdl3_set_window_size(win, 640, 480);
  assert(set_size_res == 0);

  int cur_w = 0;
  int cur_h = 0;
  int get_size_res = yguilib_sdl3_get_window_size_in_pixels(
    win,
    &cur_w,
    &cur_h
  );
  assert(get_size_res == 0);
  assert(cur_w > 0 && cur_h > 0);

  float display_scale = yguilib_sdl3_get_window_display_scale(win);
  assert(display_scale > 0.0f);
  assert(YGUILIB_SDL3_EVENT_WINDOW_MOUSE_ENTER > 0);
  assert(YGUILIB_SDL3_EVENT_WINDOW_MOUSE_LEAVE > 0);
  assert(YGUILIB_SDL3_EVENT_MOUSE_WHEEL > 0);

  int start_text_res = yguilib_sdl3_start_text_input(win);
  assert(start_text_res == 0);

  yguilib_sdl3_Rect text_area = {10, 20, 100, 30};
  int set_area_res = yguilib_sdl3_set_text_input_area(win, &text_area, 5);
  assert(set_area_res == 0);

  int clear_area_res = yguilib_sdl3_set_text_input_area(win, NULL, 0);
  assert(clear_area_res == 0);

  int stop_text_res = yguilib_sdl3_stop_text_input(win);
  assert(stop_text_res == 0);

  // Release mouse capture (returns 0 on desktop backends, or -1 if unsupported)
  (void)yguilib_sdl3_capture_mouse(0);

  // Invalid window id must fail for relative mode and warp
  assert(yguilib_sdl3_set_relative_mouse_mode(0, 1) == -1);
  assert(yguilib_sdl3_warp_mouse_in_window(0, 1.0f, 1.0f) == -1);

  // Relative mode may be unsupported on the dummy driver; ignore result
  (void)yguilib_sdl3_set_relative_mouse_mode(wid, 1);
  (void)yguilib_sdl3_set_relative_mouse_mode(wid, 0);
  assert(yguilib_sdl3_warp_mouse_in_window(wid, 10.0f, 10.0f) == 0);

  yguilib_sdl3_gl_destroy_context(ctx);
  yguilib_sdl3_destroy_window(win);

  const char *key_name = yguilib_sdl3_get_key_name('a');
  assert(key_name != NULL && strcmp(key_name, "A") == 0);

  uint32_t key_ret = yguilib_sdl3_get_key_from_name("Return");
  assert(key_ret == 13);

  yguilib_sdl3_log_priority(
    YGUILIB_SDL3_LOG_PRIORITY_INFO,
    "Testing yguilib_sdl3_log_priority info"
  );
  yguilib_sdl3_log_priority(
    YGUILIB_SDL3_LOG_PRIORITY_WARN,
    "Testing yguilib_sdl3_log_priority warn"
  );

  yguilib_sdl3_quit();
  return 0;
}
