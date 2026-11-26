# Phase 4: Aggregate `--checks` & Skill Doc Cleanup

Overview: [skill-checks.md](skill-checks.md). Read `AGENTS.md` first.
Phases 1-3 added rules 7-10 to `check_boundaries.d` and 13-14 to
`check_style.d`.

## Target Files

- `.agents/skills/build-and-test/scripts/run_verify.d`
- `.agents/skills/build-and-test/SKILL.md`
- `SKILL.md` of: `define-gui-widget`, `refactor-widget`, `rename-module`,
  `rename-symbol`, `rename-type`, `wrap-c-lib`

## Steps

1. **`--checks` option in `run_verify.d`**: before building, run in order
   (each via `rdmd`, each under `timeout 120`, stop at first error exit):
   1. `check-line-length/scripts/check_line_length.d`
   2. `check-codestyle/scripts/check_style.d`
   3. `check-null-safety/scripts/check_null_safety.d`
   4. `check-boundaries/scripts/check_boundaries.d`
   5. `manage-assets/scripts/manage_assets.d --check`

   Then continue with the normal build + timeout-wrapped tests. Combine
   with `--build-only` / `--test-only` as today. Add `--checks-only` to
   skip build and tests. Print a one-line summary per checker.

2. **Replace duplicated verification blocks**: in each listed `SKILL.md`,
   replace the multi-command "Verify"/"Standard Verification Suite" block
   with
   `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`,
   keeping only skill-specific extra steps (e.g. `define_gui_widget.d
   --audit`, `refactor_widget.d -a`).

3. **`ARCHITECTURE.md` reminders**: in `define-gui-widget`,
   `refactor-widget`, `rename-symbol`, and `rename-type`, add one line:
   "If modules were added, moved, or data flow changed, update
   `ARCHITECTURE.md` (keep it under 250 lines)." (`rename-module` and
   `wrap-c-lib` already have it.)

4. Document `--checks` / `--checks-only` in `build-and-test/SKILL.md`.

## Acceptance

```bash
rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks
# -> all checkers pass, build succeeds, all tests pass
rdmd .agents/skills/check-line-length/scripts/check_line_length.d \
  -f .agents/skills/*/SKILL.md
```

Update the overview status table, then propose the TODO.md items listed
in the overview to the user (do not add them unasked).
