module yguilib.timercontrol;

import yguilib.controller : Controller;
import yguilib.timers : TimerMode;
import yguilib.widget.system : WidgetSystem;

/// Opaque identifier for a registered timer (0 = invalid / inactive).
alias TimerId = uint;
enum TimerId invalidTimerId = 0;

/// Main-thread timer registration service replacing per-event timeoutMs.
interface TimerControl {
  /**
   * Starts a timer owned by `target` (must not be null), firing on the main
   * thread during Phase 2b of the event loop (after Phase 1 input drain and
   * Phase 2a model-sync `update()`, and before Phase 3 `updateView()` and
   * rendering).
   *
   * When due in Phase 2b, `UiSystem` calls `target.onTimer(id, dt)`. If it
   * returns `true`, `target.updateView()` is scheduled for Phase 3.
   * Automatically cancelled when `target` is popped from `ControllerStack`.
   *
   * Note: Timers are not deduplicated per `target`. Calling this multiple
   * times for the same owner registers independent timers; if multiple are
   * due in the same event-loop step, `onTimer` is called independently for
   * each due timer `(id, dt)`. Calling `startControllerTimer()` /
   * `stopTimer()` from inside `onTimer()` is safe.
   */
  TimerId startControllerTimer(
    Controller target,
    uint intervalMs,
    TimerMode mode
  );

  /**
   * Starts a timer owned by `target` (must not be null), firing on the main
   * thread during Phase 2b of the event loop.
   *
   * When due in Phase 2b, `UiSystem` calls `target.onTimer(ctx, id, dt)`
   * regardless of `SystemPhase` flags, before Phase 3 layout and rendering.
   * Automatically cancelled when `target` is unregistered via
   * `unregisterWidgetSystem()`.
   */
  TimerId startSystemTimer(
    WidgetSystem target,
    uint intervalMs,
    TimerMode mode
  );

  /// Cancels an active timer. Passing `invalidTimerId` (0) or an already
  /// stopped/expired ID is a safe no-op.
  void stopTimer(TimerId id);

  /// Returns `true` if `id` refers to a currently active timer.
  bool isTimerActive(TimerId id) const;
}
