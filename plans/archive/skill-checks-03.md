# Phase 3: Controller & Timer Style Rules

Overview: [skill-checks.md](skill-checks.md). Read `AGENTS.md` and
`codestyle.md` first.

## Target Files

- `.agents/skills/check-codestyle/scripts/check_style.d`
- `.agents/skills/check-codestyle/SKILL.md`

## Context

`check_style.d` has 12 checks (see `SKILL.md` "Checks Enforced") and runs
on git diff additions by default, or on full files with `--all` / paths.
Rules from `AGENTS.md` "Controllers":

- `DefaultController` subclasses overriding `handleEvent(AppEvent ev)`
  must return `super.handleEvent(ev)` for unhandled events.
- Animate via `startTimer`/`stopTimer`; stop when idle.

There are 34 `override HandleResult handleEvent` sites today, 19 outside
the skipped directories below; all 19 already call `super.handleEvent(`.
4 of them are `WidgetViewControllerBase` subclasses in
`yguilib/source/yguilib/controls/` (`common`, `scrollbars`, `tabcontrol`,
`virtlist`); they share the same fallback contract and are intentionally
in scope.

## Steps

1. **Rule 13 - handleEvent falls through to super** (error):
   for each `override HandleResult handleEvent(` body in any class
   (`DefaultController` and `WidgetViewControllerBase` subclasses alike;
   no base-class resolution needed), require `super.handleEvent(` to
   appear in the body. Find the body via brace matching; reuse the
   function-body helpers of the 50-line function-length check.
   Skip `yguilib/source/yguilib/controller/` and
   `yguilib/source/yguilib/internal/` (base classes that define the
   fallback). Only scan when the full body is available: in diff mode,
   check functions that overlap added lines, reading the whole file from
   disk.

2. **Rule 14 - timers are stopped** (warning):
   per class body, warn when it calls `startTimer(` but never calls
   `stopTimer(`. Skip `unittest` blocks and the timer infrastructure files
   (`timercontrol.d`, `internal/timer_service.d`, `internal/uisystem_impl.d`,
   `controller/package.d`).

3. Document rules 13-14 in `SKILL.md` and `--help`.

## Acceptance

```bash
rdmd .agents/skills/check-codestyle/scripts/check_style.d --all
# -> 0 errors; warning count must not grow beyond the 30 present before
#    this phase (rule 14 should add none on the current tree)
```

Negative tests (do not commit): remove `return super.handleEvent(ev);`
from one guidemo page controller (expect rule 13 error); comment out a
`stopTimer` call in `hover_button_system.d` (expect rule 14 warning).
Revert both.

Run the full verification and update the overview status table.
