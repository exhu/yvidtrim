# Timers, Controllers, and WidgetSystems Update Architecture

Overview for simplifying and unifying the timer, controller, and widget
system update architecture across `yguilib`, `guidemo`, and `yvidtrim`
(first item in `TODO.md`, based on Variant D hybrid in
`documentation/timers-and-systems.md`).

## Architecture Overview

```
+------------------------------------------------------------------------+
| Phase 1: Wait & Drain (UiSystemImpl.drainMessageBus)                   |
|   - AppEvent.Kind.update -> needModelUpdate = true                     |
|   - discrete events      -> Controller.handleEvent(ev)                 |
+-----------------------------------+------------------------------------+
                                    |
                                    v
+------------------------------------------------------------------------+
| Phase 2: Updates (UiSystemImpl.runPhase2Updates)                       |
|   2a. if (needModelUpdate):                                            |
|         - Controller.update() -> if true, dirtyViews.addUnique(ctrl)   |
|         - pipeline.runUpdatePhase(win) -> SystemPhase.update:          |
|             WidgetSystem.update(ctx)                                   |
|   2b. timerService.fireDueTimers(now):                                 |
|         - Controller owner   -> ctrl.onTimer(id, dt)                   |
|             -> if true, dirtyViews.addUnique(ctrl)                     |
|         - WidgetSystem owner -> pipeline.runSystemTimer(sys,win,id,dt) |
|             -> sys.onTimer(ctx, id, dt)                                |
+-----------------------------------+------------------------------------+
                                    |
                                    v
+------------------------------------------------------------------------+
| Phase 3: Render (UiSystemImpl.runPhase3Render)                         |
|   3a. for each c in dirtyViews: c.updateView() -> needRender |= res    |
|   3b. if (needRender || treeDirty || treeLayoutDirty):                 |
|         pipeline.updateAndRender(win)                                  |
+------------------------------------------------------------------------+
```

## Key Decisions

- **Owner-Bound Timers (`TimerControl` & `TimerService`)**:
  Replace `startCallbackTimer`, `startControllerTimer`, and
  `startSystemTimer` (plus `TimerCallback`) with a single
  `startTimer(Object owner, uint intervalMs, TimerMode mode)` method.
  Replace `stopTimersForController` and `stopTimersForSystem` with
  `stopTimersForOwner(Object owner)`. `UiSystemImpl.popController()` and
  `UiSystemImpl.unregisterWidgetSystem()` cancel all timers owned by the
  removed instance.
- **Controller Timers & Update Semantics**:
  Replace `Controller.tick(float dt)` with
  `Controller.onTimer(TimerId id, float dt)` (called independently per due
  timer) and replace `DefaultController.startTickTimer` / `stopTickTimer`
  with `startTimer` / `stopTimer`. Document `Controller` Phase 2/3 rules:
  `onTimer` may call `sendUpdate()` or return `true` to request preemptive
  `updateView()`, while `Controller.update()` is normally what schedules
  `updateView()`.
- **WidgetSystem Timers & Non-Timed `SystemPhase.update`**:
  Add `WidgetSystem.onTimer(ref WidgetSystemContext ctx, TimerId id,
  float dt)` and `protected` `startTimer` / `stopTimer` helpers on
  `WidgetSystem`. Change `WidgetSystem.update(ref WidgetSystemContext ctx)`
  to take no `dt` and run `pipeline.runUpdatePhase(fMainWindow)` in
  Phase 2a when `needModelUpdate` is true.

## Phases

- Phase 1: [timers-and-systems-ph01.md](timers-and-systems-ph01.md)
  - Unify `TimerService` and `TimerControl` around `Object owner`,
    refactor `WidgetSystem` / `WidgetSystemPipeline` (`onTimer` and
    non-timed Phase 2a `update`), add `Controller.onTimer` bridge, and
    update `yguilib` system callers and unit test hosts.
- Phase 2: [timers-and-systems-ph02.md](timers-and-systems-ph02.md)
  - Migrate all `Controller` callers (`guidemo` and `yguilib`) from
    `tick` / `startTickTimer` / `stopTickTimer` to `onTimer` /
    `startTimer` / `stopTimer`, remove `Controller.tick`, and add
    multi-timer and Phase 2a `WidgetSystem.update` unit tests.
- Phase 3: [timers-and-systems-ph03.md](timers-and-systems-ph03.md)
  - Remove the completed item from `TODO.md`, update `ARCHITECTURE.md`,
    `AGENTS.md`, `documentation/timers-and-systems.md`, and
    `.agents/skills/define-gui-widget/SKILL.md`, and run all checks.
