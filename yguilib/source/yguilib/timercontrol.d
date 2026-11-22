module yguilib.timercontrol;

import yguilib.timers : TimerMode;

/// Opaque identifier for a registered timer (0 = invalid / inactive).
alias TimerId = uint;
enum TimerId invalidTimerId = 0;

/// Main-thread timer registration service replacing per-event timeoutMs.
interface TimerControl {
  /**
   * Starts a timer owned by `owner` (must not be null), firing on the main
   * thread during Phase 2b of the event loop (after Phase 1 input drain and
   * Phase 2a model-sync `update()`, and before Phase 3 `updateView()` and
   * rendering).
   *
   * Supported owners:
   * - `Controller`: When due in Phase 2b, `UiSystem` calls
   *   `owner.onTimer(id, dt)`. If it returns `true`, `owner.updateView()` is
   *   scheduled for Phase 3. Automatically cancelled when `owner` is popped
   *   from `ControllerStack`.
   * - `WidgetSystem`: When due in Phase 2b, `UiSystem` calls
   *   `owner.onTimer(ctx, id, dt)` regardless of `SystemPhase` flags, before
   *   Phase 3 layout and rendering. Automatically cancelled when `owner` is
   *   unregistered via `unregisterWidgetSystem()`.
   *
   * Note: Timers are not deduplicated per `owner`. Calling this multiple
   * times for the same owner registers independent timers; if multiple are
   * due in the same event-loop step, `onTimer` is called independently for
   * each due timer `(id, dt)`. Calling `startTimer()` / `stopTimer()` from
   * inside `onTimer()` is safe.
   */
  TimerId startTimer(
    Object owner,
    uint intervalMs,
    TimerMode mode
  );

  /// Cancels an active timer. Passing `invalidTimerId` (0) or an already
  /// stopped/expired ID is a safe no-op.
  void stopTimer(TimerId id);

  /// Returns `true` if `id` refers to a currently active timer.
  bool isTimerActive(TimerId id) const;
}
