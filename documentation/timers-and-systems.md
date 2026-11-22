# Timers, Controllers, and WidgetSystems: Analysis and Improvement Variants

## 1. Current Architecture Overview

The event loop in `UiSystemImpl.runEventLoopStep()`
(`yguilib/source/yguilib/internal/uisystem_impl.d`) runs in three phases:

```text
  +----------------------------------------------------------------------+
  | Phase 1: Wait & Drain                                                |
  |   waitForEventsIfIdle() -> SDL_WaitEvent(nextWaitTimeoutMs)          |
  |   drainSdlEvents() -> drainMessageBus()                              |
  |     - AppEvent.Kind.update   -> needModelUpdate = true               |
  |     - discrete events        -> Controller.handleEvent(ev)           |
  +----------------------------------------------------------------------+
                                    |
                                    v
  +----------------------------------------------------------------------+
  | Phase 2: Updates (runPhase2Updates)                                  |
  |   2a. if (needModelUpdate):                                          |
  |         Controller.update() -> if true, dirtyViews.addUnique(c)      |
  |   2b. timerService.fireDueTimers(now):                               |
  |         - controller   -> c.tick(dt) -> if true, dirtyViews.addUnique|
  |         - widgetSystem -> pipeline.runSystemUpdate(sys, win, dt)     |
  |         - callback     -> cb(id, dt) -> if true, needRender = true   |
  +----------------------------------------------------------------------+
                                    |
                                    v
  +----------------------------------------------------------------------+
  | Phase 3: Render (runPhase3Render)                                    |
  |   3a. for each c in dirtyViews: c.updateView() -> needRender |= res  |
  |   3b. if (needRender || treeDirty || treeLayoutDirty):               |
  |         pipeline.updateAndRender(win)                                |
  |           preLayout -> layout -> postLayout -> render -> swapBuffers |
  +----------------------------------------------------------------------+
```

`TimerControl` (`yguilib/source/yguilib/uisystem.d`) exposes three registration
methods backed by `TimerService`
(`yguilib/source/yguilib/internal/timer_service.d`):

- `startCallbackTimer(intervalMs, mode, cb)`:
  Invokes `cb(TimerId, dt)`. No automatic owner cleanup; returning `true` sets
  `needRender = true`, without scheduling `Controller.updateView()` or
  providing `WidgetSystemContext`.
- `startControllerTimer(target, intervalMs, mode)`:
  Invokes `target.tick(dt)`. Automatically cancelled when `target` is popped
  from `ControllerStack`. Returning `true` schedules `target.updateView()` in
  Phase 3 (deduplicated via `dirtyViews.addUnique`).
- `startSystemTimer(target, intervalMs, mode)`:
  Invokes `pipeline.runSystemUpdate(target, fMainWindow, dt)`, which calls
  `target.update(ctx, dt)` if `SystemPhase.update` is set. Automatically
  cancelled when `target` is unregistered from `WidgetSystemPipeline`.

---

## 2. Identified Problems

### 2.1 Multiple timers per Controller or WidgetSystem cannot be distinguished

`TimerService.startControllerTimer` and `startSystemTimer` always append a new
`TimerEntry` with a new `TimerId` and do not deduplicate by target. When
multiple timers for the same target are due in the same event-loop step,
`fireDueTimers` invokes `controller.tick(dt)` or `system.update(ctx, dt)` once
per due timer, each with that timer's own `dt`.

Crucially, neither `Controller.tick(float dt)` nor
`WidgetSystem.update(ref WidgetSystemContext ctx, float dt)` receives the
`TimerId` that fired.

**Impact on multi-pace animations and controls:**
Consider a `WidgetSystem` (or `Controller`) managing multiple controls with
different animation paces:
- Control A runs a smooth 60 FPS hover fade (`16 ms`).
- Control B blinks a text caret every `500 ms`.
- Control C runs a delayed tooltip reveal (`400 ms` one-shot).

With the current API, the system has only bad choices:
1. **Register multiple `startSystemTimer` entries on itself**:
   `update(ctx, dt)` gets called multiple times per frame with different `dt`
   values and no way to know which timer fired. Stepping all animations on
   every `update(ctx, dt)` call corrupts animation speeds (double-stepping).
2. **Run a single timer at the fastest pace (`16 ms`) and multiplex manually**:
   Forces the system to track per-control accumulators/deadlines manually, and
   if only a `500 ms` caret blink is active, the system must dynamically stop
   and restart its single timer whenever the fastest active pace changes.
3. **Fall back to `startCallbackTimer` per control**:
   Gives per-animation callbacks and `TimerId`, but loses:
   - automatic cleanup when the system is unregistered or controller is popped,
   - `WidgetSystemContext` construction (private to `WidgetSystemPipeline`),
   - deduplicated `Controller.updateView()` scheduling via `dirtyViews`.

### 2.2 `runSystemUpdate` couples `SystemPhase.update` to active timers

In `WidgetSystem` (`yguilib/source/yguilib/widget/system.d`),
`SystemPhase.update` (`update(ref WidgetSystemContext ctx, float dt)`) is only
ever invoked by `UiSystemImpl.runPhase2Updates` when a timer registered via
`startSystemTimer` expires.

Notably:
- `WidgetSystemPipeline.updateSystems`
  (`yguilib/source/yguilib/widget/internal/system_pipeline.d`) is populated in
  `rebuildPhaseLists()` but never iterated.
- `needModelUpdate` in `runPhase2Updates` only invokes `Controller.update()`,
  never any `WidgetSystem`.
- Non-timed widget-tree work currently uses `SystemPhase.preLayout`, which only
  runs inside `pipeline.updateAndRender()` when `needRender || treeNeedsRender`
  is already true in Phase 3.

As a result, a `WidgetSystem` that wants to perform non-timed Phase 2 work
(for example, reacting to `AppEvent.Kind.update`, flushing deferred state
mutations, or coalescing per-step work without an active timer and without the
widget tree already being dirty) has no clean Phase 2 hook. The only current
workaround is scheduling a `0 ms` `TimerMode.oneShot` timer.

Additionally, naming the phase `SystemPhase.update` and method `update(ctx, dt)`
conflicts with `Controller`, where `update()` is non-timed model sync and
`tick(dt)` is timer-driven.

### 2.3 Cumbersome split between `Controller.update()` and `Controller.tick(dt)`

`Controller` (`yguilib/source/yguilib/controller/package.d`) splits Phase 2 work
across two separate methods:
- `bool update()`: called in Phase 2a when `Result.update` or `sendUpdate()`
  sets `needModelUpdate = true`.
- `bool tick(float dt)`: called in Phase 2b once per due controller timer.

Both run in Phase 2, both mutate controller/model state, and both return `bool`
to schedule Phase 3 `updateView()`.

This split causes friction:
- **Fragmented state transitions**: A controller whose state evolves from both
  user/model events and timers (e.g., playback scrubbing, debounced search,
  animated transitions) must coordinate shared flags across `handleEvent()`,
  `update()`, `tick(dt)`, and `updateView()`.
- **No timer routing in `tick(dt)`**: A controller with more than one timer
  (e.g., a 60 FPS animation plus a 1-second status refresh or debounce timer)
  cannot distinguish them inside `tick(dt)`.
- **Asymmetric API**: `DefaultController` provides `startTickTimer` /
  `stopTickTimer` for `tick(dt)`, while callback timers must go through
  `uiSystem.startCallbackTimer` with manual cleanup in `onPop()`.

### 2.4 Overlapping `TimerControl` API with split capabilities

Currently, no single `start*Timer` method has all desirable properties:

```text
  Method                 | Per-timer cb | Auto-cleanup | Phase 2/3 integration
  -----------------------+--------------+--------------+-----------------------
  startCallbackTimer     | Yes (id, dt) | No           | needRender only
  startControllerTimer   | No (tick)    | Yes (onPop)  | dirtyViews.addUnique
  startSystemTimer       | No (update)  | Yes (unreg)  | WidgetSystemContext
```

Every caller is forced to trade off per-timer dispatch against lifecycle safety
and Phase 2/3 integration.

---

## 3. Architecture Improvement Variants

### Variant A: Owner-Scoped Callback Timers (Unified Timer API)

Replace target-dispatched `tick(dt)` / `update(ctx, dt)` timers with
owner-scoped callbacks. Timers are always callback-based, and ownership is
tracked explicitly (via an owner token, `TimerScope`, or overloads accepting a
`Controller` / `WidgetSystem` owner).

```text
  Controller / WidgetSystem
     |-- startTimer(16ms, repeat, &onHoverFade)   [owner = this]
     |-- startTimer(500ms, repeat, &onCaretBlink) [owner = this]
     +-- startTimer(400ms, oneShot, &onTooltip)   [owner = this]
           |
           v  (on popController / unregisterWidgetSystem)
     TimerService.stopTimersForOwner(owner)  // cancels all 3 automatically
```

Key design points:
- **Controller-owned timers**: Callback returns `bool` (or calls
  `requestUpdateView()`), and `UiSystemImpl` routes `true` into
  `dirtyViews.addUnique(ownerController)`. `Controller.tick(float dt)` can be
  removed completely; `Controller` keeps only `update()` (non-timed model sync)
  and `updateView()`.
- **System-owned timers**: Callback signature receives
  `(ref WidgetSystemContext ctx, TimerId id, float dt)` (built by
  `WidgetSystemPipeline`), so any system can attach independent callbacks per
  control or per animation pace while retaining full `WidgetSystemContext`
  access and automatic cleanup on `unregisterWidgetSystem()`.
- **Non-timed `SystemPhase.update`**: Now freed from timers. Either:
  - `SystemPhase.update` becomes a non-timed Phase 2 hook
    `update(ref WidgetSystemContext ctx)` invoked during Phase 2 when
    `needModelUpdate` is set (or when a system marks itself dirty), or
  - `SystemPhase.update` is removed if `SystemPhase.preLayout` + dirty flags
    are sufficient.

**Pros:**
- Solves multi-pace animations in both controllers and systems cleanly.
- Eliminates the `Controller.update()` vs `Controller.tick(dt)` split.
- Eliminates the capability trade-off in `TimerControl` (per-timer dispatch +
  auto-cleanup + Phase 2/3 integration all in one model).
- Easy to bind per-control closures/methods without manual `TimerId` switch
  tables.

**Cons:**
- Capturing lambdas allocate GC closures unless using method delegates or a
  user-data/widget-id parameter (e.g., `Widget` or `uint` tag).
- Breaking change to `Controller.tick`, `TimerControl`, and existing callers.

---

### Variant B: Pass `TimerId` (or Tag) into `tick` + Separate Non-Timed `update`

Keep the current target-based dispatch model, but fix its two immediate
limitations:
1. Pass `TimerId` (and optionally a `uint tag` or `uintptr_t`) into the timer
   callbacks:
   - `Controller.tick(TimerId id, float dt)`
   - `WidgetSystem.tick(ref WidgetSystemContext ctx, TimerId id, float dt)`
2. Rename `SystemPhase.update` -> `SystemPhase.tick` for timer-driven updates.
3. Add a separate non-timed `SystemPhase.update` (`update(ctx)`) invoked by
   `WidgetSystemPipeline.runUpdatePhase(window)` during Phase 2a when
   `needModelUpdate` is true (using the currently unused `updateSystems` list).

**Pros:**
- Minimal conceptual change from the existing design.
- Zero GC closure allocations (no delegates needed for controller/system
  timers).
- Fixes the `SystemPhase.update` naming/coupling problem and lets systems
  participate in non-timed Phase 2 updates.

**Cons:**
- Systems and controllers with multiple timers still need boilerplate
  `if (id == fadeTimerId) ... else if (id == blinkTimerId) ...` or a map from
  `TimerId` to animated control.
- Keeps the `Controller.update()` vs `Controller.tick()` split.
- `startCallbackTimer` remains a separate, non-owned mechanism.

---

### Variant C: Unified Phase 2 `update(ctx)` + Decoupled Wakeup Scheduling

Separate *when the event loop wakes up* from *how controllers/systems update*.

```text
  TimerService (wakeup scheduler only)
     - Tracks earliest deadline (nextFireNs) per registered wakeup
     - Wakes SDL_WaitEvent on time
           |
           v
  Phase 2: Unified Update
     - Controller.update(ref UpdateContext ctx)
         ctx.nowNs, ctx.hasModelUpdate, ctx.firedTimers / ctx.dt
     - WidgetSystem.update(ref WidgetSystemContext ctx)
         runs for systems that either:
           (a) opted into non-timed update when dirty/modelUpdate, OR
           (b) had a wakeup fire
```

In this model:
- Controllers have **one** Phase 2 method: `bool update(ref UpdateContext ctx)`.
  Whether triggered by `sendUpdate()`, `Result.update`, or a timer, all
  controller update logic lives in one place and runs at most once per step.
- Systems managing multiple animations at different paces store per-control
  animation deadlines (using `nowNs` from context) and schedule only a single
  next-earliest wakeup (or let an animation scheduler component drive them).

**Pros:**
- Completely eliminates the `update()` vs `tick()` split in `Controller`.
- Guarantees a controller/system is called at most once per event-loop step,
  even if multiple animations or model updates coincide.
- Fits naturally with reactive/retained UI loops and 0% idle CPU.

**Cons:**
- Higher complexity inside systems/controllers that juggle multiple paces
  (they must compute their own next earliest deadline or use a helper
  scheduler struct).
- Larger refactor of `Controller`, `WidgetSystem`, and `TimerService`.

---

### Variant D: Hybrid (Recommended) — Owner-Scoped Callbacks + Phase 2 Update

Combine Variant A's owner-scoped timer callbacks with a clean separation
between **timed callbacks** and **non-timed Phase 2 updates**:

1. **Owner-scoped timer callbacks in `TimerControl` (or `TimerScope`):**
   - `startControllerTimer(Controller owner, uint intervalMs, TimerMode mode,
     ControllerTimerCallback cb)`:
     - `cb(TimerId id, float dt)` returns `bool` (`requestUpdateView`).
     - Auto-cancelled on `popController()`.
     - Returning `true` adds `owner` to `dirtyViews` (deduplicated).
     - `DefaultController` exposes `startTimer(intervalMs, mode, cb)` /
       `stopTimer(id)` helpers.
   - `startSystemTimer(WidgetSystem owner, uint intervalMs, TimerMode mode,
     SystemTimerCallback cb)`:
     - `cb(ref WidgetSystemContext ctx, TimerId id, float dt)` runs inside
       `WidgetSystemPipeline` with a valid `WidgetSystemContext`.
     - Auto-cancelled on `unregisterWidgetSystem()`.
   - Optional `startCallbackTimer(intervalMs, mode, cb)` stays only for
     non-controller, non-system callers (or is replaced by a generic
     `TimerOwner` handle).
   - Optional lightweight `tag` / `Widget` payload overload can avoid closure
     allocations when binding one method to many controls:
     e.g., `startSystemTimer(this, 16, TimerMode.repeat, widget, &onAnimTick)`.

2. **Single `Controller.update()` in Phase 2 (remove `Controller.tick`):**
   - `Controller.update()` handles model-sync (`Result.update` /
     `sendUpdate()`).
   - Timed actions live in their specific timer callbacks (which can directly
     update state and return `true` to schedule `updateView()`, or call
     `sendUpdate()` if full model-sync is needed).
   - No artificial split between `update()` and `tick(dt)`.

3. **Non-timed `SystemPhase.update` for `WidgetSystem`:**
   - `WidgetSystem.update(ref WidgetSystemContext ctx)` (no `float dt`) is
     invoked by `WidgetSystemPipeline.runUpdatePhase(fMainWindow)` during
     Phase 2a (using the existing `updateSystems` list) when `needModelUpdate`
     is true (or when a system requests an update via `host.requestSystemUpdate`
     / `sendUpdate`).
   - Timed animations in a `WidgetSystem` use `startSystemTimer` with
     per-animation/per-control callbacks, independent of `SystemPhase.update`.

#### Comparison Matrix

```text
  Criterion                    | Current | Var A | Var B | Var C | Var D (Rec)
  -----------------------------+---------+-------+-------+-------+------------
  Multi-pace per system/ctrl   | Poor    | Good  | Fair  | Fair  | Good
  Auto-cleanup on pop/unreg    | Partial | Yes   | Yes   | Yes   | Yes
  Non-timed SystemPhase.update | No      | Opt.  | Yes   | Yes   | Yes
  No tick() vs update() split  | No      | Yes   | No    | Yes   | Yes
  Zero-closure option          | Partial | Opt.  | Yes   | Yes   | Yes (tag)
  Migration effort             | -       | Med   | Low   | High  | Med
```

---

## 4. Suggested Migration Path (Variant D)

If adopting Variant D, the refactor can be done incrementally:

1. **Phase 1 — Extend `TimerService` & `TimerControl`**:
   Add owner-scoped callback support (controller-owned and system-owned
   callbacks) alongside existing methods, keeping `stopTimersForController` and
   `stopTimersForSystem` working for all timers of an owner.
2. **Phase 2 — Migrate `WidgetSystem` timers & decouple `SystemPhase.update`**:
   Move any timed systems to system-owned callbacks; change
   `WidgetSystem.update(ctx, dt)` -> `WidgetSystem.update(ctx)` and wire
   `pipeline.runUpdatePhase(fMainWindow)` into `UiSystemImpl.runPhase2Updates`
   under `needModelUpdate`.
3. **Phase 3 — Migrate `Controller` timers and remove `Controller.tick`**:
   Replace `DefaultController.startTickTimer` + `tick(dt)` overrides with
   `startTimer(intervalMs, mode, cb)` returning `bool` (`updateView`), then
   remove `Controller.tick(float dt)` and the old target-only `TimerEntry`
   kinds.
