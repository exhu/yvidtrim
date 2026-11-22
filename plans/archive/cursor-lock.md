# Cursor Lock Mode (Knob Support) Plan

## Overview
`MouseEvent.captureCursor` (bool) already captures the mouse via
`SDL_CaptureMouse` during a drag. Knobs / scrubby sliders also need a
pointer *lock*: cursor hidden, unbounded relative deltas, cursor restored
to the press point on release. Replace the bool with
`enum CursorCapture { none, capture, lock }` and implement `lock` via SDL
relative mouse mode.

```
mouseDown on widget(cursorCapture=lock)
  -> InputSystem.syncCursorCapture: lockOrigin=press point,
     set_relative_mouse_mode(win,1)   (cursor hidden)
mouseMotion (FIFO, no coalescing)
  -> mouseDrag(local/window = lockOrigin, rel = xrel/yrel), no hover update
mouseUp / widget released / disabled
  -> set_relative_mouse_mode(win,0), warp_mouse_in_window(win, lockOrigin)
```

## Phases
- [Phase 1: C wrapper + D binding](cursor-lock-ph01.md)
- [Phase 2: CursorCapture enum, builder, InputSystem](cursor-lock-ph02.md)
- [Phase 3: guidemo knob page, docs, TODO](cursor-lock-ph03.md)

Verify each phase: `ninja -C _build && meson test -C _build`.
