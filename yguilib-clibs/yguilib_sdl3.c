#include "yguilib_sdl3.h"

#include <SDL3/SDL.h>

static int g_sdl_initialized = 0;
static uint32_t g_wake_event_type = 0;

static int convert_sdl_event(const SDL_Event *src, yguilib_sdl3_Event *dst) {
  dst->window_id = 0;
  if (g_wake_event_type != 0 && src->type == g_wake_event_type) {
    dst->type = YGUILIB_SDL3_EVENT_WAKE;
    return 1;
  }
  switch (src->type) {
    case SDL_EVENT_QUIT:
      dst->type = YGUILIB_SDL3_EVENT_QUIT;
      return 1;
    case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
      dst->type = YGUILIB_SDL3_EVENT_WINDOW_CLOSE;
      dst->window_id = src->window.windowID;
      return 1;
    default:
      dst->type = YGUILIB_SDL3_EVENT_UNKNOWN;
      return 1;
  }
}

uint32_t yguilib_sdl3_register_wake_event(void) {
  if (g_wake_event_type != 0 && g_wake_event_type != (uint32_t)-1) {
    return g_wake_event_type;
  }
  uint32_t ev = SDL_RegisterEvents(1);
  if (ev == (uint32_t)-1) {
    return 0;
  }
  g_wake_event_type = ev;
  return g_wake_event_type;
}

int yguilib_sdl3_init(void) {
  if (!g_sdl_initialized) {
    if (!SDL_Init(SDL_INIT_EVENTS | SDL_INIT_VIDEO)) {
      return -1;
    }
    if (yguilib_sdl3_register_wake_event() == 0) {
      SDL_Quit();
      return -1;
    }
    g_sdl_initialized = 1;
  }
  return 0;
}

void yguilib_sdl3_quit(void) {
  if (g_sdl_initialized) {
    SDL_Quit();
    g_sdl_initialized = 0;
    g_wake_event_type = 0;
  }
}

int yguilib_sdl3_send_wake_event(void) {
  if (g_wake_event_type == 0 || g_wake_event_type == (uint32_t)-1) {
    return -1;
  }
  SDL_Event event;
  SDL_zero(event);
  event.type = g_wake_event_type;
  return SDL_PushEvent(&event) ? 0 : -1;
}

int yguilib_sdl3_wait_event(yguilib_sdl3_Event *event, int timeout_ms) {
  if (!event) {
    return -1;
  }
  SDL_Event sdl_event;
  bool ok;
  if (timeout_ms < 0) {
    ok = SDL_WaitEvent(&sdl_event);
  } else {
    ok = SDL_WaitEventTimeout(&sdl_event, (Sint32)timeout_ms);
  }
  if (!ok) {
    event->type = YGUILIB_SDL3_EVENT_NONE;
    event->window_id = 0;
    return 0;
  }
  return convert_sdl_event(&sdl_event, event);
}

int yguilib_sdl3_poll_event(yguilib_sdl3_Event *event) {
  if (!event) {
    return -1;
  }
  SDL_Event sdl_event;
  if (!SDL_PollEvent(&sdl_event)) {
    event->type = YGUILIB_SDL3_EVENT_NONE;
    event->window_id = 0;
    return 0;
  }
  return convert_sdl_event(&sdl_event, event);
}

int yguilib_sdl3_hello(void) {
  return 0;
}
