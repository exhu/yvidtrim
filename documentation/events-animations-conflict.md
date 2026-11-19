# Input Events and Animation Updates Conflict: Analysis & Improvement Options

This report analyzes the conflict between input event processing and active
animations described in the first item of `TODO.md`, identifies the root causes
in `yguilib`, and proposes architectural options to resolve it.

---

## 1. Problem Analysis & Root Causes

In `yguilib`, the main event loop (`UiSystemImpl.runEventLoopStep` in
`yguilib/source/yguilib/internal/uisystem_impl.d`) currently couples SDL event
waiting, `MessageBus` dispatching, animation timeouts, and rendering in a
one-event-per-step cycle:

```
+-------------------------------------------------------------------------+
|                   CURRENT runEventLoopStep() FLOW                       |
+-------------------------------------------------------------------------+
  pollSdlEvent(currentTimeoutMs) -> SDL_WaitEventTimeout(timeoutMs)
    |
    +-- If SDL event arrived: push AppEvent to MessageBus + SDL Wake
    v
  nullableEvent = messageBus.get()
    |
    +-- [Branch A: !nullableEvent.isNull]
    |     dispatchEvent(event) -> ControllerStack.handleEvent(event)
    |       -> if Result.update:     sendAppEvent(Kind.update [noRepeat])
    |       -> if Result.updateView: updateView() -> send(Kind.updateUiLayer)
    |
    +-- [Branch B: nullableEvent.isNull && waitRes == 0 && timeoutMs >= 0]
          dispatchEvent(Kind.update) -> updateAndRender(activeController)
```

Five interacting mechanisms cause animations and input events to conflict:

### 1.1. Relative Idle Timeout Starves `Kind.update` Under Input Floods
`Branch B` (which synthesizes `AppEvent.Kind.update`) executes **only** when
`yguilib_sdl3_wait_event` times out (`waitRes == 0`) **and** `MessageBus` is
empty. Because `currentTimeoutMs` (typically `16` ms for 60 FPS) is passed as a
relative sleep timeout on each step, any input stream arriving faster than
16 ms (such as a 125-1000 Hz mouse generating motion events every 1-8 ms)
wakes `SDL_WaitEventTimeout` before it expires. The 16 ms wait is reset on
every mouse movement, so `waitRes == 0` never occurs and `Kind.update` is
completely starved while the cursor moves.

### 1.2. Single-Event Poll/Dispatch Imbalance Multiplies Queue Depth
Each call to `runEventLoopStep()` polls at most one SDL event and pops at most
one `AppEvent` from `MessageBus`. However, dispatching one input event often
enqueues multiple internal events into `MessageBus`:
- `InputSystem` bubbles a `Kind.view` event (e.g., `mouseMove`, `mouseEnter`).
- `applyViewUpdatesAndRender()` enqueues `Kind.updateUiLayer`.
- A controller returning `Result.update` enqueues `Kind.update`.

Because one hardware event produces 2-3 internal `MessageBus` events while the
loop drains only one event per iteration (and sends an SDL wake event each
time), rapid mouse movement saturates `MessageBus` and increases input latency.

### 1.3. `MessageBus.noRepeat` Checks Only `events[head]`
In `yguilib/source/yguilib/events/internal/message_bus.d`:

```d
if (ev.noRepeat && !isQueueEmpty() && (ev == events[head])) {
  allowedToSend = false;
}
```

`ev == events[head]` only compares against the **oldest** event at the front of
the queue. When the queue holds `[mouseMotion_2, mouseMotion_3, update]`,
`events[head]` is `mouseMotion_2`. Calling `sendAppEvent` with
`makeNoRepeat(Kind.update)` or `makeNoRepeat(Kind.updateUiLayer)` fails the
check and appends duplicate `update` and `updateUiLayer` events. If a
controller returns `Result.update` on input events during a mouse flood, the
queue fills with redundant `update` and `updateUiLayer` passes, each blocking
on VSync (`swapBuffers()`) and stalling input responsiveness.

### 1.4. `updateUiLayer` Busy-Loop in `LayoutPainterPageController`
To keep its alpha animation progressing during mouse movement,
`LayoutPainterPageController.handleEvent`
(`source/guidemo/pages/layout_painter_controller.d`) runs `update()` on its
fallback branch for **any** event:

```d
HandleResult res;
res.result = isAnimating() && update()
  ? HandleResult.Result.updateView
  : HandleResult.Result.nothing;
res.consume = false;
res.timeoutMs = animationTimeoutMs();
return res;
```

Because `AppEvent.Kind.updateUiLayer` is dispatched through the entire
`ControllerStack`, `LayoutPainterPageController` receives `updateUiLayer`, runs
`update()`, mutates `model.alphaValue`, and returns `Result.updateView`.
`applyViewUpdatesAndRender()` then invokes `updateView()` and immediately
enqueues another `updateUiLayer` event with an SDL wake signal:

```
updateUiLayer -> LayoutPainterPageController.handleEvent()
  -> calls update() (dt clamped to 1 ms) -> returns Result.updateView
  -> applyViewUpdatesAndRender() -> sendUpdateUiLayerEvent() + SDL Wake
  -> immediate next iteration (0 ms sleep, bypasses 16 ms timeoutMs!)
```

### 1.5. Fragile Per-Event `timeoutMs` Propagation Across `ControllerStack`
Every animating controller must manually populate `res.timeoutMs = 16` on every
return path of `handleEvent()`. Furthermore, if a higher controller on the
stack consumes an event (`consume = true`) and specifies its own `timeoutMs`
(e.g., `100` ms), `applyTimeout()` overwrites `currentTimeoutMs` with `100` ms
even if an unvisited lower controller required `16` ms.

---

## 2. Architectural Options

### Option 1: Deadline-Driven Timer Service in `UiSystem` / `MessageBus`
*(Corresponds to the first suggestion in `TODO.md`)*

Instead of controllers returning `timeoutMs` from `handleEvent()`, introduce a
deadline-based timer/animation scheduler in `UiSystem` (or `MessageBus`).

#### How It Works
1. **Timer Registration API**: Controllers and systems register one-shot or
   repeating timers (or an active animation ticker) with `UiSystem`:
   ```d
   TimerId id = uiSystem.startTimer(16.msecs, TimerMode.repeat);
   uiSystem.stopTimer(id);
   ```
   Alternatively, controllers expose a property `@property int timeoutMs()
   const` (matching `WidgetSystem.timeoutMs`) queried by `UiSystem`.
2. **Absolute Wall-Clock Deadlines (`MonoTime`)**: `UiSystem` tracks the next
   fire timestamp `nextDeadlineNs` using `MonoTime`.
3. **Remaining-Time Wait Calculation**: Before calling `pollSdlEvent()`,
   `UiSystem` computes:
   ```
   remainingMs = max(0, (nextDeadlineNs - nowNs) / 1_000_000)
   ```
   If no timers or animations are active, `remainingMs = -1` (0% CPU idle
   sleep).
4. **Deadline Expiry Independent of Input Queue**: On every loop iteration,
   when `nowNs >= nextDeadlineNs`, `UiSystem` fires the timer / `Kind.update`
   event regardless of whether `SDL_WaitEventTimeout` returned `0` or was woken
   early by mouse motion.

```
Time (ms):   0        4        8       12       16
             |--------|--------|--------|--------|
SDL Input:   [move]   [move]   [move]   [move]
Wait time:   16ms     12ms     8ms      4ms      0ms -> Deadline reached!
                                                        Emit Kind.update
```

#### Pros & Cons
- **Pros**:
  - Controllers completely forget about `HandleResult.timeoutMs`.
  - Animations advance reliably at 60 FPS even during continuous 1000 Hz mouse
    movement because the wait timeout counts down to an absolute deadline.
  - Supports multiple independent periods (e.g., 16 ms UI animation, 33 ms
    video frame step, 500 ms cursor blink).
  - Event consumption by a top controller no longer hides a lower controller's
    animation timeout.
- **Cons**:
  - Still requires fixing `MessageBus` queueing/draining so timer events are
    not delayed behind a backlog of hundreds of uncoalesced mouse events.

---

### Option 2: Priority / Proportional Fair Queue in `MessageBus`
*(Corresponds to the second suggestion in `TODO.md`)*

Upgrade `MessageBus` from a flat FIFO slice to a multi-lane priority queue with
full-queue deduplication, event coalescing, and proportional scheduling.

#### How It Works
1. **Full-Queue `noRepeat` & Coalescing**:
   - Track pending `noRepeat` singleton events (`Kind.update`,
     `Kind.updateUiLayer`, `Kind.windowRedraw`) with a bitmask or scan of
     `events[head .. $]` so at most one instance can exist in the queue at any
     time.
   - Coalesce consecutive `Kind.mouseMotion` (and `Kind.windowResized`) events
     in-place so rapid cursor movement updates the queued motion event's
     `(x, y)` and accumulates `(xrel, yrel)` instead of growing the queue.
2. **Priority Lanes with Starvation Bound (Proportional Fairness)**:
   Partition `MessageBus` into three lanes:
   - **High / Control Lane**: `appQuit`, `windowClose`, `update` (when due).
   - **Input / View Lane**: `key*`, `mouse*`, `view`, `user`, `window*`.
   - **Render Lane (Lowest / End-of-Batch)**: `updateUiLayer`.
3. **Proportional Dispatch Quota**:
   - Allow at most `N` (e.g., `N = 4` or `8`) consecutive events from the Input
     Lane before promoting a pending `Kind.update` or `Kind.updateUiLayer`
     event.

```
+-------------------------------------------------------------------------+
|                    PRIORITIZED & COALESCED MESSAGEBUS                   |
+-------------------------------------------------------------------------+
  Incoming send(ev)
    |
    +-- Kind.mouseMotion   --> Coalesce with tail mouseMotion in Input Lane
    +-- ev.noRepeat        --> Drop if bitmask says Kind already queued
    |
    v
  +---------------------------------------------------------------------+
  | Lane 0 (Periodic/Control): [ Kind.update ]                          |
  | Lane 1 (Input/View):       [ keyDown, mouseMotion(coalesced), view ]|
  | Lane 2 (Render Barrier):   [ Kind.updateUiLayer ]                   |
  +---------------------------------------------------------------------+
    |
    v
  get() -> Enforces max N input events per update/render cycle
```

#### Pros & Cons
- **Pros**:
  - Fixing `noRepeat` across the whole queue and coalescing `mouseMotion`
    immediately eliminates queue saturation and VSync backlog stalls.
  - Proportional scheduling guarantees a fixed ratio between input response
    and animation/render progression.
- **Cons**:
  - A priority queue only orders events that have *already been enqueued*. If
    `Kind.update` is only generated when `pollSdlEvent` times out (`waitRes ==
    0`), `Lane 0` will still be empty during an SDL input flood unless paired
    with wall-clock deadline tracking (Option 1 or Option 3).

---

### Option 3: Phased Frame Loop (Batch Input -> Deadline Update -> Render)

Restructure `UiSystemImpl.runEventLoopStep()` from a single-event dispatcher
into a deterministic 3-phase GUI frame loop while preserving 0% CPU idle sleep.

#### How It Works
Each iteration of the main loop executes three distinct phases:

```
+-------------------------------------------------------------------------+
|                      PHASED GUI EVENT LOOP STEP                         |
+-------------------------------------------------------------------------+
  1. COMPUTE WAIT TIMEOUT
     waitMs = hasActiveAnimations ? max(0, nextFrameNs - nowNs) : -1
       |
       v
  2. PHASE 1: INPUT & EVENT DRAIN
     - yguilib_sdl3_wait_event(&ev, waitMs) (blocks once if idle)
     - while (yguilib_sdl3_poll_event(&ev)) -> enqueue to MessageBus
       (coalescing consecutive mouseMotion events)
     - Drain queued events from MessageBus (up to a safety cap, e.g. 64):
       dispatchEvent(ev) -> records needUpdate and dirty controllers
       |
       v
  3. PHASE 2: PERIODIC & ANIMATION UPDATE
     - If needUpdate OR (hasActiveAnimations && nowNs >= nextFrameNs):
         nextFrameNs = nowNs + 16ms
         For each controller in ControllerStack:
           if (controller.update()) mark controller view dirty
       |
       v
  4. PHASE 3: VIEW SYNC & RENDER
     - For each dirty controller (oldest to newest):
         if (controller.updateView()) needRender = true
     - If needRender || mainWindow.rootWidget.isTreeDirty():
         pipeline.updateAndRender(mainWindow)  // Runs once per frame!
```

Key structural change in Phase 3: `updateUiLayer` no longer needs to be sent as
an `AppEvent` through user controllers in `ControllerStack`. Instead,
`UiSystemImpl` invokes `pipeline.updateAndRender(fMainWindow)` directly at the
end of the tick whenever any view or widget requested a redraw.

#### Pros & Cons
- **Pros**:
  - **Eliminates `updateUiLayer` recursion**: Because `updateUiLayer` is no
    longer dispatched to user controllers' `handleEvent`, workarounds like
    `LayoutPainterPageController` cannot cause infinite render loops.
  - **Batch input draining**: All queued SDL and `MessageBus` events since the
    last frame are processed before blocking on `swapBuffers()`, minimizing
    input-to-photon latency.
  - **At most one render/VSync per tick**: Even if 20 input and view events are
    processed in Phase 1, `updateView()` and `pipeline.updateAndRender()` run
    once at the end of the step.
  - **0% CPU when idle**: When `hasActiveAnimations == false`, `waitMs = -1`
    and `yguilib_sdl3_wait_event` sleeps indefinitely until hardware or
    cross-thread wake events arrive.
- **Cons**:
  - Requires updating unit tests in `uisystem_impl.d` that inspect event trace
    logs expecting `AppEvent.Kind.updateUiLayer` to pass through controllers.

---

### Option 4: Separate `Controller.update()` Lifecycle from `handleEvent()`

Align `Controller` with `WidgetSystem` by separating discrete event handling
from continuous time-based updates and timeout queries.

#### How It Works
1. **Declarative `@property int timeoutMs() const` on `Controller`**:
   Just as `WidgetSystem` already defines `@property int timeoutMs() const`
   (defaulting to `-1`), add `@property int timeoutMs() const` to `Controller`
   and `DefaultController` (and deprecate `HandleResult.timeoutMs`).
   - `UiSystemImpl` queries `min(pipeline.timeoutMs, controllers.timeoutMs)` at
     the end of each tick.
   - In `LayoutPainterPageController`:
     ```d
     override @property int timeoutMs() const {
       return (isPageActive(demoTracker.model, DemoPage.layoutPainter) &&
               !alphaTimer.isPaused()) ? 16 : -1;
     }
     ```
2. **Direct `Controller.update()` Invocation**:
   - Instead of synthesizing `AppEvent(AppEvent.Kind.update)` and routing it
     through `Controller.handleEvent(ev)`—which relies on every controller
     remembering to call `super.handleEvent(ev)` and not consuming the event—
     `UiSystemImpl` calls `controller.update()` directly on all active
     controllers whenever a frame deadline expires or `Result.update` was
     requested.
   - `Controller.handleEvent(AppEvent ev)` is then strictly reserved for
     discrete events (`keyDown`, `mouse*`, `view`, `user`, `window*`).

#### Pros & Cons
- **Pros**:
  - Unifies the animation mental model between `Controller` and `WidgetSystem`.
  - Makes `LayoutPainterPageController.handleEvent` trivial: it only handles
    `Kind.keyDown`, while `update()` handles `alphaTimer` and `timeoutMs`
    reports `16` when Page 1 is active.
  - Eliminates the bug class documented in `AGENTS.md` where forgetting
    `super.handleEvent(ev)` silently skips `update()`.
- **Cons**:
  - Minor API change across existing controllers that override `handleEvent` to
    intercept `AppEvent.Kind.update` (such as `HoverButtonController` and
    `LayoutPainterPageController`).

---

## 3. Comparison Matrix

```
+---------------------------+----------+----------+----------+----------+
| Criterion                 | Option 1 | Option 2 | Option 3 | Option 4 |
|                           | Deadlines| PrioBus  | Phased   | Lifecycle|
+---------------------------+----------+----------+----------+----------+
| Fixes mouse flood freeze  | Yes      | Partial* | Yes      | With 1/3 |
| Fixes queue saturation    | No       | Yes      | Yes      | No       |
| Stops updateUiLayer loop  | Partial  | Yes      | Yes      | Yes      |
| Removes HandleResult.time | Yes      | No       | Optional | Yes      |
| Preserves 0% idle CPU     | Yes      | Yes      | Yes      | Yes      |
| Multi-timer support       | Best     | Fair     | Good     | Good     |
| Implementation scope      | Medium   | Small    | Medium   | Small    |
+---------------------------+----------+----------+----------+----------+
*Option 2 requires Option 1 or 3 so Kind.update is enqueued on wall-clock
 deadlines rather than only when SDL_WaitEventTimeout is idle.
```

---

## 4. Recommended Implementation Plan

The options are complementary and work best when combined in three focused
steps:

1. **Step 1: Harden `MessageBus` Deduplication & Coalescing (from Option 2)**
   - Fix `MessageBus.send()` so `ev.noRepeat` checks all pending events in
     `events[head .. $]` (or uses a bitmask for `update` / `updateUiLayer`)
     instead of only `events[head]`.
   - Coalesce consecutive `AppEvent.Kind.mouseMotion` events in `MessageBus`
     so high-frequency mouse input cannot flood the queue.

2. **Step 2: Adopt Wall-Clock Deadlines & Phased Loop (Options 1 + 3)**
   - In `UiSystemImpl`, track `nextUpdateDeadlineNs` via `MonoTime` instead of
     relying on `SDL_WaitEventTimeout` returning `0`.
   - Compute `waitMs = max(0, (nextUpdateDeadlineNs - nowNs) / 1_000_000)` when
     animations/timers are active, or `-1` when idle.
   - Drain pending SDL events (`wait_event` once, then `poll_event`) and
     queued `MessageBus` events in a batch, trigger `update()` whenever
     `nowNs >= nextUpdateDeadlineNs` or `Result.update` was returned, and run
     `updateView()` + `pipeline.updateAndRender()` once at the end of the step.

3. **Step 3: Decouple Timeout & `update()` from `handleEvent()` (Option 4)**
   - Add `@property int timeoutMs() const` to `Controller` (mirroring
     `WidgetSystem.timeoutMs`) and/or a timer registration API on `UiSystem`,
     removing the need to return `timeoutMs` from every `handleEvent()` branch.
   - Simplify `LayoutPainterPageController` and `HoverButtonController` so
     `handleEvent()` only processes input/view events and `update()` advances
     animations on deadline ticks.
