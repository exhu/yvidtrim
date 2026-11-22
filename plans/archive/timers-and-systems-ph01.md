# Phase 1: Owner-Bound Timers and WidgetSystem Phase 2 Split

Unify `TimerService` and `TimerControl` around `Object owner`, remove
`startCallbackTimer` and `TimerCallback`, decouple `SystemPhase.update`
from timers via `WidgetSystem.onTimer` + Phase 2a `update(ctx)`, and
bridge `Controller.onTimer(TimerId id, float dt)` so the codebase builds
and passes all tests before Phase 2 removes `Controller.tick`.

## Tasks

### 1. `yguilib/source/yguilib/timers.d`

- Remove `alias TimerCallback = bool delegate(TimerId id, float dt);`.

### 2. `yguilib/source/yguilib/internal/timer_service.d`

- In `TimerEntry`:
  - Remove `enum TargetKind`, `targetKind`, `controllerTarget`,
    `systemTarget`, and `callback`.
  - Add `Object owner = null;`.
- In `TimerService`:
  - Replace `startCallbackTimer`, `startControllerTimer`, and
    `startSystemTimer` with:
    ```d
    TimerId startTimer(
      Object owner,
      uint intervalMs,
      TimerMode mode
    ) {
      assert(owner !is null, "Timer owner must not be null");
      TimerEntry entry;
      entry.owner = owner;
      return addEntry(entry, intervalMs, mode);
    }
    ```
  - Replace `stopTimersForController` and `stopTimersForSystem` with:
    ```d
    void stopTimersForOwner(Object owner) {
      if (owner is null) {
        return;
      }
      foreach (ref e; entries[]) {
        if (e.active && e.owner is owner) {
          deactivateEntry(e);
        }
      }
      compactIfIdle();
    }
    ```
  - Update `deactivateEntry` to set `e.owner = null;`.
  - Update `timer_service.d` unit tests to register dummy `Object` /
    `Controller` / `WidgetSystem` owners via `startTimer` and clean up
    via `stopTimersForOwner`.

### 3. `yguilib/source/yguilib/uisystem.d`

- Remove `TimerCallback` from `import yguilib.timers`.
- Replace `startCallbackTimer`, `startControllerTimer`, and
  `startSystemTimer` on `TimerControl` with:
  ```d
  TimerId startTimer(
    Object owner,
    uint intervalMs,
    TimerMode mode
  );
  ```
- Document `TimerControl.startTimer` behavior for `Controller` and
  `WidgetSystem` owners (auto-cleanup on `popController()` /
  `unregisterWidgetSystem()`, independent `onTimer` dispatch per due
  timer).

### 4. `yguilib/source/yguilib/controller/package.d`

- Add `bool onTimer(TimerId id, float dt);` to `Controller` with doc
  comments explaining:
  - Called independently for each due timer owned by the controller in
    Phase 2b.
  - May call `sendUpdate()` if model/logic recalc or view sync is
    needed, or return `true` to request `updateView()` immediately during
    the current update step (e.g. preemptive animations regardless of
    event queue depth).
  - Usually only `Controller.update()` is meant to schedule
    `updateView()`.
- In `DefaultController`:
  - Add `override bool onTimer(TimerId id, float dt) { return tick(dt); }`
    (temporary Phase 1 bridge; removed with `tick` in Phase 2).
  - Add `protected` `startTimer(uint intervalMs, TimerMode mode)` and
    `stopTimer(ref TimerId id)` calling `uiSystem.startTimer(this, ...)`
    and `uiSystem.stopTimer(id)`.
  - Temporarily forward `startTickTimer` to `startTimer` and
    `stopTickTimer` to `stopTimer`.

### 5. `yguilib/source/yguilib/widget/system.d`

- Import `TimerId, TimerMode, invalidTimerId` from `yguilib.timers`.
- Store `protected WidgetSystemHost host;` in `onRegister(newHost)` and
  clear `host = null;` in `onUnregister()`.
- Update `WidgetSystem` lifecycle methods:
  - Change `void update(ref WidgetSystemContext ctx, float dt) {}` to:
    `void update(ref WidgetSystemContext ctx) {}` (Phase 2a non-timed
    update).
  - Add `void onTimer(ref WidgetSystemContext ctx, TimerId id, float dt)
    {}` (Phase 2b timer handler, not gated on `SystemPhase.update`).
  - Add `protected` helpers `startTimer(uint intervalMs, TimerMode mode)`
    and `stopTimer(ref TimerId id)` delegating to `host`.
- Update `system.d` unit test (`customSys.update(ctx);` and
  `customSys.onTimer(ctx, 1, 0.016f);`).

### 6. `yguilib/source/yguilib/widget/internal/system_pipeline.d`

- Import `TimerId` from `yguilib.timers`.
- Replace `runSystemUpdate(WidgetSystem system, Window window, float dt)`
  with:
  - `void runUpdatePhase(Window window)` iterating `updateSystems` and
    calling `s.update(ctx)`.
  - `void runSystemTimer(WidgetSystem system, Window window, TimerId id,
    float dt)` creating `WidgetSystemContext` and calling
    `system.onTimer(ctx, id, dt)`.
- Update `DummyHost` to implement `startTimer(Object, uint, TimerMode)`.
- Update `system_pipeline.d` unit tests for `runUpdatePhase` and
  `runSystemTimer`.

### 7. `yguilib/source/yguilib/internal/uisystem_impl.d`

- Remove `TimerCallback` import.
- Replace `startCallbackTimer`, `startControllerTimer`, and
  `startSystemTimer` with:
  ```d
  override TimerId startTimer(
    Object owner,
    uint intervalMs,
    TimerMode mode
  ) {
    return timerService.startTimer(owner, intervalMs, mode);
  }
  ```
- Update `unregisterWidgetSystem`, `popController`, and `mainEventLoop`
  scope exit to call `timerService.stopTimersForOwner(...)`.
- In `runPhase2Updates`:
  - Inside `if (needModelUpdate)`, call `pipeline.runUpdatePhase(fMainWindow);`
    after the `Controller.update()` loop.
  - Inside `timerService.fireDueTimers`, dispatch via `cast(Controller)
    entry.owner` -> `ctrl.onTimer(entry.id, dt)` (adding to `dirtyViews`
    when `true`), or `cast(WidgetSystem) entry.owner` ->
    `pipeline.runSystemTimer(sys, fMainWindow, entry.id, dt)`.
- Update the flood/timer test in `uisystem_impl.d` to use `startTimer`,
  `onTimer`, and Phase 2a/2b behavior.

### 8. Update `yguilib` WidgetSystems & Test Hosts

- `yguilib/source/yguilib/controls/hover_button_system.d`:
  - Remove `SystemPhase.update` from `phases()`.
  - Replace `override void update(ref WidgetSystemContext ctx, float dt)`
    with `override void onTimer(ref WidgetSystemContext ctx, TimerId id,
    float dt)`.
  - Use inherited `WidgetSystem.host`, `startTimer`, and `stopTimer`
    (remove duplicate `host` field if inherited cleanly, or keep
    `onRegister` / `onUnregister` consistent with `super`).
  - Update `DummyHost` and unit tests (`sys.onTimer(ctx, 1, 0.016f)`).
- `yguilib/source/yguilib/widget/internal/input_system.d`,
  `yguilib/source/yguilib/widget/internal/scroll_system.d`, and
  `yguilib/source/yguilib/widget/internal/virtlist_system.d`:
  - Update unit test host classes (`TestUiSystem`, `TestScrollHost`,
    `TestVirtListHost`) to implement `startTimer(Object, uint, TimerMode)`.
- `source/guidemo/hover_button.d` (`TestUiSystem`) and
  `yguilib/source/yguilib/controls/virtlist.d` (line 1338):
  - Update `TestUiSystem` in `hover_button.d` to implement
    `startTimer(Object, uint, TimerMode)`.
  - Update `uiSystem.startControllerTimer(this, ...)` in `virtlist.d` to
    `uiSystem.startTimer(this, ...)`.

## Verification

```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
```
