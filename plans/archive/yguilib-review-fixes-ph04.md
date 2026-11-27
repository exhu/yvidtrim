# ph04: `core` Runtime, `Window`, `UiSystemImpl` & `TimerControl` Split

Overview: `plans/yguilib-review-fixes.md`.
Review: `documentation/yguilib-review-report-core.md` (commit `7a96feaa`).
Paths below are relative to `yguilib/source/yguilib/` unless noted.

Goal: Address `core` runtime findings (`1.1`-`1.4`, `1.10`-`1.11`,
`1.13`-`1.15`, `1.18`-`1.22`, `2.1`-`2.3`, `3.2`-`3.3`, `3.5`-`3.8`, `4.2`,
`5.2`-`5.5`, `6.1`-`6.4`) and `widget` `3.1` (`notifyWindowClosed` wiring).

## Files

- `window.d`, `app.d`, `uisystem.d`, `timercontrol.d`, `timers.d`
- `internal/uisystem_impl.d`, `internal/uisystem_controller.d`,
  `internal/timer_service.d`, `internal/logger.d`, `internal/memstats.d`,
  `internal/assets.d`
- `controller/internal/controller_stack.d` (`pushBottom`)
- `TimerControl` implementers/callers: `controller/package.d`,
  `widget/system.d`, `controls/testing.d`,
  `widget/internal/{input,scroll,system_pipeline,virtlist}_system.d`,
  `source/guidemo/hover_button.d`

## Steps

1. **`Window` & `App` lifecycle/safety (`1.1`, `1.3`, `1.4`, `1.18`, `3.6`, `3.7`)**:
   - Remove `Window.~this()` completely (`1.1`); rely on main-thread
     `destroy()`.
   - Add `scope (failure) destroy();` in `Window.create()` (`1.3`).
   - Validate `scaling > 0.0f && isFinite(scaling)` in `unitsScaling` and
     `onDisplayScaleChanged` (`1.4`).
   - Assert `width > 0 && height > 0` in `makeAppWithTitleWh`, `Window.this`,
     and `Window.resize` (`1.18`).
   - Remove unused `Window.redraw()` (`3.7`); move `App.fUi` to `private:`
     (`3.6`).
2. **`UiSystemImpl` event loop, stack order & release (`1.2`, `1.13`, `1.14`, `1.22`, `2.2`, `3.2`, `3.5`, `4.2`, `5.2`-`5.4`)**:
   - Add `pushBottom(Controller)` to `ControllerStackStorage` and push
     `UiSystemController` at the bottom in `mainEventLoop()` (`1.2`).
   - Call `pipeline.notifyWindowClosed(fMainWindow)` in `mainEventLoop()`
     `scope (exit)` before `fMainWindow.destroy()` (`1.22`, `widget` 3.1).
   - Make `releaseWidget()` re-entrancy safe: mark `w` releasing before
     notifications, snapshot `w.children` into `SmallBuffer!(Widget, 16)`,
     snapshot `controllers` and registries (`1.13`, `2.2`).
   - Check `if (yguilib_sdl3_init() != 0)` before `scope (exit) quit` and
     handle `res < 0` in `waitForEventsIfIdle()` (`1.14`).
   - Remove dead private methods/field (`hasPendingAppEvents`, `redraw`,
     private scaling methods, `fPendingRedraw`) (`3.2`).
   - Document nullable returns on `mainWindow`, `findWidgetSystem`,
     `findWidgetSystemByType` and mark `eventStatsEnabled()` `const` in
     `uisystem.d` (`3.5`, `5.3`).
   - Add `invariant`, fix visibility order, prune unused imports, remove
     stale comment, deduplicate test controllers (`4.2`, `5.2`-`5.4`).
3. **`TimerControl` split & `timers.d` (`3.3`, `1.10`, `1.11`, `1.19`, `1.21`, `3.7`, `3.8`, `5.4`, `5.5`, `6.2`)**:
   - Split `TimerControl.startTimer` into `startControllerTimer(Controller,
     uint intervalMs, TimerMode mode)` and `startSystemTimer(WidgetSystem,
     uint intervalMs, TimerMode mode)`. Update `DefaultController`,
     `WidgetSystem`, `UiSystemImpl`, and all mock `WidgetSystemHost` /
     `TimerControl` test doubles (`search_code.d -e 'startTimer'`).
   - Skip active IDs on wrap in `TimerService.allocateId()` and document
     nullable `clock` / `stopTimersForOwner` (`1.21`, `5.4`).
   - In `timers.d`: clamp `AnimationTimer.duration` to `2.0f * fDuration`
     for `pingPong`, guard `NaN` with `!(x > 0) || !isFinite(x)`, document
     `start()`, remove `MeasureScopeTime` stub, guard `if (running) return;`
     in `StopWatchNs.start()`, add `const nothrow @safe` to `elapsed()`,
     rename `aPaused` -> `isPaused`, add injectable clock to eliminate
     `Thread.sleep` tests.
4. **`memstats.d`, `logger.d`, `internal/assets.d` (`1.15`, `1.20`, `2.1`, `2.3`, `5.2`, `6.1`)**:
   - Guard `d.w <= 0 || d.h <= 0` in `TextureStats.bytesOf` + assert in
     `onAlloc`; throttle `HeapStats.sample()` (250 ms via `MonoTime`,
     unconditional in `logMemStats()`); fix visibility section order.
   - Single-allocation `\0` format in `SdlLogger`; restore `sharedLog` in
     `scope (exit)` and assert all `LogLevel` mappings.
   - CTFE prefix assertion in `withMaskDefine` (`internal/assets.d`).
5. **Tests (`6.3`, `6.4`)**:
   - Add unit tests for `app.d`, `window.d` (`handleWindowEvent`,
     screenshot, `resize`, `updateViewRect`), `uisystem_controller.d`, and
     `timer_service.d` edge cases.

## Verification

- `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`
