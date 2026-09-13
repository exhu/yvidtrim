#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum yguilib_sdl3_EventType {
  YGUILIB_SDL3_EVENT_NONE = 0,
  YGUILIB_SDL3_EVENT_QUIT,
  YGUILIB_SDL3_EVENT_WINDOW_CLOSE,
  YGUILIB_SDL3_EVENT_WINDOW_RESIZED,
  YGUILIB_SDL3_EVENT_WINDOW_EXPOSED,
  YGUILIB_SDL3_EVENT_WINDOW_DISPLAY_SCALE_CHANGED,
  YGUILIB_SDL3_EVENT_MOUSE_MOTION,
  YGUILIB_SDL3_EVENT_MOUSE_BUTTON_DOWN,
  YGUILIB_SDL3_EVENT_MOUSE_BUTTON_UP,
  YGUILIB_SDL3_EVENT_KEY_DOWN,
  YGUILIB_SDL3_EVENT_KEY_UP,
  YGUILIB_SDL3_EVENT_TEXT_EDITING,
  YGUILIB_SDL3_EVENT_TEXT_INPUT,
  YGUILIB_SDL3_EVENT_WAKE,
  YGUILIB_SDL3_EVENT_UNKNOWN,
} yguilib_sdl3_EventType;

typedef struct yguilib_sdl3_Rect {
  int32_t x;
  int32_t y;
  int32_t w;
  int32_t h;
} yguilib_sdl3_Rect;

typedef struct yguilib_sdl3_Event {
  yguilib_sdl3_EventType type;
  uint32_t window_id;
  int32_t width;
  int32_t height;
  float x;
  float y;
  float scale;
  uint32_t key;
  uint32_t scancode;
  uint16_t mod;
  uint8_t repeat;
  uint8_t padding;
  const char *text;
  int32_t start;
  int32_t length;
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
 * Sets the window size in pixels / screen coordinates.
 *
 * @param window Pointer to the window handle.
 * @param width New width.
 * @param height New height.
 * @return 0 on success, or -1 on failure.
 */
int yguilib_sdl3_set_window_size(
  yguilib_sdl3_Window *window,
  int width,
  int height
);

/**
 * Gets the size of the window in pixels.
 *
 * @param window Pointer to the window handle.
 * @param width Pointer to int receiving width.
 * @param height Pointer to int receiving height.
 * @return 0 on success, or -1 on failure.
 */
int yguilib_sdl3_get_window_size_in_pixels(
  const yguilib_sdl3_Window *window,
  int *width,
  int *height
);

/**
 * Gets the display scale factor for the given window.
 *
 * @param window Pointer to the window handle.
 * @return Display scale factor (e.g. 1.0 for 100%, 2.0 for 200%), or
 *         0.0f on failure.
 */
float yguilib_sdl3_get_window_display_scale(const yguilib_sdl3_Window *window);

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

typedef void (*yguilib_sdl3_GLProc)(void);

/**
 * Gets the address of an OpenGL ES function.
 *
 * @param proc Function name (UTF-8).
 * @return Function pointer, or NULL if unavailable.
 */
yguilib_sdl3_GLProc yguilib_sdl3_gl_get_proc_address(const char *proc);

int yguilib_sdl3_hello(void);

typedef enum yguilib_sdl3_LogPriority {
  YGUILIB_SDL3_LOG_PRIORITY_VERBOSE = 1,
  YGUILIB_SDL3_LOG_PRIORITY_DEBUG = 2,
  YGUILIB_SDL3_LOG_PRIORITY_INFO = 3,
  YGUILIB_SDL3_LOG_PRIORITY_WARN = 4,
  YGUILIB_SDL3_LOG_PRIORITY_ERROR = 5,
  YGUILIB_SDL3_LOG_PRIORITY_CRITICAL = 6,
} yguilib_sdl3_LogPriority;

/**
 * Logs a message using SDL_Log.
 *
 * @param message Null-terminated UTF-8 message.
 */
void yguilib_sdl3_log(const char *message);

/**
 * Logs a message with specified priority using SDL_LogMessage.
 *
 * @param priority Log priority level.
 * @param message Null-terminated UTF-8 message.
 */
void yguilib_sdl3_log_priority(
  yguilib_sdl3_LogPriority priority,
  const char *message
);

/**
 * Starts accepting Unicode text input in the given window.
 *
 * @param window Pointer to the window handle.
 * @return 0 on success, or -1 on failure.
 */
int yguilib_sdl3_start_text_input(yguilib_sdl3_Window *window);

/**
 * Stops accepting Unicode text input in the given window.
 *
 * @param window Pointer to the window handle.
 * @return 0 on success, or -1 on failure.
 */
int yguilib_sdl3_stop_text_input(yguilib_sdl3_Window *window);

/**
 * Sets the rectangle used to type Unicode text input and position IME candidate
 * windows.
 *
 * @param window Pointer to the window handle.
 * @param rect Pointer to the area rectangle, or NULL to clear it.
 * @param cursor Cursor offset relative to rect->x.
 * @return 0 on success, or -1 on failure.
 */
int yguilib_sdl3_set_text_input_area(
  yguilib_sdl3_Window *window,
  const yguilib_sdl3_Rect *rect,
  int cursor
);

/**
 * Gets the key code corresponding to the given scancode and modifier state.
 *
 * @param scancode SDL scancode value.
 * @param modstate Modifier state.
 * @param key_event Non-zero if the keycode will be used in key events.
 * @return The keycode value, or 0 on failure.
 */
uint32_t yguilib_sdl3_get_key_from_scancode(
  uint32_t scancode,
  uint16_t modstate,
  int key_event
);

/**
 * Gets a human-readable name for a key.
 *
 * @param key The keycode value.
 * @return Pointer to UTF-8 name string, or "" if not found.
 */
const char *yguilib_sdl3_get_key_name(uint32_t key);

/**
 * Gets a key code from a human-readable name.
 *
 * @param name UTF-8 key name.
 * @return Key code, or 0 if not recognized.
 */
uint32_t yguilib_sdl3_get_key_from_name(const char *name);

/**
 * Gets a scancode from a human-readable name.
 *
 * @param name UTF-8 scancode name.
 * @return Scancode value, or 0 if not recognized.
 */
uint32_t yguilib_sdl3_get_scancode_from_name(const char *name);

/**
 * Gets a human-readable name for a scancode.
 *
 * @param scancode Scancode value.
 * @return Pointer to UTF-8 name string, or "" if not found.
 */
const char *yguilib_sdl3_get_scancode_name(uint32_t scancode);

#ifdef __cplusplus
}
#endif

