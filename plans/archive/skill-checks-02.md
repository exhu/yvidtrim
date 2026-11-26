# Phase 2: Test Target Coverage

Overview: [skill-checks.md](skill-checks.md). Read `AGENTS.md` and
`codestyle.md` first. Phase 1 added rules 7-8 and the
`codeWithoutUnittests` helper to `check_boundaries.d`.

## Target Files

- `.agents/skills/check-boundaries/scripts/check_boundaries.d`
- `.agents/skills/check-boundaries/SKILL.md`
- `.agents/skills/build-and-test/SKILL.md` ("Adding Meson Unit Test
  Targets" section: point to the new rules)

## Context

`AGENTS.md`: every module with `unittest` blocks needs a Meson test target
using the shared `test_main.d`; no per-module `version (unittest) void
main()`. Test executables are in `meson.build` (`yvidtrim_test`,
`guidemo_test`, `hover_button_test`) and `yguilib/meson.build`
(`yguilib_test`, `helloworld_test`), all with `d_unittest : true`. Paths in
`files(...)` are relative to the `meson.build` that lists them.

## Steps

1. **Rule 9 - unittest modules are built by a test** (`checkTestCoverage`):
   - Collect quoted `'*.d'` paths from `meson.build` and
     `yguilib/meson.build`, resolved relative to each file's directory.
   - Error for every `.d` file under `yguilib/source`, `yguilib/examples`,
     `yguilib/benchmarks`, `source/` that has a top-level or nested
     `unittest` block but is not in that set.
   - Keep it a heuristic (string match, no Meson evaluation) and say so in
     `SKILL.md`. Exclude `.agents/` and `subprojects/`.
   - Optional: warn if a `meson.build` lists a `.d` path that does not
     exist on disk.

2. **Rule 10 - no ad-hoc test mains** (`checkNoUnittestMain`):
   error when a `version (unittest)` block contains a `main(` declaration
   in any file other than `*/test_main.d`. Match `version(unittest)` with
   or without the space.

3. Wire both into `main`; document as items 9-10 in `SKILL.md`.

## Acceptance

```bash
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
# -> exit 0 on the current tree (baseline: all unittest modules listed)
```

Negative tests (do not commit): create an untracked
`yguilib/source/yguilib/probe_cov.d` with a `unittest {}` (expect rule 9
error), and add `version (unittest) void main() {}` to it (expect rule 10
error). Delete the file.

Run the full verification and update the overview status table.
