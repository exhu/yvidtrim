# Phase 1: ButtonRepeat in ButtonSystem

Overview: [button-repeat.md](button-repeat.md). Read AGENTS.md and
codestyle.md first (2-space indent, <= 80 cols, keep comments).

File: `yguilib/source/yguilib/controls/button.d` only.

## Steps
1. Add near `ButtonTrigger`:
   ```d
   /// Auto-repeat of the press-trigger action while a button is held.
   struct ButtonRepeat {
     bool enabled = false;
     /// Delay before the first repeated event.
     uint delayMs = 400;
     /// Interval between subsequent repeated events.
     uint intervalMs = 80;
   }
   ```
   Add `ButtonRepeat repeat;` to `ButtonComponent` (doc comment).
2. `ButtonBuilder`: field `ButtonRepeat buttonRepeat;`, setters
   `repeat(uint delayMs = 400, uint intervalMs = 80)` (sets enabled true)
   and `repeat(in ButtonRepeat r)`. In `build()` assert
   `!buttonRepeat.enabled || buttonTrigger == ButtonTrigger.press` and
   copy into `comp.repeat`.
3. `ButtonSystem` private state: `TimerId repeatTimerId = invalidTimerId;
   bool repeatInDelay = false;`.
4. `handleMouseButtonDown`: in the press-trigger branch after
   `emitButtonAction`, if `comp.repeat.enabled` call
   `startRepeat(comp)`: `stopRepeat()`, then
   `repeatTimerId = startTimer(comp.repeat.delayMs, TimerMode.oneShot)`,
   `repeatInDelay = true`. Guard `host !is null` like `ensureAnimTimer`.
5. `onTimer(ctx, id, dt)`: if `id != invalidTimerId && id ==
   repeatTimerId` -> `onRepeatTimer(ctx)` and return; otherwise existing
   anim stepping unchanged (existing tests call `onTimer(ctx, 1, dt)`
   with no repeat timer and must keep working).
6. `onRepeatTimer(ref WidgetSystemContext ctx)`:
   - `comp = pressedComponent()`; if null -> `stopRepeat()`, return.
   - if `repeatInDelay`: oneShot expired, so `repeatTimerId =
     invalidTimerId`; start `startTimer(comp.repeat.intervalMs,
     TimerMode.repeat)`; `repeatInDelay = false`.
   - if `comp.isPressed` -> `emitButtonAction(ctx, press.pressed,
     comp.actionEvent)`.
7. `stopRepeat()`: `stopTimer(repeatTimerId); repeatInDelay = false;`.
   Call it: in `handleMouseButtonUp` (after the press ends), in
   `pressedComponent()` where `press.end()` forgets a disabled press, in
   `postLayout` when `press.pressed` becomes null after
   `forgetInvisible()`, in `onWidgetReleased` when the released widget
   was `press.pressed` (check before `press.forget`) and in
   `onUnregister`. Also when a press begins on a non-repeat button.
8. Update the module DESIGN comment: add a "Repeat" bullet (timeline,
   drag-off skip, stop conditions) and extend the "Timers" bullet
   (repeat timer only while a repeat button is held).
9. New `unittest` block (pattern of the existing ones, use
   `DummyWidgetSystemHost`; `host.sentEvents`, `host.isTimerActive`):
   - `.repeat()` sets `comp.repeat` (enabled, 400, 80); default button
     has `repeat.enabled == false` and press starts no repeat timer.
   - repeat button (`.trigger(ButtonTrigger.press).repeat(300, 50)`):
     press -> 1 event, `sys.repeatTimerId` active;
     `onTimer(ctx, sys.repeatTimerId, 0.3f)` -> 2 events and a new
     active interval timer id; two more fires -> 4 events.
   - `onTimer(ctx, sys.animTimerId, 0.016f)` emits nothing (when anim
     timer active).
   - motion off the button -> repeat fire emits nothing; motion back ->
     fire emits.
   - release -> repeat timer inactive, `repeatTimerId == invalidTimerId`.
   - press, `setInputEnabled(false)`, fire -> no event, timer stopped.
   - press then `onWidgetReleased(btn)` -> timer stopped; press, set
     invisible, `postLayout` -> timer stopped.
   - finish with `sys.onUnregister()`.

## Verify
`ninja -C _build && meson test -C _build` passes; no line > 80 chars in
button.d. Do not touch tabcontrol.d / scrollbars.d (phase 2).
