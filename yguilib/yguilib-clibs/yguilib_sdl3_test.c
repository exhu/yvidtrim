#include "yguilib_sdl3.h"
#include <assert.h>
#include <stddef.h>
#include <string.h>

int main(void) {
  assert(yguilib_sdl3_hello() == 0);

  int init_res = yguilib_sdl3_init();
  assert(init_res == 0);
  assert(YGUILIB_SDL3_EVENT_WINDOW_EXPOSED > 0);

  uint32_t wake_type = yguilib_sdl3_register_wake_event();
  assert(wake_type > 0);

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
  assert(sizeof(yguilib_sdl3_Event) == 56);

  int start_text_res = yguilib_sdl3_start_text_input(win);
  assert(start_text_res == 0);

  yguilib_sdl3_Rect text_area = {10, 20, 100, 30};
  int set_area_res = yguilib_sdl3_set_text_input_area(win, &text_area, 5);
  assert(set_area_res == 0);

  int clear_area_res = yguilib_sdl3_set_text_input_area(win, NULL, 0);
  assert(clear_area_res == 0);

  int stop_text_res = yguilib_sdl3_stop_text_input(win);
  assert(stop_text_res == 0);

  yguilib_sdl3_gl_destroy_context(ctx);
  yguilib_sdl3_destroy_window(win);

  uint32_t scancode_a = yguilib_sdl3_get_scancode_from_name("A");
  assert(scancode_a == 4);

  const char *scancode_name = yguilib_sdl3_get_scancode_name(4);
  assert(scancode_name != NULL && strcmp(scancode_name, "A") == 0);

  uint32_t key_a = yguilib_sdl3_get_key_from_scancode(4, 0, 0);
  assert(key_a == 'a');

  const char *key_name = yguilib_sdl3_get_key_name('a');
  assert(key_name != NULL && strcmp(key_name, "A") == 0);

  uint32_t key_ret = yguilib_sdl3_get_key_from_name("Return");
  assert(key_ret == 13);

  yguilib_sdl3_log("Testing yguilib_sdl3_log output");
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
