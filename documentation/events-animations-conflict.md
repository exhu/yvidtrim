# Input Events and Animation Updates Conflict: Analysis & Improvement Options

This report analyzes the conflict between input event processing and active
animations described in the first item of `TODO.md`, identifies all root causes
in `yguilib` and `guidemo`, establishes non-negotiable invariants for pointer
input fidelity, and proposes architectural options and an implementation plan.

---

## 1. Core Design Invariants

Any solution must uphold three invariants so fixing animation starvation does
not degrade pointer interaction quality or idle power usage.

### 1.1. Never Merge or Coalesce `mouseMotion` Events
Consecutive `AppEvent.Kind.mouseMotion` events **must never be merged** into a
single endpoint or accumulated `(xrel, yrel)` vector before hit-testing.

A user may sweep the cursor rapidly in a curve or zig-zag across multiple
controls within a single 16 ms frame (before the next animation update fires):

```
  Actual curved path (5 SDL samples)     Merged vector (start -> end only)
  +------+     +------+     +------+     +------+     +------+     +------+
  | Btn1 |     | Btn2 |     | Btn3 |     | Btn1 |     | Btn2 |     | Btn3 |
  +------+     +------+     +------+     +------+     +------+     +------+
      \       /        \       /              \                        /
       *--*--*          *--*--*                \______________________/
    Hits Btn1, Btn2, and Btn3                Skips Btn1, Btn2, and Btn3!
```

- Every raw `mouseMotion` sample delivered by SDL3 must reach hit-testing
  (`InputSystem` and `WidgetSystem`s such as `AnimatedHoverButtonSystem`) in
  exact chronological order.
- Preserving every sample guarantees that `mouseEnter` / `mouseLeave`
  transitions fire for every widget touched along the sampled polyline, no
  matter how complex the curve. (It also keeps the door open for future
  segment-swept hit-testing or freehand gesture/drawing input.)
- **Performance reality**: Hit-testing 16-32 unmerged `mouseMotion` events per
  16 ms frame (1000-2000 Hz mouse polling) against a flat `VisibleWidgets` array
  takes tens of microseconds (< 0.5% of a frame budget). The real bottleneck is
  **per-event rendering / VSync**, **relative timeout resets**, and **event-loop
  imbalance**, not preserving raw pointer coordinates.
- **Heavy reaction separation**: While `handleEvent()` must receive every
  motion/transition event, expensive work triggered by continuous motion (e.g.,
  FFmpeg frame seeking during timeline scrubbing in `yvidtrim`, relayout, or
  OpenGL uploads) belongs in `update()` / `updateView()` once per frame,
  matching the contract already documented on `Controller.handleEvent`
  (`yguilib/source/yguilib/controller/package.d:31-33`).

### 1.2. Preserve Sub-Frame `mouseEnter` + `mouseLeave` Hover Trails
Preserving every `mouseMotion` sample is necessary, **but not sufficient by
itself** once event draining is decoupled from frame updates!

Trace a fast curved sweep over `Btn1 -> Btn2 -> Btn3` within one 16 ms frame
(before the next animation step runs):
1. Sample 1 hits `Btn1` -> `mouseEnter(Btn1)` sets `isHovered = true`.
2. Sample 2 moves to `Btn2` -> `mouseLeave(Btn1)` sets `isHovered = false`,
   `mouseEnter(Btn2)` sets `isHovered = true`.
3. Sample 3 moves to `Btn3` -> `mouseLeave(Btn2)` sets `isHovered = false`,
   `mouseEnter(Btn3)` sets `isHovered = true`.
4. Animation tick runs at end of frame:
   - In `HoverButtonController` (`source/guidemo/hover_button.d:382-396`),
     `Btn1` and `Btn2` have `hoverProgress == 0.0f` and `isHovered == false`,
     so `isAnyAnimating()` returns `false` and **no fade animation starts**.
   - In `AnimatedHoverButtonSystem`
     (`source/guidemo/hover_button_system.d:338-358`), `comp.isHovered` flips
     `false -> true -> false` before `preLayout()` steps `hoverTimer`;
     `hoverTimer.isAtTarget(false)` is already `true` (`elapsed == 0`), so
     `Btn1` and `Btn2` are dropped from `activeButtons` with **zero visual
     feedback**.

To keep multi-button sweep trails working under batched input draining,
hover-animated controls/systems must **latch a hover pulse** on `mouseEnter`
(e.g., a two-phase `entering -> peak -> leaving` state or a minimum pulse
target/impulse floor) so a button touched and left within a single frame still
ramps visibly and fades out smoothly.

### 1.3. Zero-CPU Idle Sleep & Main-Thread Graphics Boundary
- When no animations or timers are active and no events are pending, the main
  loop must block indefinitely (`timeoutMs = -1`) at 0% CPU.
- All widget mutations and OpenGL ES calls stay strictly on the main thread;
  background threads communicate exclusively via `MessageBus.send()` with
  race-free wakeup signaling.

---

## 2. Problem Analysis & Root Causes

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
    |     dispatchEvent(event)  (UiSystemController is TOP of stack!)
    |       -> UiSystemController runs pipeline.handleEvent()
    |            -> if requestUpdateView: pipeline.updateAndRender() NOW!
    |       -> User controllers run handleEvent()
    |            -> if Result.update:     sendAppEvent(Kind.update)
    |            -> if Result.updateView: updateView() -> Kind.updateUiLayer
    |
    +-- [Branch B: nullableEvent.isNull && waitRes == 0 && timeoutMs >= 0]
          dispatchEvent(Kind.update)   -> may run pipeline.updateAndRender()
          updateAndRender(activeCtrl)  -> runs UiSystemController.updateView()
                                          a SECOND time!
    |
    v
  messageBus.ensureWake() -> pushes another SDL Wake if queue non-empty
```

Seven interacting mechanisms cause animations and input events to conflict:

### 2.1. Relative Idle Timeout Starves `Kind.update` Under Input Floods
`Branch B` (which synthesizes `AppEvent.Kind.update`) executes **only** when
`yguilib_sdl3_wait_event` times out (`waitRes == 0`) **and** `MessageBus` is
empty (`uisystem_impl.d:402`). Because `currentTimeoutMs` (typically `16` ms
for 60 FPS) is passed as a relative sleep timeout on each step, any input
stream arriving faster than 16 ms (such as a 125-1000 Hz mouse generating
motion events every 1-8 ms) wakes `SDL_WaitEventTimeout` before it expires.
The 16 ms wait resets on every mouse event, so `waitRes == 0` never occurs and
`Kind.update` is completely starved while the cursor moves.

### 2.2. Per-Event Rendering & VSync Stalls (`swapBuffers()` Inside Dispatch)
`UiSystemImpl.mainEventLoop()` (`uisystem_impl.d:168`) pushes
`UiSystemController` **last**, placing it at the **top** of `ControllerStack`
so it runs first on every event. Currently, rendering is triggered inline on
individual input events rather than once per frame:
- In `AnimatedHoverButtonSystem.handleMouseMotion()`
  (`source/guidemo/hover_button_system.d:370-371`), whenever **any** button is
  animating, **every** `mouseMotion` event returns `requestUpdateView = true`.
  `UiSystemController` converts that into `Result.updateView`, causing
  `applyViewUpdatesAndRender()` to call `UiSystemController.updateView()` ->
  `pipeline.updateAndRender()` -> `window.swapBuffers()` **synchronously on
  every mouse packet**.
- Similarly, `HoverButtonController` returns `Result.updateView` on every
  `"hoverBtn.move"` (`source/guidemo/hover_button.d:450-456`), and
  `ScrollbarWidgetViewController` returns `Result.updateView` on every
  `scrollbarThumbDrag` (`source/guidemo/scrollbars.d:732`), each scheduling
  `Kind.updateUiLayer` -> `swapBuffers()`.
- With 60 Hz VSync (`swapBuffers()` blocking ~16.6 ms) and unmerged 500-1000 Hz
  mouse input (8-16 samples per 16 ms), rendering per event amplifies ~0.05 ms
  of hit-testing into 130-266 ms of VSync backlog per frame.

### 2.3. Single-Event Poll/Dispatch Imbalance & Spurious `SDL_WAKE` Accumulation
Each call to `runEventLoopStep()` polls at most one SDL event and pops at most
one `AppEvent` from `MessageBus` (`yguilib_sdl3_poll_event()` already exists in
`yguilib/yguilib-clibs/yguilib_sdl3.h:159` but is never used). Meanwhile, one
hardware `mouseMotion` event can enqueue 1-3 follow-up `MessageBus` events
(`mouseEnter`, `mouseLeave`, `mouseMove`, `mouseDrag`, `updateUiLayer`,
`update`).

Worse, `SDL_WAKE` events accumulate in SDL's queue:
1. `MessageBus.send()` (`message_bus.d:68-77`) calls
   `yguilib_sdl3_send_wake_event()` even when called from the **main thread**
   (inside `pollSdlEvent` or `dispatchEvent`), queuing a redundant
   `YGUILIB_SDL3_EVENT_WAKE` onto SDL's queue.
2. `MessageBus.ensureWake()` (`message_bus.d:110-121`) unconditionally pushes
   another `SDL_WAKE` at the end of every step whenever `head < events.length`,
   ignoring `wakeSent`.
3. When `pollSdlEvent` later pops a stale `SDL_WAKE`, `appEventFromSdlEvent()`
   returns `Nullable!AppEvent.init`, yet `waitRes` is `1` (not `0`), wasting a
   loop iteration and preventing `Branch B` (`waitRes == 0`) from firing even
   when `MessageBus` is empty.

### 2.4. `MessageBus.noRepeat` Bug & Unbounded Linear Queue Growth
In `yguilib/source/yguilib/events/internal/message_bus.d`:

```d
if (ev.noRepeat && !isQueueEmpty() && (ev == events[head])) {
  allowedToSend = false;
}
```

Two distinct bugs exist in `MessageBus`:
1. **Front-only deduplication & flag mismatch**: `ev == events[head]` compares
   only against the **oldest** element at `head`. When the queue holds
   `[mouseMotion_2, mouseMotion_3, update]`, `events[head]` is `mouseMotion_2`,
   so `makeNoRepeat(Kind.update)` and `makeNoRepeat(Kind.updateUiLayer)` bypass
   deduplication and append duplicates. Moreover, struct equality compares
   `fnoRepeat`, so `makeNoRepeat(Kind.update)` does not even match an existing
   `AppEvent(Kind.update)` (`fnoRepeat == false`).
2. **Unbounded memory growth under sustained input**: `events` is a linear
   slice with a monotonically advancing `head` (`message_bus.d:227-240`).
   `resetIfEmpty()` only resets `events.length = 0; head = 0;` when the queue
   hits zero (`head >= events.length`). Under continuous unmerged mouse motion
   where at least one event remains queued, `events` never resets and grows
   indefinitely on the GC heap.

### 2.5. `updateUiLayer` Busy-Loop & `DeltaTimer.minStep` Speed-Up
To keep its alpha pulse moving during mouse motion,
`LayoutPainterPageController.handleEvent`
(`source/guidemo/pages/layout_painter_controller.d:118-122`) runs `update()` on
its fallback branch for **every** event, including `Kind.updateUiLayer`:

```
updateUiLayer -> LayoutPainterPageController.handleEvent()
  -> calls update() (dt clamped to minStep = 1 ms) -> returns Result.updateView
  -> applyViewUpdatesAndRender() -> sendUpdateUiLayerEvent() + SDL Wake
  -> immediate next iteration (0 ms sleep, bypasses 16 ms timeoutMs!)
```

Similarly, `MainController.handleEvent` in `source/yvidtrim/app.d:133-135`
returns `Result.update` for every unhandled event (including `mouseMotion`),
flooding `Kind.update`.

Compounding this, `DeltaTimer.step()` (`yguilib/source/yguilib/timers.d`)
clamps `dt` upward to `minStep = 0.001f` (1 ms). Whenever animations step more
than once per millisecond (from the `updateUiLayer` busy-loop when VSync is
off, per-event `HoverButtonController.updateView()` on 1000 Hz `mouseMove`, or
double `preLayout()` calls), every sub-millisecond call is inflated to 1 ms,
running animations **several times faster than real time**.

### 2.6. Double `preLayout` & Render Execution on Timeout Ticks
In `runEventLoopStep` Branch B (`uisystem_impl.d:402-407`):
1. `dispatchEvent(Kind.update)` dispatches to `UiSystemController`, which runs
   `pipeline.handleEvent(Kind.update)`. When `AnimatedHoverButtonSystem` is
   animating, it returns `requestUpdateView = true`, so `dispatchEvent` calls
   `UiSystemController.updateView()` -> `pipeline.updateAndRender()` (running
   `preLayout()`, `render()`, and `swapBuffers()`).
2. Immediately afterward, line 406 unconditionally calls
   `updateAndRender(activeController)` where `activeController` is
   `UiSystemController`! Because `AnimatedHoverButtonSystem.preLayout()` checks
   `if (!needsAnimationStep && !isAnyAnimating())` (`hover_button_system.d:292`)
   and `isAnyAnimating()` is still `true`, `preLayout()` advances the animation
   **a second time**, re-dirties the widget, and calls `swapBuffers()` **twice**
   in a single timeout tick.

More broadly, advancing time inside `SystemPhase.preLayout` couples animation
progress to unrelated redraw triggers (window expose, resize, or sibling view
updates).

### 2.7. Fragile Per-Event `timeoutMs` Propagation & Modal Stack Ordering
Every animating controller must populate `res.timeoutMs` on every return path
of `handleEvent()`. Furthermore:
- If an upper controller consumes an event (`consume = true`) and specifies its
  own `timeoutMs` (e.g., `100` ms), `applyTimeout()` (`uisystem_impl.d:288-299`)
  overwrites `currentTimeoutMs` with `100` ms even if an unvisited lower
  controller needed `16` ms.
- Because `UiSystemController` is pushed at the top of `ControllerStack` inside
  `mainEventLoop()`, controllers pushed before `mainEventLoop()` sit below it,
  whereas modal controllers pushed later during runtime sit **above** it. A
  modal controller consuming an event can skip `UiSystemController` entirely,
  suppressing both `InputSystem` and `pipeline.timeoutMs`.

---

## 3. Architectural Options

All options below preserve the Section 1 invariants: **no `mouseMotion`
coalescing** and **0% idle CPU**.

### Option 1: Deadline-Driven Timer Service in `UiSystem`
*(Corresponds to the first suggestion in `TODO.md`)*

Replace per-event relative `HandleResult.timeoutMs` sleeps with an absolute
wall-clock deadline scheduler in `UiSystem`.

#### How It Works
1. **Timer / Timeout Registration**:
   - Controllers and systems either register one-shot/repeating timers with
     `UiSystem` (`TimerId id = ui.startTimer(16.msecs, TimerMode.repeat);
     ui.stopTimer(id);`), or expose `@property int timeoutMs() const`
     (matching `WidgetSystem.timeoutMs`) queried by `UiSystem`.
2. **Absolute Wall-Clock Deadlines (`MonoTime`)**:
   - `UiSystem` tracks `nextDeadlineNs` using `MonoTime`.
   - If a new shorter-period timer/animation starts while a longer deadline is
     pending (e.g., a 16 ms hover animation starts while a 500 ms cursor blink
     is waiting), `nextDeadlineNs` is clamped immediately to
     `min(nextDeadlineNs, nowNs + newPeriodNs)`.
3. **Remaining-Time Wait Calculation**:
   ```
   remainingMs = hasActiveDeadline
     ? max(0, (nextDeadlineNs - nowNs) / 1_000_000)
     : -1
   ```
4. **Drift- & VSync-Safe Deadline Advancement**:
   - Anchor the next periodic deadline to `tickStartNs + periodNs` (clamping to
     `nowNs + periodNs` if behind by more than one period to avoid spiral of
     death), **not** to `afterSwapBuffersNs + periodNs`.
   - Anchoring after `swapBuffers()` causes a classic double-wait under VSync
     (16 ms VSync + 16 ms timer wait -> 30 FPS instead of 60 FPS).
5. **Deadline Expiry Independent of Input Arrival**:
   - On every loop step, whenever `nowNs >= nextDeadlineNs`, `UiSystem` fires
     the timer / animation update regardless of whether `SDL_WaitEventTimeout`
     timed out (`0`) or woke early on mouse input (`1`).

```
Time (ms):   0        4        8       12       16
             |--------|--------|--------|--------|
SDL Input:   [move]   [move]   [move]   [move]
Wait time:   16ms     12ms     8ms      4ms      0ms -> Deadline reached!
                                                        Run animation tick
```

#### Pros & Cons
- **Pros**:
  - Eliminates relative-timeout starvation under 125-1000+ Hz mouse input.
  - Supports multiple independent cadences (16 ms UI animations, 24/29.97/60 fps
    video playback in `yvidtrim`, 500 ms cursor blink, one-shot tooltip delays).
  - Event consumption by a top/modal controller can no longer hide a lower
    controller's or `WidgetSystem`'s animation cadence.
- **Cons**:
  - Alone, it does not fix per-event `swapBuffers()` stalls, `MessageBus`
    linear memory growth, or `updateUiLayer` recursion; must be paired with
    Options 2 and 3.

---

### Option 2: Hardened `MessageBus` (Ring Buffer, Exact `noRepeat`, Priority)
*(Refines the second suggestion in `TODO.md`, without `mouseMotion` merging)*

Upgrade `MessageBus` into a bounded-overhead, race-free queue with exact
singleton deduplication and optional priority lanes while keeping every
`mouseMotion` sample untouched in FIFO order.

#### How It Works
1. **Ring Buffer Storage**:
   - Replace the linear `AppEvent[] + head` slice with a power-of-two circular
     ring buffer (growing on overflow, reusing slots in O(1) without ever
     requiring the queue to hit empty). Eliminates unbounded GC growth during
     sustained unmerged mouse input.
2. **O(1) Full-Queue `noRepeat` Bitmask (Idempotent Signals Only)**:
   - Track pending payloadless singleton events (`Kind.update`,
     `Kind.updateUiLayer`, `Kind.windowRedraw`) via a `uint pendingNoRepeatMask`
     bitmask cleared on dequeue.
   - Ignore `fnoRepeat` differences so `AppEvent(Kind.update)` and
     `AppEvent.makeNoRepeat(Kind.update)` deduplicate against each other.
   - **Strictly NO coalescing of `Kind.mouseMotion`** (or `key*` /
     `mouseButton*`): every pointer waypoint stays intact in chronological
     order.
3. **Race-Free, Main-Thread-Silent Wakeups**:
   - Main-thread `send()` calls (`pollSdlEvent`, `InputSystem`, `ScrollSystem`,
     `sendUpdate()`) **never** call `yguilib_sdl3_send_wake_event()`.
   - Before blocking in `yguilib_sdl3_wait_event`, the main thread locks
     `MessageBus`: if non-empty, it skips `wait_event` (drains immediately); if
     empty, it clears `wakeSent = false` while holding the lock and then enters
     `wait_event`.
   - Any background thread calling `send()` after the lock is released sees
     `!wakeSent`, sets `wakeSent = true`, and pushes exactly one `SDL_WAKE`.
     Zero lost wakeups and zero main-thread `SDL_WAKE` pollution.
4. **Priority Lanes with Bounded Input Quota (Optional with Option 3)**:
   - Partition into **Control/Timer Lane** (`appQuit`, `windowClose`, due
     `update`/timer events), **Input/View Lane** (`mouse*`, `key*`, `view`,
     `user`, `window*`), and **Render Barrier** (`updateUiLayer`).
   - Dispatch at most `N` input events (or up to the next deadline) before
     servicing a due timer/update event. Remaining `mouseMotion` events stay
     intact in FIFO order and resume immediately on the next tick with
     `waitMs = 0`.

```
+-------------------------------------------------------------------------+
|              HARDENED MESSAGEBUS (NO MOUSE MOTION MERGING)              |
+-------------------------------------------------------------------------+
  Incoming send(ev)
    |
    +-- ev.noRepeat (update/updateUiLayer/windowRedraw)
    |     --> O(1) pendingNoRepeatMask check (drop duplicate)
    +-- Kind.mouseMotion & all discrete input
    |     --> Append in exact FIFO order into Ring Buffer (NEVER merged!)
    +-- Background thread only & !wakeSent
          --> Set wakeSent = true, push single SDL_WAKE
    |
    v
  +---------------------------------------------------------------------+
  | Lane 0 (Control/Due Timers): [ appQuit, due timer/update ]          |
  | Lane 1 (Input/View Ring):    [ motion1, motion2, motion3, view... ] |
  | Lane 2 (Render Barrier):     [ updateUiLayer ] (if still event-led) |
  +---------------------------------------------------------------------+
```

#### Pros & Cons
- **Pros**:
  - Fixes linear memory growth, `noRepeat` duplication, and `SDL_WAKE` spam
    with small, self-contained changes.
  - Preserves 100% of curved `mouseMotion` trajectories.
- **Cons**:
  - Priority ordering only schedules events already enqueued; still requires
    wall-clock deadlines (Option 1) to emit updates during input floods and
    batched rendering (Option 3) to stop per-event `swapBuffers()` stalls.

---

### Option 3: Phased Frame Loop (Bounded Drain -> Deadline Update -> Render)

Restructure `UiSystemImpl.runEventLoopStep()` from a single-event dispatcher
into a deterministic 3-phase GUI tick while preserving every `mouseMotion`
sample and 0% idle CPU.

#### How It Works
```
+-------------------------------------------------------------------------+
|                      PHASED GUI EVENT LOOP TICK                         |
+-------------------------------------------------------------------------+
  0. WAIT DECISION (race-free lock check on MessageBus)
     - If messageBus.hasPending():
         do NOT block (skip wait_event, go straight to poll_event)
     - Else:
         waitMs = hasActiveDeadline
           ? max(0, (nextDeadlineNs - nowNs) / 1_000_000) : -1
         clear wakeSent under lock -> yguilib_sdl3_wait_event(&ev, waitMs)
       |
       v
  1. PHASE 1: BOUNDED INPUT & EVENT DRAIN (NO RENDERING!)
     - Drain all currently queued SDL events via yguilib_sdl3_poll_event(&ev)
       (ignore WAKE; push ALL mouseMotion samples intact in FIFO order).
     - Pop and dispatch MessageBus events (hardware + derived Kind.view
       events such as mouseEnter/mouseLeave/mouseMove/mouseDrag) until:
         (a) MessageBus is empty, OR
         (b) safety cap reached (e.g., 256-512 events), OR
         (c) active animation deadline expired (nowNs >= nextDeadlineNs).
     - Controllers/systems update lightweight state only; record dirtyViews
       and needModelUpdate. NEVER call updateView() or swapBuffers() here!
       |
       v
  2. PHASE 2: MODEL SYNC & DEADLINE ANIMATION UPDATE
     - If needModelUpdate (from Result.update / sendUpdate()):
         run model-sync update pass across controllers.
     - If hasActiveDeadline && nowNs >= nextDeadlineNs:
         compute real dt (clamped [0, maxStep]); advance deadline from
         tickStartNs + periodNs.
         - Step active Controllers (controller.update / tick)
         - Step active WidgetSystems (pipeline.update(dt))
         Mark any changed controller views dirty.
       |
       v
  3. PHASE 3: BATCHED VIEW SYNC & SINGLE FRAME RENDER
     - For each dirty controller (oldest to newest):
         if (controller.updateView()) needRender = true
     - If needRender || rootWidget.isTreeDirty() ||
          rootWidget.isTreeLayoutDirty():
         pipeline.updateAndRender(mainWindow)   // Runs AT MOST ONCE!
     - Note: if postLayout() (ScrollSystem / InputSystem.refreshHover) or
       updateView() (syncPageShell calling sendUpdate()) enqueued follow-up
       events, Step 0 of the next tick sees hasPending() == true and runs
       immediately with zero sleep!
```

Key structural properties:
- **Every `mouseMotion` sample is hit-tested in Phase 1** before rendering: a
  1000 Hz curved sweep over 5 buttons delivers all ~16 samples and all
  `mouseEnter`/`mouseLeave` events in ~0.05 ms, then renders **once** in Phase
  3 instead of stalling on 16 VSync `swapBuffers()` calls.
- **`updateUiLayer` is no longer dispatched through user controllers**:
  `UiSystemImpl` invokes `pipeline.updateAndRender(fMainWindow)` directly in
  Phase 3 whenever any view or widget is dirty, eliminating `updateUiLayer`
  recursion (such as `LayoutPainterPageController`) and removing Branch B's
  duplicate `updateAndRender(activeController)` call.
- **No dropped events under budget cap**: If an extreme burst (e.g., 8000 Hz
  mouse or slow CPU frame) hits Phase 1's deadline/count budget, Phase 2 and
  Phase 3 still run on schedule to keep animations smooth, and the remaining
  `mouseMotion` events stay in FIFO order in `MessageBus` to be drained on the
  very next tick (`Step 0` skips sleeping).
- **Mid-batch layout changes**: If a button click or resize in Phase 1 marks
  layout dirty before a trailing `mouseMotion`, Phase 3 runs layout and
  `InputSystem.postLayout` calls `refreshHover()` to reconcile hover targets
  against the new widget rects.

#### Pros & Cons
- **Pros**:
  - Completely eliminates per-event VSync stalls while keeping 100% of curved
    `mouseMotion` trajectories intact.
  - Eliminates `updateUiLayer` recursion and Branch B double-rendering.
  - Processes `postLayout` view events (`ScrollSystem`, `refreshHover`) and
    `syncPageShell`'s `sendUpdate()` cleanly with zero idle delay.
  - Preserves 0% CPU idle sleep when no animations/events are active.
- **Cons**:
  - Requires updating `uisystem_impl.d` unit tests that assert
    `AppEvent.Kind.updateUiLayer` passing through user controllers or
    single-event `runEventLoopStep` stepping.
  - Exposes the sub-frame `enter + leave` cancellation behavior described in
    Section 1.2, so hover widgets must adopt hover-pulse latching.

---

### Option 4: Unify `timeoutMs` & `update` for `Controller` and `WidgetSystem`

Align `Controller` and `WidgetSystem` so discrete event handling, continuous
time-based updates, and timeout queries have one clean mental model across the
entire library.

#### How It Works
1. **Declarative `@property int timeoutMs() const` on `Controller`**:
   - Mirror `WidgetSystem.timeoutMs` on `Controller` / `DefaultController`
     (defaulting to `-1`), and deprecate `HandleResult.timeoutMs` and
     `SystemEventResult.timeoutMs`.
   - `UiSystemImpl` queries the minimum non-negative timeout across all
     controllers on `ControllerStack` and `pipeline.timeoutMs` (plus any
     registered timers from Option 1). Modal consumption can no longer mask
     active animations.
2. **Add `SystemPhase.update` to `WidgetSystem` / `WidgetSystemPipeline`**:
   - Add an `update(ref WidgetSystemContext ctx, float dt)` hook (gated by
     `SystemPhase.update`) executed in Phase 2 alongside `Controller.update()`.
   - Move `AnimatedHoverButtonSystem`'s animation stepping out of
     `handleEvent(Kind.update)` + `preLayout()` into `update(ctx, dt)`. Now
     `preLayout` is strictly for pre-layout data/tree sync (like `DataSystem`),
     and window expose/resize redraws never spuriously advance animations.
3. **Separate Model-Sync `update()` from Time-Stepped Animations & Fix `dt`**:
   - Either pass real frame `dt` (clamped `[0, maxStep]`, with no artificial
     1 ms floor!) into animation ticks, or separate `update()` (model sync,
     triggered by `Result.update` / `sendUpdate()`) from `tick(float dt)` /
     timer callbacks, and remove `DeltaTimer.minStep = 0.001f` (using explicit
     `dt` or injectable clock in unit tests).
   - Eliminates animation speed-up when multiple model updates happen within
     < 1 ms.
4. **Hover-Pulse Latch for Swept Controls**:
   - Update `HoverButtonController` and `AnimatedHoverButtonSystem` so
     `mouseEnter` latches a visible hover pulse (e.g., ramping up to a visible
     peak before fading out on `mouseLeave`), ensuring curved sweeps over
     multiple buttons inside a single frame trigger smooth cascading hover
     trails.

#### Pros & Cons
- **Pros**:
  - Unifies animation design across `Controller` and `WidgetSystem`.
  - Makes `LayoutPainterPageController`, `HoverButtonController`, and
    `AnimatedHoverButtonSystem` dramatically simpler and bug-free.
  - Eliminates the `AGENTS.md` footgun where forgetting
    `super.handleEvent(ev)` silently skips `update()`.
  - Fixes `DeltaTimer.minStep` real-time drift and makes animation unit tests
    100% deterministic.
- **Cons**:
  - Modifies `Controller` and `WidgetSystem` interfaces (small migration across
    existing controllers/systems in `yguilib`, `guidemo`, and `yvidtrim`).

---

## 4. Comparison Matrix

```
+---------------------------------+----------+----------+----------+----------+
| Criterion                       | Option 1 | Option 2 | Option 3 | Option 4 |
|                                 | Deadlines| RingBus  | Phased   | Lifecycle|
+---------------------------------+----------+----------+----------+----------+
| Preserves curved mouseMotion    | Yes      | Yes      | Yes      | Yes      |
| Fixes mouse-flood update starve | Yes      | Partial* | Yes      | With 1/3 |
| Fixes per-event VSync stalls    | No       | No       | Yes      | Partial  |
| Fixes ring mem & SDL_WAKE spam  | No       | Yes      | Partial  | No       |
| Stops updateUiLayer busy-loop   | Partial  | Partial  | Yes      | Yes      |
| Fixes double preLayout/render   | No       | No       | Yes      | Yes      |
| Fixes DeltaTimer 1ms speed-up   | No       | No       | Partial  | Yes      |
| Supports WidgetSystem + Ctrl    | Yes      | N/A      | Yes      | Best     |
| Preserves 0% idle CPU           | Yes      | Yes      | Yes      | Yes      |
| Multi-timer / video FPS support | Best     | Fair     | Good     | Good     |
| Implementation scope            | Medium   | Small    | Medium   | Medium   |
+---------------------------------+----------+----------+----------+----------+
*Option 2 requires Option 1 or 3 to trigger updates on wall-clock deadlines
 rather than only when SDL_WaitEventTimeout returns 0.
```

---

## 5. Recommended Implementation Plan

The four options are complementary and solve distinct parts of the problem.
Implement them in four incremental, testable steps (and remove the completed
first item from `TODO.md` once verified):

1. **Step 1: Harden `MessageBus` Without Coalescing `mouseMotion` (Option 2)**
   - Convert `MessageBus` storage to a ring buffer to prevent unbounded GC
     growth during sustained unmerged mouse input.
   - Replace front-only `ev == events[head]` with an O(1) `pendingNoRepeatMask`
     bitmask for idempotent singleton signals (`update`, `updateUiLayer`,
     `windowRedraw`), ignoring `fnoRepeat` mismatches.
   - Make `SDL_WAKE` background-thread-only with lock-protected `wakeSent`
     arming right before `wait_event`, eliminating `ensureWake()` and ghost
     main-thread wake events.
   - Keep every `AppEvent.Kind.mouseMotion` intact in strict FIFO order.

2. **Step 2: Adopt Wall-Clock Deadlines & Phased Frame Loop (Options 1 + 3)**
   - In `UiSystemImpl`, track absolute `MonoTime` deadlines (anchored to
     `tickStartNs + periodNs` with lag clamping for VSync safety; clamped
     immediately when shorter timeouts activate).
   - Drain pending SDL events via `yguilib_sdl3_wait_event` (only when
     `MessageBus` is empty) followed by `yguilib_sdl3_poll_event` loop.
   - Execute Phase 1 (bounded input/event dispatch with zero rendering),
     Phase 2 (model sync + deadline-driven controller and system updates), and
     Phase 3 (batched `updateView()` + one `pipeline.updateAndRender()` pass).
   - Remove Branch B's duplicate `updateAndRender(activeController)` call and
     stop routing `updateUiLayer` through user controllers.

3. **Step 3: Unify `Controller` & `WidgetSystem` Update Lifecycles (Option 4)**
   - Add `@property int timeoutMs() const` to `Controller` / `DefaultController`
     (and optionally a multi-timer API on `UiSystem` for future video playback
     and one-shot UI timers), deprecating `HandleResult.timeoutMs` and
     `SystemEventResult.timeoutMs`.
   - Add `SystemPhase.update` (`update(ref WidgetSystemContext ctx, float dt)`)
     to `WidgetSystem` and `WidgetSystemPipeline`.
   - Eliminate `DeltaTimer.minStep = 0.001f` speed-up by passing real frame
     `dt` (or making `DeltaTimer` clock-injectable with `minStep = 0.0f`).

4. **Step 4: Update Animated Controls & Add Regression Tests**
   - Simplify `LayoutPainterPageController`, `HoverButtonController`,
     `AnimatedHoverButtonSystem`, and `source/yvidtrim/app.d` to use the clean
     lifecycle (no `updateUiLayer` fallback, no per-`mouseMotion` render
     requests, no animation stepping in `preLayout`).
   - Add sub-frame hover-pulse latching to `HoverButtonController` and
     `AnimatedHoverButtonSystem` so rapid curved sweeps across multiple buttons
     within one frame visibly start hover animations on every touched button.
   - Add unit tests verifying:
     1. Curved multi-button `mouseMotion` burst within a single frame delivers
        `mouseEnter`/`mouseLeave` and starts hover animations on all touched
        buttons without dropping any waypoint.
     2. Continuous 1000 Hz `mouseMotion` stream does not starve deadline
        animations, does not grow `MessageBus` memory, and renders at most once
        per frame.
     3. Idle loop computes `waitMs = -1` (0% CPU) once all animations finish.
