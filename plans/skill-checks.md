# Skill Checks for AGENTS.md Rules

## Overview

Several `AGENTS.md` rules are only documented and never checked by a skill
script. This plan adds static checks for them to the existing D skill
scripts, then adds one aggregate entry point so skills stop repeating
their own copies of the verification block.

Rules gaining a check:

```
AGENTS.md rule                         -> script / rule id
------------------------------------------------------------------
GLES only via glad2.gles2              -> check_boundaries  (7)
Controllers never touch App/Window     -> check_boundaries  (8)
  or create their View
unittest modules in a Meson test       -> check_boundaries  (9)
No version(unittest) void main()       -> check_boundaries (10)
handleEvent returns super.handleEvent  -> check_style      (13)
startTimer paired with stopTimer       -> check_style      (14)
```

Not automated (too semantic for a line-based checker; stays a review
item): "never coalesce `mouseMotion`", "GUI on main thread only".

Baseline measured on 2026-11-26: all six new rules pass on the current
tree when `unittest { ... }` blocks are skipped (the only `yguilib.app`
imports in controllers are inside unittests). Any new finding a phase
reports on existing code is a checker bug unless shown otherwise.

## Shared Constraints (all phases)

- Scripts are D + Phobos, run with `rdmd`; follow `codestyle.md`
  (2-space indent, 80 cols, no default params, no `out`, no overloads).
- Keep existing rule numbering; append new rules, update `--help` and the
  skill's `SKILL.md` "Checks/Boundaries Enforced" list.
- Errors exit `1`; warnings print but exit `0`.
- Verify with
  `rdmd .agents/skills/build-and-test/scripts/run_verify.d` (timeout-
  wrapped), plus `check_line_length.d -f` on every touched file.

## Phases

- [Phase 1: GLES & controller boundaries](skill-checks-01.md)
  Rules 7-8 in `check_boundaries.d`, with a shared unittest-block
  stripper.
- [Phase 2: Test target coverage](skill-checks-02.md)
  Rules 9-10 in `check_boundaries.d`: every module with `unittest` is
  listed in a Meson file, no ad-hoc `version (unittest)` `main`.
- [Phase 3: Controller & timer style rules](skill-checks-03.md)
  Rules 13-14 in `check_style.d`.
- [Phase 4: Aggregate `--checks` & skill doc cleanup](skill-checks-04.md)
  `run_verify.d --checks`; replace duplicated verification blocks;
  add `ARCHITECTURE.md` reminders.

## Status

| Phase | State   | Notes |
|-------|---------|-------|
| 1     | pending |       |
| 2     | pending |       |
| 3     | pending |       |
| 4     | pending |       |

## Proposed TODO.md Update

Add under a new "tooling" heading (not part of this plan):

- planning skill: scaffold `plans/<name>.md` + `-phNN.md`, run phases via
  the implementer agent, update overview status
- decide `setCaption`/`setVisible`/... naming vs codestyle "no set..." rule
  (rename via `rename-symbol`, or document an exception), then make
  `check_style.d` flag `get*`/`set*` names
