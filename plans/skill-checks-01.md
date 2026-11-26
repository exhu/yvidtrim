# Phase 1: GLES & Controller Boundaries

Overview: [skill-checks.md](skill-checks.md). Read `AGENTS.md` and
`codestyle.md` first.

## Target Files

- `.agents/skills/check-boundaries/scripts/check_boundaries.d`
- `.agents/skills/check-boundaries/SKILL.md`

## Context

`check_boundaries.d` has one `void checkXxx(..., ref BoundaryViolation[]
violations)` function per rule, called from `main` (lines ~267-330).
Rules 1-6 are documented in `SKILL.md` "Boundaries Enforced".

## Steps

1. **Unittest stripper helper**: add
   `string codeWithoutUnittests(string source)` returning the source with
   every `unittest { ... }` block replaced by blank lines (keep the line
   count so reported line numbers stay correct). Track braces; ignore braces
   inside `//`, `/* */`, `/+ +/` comments and string/char literals.
   Add a `unittest` for it inside the script (nested braces, a `}` in a
   string, and a comment).

2. **Rule 7 - GLES only via glad2.gles2** (`checkGlesImports`):
   scan `.d` files under `yguilib/source`, `source`, `yguilib/examples`,
   `yguilib/benchmarks`. Error on any `import` of a module whose name
   starts with `glad`, `bindbc.opengl`, `derelict.opengl`, or `gl.` other
   than exactly `glad2.gles2`. Also error on D files that `import` a module
   resolving to a `.c`/`.h` file (ImportC); in practice flag
   `import <name>;` where `<name>.c` or `<name>.h` exists next to the file
   or in a `-clibs` dir.

3. **Rule 8 - Controller isolation** (`checkControllerIsolation`):
   files whose basename matches `*controller*.d` under `source/` and
   `yguilib/examples/`, after `codeWithoutUnittests`:
   - error on `import yguilib.app` or `import yguilib.window`;
   - error on `new <Ident>View(` (controllers never create their View).
   Do not apply to `yguilib/source/yguilib/` (library controller
   infrastructure, e.g. `internal/uisystem_controller.d`).

4. Call both from `main`, document them as items 7 and 8 in `SKILL.md`.

## Acceptance

```bash
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
# -> "All architectural boundaries ... satisfied." (exit 0)
```

Negative test (do not commit): temporarily add
`import yguilib.app : App;` at the top level of
`source/guidemo/pages/button_controller.d` and `import glad2.gles31;` to
any yguilib module; the checker must report both and exit 1. Revert.

Then run the full verification from the overview's shared constraints and
update the overview status table.
