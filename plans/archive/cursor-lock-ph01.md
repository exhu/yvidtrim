# Cursor Lock Phase 1: C wrapper + D binding

Read AGENTS.md and codestyle.md first (2-space indent, 80 cols, C
snake_case, `yguilib_sdl3_` prefix).

## Steps
1. `yguilib/yguilib-clibs/yguilib_sdl3.h` (next to
   `yguilib_sdl3_capture_mouse`, ~line 393) declare with doc comments:
   - `int yguilib_sdl3_set_relative_mouse_mode(uint32_t window_id,
     int enabled);` -- enables/disables SDL relative mouse mode for the
     window (cursor hidden, motion reported as deltas).
   - `int yguilib_sdl3_warp_mouse_in_window(uint32_t window_id, float x,
     float y);` -- moves the cursor to window-relative position.
   Both return 0 on success, -1 on failure.
2. `yguilib/yguilib-clibs/yguilib_sdl3.c` (next to
   `yguilib_sdl3_capture_mouse`, ~line 451): implement. Return -1 when
   `!g_sdl_initialized`; look up `SDL_GetWindowFromID(window_id)`, return -1
   if NULL; call `SDL_SetWindowRelativeMouseMode(win, enabled != 0)` /
   `SDL_WarpMouseInWindow(win, x, y)` (void in SDL3 -> return 0).
3. `yguilib/yguilib-clibs/yguilib_sdl3_test.c`: add asserts that both
   return -1 for an invalid window id (e.g. 0) and, near the existing
   `capture_mouse(0)` call while the window exists, call them with the
   window's id if an id getter exists (check header); otherwise only the
   invalid-id checks. Keep test passing in headless/dummy video driver.
4. `yguilib/source/yguilib/clibs/sdl3.d`: add matching `extern(C)`
   declarations next to `yguilib_sdl3_capture_mouse` (~line 722).
5. Run `ninja -C _build && meson test -C _build`; all must pass.
