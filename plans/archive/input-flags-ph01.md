# input-flags ph01: core semantics

Overview: [input-flags.md](input-flags.md). Follow AGENTS.md and
codestyle.md (2-space indent, max 80 cols, keep existing comments).

## Target semantics
- `Widget.handleInput` (default `false`): the widget takes part in pointer
  hit-tests and blocks click/hover-through to widgets behind it.
- `Widget.inputEnabled` (default `true`): enabled state. When it is false,
  the widget shows disabled visuals and no mouse view events, drag or cursor
  capture are produced for it. A disabled widget with `handleInput` still
  blocks.

## Steps
1. `yguilib/source/yguilib/widget/package.d`
   - Field `inputEnabled`: change the default to `true`. Rewrite the doc
     comments of `handleInput` and `inputEnabled` to match the semantics
     above.
   - Update the `setInputEnabled` doc comment if needed.
   - Fix unit tests that assume the old default, e.g. the simple-dump test
     `cf["inputEnabled"].boolean == false` becomes `true`.
2. `yguilib/source/yguilib/widget/builder.d`
   - `ensureMouseEvent()` (used by every `onMouse*` and `cursorCapture`
     method) sets `fWidget.handleInput = true`.
   - Remove `fWidget.inputEnabled = true` from `onMouseDown`, `onMouseUp`
     and `onMouseDrag`, and fix their docstrings ("makes the widget hittable"
     instead of "enables input").
   - Update the docstrings of the `inputEnabled(bool)` and
     `handleInput(bool)` builder methods.
3. `yguilib/source/yguilib/widget/internal/input_system.d`
   - `handleMouseDown`: going from top to bottom over the visible widgets,
     skip a hit widget when `!w.handleInput`. The first hit widget with
     `handleInput` is the target:
     - if it has `components.mouseEvent` and `inputEnabled`, keep the
       existing press logic (pressedWidgets, capture, `mouseDown` event);
     - in every case, `return` (it blocks).
   - `findHoverTargetIndex`: return the first hit with `handleInput`. Remove
     the `keyboardEvent` `continue` branch.
   - `collectHovered`: no change. Ancestors receive hover when they have
     `inputEnabled` and a `mouseEvent`.
   - Keep the `inputEnabled` gates in `handleMouseUp`, `dispatchMouseDrag`
     and `syncCursorCapture`.
   - Unit tests in this file:
     - in tests that use a widget as a hit target, change
       `x.inputEnabled = true` to `x.handleInput = true` (`inputEnabled` is
       now `true` by default);
     - keep `inputEnabled = false` where the test means "disabled", and add
       `handleInput = true` where the widget must still block (e.g. T14);
     - T24 (overlay) and T25 (keyboard-only widget) are transparent because
       `handleInput == false`. Update their setup and comments;
     - add a test: a disabled plain panel with `handleInput = true` over a
       button blocks the click (no events);
     - add a test: a widget with a `MouseEvent` but `handleInput == false`
       is not hit, and the click reaches the widget below.
4. `yguilib/source/yguilib/controls/tooltip.d`
   - `findUnobstructedTooltipTarget`: change the blocking condition to
     `!w.handleInput && tt is null` → continue. Update its doc comment
     ("checks only `visible`, `handleInput`, and `Tooltip`").
   - Layer and popup builders: remove `.inputEnabled(false)` (both are
     transparent by default because `handleInput` is false).
   - Unit tests: the modal backdrop uses `.handleInput(true)`.
     Pass-through containers rely on the default. Replace assertions like
     `!layer.inputEnabled` with `!layer.handleInput`. Where tests used
     `.inputEnabled(true)` to make a widget block, use `.handleInput(true)`.
5. Fix any other test failures caused by the new default or semantics.
   Only fix them; no unrelated changes.

## Verify
`ninja -C _build && meson test -C _build`: everything passes.
