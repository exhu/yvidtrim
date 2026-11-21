# Phase 1: Code Style Rules & Skills Updates for `package.d` and `rename-module`

Update `codestyle.md` and the D helper scripts / documentation in
`.agents/skills/` to forbid `public import` re-exports, allow multi-module
packages without `package.d`, enforce that `yguilib` never imports `guidemo`,
and support moving modules from `source/` into `yguilib/source/`.

## Rules & Conventions
- Adhere to `codestyle.md`: 2-space indent, LF, max 80 chars/line, opening `{`
  on same line.
- Keep Markdown files within 80 characters per line.

## Tasks

### 1. Update `codestyle.md`
- In Section 5 (`## 5. D Modules, Architecture & Assets`), replace the
  `No umbrella root package.d` and `Subsystem facades` bullets with:
  - **No umbrella root `package.d`:** Consumers must import subsystems or
    modules explicitly (e.g., `import yguilib.render;`,
    `import yguilib.controls.scrollbars;`).
  - **No `public import` re-exports:** Never use `public import` (in
    `package.d` or any other module) to re-export symbols from other modules.
  - **Package directories & `package.d`:** Keep a single-module subsystem as a
    single `.d` file rather than `<pkg>/package.d` (unless it encapsulates an
    `internal/` directory). Multi-module packages (e.g., `yguilib.controls`) do
    not require `package.d`; only create `<pkg>/package.d` when `<pkg>` itself
    defines shared top-level types or functions for that subsystem.

### 2. Update `.agents/skills/check-boundaries/`
- In `.agents/skills/check-boundaries/scripts/check_boundaries.d`:
  - Replace `BoundaryViolationType.missingDomainFacade` with
    `BoundaryViolationType.publicImportReexport`.
  - In `checkYguilibIndependence`: check for both `"yvidtrim"` and `"guidemo"`
    in D `import` lines and C `#include` lines inside `yguilib/`, reporting a
    `yguilibIndependence` violation if either is found.
  - Add `checkPublicImportReexports(string filePath, string content, ref
    BoundaryViolation[] violations)`:
    - For `.d` files, scan non-comment lines with
      `ctRegex!(r"^\s*public\s+import\b")`.
    - When matched, append a `BoundaryViolation` with
      `BoundaryViolationType.publicImportReexport` and message:
      `"Public import re-exports are prohibited; import modules explicitly."`.
    - Call `checkPublicImportReexports` in the main file scan loop for `.d`
      files.
  - In `checkDomainFacades`:
    - Remove the `if (moduleCount > 1 && !hasPackageD)` block so multi-module
      packages without `package.d` (such as `yguilib/source/yguilib/controls`)
      are allowed.
    - Keep the `if (moduleCount == 0 && hasPackageD && !hasInternalDir)` check
      (`BoundaryViolationType.singleModulePackageDir`).
- In `.agents/skills/check-boundaries/SKILL.md`:
  - Update the `Boundaries Enforced` list to reflect:
    1. `yguilib` Independence (`yguilib/` never imports `yvidtrim` or
       `guidemo`).
    2. Internal Encapsulation (no `public` in `internal/`).
    3. No Umbrella Root Imports & No `public import` Re-exports.
    4. Package Directory Rule (no single-module `package.d` directories without
       `internal/`; multi-module packages do not require `package.d`).
    5. Private C Wrapper Abstraction.

### 3. Update `.agents/skills/check-codestyle/`
- In `.agents/skills/check-codestyle/scripts/check_style.d`:
  - Add `auto publicImportRe = ctRegex!(r"^\s*public\s+import\b");` in
    `checkFileContent`.
  - Under `if (isD)`, when `checkThisLine` is true and
    `!matchFirst(rawLine, publicImportRe).empty`, record an `IssueLevel.error`:
    `"Public import re-exports are not allowed; import modules explicitly."`.
- In `.agents/skills/check-codestyle/SKILL.md`:
  - Add item 11 under `## Checks Enforced`:
    `11. **No Public Import Re-exports (D)**: Errors when a D module uses`
    `public import to re-export another module.`

### 4. Update `.agents/skills/rename-module/`
- In `.agents/skills/rename-module/scripts/rename_module.d`:
  - In `resolveMovePlan`: determine the destination root from `newMod`:
    ```d
    string dstRoot = (newMod == "yguilib" || newMod.startsWith("yguilib."))
      ? "yguilib/"
      : "";
    ```
    and set `plan.dstFile = dstRoot ~ tail;` (keeping `plan.srcFile = f;`,
    `plan.mesonDir = r;`, `plan.srcRel = f[r.length .. $];`,
    `plan.dstRel = tail;`).
  - In `processMesonFile`: if `plan.srcFile` and `plan.dstFile` are in the
    same root (`plan.mesonDir == dstRoot`), replace `'plan.srcRel'` with
    `'plan.dstRel'`.
- In `.agents/skills/rename-module/SKILL.md`:
  - Under `### 2. Review Architectural & Visibility Impact`, replace the
    `**package.d re-exports**` bullet with:
    `- **No package.d re-exports**: Per codestyle.md, never add public import`
    `  re-exports in package.d; update consumers to import the moved module`
    `  directly.`

### 5. Update `.agents/skills/define-gui-widget/SKILL.md`
- Update line 86 from `(see source/guidemo/tabcontrol.d)` to
  `(see yguilib/source/yguilib/controls/tabcontrol.d)`.
- Update line 98 from `source/guidemo/hover_button_system.d` to
  `yguilib/source/yguilib/controls/hover_button_system.d`.

## Verification (Phase 1)
```bash
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d --all
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
ninja -C _build && meson test -C _build
```
