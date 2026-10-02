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
  SDL_zerop(dst);
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
      dst->window.window_id = src->window.windowID;
      return 1;
    case SDL_EVENT_WINDOW_EXPOSED: {
      dst->type = YGUILIB_SDL3_EVENT_WINDOW_EXPOSED;
      dst->window.window_id = src->window.windowID;
      dst->window.scale = 1.0f;
      int pw = 0;
      int ph = 0;
      SDL_Window *win = SDL_GetWindowFromID(src->window.windowID);
      if (win) {
        SDL_GetWindowSizeInPixels(win, &pw, &ph);
        dst->window.scale = SDL_GetWindowDisplayScale(win);
      }
      dst->window.width = pw;
      dst->window.height = ph;
      return 1;
    }
    case SDL_EVENT_WINDOW_RESIZED:
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED: {
      dst->type = YGUILIB_SDL3_EVENT_WINDOW_RESIZED;
      dst->window.window_id = src->window.windowID;
      dst->window.scale = 1.0f;
      int pw = (int)src->window.data1;
      int ph = (int)src->window.data2;
      SDL_Window *win = SDL_GetWindowFromID(src->window.windowID);
      if (win) {
        SDL_GetWindowSizeInPixels(win, &pw, &ph);
        dst->window.scale = SDL_GetWindowDisplayScale(win);
      }
      dst->window.width = pw;
      dst->window.height = ph;
      return 1;
    }
    case SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED: {
      dst->type = YGUILIB_SDL3_EVENT_WINDOW_DISPLAY_SCALE_CHANGED;
      dst->window.window_id = src->window.windowID;
      dst->window.scale = 1.0f;
      SDL_Window *win = SDL_GetWindowFromID(src->window.windowID);
      if (win) {
        int pw = 0;
        int ph = 0;
        SDL_GetWindowSizeInPixels(win, &pw, &ph);
        dst->window.width = pw;
        dst->window.height = ph;
        dst->window.scale = SDL_GetWindowDisplayScale(win);
      }
      return 1;
    }
    case SDL_EVENT_MOUSE_MOTION: {
      dst->type = YGUILIB_SDL3_EVENT_MOUSE_MOTION;
      dst->motion.window_id = src->motion.windowID;
      dst->motion.x = src->motion.x;
      dst->motion.y = src->motion.y;
      dst->motion.state = (uint32_t)src->motion.state;
      dst->motion.xrel = src->motion.xrel;
      dst->motion.yrel = src->motion.yrel;
      return 1;
    }
    case SDL_EVENT_MOUSE_BUTTON_DOWN: {
      dst->type = YGUILIB_SDL3_EVENT_MOUSE_BUTTON_DOWN;
      dst->button.window_id = src->button.windowID;
      dst->button.x = src->button.x;
      dst->button.y = src->button.y;
      dst->button.button = src->button.button;
      dst->button.down = 1;
      dst->button.clicks = src->button.clicks;
      return 1;
    }
    case SDL_EVENT_MOUSE_BUTTON_UP: {
      dst->type = YGUILIB_SDL3_EVENT_MOUSE_BUTTON_UP;
      dst->button.window_id = src->button.windowID;
      dst->button.x = src->button.x;
      dst->button.y = src->button.y;
      dst->button.button = src->button.button;
      dst->button.down = 0;
      dst->button.clicks = src->button.clicks;
      return 1;
    }
    case SDL_EVENT_MOUSE_WHEEL: {
      dst->type = YGUILIB_SDL3_EVENT_MOUSE_WHEEL;
      dst->wheel.window_id = src->wheel.windowID;
      dst->wheel.x = src->wheel.x;
      dst->wheel.y = src->wheel.y;
      dst->wheel.mouse_x = src->wheel.mouse_x;
      dst->wheel.mouse_y = src->wheel.mouse_y;
      dst->wheel.direction = (int32_t)src->wheel.direction;
      dst->wheel.integer_x = src->wheel.integer_x;
      dst->wheel.integer_y = src->wheel.integer_y;
      return 1;
    }
    case SDL_EVENT_KEY_DOWN:
    case SDL_EVENT_KEY_UP: {
      dst->type = (src->type == SDL_EVENT_KEY_DOWN)
        ? YGUILIB_SDL3_EVENT_KEY_DOWN
        : YGUILIB_SDL3_EVENT_KEY_UP;
      dst->key.window_id = src->key.windowID;
      dst->key.key = (uint32_t)src->key.key;
      dst->key.scancode = (uint32_t)src->key.scancode;
      dst->key.mod = (uint16_t)src->key.mod;
      dst->key.repeat = src->key.repeat ? 1 : 0;
      return 1;
    }
    case SDL_EVENT_TEXT_EDITING: {
      dst->type = YGUILIB_SDL3_EVENT_TEXT_EDITING;
      dst->text_editing.window_id = src->edit.windowID;
      dst->text_editing.text = src->edit.text;
      dst->text_editing.start = src->edit.start;
      dst->text_editing.length = src->edit.length;
      return 1;
    }
    case SDL_EVENT_TEXT_INPUT: {
      dst->type = YGUILIB_SDL3_EVENT_TEXT_INPUT;
      dst->text_input.window_id = src->text.windowID;
      dst->text_input.text = src->text.text;
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
    SDL_zerop(event);
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
    SDL_zerop(event);
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

int yguilib_sdl3_start_text_input(yguilib_sdl3_Window *window) {
  if (!window || !window->handle) {
    return -1;
  }
  return SDL_StartTextInput(window->handle) ? 0 : -1;
}

int yguilib_sdl3_stop_text_input(yguilib_sdl3_Window *window) {
  if (!window || !window->handle) {
    return -1;
  }
  return SDL_StopTextInput(window->handle) ? 0 : -1;
}

int yguilib_sdl3_set_text_input_area(
  yguilib_sdl3_Window *window,
  const yguilib_sdl3_Rect *rect,
  int cursor
) {
  if (!window || !window->handle) {
    return -1;
  }
  SDL_Rect sdl_rect;
  const SDL_Rect *p_sdl_rect = NULL;
  if (rect) {
    sdl_rect.x = rect->x;
    sdl_rect.y = rect->y;
    sdl_rect.w = rect->w;
    sdl_rect.h = rect->h;
    p_sdl_rect = &sdl_rect;
  }
  return SDL_SetTextInputArea(window->handle, p_sdl_rect, cursor) ? 0 : -1;
}

uint32_t yguilib_sdl3_get_key_from_scancode(
  uint32_t scancode,
  uint16_t modstate,
  int key_event
) {
  return (uint32_t)SDL_GetKeyFromScancode(
    (SDL_Scancode)scancode,
    (SDL_Keymod)modstate,
    key_event != 0
  );
}

const char *yguilib_sdl3_get_key_name(uint32_t key) {
  return SDL_GetKeyName((SDL_Keycode)key);
}

uint32_t yguilib_sdl3_get_key_from_name(const char *name) {
  if (!name) {
    return 0;
  }
  return (uint32_t)SDL_GetKeyFromName(name);
}

uint32_t yguilib_sdl3_get_scancode_from_name(const char *name) {
  if (!name) {
    return 0;
  }
  return (uint32_t)SDL_GetScancodeFromName(name);
}

const char *yguilib_sdl3_get_scancode_name(uint32_t scancode) {
  return SDL_GetScancodeName((SDL_Scancode)scancode);
}
