#include "yguilib_sdl3.h"
#include <assert.h>

int main(void) {
  assert(yguilib_sdl3_hello() == 0);

  int init_res = yguilib_sdl3_init();
  assert(init_res == 0);

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

  yguilib_sdl3_quit();
  return 0;
}
