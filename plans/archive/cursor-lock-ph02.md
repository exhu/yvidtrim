# Cursor Lock Phase 2: CursorCapture enum, builder, InputSystem

Read AGENTS.md and codestyle.md first. Phase 1 added C functions
`yguilib_sdl3_set_relative_mouse_mode(uint window_id, int enabled)` and
`yguilib_sdl3_warp_mouse_in_window(uint window_id, float x, float y)`
(D decls in `yguilib/source/yguilib/clibs/sdl3.d`). They return -1 when
SDL is not initialised (headless unit tests); logic must not depend on the
return value.

## Steps
1. `yguilib/source/yguilib/widget/input_components.d`: add documented
   `enum CursorCapture { none, capture, lock }`:
   - `capture`: SDL_CaptureMouse while pressed (current behaviour).
   - `lock`: hide cursor + relative mode while pressed; drag events carry
     deltas in relX/relY, local/window coords stay at the press point;
     cursor warped back to press point on release. Implies capture.
   Replace `bool captureCursor` in `MouseEvent` with
   `CursorCapture cursorCapture = CursorCapture.none;` (keep/adapt doc).
2. `yguilib/source/yguilib/widget/builder.d` (~line 589):
   `onMouseDrag(string eventName, CursorCapture capture)` and replace
   `captureCursor(bool)` with `cursorCapture(CursorCapture)`. Update
   caller `yguilib/source/yguilib/controls/scrollbars.d:1006` to
   `CursorCapture.capture`. grep for any other `captureCursor` users
   (D sources and guidemo help strings in
   `source/guidemo/pages/scrollbars_page.d` ~line 427, 665) and update.
3. `yguilib/source/yguilib/widget/internal/input_system.d`:
   - State: `bool hasCursorLock; uint lockWindowId; PointF lockOrigin;`
     plus `uint lastWindowId` updated from `event.mouse.windowId` on every
     mouse event.
   - `syncCursorCapture()`: compute wanted mode = max over active pressed
     widgets (non-null, !released, inputEnabled, mouseEvent !is null).
     Capture flag = wanted >= capture (existing hasCursorCapture logic).
     Lock: on transition to locked, set `lockWindowId = lastWindowId`,
     `lockOrigin` = press point (pass it from handleMouseDown, or record
     `lastPressPos` before calling sync), call
     `set_relative_mouse_mode(lockWindowId, 1)`. On transition to unlocked
     call `set_relative_mouse_mode(lockWindowId, 0)` then
     `warp_mouse_in_window(lockWindowId, lockOrigin.x, lockOrigin.y)`, and
     set `lastMousePos = lockOrigin`.
   - Add `@property bool isCursorLocked() const nothrow @safe`. Keep
     `isCursorCaptured` (true for capture or lock).
   - `handleMouseMotion`: if `hasCursorLock`, do NOT update
     `lastMousePos`/hover; call `dispatchMouseDrag(lockOrigin,
     PointF(xrel, yrel), widgets)`. Each event dispatched individually
     (no coalescing; see AGENTS.md Pointer Motion Fidelity).
   - `handleMouseUp`: if locked, use `lockOrigin` as the position for the
     target's mouseUp payload; then sync (which unlocks).
   - Also call `syncCursorCapture()` where a pressed widget may become
     inactive (onWidgetReleased already does). In dispatchMouseDrag, if a
     pressed widget is found `released` or `!inputEnabled` while locked,
     call sync after the loop so the lock is dropped.
4. Unit tests in input_system.d (near existing "mouseDrag delivery ...
   cursor capture state" unittest ~line 1086, update it to
   `CursorCapture.capture`):
   - Lock widget: mouseDown -> `isCursorLocked && isCursorCaptured`;
     motion events with arbitrary x/y and xrel/yrel deliver mouseDrag
     with windowX/Y == press point, local == press-local, rel == deltas;
     a second hoverable widget under the motion x/y gets no mouseEnter;
     two motion events -> two drag events in order. mouseUp -> unlocked,
     not captured, mouseUp payload at press point.
   - Releasing (`onWidgetReleased`) the locked widget mid-drag clears
     lock.
   - capture-only widget: `isCursorCaptured && !isCursorLocked`.
5. `ninja -C _build && meson test -C _build`; all must pass.
