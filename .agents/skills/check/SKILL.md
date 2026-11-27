---
name: check
description: >-
  Static checks for yvidtrim and yguilib: 80-column and total line limits,
  codestyle.md rules for D and C, null-safety contracts, and architectural
  boundaries (yguilib independence, encapsulation, controller isolation,
  ARCHITECTURE.md size, Meson unittest coverage). Use to verify code or docs
  before finishing a change.
---

# Static Checks (`check`)

Four checkers plus a driver that runs them in order. The driver also runs the
`manage-assets` check and, on request, the `gui-widget` audit.

```bash
# line-length, codestyle, null-safety, boundaries, assets
rdmd .agents/skills/check/scripts/run_checks.d

rdmd .agents/skills/check/scripts/run_checks.d --only codestyle,boundaries
rdmd .agents/skills/check/scripts/run_checks.d --skip line-length --keep-going
```

To run the checks and then build and test, use
`rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`.

## Driver Options

- `--only <names>`: Run only these checks (comma list or repeated).
- `--skip <names>`: Skip these checks (comma list or repeated).
- `--style-all`: Pass `--all` to `check_style.d` (default: diff additions).
- `--audit-widgets`: Also run `gui_widget.d --audit` (name: `gui-widget`).
- `--keep-going`: Run every check instead of stopping at the first failure.

Each check runs under `timeout 120`. Run a script below directly when you need
its own arguments (paths, `--staged`, and so on).

---

## Line Length (`check_line_length.d`)

```bash
rdmd .agents/skills/check/scripts/check_line_length.d \
  [options] [target/file...] [max-width]
```

- **Combined default git check**: Running with no arguments inspects unstaged
  additions (`git diff -U0`), staged additions (`git diff -U0 --cached`), and
  full scans of staged renamed (`git mv`) files in one call.
- **Full file scanning & line-count cap**: Scans entire files on disk using
  `-f` / `--file` (or automatically for untracked files), and optionally
  enforces total file line limits with `-m` / `--max-lines` (replacing `wc -l`).
- **Accurate line tracking**: Parses unified diff hunk headers
  (`@@ -a,b +c,d @@`) to report exact line numbers in target files.
- **Tab stop expansion**: Converts tab characters (`\t`) to visual column stops
  (default: 4 columns).
- **Clear pass/fail output**: Prints `Line length check passed (0 violations).`
  on exit code `0`, or `filePath:line: [length/limit] line content` on exit
  code `1` (no `echo` wrappers needed).

### Examples

#### 1. Check all unstaged, staged, and renamed changes against 80 columns:
```bash
rdmd .agents/skills/check/scripts/check_line_length.d
```

#### 2. Check a specific modified file (git diff additions only):
```bash
rdmd .agents/skills/check/scripts/check_line_length.d \
  yguilib/source/yguilib/uisystem.d
```

#### 3. Check an entire file on disk (all lines, replacing awk):
```bash
rdmd .agents/skills/check/scripts/check_line_length.d \
  -f .agents/skills/check/SKILL.md
```
*(Note: Untracked files on disk default to full file scan automatically).*

#### 4. Check both 80-char width and total line count (replacing wc -l):
```bash
rdmd .agents/skills/check/scripts/check_line_length.d \
  -f --max-lines 249 ARCHITECTURE.md
```

#### 5. Check with a custom column limit (e.g. 100 columns):
```bash
rdmd .agents/skills/check/scripts/check_line_length.d \
  -f yguilib/source/yguilib/uisystem.d 100
# or using flag:
rdmd .agents/skills/check/scripts/check_line_length.d \
  -w 100 yguilib/source/yguilib/uisystem.d
```

#### 6. Check against a specific commit or staged changes only:
```bash
rdmd .agents/skills/check/scripts/check_line_length.d \
  HEAD~1 yguilib/source/yguilib/uisystem.d
rdmd .agents/skills/check/scripts/check_line_length.d --staged
```

#### 7. Pipe git diff or raw file output directly:
```bash
git diff -U0 HEAD~2 | \
  rdmd .agents/skills/check/scripts/check_line_length.d

# Or check raw text from stdin:
cat somefile.txt | \
  rdmd .agents/skills/check/scripts/check_line_length.d -f
```

### Options

- `-f, --file`: Check entire file(s) on disk instead of git diff additions.
- `-w, --max-width`: Maximum visual column width (default: 80).
- `-m, --max-lines`: Maximum total line count per file (default: 0 = unlimited).
- `-t, --tab-width`: Tab stop width in columns (default: 4).
- `--staged, --cached`: Inspect staged changes only.
- `--stdin`: Force reading diff or raw lines from standard input.
- `-h, --help`: Display help and options.

---

## Code Style (`check_style.d`)

Enforces [codestyle.md](../../../codestyle.md).

```bash
rdmd .agents/skills/check/scripts/check_style.d [options] [files...]
```

### Checks Enforced
1. **Brace Placement**: Verifies that opening `{` is on the same line as the
   declaration or control flow block (`struct`, `class`, `function`, `if`,
   `while`, etc.). Rejects opening braces placed on standalone newlines.
2. **Indentation**: Enforces 2-space indentation. Rejects literal tab (`\t`)
   characters and warns on non-multiple-of-2 indentation.
3. **File Naming**: Enforces all-lowercase source filenames (`.d`, `.c`, `.h`).
4. **Visibility Section Order (D)**: Enforces block-style declarations
   (`public:`, then `protected:`, then `private:`). Flags inline per-symbol
   visibility attributes such as `private void foo()` or `public int bar`.
5. **Scoped Import Auditing (D)**: Flags top-level module imports of heavy
   standard library packages (`std.algorithm`, `std.format`, `std.json`,
   `std.regex`) so they are scoped inside function or template bodies.
6. **Function Length**: Warns when function bodies exceed 50 lines.
7. **No Default Parameter Values (D)**: Errors when a D function, method, or
   constructor declaration uses default parameter values (`=`).
8. **No Overloaded Functions (D)**: Warns when the same function or method
   name is declared multiple times in the same scope (excluding `this`,
   `~this`, `op*` operators, `visit`, and conditional `version`/`static if`
   blocks).
9. **No Consecutive Capital Letters (D)**: Warns when D type or function names
   contain consecutive uppercase ASCII letters (e.g., `ID`, `makeGUID`,
   `colorRGB` instead of `Id`, `makeGuid`, `colorRgb`), excluding `clibs/`
   bindings.
10. **Constructor Constraints (D)**: Warns when a class/struct defines more
    than one non-`@disable` `this(...)` constructor or a constructor has more
    than 3 parameters.
11. **No Public Import Re-exports (D)**: Errors when a D module uses
    `public import` to re-export another module.
12. **No `out` Parameters (D)**: Errors when a D function, method, or
    constructor declaration uses `out` parameters (excluding `clibs/`
    bindings).
13. **handleEvent Falls Through to Super (D)**: Errors when an
    `override HandleResult handleEvent(...)` body does not call
    `super.handleEvent(`, so unhandled events (quit, redraw) are lost. The
    body is found by brace matching on the whole file, so diff mode checks
    every function that overlaps an added line. Skips
    `yguilib/source/yguilib/controller/` and
    `yguilib/source/yguilib/internal/`, which define the fallback.
14. **Timers Are Stopped (D)**: Warns when a class body calls `startTimer(`
    but never `stopTimer(`, so an animation timer may keep running when idle.
    Skips `unittest` blocks and the timer infrastructure files
    (`timercontrol.d`, `internal/timer_service.d`,
    `internal/uisystem_impl.d`, `controller/package.d`).
15. **No `get`/`set` Prefix (D)**: Warns when a declared D function or method
    name matches `^(get|set)[A-Z]` (excluding `clibs/` bindings); use a
    property pair or a verb (`codestyle.md` section 2).

### CLI Usage

#### Check Unstaged Changes (Git Diff Additions)
```bash
rdmd .agents/skills/check/scripts/check_style.d
```

#### Check Staged Changes
```bash
rdmd .agents/skills/check/scripts/check_style.d --staged
```

#### Scan Specific Files or Directories
```bash
rdmd .agents/skills/check/scripts/check_style.d \
  source/yvidtrim/app.d yguilib/source/yguilib/
```

#### Scan the Entire Project
```bash
rdmd .agents/skills/check/scripts/check_style.d --all
```

#### Check an Inline Snippet or Stdin (Rule Verification)
```bash
rdmd .agents/skills/check/scripts/check_style.d \
  --check-code "void setFoo(int v) {}"
```

### Options

- `--diff`: Check unstaged git diff additions (default).
- `--staged`, `--cached`: Check staged git diff additions.
- `--all`: Scan all tracked source files on disk.
- `--check-code <snippet>`: Check an inline D code snippet (no temp file).
- `--stdin`: Read D source code from stdin.
- `--max-func-lines <N>`: Maximum allowable function length (default: 50).
- `-h`, `--help`: Display help and options.

---

## Null Safety (`check_null_safety.d`)

Enforces the null handling conventions in
[codestyle.md](../../../codestyle.md).

```bash
rdmd .agents/skills/check/scripts/check_null_safety.d [options] [files...]
```

### Contracts Audited
1. **D Constructor Non-Null Assertions**:
   By default, reference types (classes and interfaces) and raw pointers passed
   into constructors cannot be null. Constructors accepting these types must
   include `assert(arg !is null)`, unless explicitly documented with
   `@nullable` or `allowed to be null`.
2. **D Class & Struct Invariants**:
   Recommends class/struct invariants with `assert(field !is null)` for
   persistent non-null fields rather than repetitive null checks throughout
   methods.
3. **C Wrapper NULL Documentation**:
   Functions declared in private C wrapper headers (`yvidtrim-clibs/*.h` and
   `yguilib/yguilib-clibs/*.h`) accepting or returning pointer types must have
   doc comments explicitly stating whether `NULL` is valid or undefined.

### CLI Usage

#### Audit All Project Files
```bash
rdmd .agents/skills/check/scripts/check_null_safety.d
```

#### Audit Specific Files
```bash
rdmd .agents/skills/check/scripts/check_null_safety.d \
  yguilib/source/yguilib/app.d yguilib/yguilib-clibs/yguilib_sdl3.h
```

### Options

- `-h`, `--help`: Display help and options.

---

## Boundaries (`check_boundaries.d`)

Enforces [codestyle.md](../../../codestyle.md) and
[AGENTS.md](../../../AGENTS.md).

```bash
rdmd .agents/skills/check/scripts/check_boundaries.d [options]
```

### Boundaries Enforced
1. **`yguilib` Independence**:
   Ensures that `yguilib/` (both D code and C wrapper code) never imports or
   depends on `yvidtrim` or `guidemo` (`source/yvidtrim`, `source/guidemo`,
   or `yvidtrim-clibs`).
2. **Internal Encapsulation**:
   Ensures files inside any `internal/` subdirectory do not declare `public:`
   sections or inline `public` declarations. Implementation details must be
   `package(<root_pkg>):` or `private:`.
3. **No Umbrella Root Imports & No `public import` Re-exports**:
   Verifies that top-level monolithic `package.d` files do not exist and no D
   module uses `public import` to re-export symbols from other modules.
4. **Package Directory Rule**:
   Ensures isolated single modules are not unnecessarily placed in standalone
   `package.d` directories unless encapsulating `internal/` modules;
   multi-module packages do not require `package.d`.
5. **Private C Wrapper Abstraction**:
   Ensures D code only imports wrapper modules under `clibs/` and does not
   bypass private C wrappers.
6. **`ARCHITECTURE.md` Size Limit**:
   Verifies that `ARCHITECTURE.md` remains under 250 lines per `AGENTS.md`.
7. **GLES via `glad2.gles2` Only**:
   In `yguilib/source`, `source`, `yguilib/examples`, and
   `yguilib/benchmarks`, D files may import GLES only as `glad2.gles2` (no
   `glad*`, `bindbc.opengl`, `derelict.opengl`, or `gl.*` modules). D files
   must also not import a C source or header, i.e. `import <name>;` where
   `<name>.c` or `<name>.h` sits next to the file or in a `*-clibs` directory.
8. **Controller Isolation**:
   Files named `*controller*.d` under `source/` and `yguilib/examples/` must
   not import `yguilib.app` or `yguilib.window`, and must not create their
   View with `new <Name>View(`. `unittest` blocks are ignored.
9. **Unittest Modules Built by a Meson Test**:
   Every `.d` file under `yguilib/source`, `yguilib/examples`,
   `yguilib/benchmarks`, or `source` that has a top-level or nested `unittest`
   block must appear as a quoted path in `meson.build` or
   `yguilib/meson.build`. This is a heuristic: it matches quoted `*.d` strings
   and does not evaluate Meson. A listed path that does not exist on disk is
   reported as a warning (exit 0).
10. **No Ad-hoc Test `main`**:
   A `version (unittest)` block (braced or single-line, spacing optional) must
   not declare or call `main(` in any `.d` file except `*/test_main.d`.
   Comments and string literals are ignored.

### CLI Usage

#### Check All Boundaries
```bash
rdmd .agents/skills/check/scripts/check_boundaries.d
```

### Options

- `-h`, `--help`: Display help and options.
