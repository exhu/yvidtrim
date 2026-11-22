# Phase 2: Migrate Controllers, Remove `Controller.tick`, Expand Tests

Migrate all `Controller` implementations and tests from `tick(float dt)`
/ `startTickTimer` / `stopTickTimer` to `onTimer(TimerId id, float dt)`
/ `startTimer` / `stopTimer`, remove `Controller.tick` and the
temporary Phase 1 bridge, and add unit tests covering multi-timer
dispatch and Phase 2a `WidgetSystem.update(ctx)`.

## Tasks

### 1. Remove `Controller.tick` & Bridge in `yguilib`

- `yguilib/source/yguilib/controller/package.d`:
  - Remove `bool tick(float dt);` from `Controller`.
  - Remove `override bool tick(float dt)`, `startTickTimer`, and
    `stopTickTimer` from `DefaultController`.
  - Implement `override bool onTimer(TimerId id, float dt) { return false; }`
    directly on `DefaultController`.
- `yguilib/source/yguilib/controller/internal/controller_stack.d`:
  - Replace `override bool tick(float dt)` in `ModalTrackController` with
    `override bool onTimer(TimerId id, float dt)`.
- `yguilib/source/yguilib/internal/timer_service.d`:
  - Replace `override bool tick(float dt)` in `DummyCtrl` with
    `override bool onTimer(TimerId id, float dt)`.

### 2. Migrate `yguilib` Controller Callers & Tests

- `yguilib/source/yguilib/internal/uisystem_impl.d`:
  - In `TickController` test: replace `startTickTimer` / `stopTickTimer`
    with `startTimer` / `stopTimer` and `override bool tick(float dt)`
    with `override bool onTimer(TimerId id, float dt)`.
  - In `FloodController` test: replace `override bool tick(float dt)` with
    `override bool onTimer(TimerId id, float dt)`.
- `yguilib/source/yguilib/controls/virtlist.d`:
  - In `runVirtListPipelineTest` harness controller: replace
    `override bool tick(float dt)` with
    `override bool onTimer(TimerId id, float dt)`, and use
    `startTimer` / `stopTimer`.

### 3. Migrate `guidemo` Controllers & Tests

- `source/guidemo/hover_button.d`:
  - In `HoverButtonController`: replace `startTickTimer` / `stopTickTimer`
    with `startTimer` / `stopTimer`, and `override bool tick(float dt)`
    with `override bool onTimer(TimerId id, float dt)`.
  - Update `hover_button.d` unit tests to call
    `onTimer(controller.animTimerId, 0.016f)`.
- `source/guidemo/pages/layout_painter_controller.d`:
  - In `LayoutPainterPageController`: replace `startTickTimer` /
    `stopTickTimer` with `startTimer` / `stopTimer`, and
    `override bool tick(float dt)` with
    `override bool onTimer(TimerId id, float dt)` (guarding
    `if (id != alphaTimerId) return false;`).
  - Update unit tests to call `ctrl.onTimer(ctrl.alphaTimerId, 0.016f)`.
- `source/guidemo/pages/virtlist_controller.d`:
  - In `VirtListPageController` and `Page7HarnessController`: replace
    `startTickTimer` / `stopTickTimer` with `startTimer` / `stopTimer`,
    and `override bool tick(float dt)` with
    `override bool onTimer(TimerId id, float dt)`.

### 4. Add Expanded Unit Tests

- `yguilib/source/yguilib/internal/uisystem_impl.d`:
  - Add test verifying a `Controller` with two independent timers
    (`10 ms` and `25 ms`) receives distinct `TimerId` values in
    `onTimer(id, dt)` while `updateView()` runs at most once per step,
    and `popController()` stops all timers for that controller.
  - Add test verifying a `WidgetSystem` with two independent timers
    receives distinct `TimerId` values in `onTimer(ctx, id, dt)`, and a
    `SystemPhase.update` system runs `update(ctx)` in Phase 2a when
    `needModelUpdate` is true (without needing an active timer), and
    `unregisterWidgetSystem()` cancels all its timers.

## Verification

```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
```
