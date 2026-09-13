#include "yguilib_sdl3.h"

#include <SDL3/SDL.h>
#include <stdlib.h>

struct yguilib_sdl3_Window {
  SDL_Window *handle;
};

struct yguilib_sdl3_GLContext {
  SDL_GLContext handle;
};

static int g_sdl_initialized = 0;
static uint32_t g_wake_event_type = 0;

static int convert_sdl_event(const SDL_Event *src, yguilib_sdl3_Event *dst) {
  dst->window_id = 0;
  dst->width = 0;
  dst->height = 0;
  dst->x = 0.0f;
  dst->y = 0.0f;
  dst->scale = 1.0f;
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
    case SDL_EVENT_WINDOW_EXPOSED: {
      dst->type = YGUILIB_SDL3_EVENT_WINDOW_EXPOSED;
      dst->window_id = src->window.windowID;
      int pw = 0;
      int ph = 0;
      SDL_Window *win = SDL_GetWindowFromID(src->window.windowID);
      if (win) {
        SDL_GetWindowSizeInPixels(win, &pw, &ph);
        dst->scale = SDL_GetWindowDisplayScale(win);
      }
      dst->width = pw;
      dst->height = ph;
      return 1;
    }
    case SDL_EVENT_WINDOW_RESIZED:
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED: {
      dst->type = YGUILIB_SDL3_EVENT_WINDOW_RESIZED;
      dst->window_id = src->window.windowID;
      int pw = (int)src->window.data1;
      int ph = (int)src->window.data2;
      SDL_Window *win = SDL_GetWindowFromID(src->window.windowID);
      if (win) {
        SDL_GetWindowSizeInPixels(win, &pw, &ph);
        dst->scale = SDL_GetWindowDisplayScale(win);
      }
      dst->width = pw;
      dst->height = ph;
      return 1;
    }
    case SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED: {
      dst->type = YGUILIB_SDL3_EVENT_WINDOW_DISPLAY_SCALE_CHANGED;
      dst->window_id = src->window.windowID;
      SDL_Window *win = SDL_GetWindowFromID(src->window.windowID);
      if (win) {
        int pw = 0;
        int ph = 0;
        SDL_GetWindowSizeInPixels(win, &pw, &ph);
        dst->width = pw;
        dst->height = ph;
        dst->scale = SDL_GetWindowDisplayScale(win);
      }
      return 1;
    }
    case SDL_EVENT_MOUSE_MOTION: {
      dst->type = YGUILIB_SDL3_EVENT_MOUSE_MOTION;
      dst->window_id = src->motion.windowID;
      dst->x = src->motion.x;
      dst->y = src->motion.y;
      return 1;
    }
    case SDL_EVENT_MOUSE_BUTTON_DOWN: {
      dst->type = YGUILIB_SDL3_EVENT_MOUSE_BUTTON_DOWN;
      dst->window_id = src->button.windowID;
      dst->x = src->button.x;
      dst->y = src->button.y;
      return 1;
    }
    case SDL_EVENT_MOUSE_BUTTON_UP: {
      dst->type = YGUILIB_SDL3_EVENT_MOUSE_BUTTON_UP;
      dst->window_id = src->button.windowID;
      dst->x = src->button.x;
      dst->y = src->button.y;
      return 1;
    }
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

yguilib_sdl3_Window *yguilib_sdl3_create_window(
  const char *title,
  int w,
  int h
) {
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);

  SDL_Window *sdl_win = SDL_CreateWindow(title, w, h, SDL_WINDOW_OPENGL |
    SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if (!sdl_win) {
    return NULL;
  }
  SDL_ShowWindow(sdl_win);
  SDL_SyncWindow(sdl_win);
  yguilib_sdl3_Window *win =
    (yguilib_sdl3_Window *)malloc(sizeof(yguilib_sdl3_Window));
  if (!win) {
    SDL_DestroyWindow(sdl_win);
    return NULL;
  }
  win->handle = sdl_win;
  return win;
}

void yguilib_sdl3_destroy_window(yguilib_sdl3_Window *window) {
  if (window) {
    if (window->handle) {
      SDL_DestroyWindow(window->handle);
    }
    free(window);
  }
}

uint32_t yguilib_sdl3_get_window_id(const yguilib_sdl3_Window *window) {
  if (!window || !window->handle) {
    return 0;
  }
  return SDL_GetWindowID(window->handle);
}

int yguilib_sdl3_set_window_size(
  yguilib_sdl3_Window *window,
  int width,
  int height
) {
  if (!window || !window->handle) {
    return -1;
  }
  return SDL_SetWindowSize(window->handle, width, height) ? 0 : -1;
}

int yguilib_sdl3_get_window_size_in_pixels(
  const yguilib_sdl3_Window *window,
  int *width,
  int *height
) {
  if (!window || !window->handle || !width || !height) {
    return -1;
  }
  return SDL_GetWindowSizeInPixels(window->handle, width, height) ? 0 : -1;
}

float yguilib_sdl3_get_window_display_scale(const yguilib_sdl3_Window *window) {
  if (!window || !window->handle) {
    return 0.0f;
  }
  return SDL_GetWindowDisplayScale(window->handle);
}

yguilib_sdl3_GLContext *yguilib_sdl3_gl_create_context(
  yguilib_sdl3_Window *window
) {
  if (!window || !window->handle) {
    return NULL;
  }
  SDL_GLContext sdl_ctx = SDL_GL_CreateContext(window->handle);
  if (!sdl_ctx) {
    return NULL;
  }
  yguilib_sdl3_GLContext *ctx =
    (yguilib_sdl3_GLContext *)malloc(sizeof(yguilib_sdl3_GLContext));
  if (!ctx) {
    SDL_GL_DestroyContext(sdl_ctx);
    return NULL;
  }
  ctx->handle = sdl_ctx;
  return ctx;
}

void yguilib_sdl3_gl_destroy_context(yguilib_sdl3_GLContext *context) {
  if (context) {
    if (context->handle) {
      SDL_GL_DestroyContext(context->handle);
    }
    free(context);
  }
}

int yguilib_sdl3_gl_make_current(
  yguilib_sdl3_Window *window,
  yguilib_sdl3_GLContext *context
) {
  if (!window || !window->handle || !context || !context->handle) {
    return -1;
  }
  return SDL_GL_MakeCurrent(window->handle, context->handle) ? 0 : -1;
}

int yguilib_sdl3_gl_swap_window(yguilib_sdl3_Window *window) {
  if (!window || !window->handle) {
    return -1;
  }
  return SDL_GL_SwapWindow(window->handle) ? 0 : -1;
}

yguilib_sdl3_GLProc yguilib_sdl3_gl_get_proc_address(const char *proc) {
  return (yguilib_sdl3_GLProc)SDL_GL_GetProcAddress(proc);
}

void yguilib_sdl3_log(const char *message) {
  if (message) {
    SDL_Log("%s", message);
  }
}

void yguilib_sdl3_log_priority(
  yguilib_sdl3_LogPriority priority,
  const char *message
) {
  if (message) {
    SDL_LogMessage(
      SDL_LOG_CATEGORY_APPLICATION,
      (SDL_LogPriority)priority,
      "%s",
      message
    );
  }
}
