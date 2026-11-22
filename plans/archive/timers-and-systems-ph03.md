# Phase 3: Documentation, TODO Cleanup, and Full Verification

Update project documentation and `TODO.md` to reflect the new owner-bound
timer, `onTimer`, and Phase 2a `SystemPhase.update` architecture, and run
all build, test, style, boundary, and null-safety checks.

## Tasks

### 1. Update `TODO.md`

- Remove the completed first item (lines 1-19) from `TODO.md`.

### 2. Update `ARCHITECTURE.md`

- Update `Primary Data Flows` Section 2 (`Phase 2 Sync, Timers &
  Model-View-Controller Loop`) to show:
  - Phase 2a (`needModelUpdate`): `Controller.update()` and
    `SystemPhase.update: WidgetSystem.update(ctx)`.
  - Phase 2b (`TimerService`): `Controller.onTimer(id, dt)` and
    `WidgetSystem.onTimer(ctx, id, dt)`.
- Update `Zero-CPU Idle Sleep` under `Idiomatic Patterns` to reference
  `TimerControl.startTimer` / `stopTimer`.
- Keep `ARCHITECTURE.md` under 250 lines and <= 80 chars/line.

### 3. Update `AGENTS.md`, `SKILL.md`, and `documentation/timers-and-systems.md`

- `AGENTS.md`:
  - Update `Controller Event Delegation & Timers` section to reference
    `TimerControl` (`startTimer` / `stopTimer`), `Controller.onTimer`,
    `WidgetSystem.onTimer`, and non-timed `SystemPhase.update`.
- `.agents/skills/define-gui-widget/SKILL.md`:
  - Update `WidgetSystem` timer guidance to reference `onTimer`,
    `startTimer` / `stopTimer`, and non-timed `SystemPhase.update`.
- `documentation/timers-and-systems.md`:
  - Add a brief status note at the top or bottom indicating Variant D
    has been implemented.

## Verification

```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
```
