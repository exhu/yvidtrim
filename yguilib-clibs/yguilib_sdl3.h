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

int yguilib_sdl3_hello(void);

#ifdef __cplusplus
}
#endif
