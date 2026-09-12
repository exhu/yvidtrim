#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum yguilib_sdl3_EventType {
  YGUILIB_SDL3_EVENT_NONE = 0,
  YGUILIB_SDL3_EVENT_QUIT,
  YGUILIB_SDL3_EVENT_WINDOW_CLOSE,
  YGUILIB_SDL3_EVENT_WAKE,
  YGUILIB_SDL3_EVENT_UNKNOWN,
} yguilib_sdl3_EventType;

typedef struct yguilib_sdl3_Event {
  yguilib_sdl3_EventType type;
  uint32_t window_id;
} yguilib_sdl3_Event;

/**
 * Initializes SDL events and video subsystems and registers the wake event.
 *
 * @return 0 on success, or -1 on initialization failure.
 */
int yguilib_sdl3_init(void);

/**
 * Cleans up and shuts down SDL subsystems.
 */
void yguilib_sdl3_quit(void);

/**
 * Registers a custom SDL event type for waking the event loop.
 *
 * @return The registered 32-bit SDL event type ID, or 0 on failure.
 */
uint32_t yguilib_sdl3_register_wake_event(void);

/**
 * Pushes a custom wake event to the SDL event queue.
 * Safe to call from any thread.
 *
 * @return 0 on success, or -1 on failure (e.g. queue full or not initialized).
 */
int yguilib_sdl3_send_wake_event(void);

/**
 * Waits for an SDL event, converting supported events to yguilib_sdl3_Event.
 * If timeout_ms < 0, blocks indefinitely until an event arrives.
 * If timeout_ms >= 0, waits up to timeout_ms milliseconds.
 *
 * @param event Pointer to destination event structure to populate.
 * @param timeout_ms Maximum time to wait in ms (<0 for infinite).
 * @return 1 if an event was retrieved, 0 if timeout elapsed with no event,
 *         or -1 on error.
 */
int yguilib_sdl3_wait_event(yguilib_sdl3_Event *event, int timeout_ms);

/**
 * Polls for pending SDL events without blocking.
 *
 * @param event Pointer to destination event structure to populate.
 * @return 1 if an event was retrieved, 0 if no event is pending,
 *         or -1 on error.
 */
int yguilib_sdl3_poll_event(yguilib_sdl3_Event *event);

typedef struct yguilib_sdl3_Window yguilib_sdl3_Window;
typedef struct yguilib_sdl3_GLContext yguilib_sdl3_GLContext;

/**
 * Creates an SDL window configured for OpenGL ES 3.0.
 *
 * Sets SDL OpenGL attributes for OpenGL ES 3.0 and creates the window
 * with the SDL_WINDOW_OPENGL flag.
 *
 * @param title Window title (UTF-8).
 * @param w Window width in pixels.
 * @param h Window height in pixels.
 * @return Pointer to yguilib_sdl3_Window on success, or NULL on failure.
 */
yguilib_sdl3_Window *yguilib_sdl3_create_window(
  const char *title,
  int w,
  int h
);

/**
 * Destroys an SDL window created by yguilib_sdl3_create_window.
 *
 * @param window Pointer to the window handle to destroy.
 */
void yguilib_sdl3_destroy_window(yguilib_sdl3_Window *window);

/**
 * Gets the SDL window ID for the given window.
 *
 * @param window Pointer to the window handle.
 * @return Window ID, or 0 on error.
 */
uint32_t yguilib_sdl3_get_window_id(const yguilib_sdl3_Window *window);

/**
 * Creates an OpenGL ES 3.0 context for the given window.
 *
 * @param window Pointer to the window handle.
 * @return Pointer to yguilib_sdl3_GLContext on success, or NULL on failure.
 */
yguilib_sdl3_GLContext *yguilib_sdl3_gl_create_context(
  yguilib_sdl3_Window *window
);

/**
 * Destroys an OpenGL context created by yguilib_sdl3_gl_create_context.
 *
 * @param context Pointer to the context handle to destroy.
 */
void yguilib_sdl3_gl_destroy_context(yguilib_sdl3_GLContext *context);

/**
 * Makes the specified OpenGL context current on the given window.
 *
 * @param window Pointer to the window handle.
 * @param context Pointer to the GL context handle.
 * @return 0 on success, or -1 on failure.
 */
int yguilib_sdl3_gl_make_current(
  yguilib_sdl3_Window *window,
  yguilib_sdl3_GLContext *context
);

/**
 * Swaps the OpenGL display buffers for the specified window.
 *
 * @param window Pointer to the window handle.
 * @return 0 on success, or -1 on failure.
 */
int yguilib_sdl3_gl_swap_window(yguilib_sdl3_Window *window);

/**
 * Clears the active OpenGL color buffer with the given RGBA values.
 *
 * @param r Red component [0.0, 1.0].
 * @param g Green component [0.0, 1.0].
 * @param b Blue component [0.0, 1.0].
 * @param a Alpha component [0.0, 1.0].
 * @return 0 on success, or -1 on failure.
 */
int yguilib_sdl3_gl_clear(float r, float g, float b, float a);

int yguilib_sdl3_hello(void);

#ifdef __cplusplus
}
#endif
