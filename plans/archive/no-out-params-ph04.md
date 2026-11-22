# Phase 4: Documentation, Style Checker & Cleanup

Codify the rule in `codestyle.md`, add an automated `out`-parameter check to
`check_style.d`, update `check-codestyle/SKILL.md`, remove the completed item
from `TODO.md`, and run full verification.

## Files & Changes

### 1. `codestyle.md`
In Section 2 ("D Naming & Function Signatures"), add a bullet
**Return values vs `out`/`ref` parameters**:
- Do not use `out` parameters in D functions, methods, or constructors.
- Do not use `ref` parameters to return results or output flags.
- For optional single-value results, return `std.typecons.Nullable!T`.
- For multiple results, return a named `struct` (or `class` when reference
  semantics are needed).
- Permitted `ref` uses:
  - In-place mutation of an existing state, context, cache, or handle
    (e.g., `ref WidgetSystemContext`, `ref ModelTracker!M`,
    `stopTimer(ref TimerId)`).
  - Hot-path reusable buffers (`ref SmallBuffer`, `ref ReusableArray`,
    `ref Appender`).
  - Fluent struct builders (`ref WidgetBuilder`) and large input parameter
    structs (`in`, `const ref`, or `ref`).

Keep all lines <= 80 characters.

### 2. `.agents/skills/check-codestyle/scripts/check_style.d`
- Refactor `inspectParamList` to return a `ParamListInfo` struct:
  ```d
  struct ParamListInfo {
    bool hasDefault;
    bool hasOutParam;
    size_t paramCount;
  }
  ```
  (Also refactor `extractParenContent` if it uses `ref`/`out size_t endIdx`
  to return a `ParenContentResult { string content; size_t endIdx; }` struct.)
- Detect `out` parameters in each comma-separated parameter inside
  `inspectParamList` (strip leading parameter storage classes / whitespace and
  check for standalone `out` keyword, avoiding false positives on `inout` or
  identifiers like `outBuf`).
- Emit `IssueLevel.error` in both constructor and function/method declaration
  checks when `checkThisLine && !isClibBinding && info.hasOutParam`:
  - Message: `"Use a returned struct or Nullable!T instead of 'out' parameters."`
- Update the header doc comment in `check_style.d`.

### 3. `.agents/skills/check-codestyle/SKILL.md`
- Add check #12 **No `out` Parameters (D)** to the "Checks Enforced" list.

### 4. `TODO.md`
- Remove the completed first item:
  `- codestyle: a lot of places in code use ref/out parameters...`

## Rules & Verification
- Follow `codestyle.md` (<= 80 chars/line, 2-space indent, opening `{` on same
  line).
- Run full verification suite:
  ```bash
  ninja -C _build && meson test -C _build
  rdmd .agents/skills/check-codestyle/scripts/check_style.d --all
  rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
  rdmd .agents/skills/check-line-length/scripts/check_line_length.d
  ```
- Confirm zero `out` parameters remain in D sources under `source/`,
  `yguilib/source/`, and `yguilib/examples/`.
