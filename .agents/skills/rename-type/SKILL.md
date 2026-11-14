---
name: rename-type
description: >-
  Safely rename a D or C type (class, struct, interface, enum, union, alias,
  typedef) across the project with word-boundary, comment, string, collision,
  and line-length checks.
---

# Rename Type (`rename-type`)

This skill renames a type identifier (`OldType` -> `NewType`) across D
(`.d`), C (`.c`, `.h`), and optionally Markdown (`.md`) files in the
repository using a lexer-aware D script.

## Core Script

```bash
rdmd .agents/skills/rename-type/scripts/rename_type.d [options] \
  <OldType> <NewType> [paths...]
```

By default, the script runs in **dry-run** mode (no files are modified) and
scans all git-tracked `.d`, `.c`, and `.h` files (excluding `.agents/skills/`).

## Standard Workflow

### 1. Preview Matches (Dry-Run)
Run without `--apply` first to inspect all matched occurrences, check for
name collisions with `NewType`, and see if any filenames match `OldType`:

```bash
rdmd .agents/skills/rename-type/scripts/rename_type.d OldType NewType
```

Include Markdown docs (such as `ARCHITECTURE.md`) in the preview if needed:

```bash
rdmd .agents/skills/rename-type/scripts/rename_type.d \
  --include-docs OldType NewType
```

### 2. Review Special Cases
Before applying:
- **Collisions**: If `NewType` already exists in code, resolve or choose a
  different name.
- **Filenames & Modules**: If `fileHints` lists files matching the
  `snake_case` name of `OldType`, decide whether the `.d`/`.c`/`.h` file,
  D `module` declaration, `import` paths, and `meson.build` entries should
  also be renamed.
- **C Wrapper Prefix Rules**: For public symbols in `yvidtrim-clibs/` or
  `yguilib/yguilib-clibs/`, preserve `<proj>_<libname>_` prefixes per
  `AGENTS.md`.
- **Strings / Comments**: Use `--skip-strings` or `--skip-comments` if string
  literals or comments should remain unchanged.

### 3. Apply the Rename
```bash
rdmd .agents/skills/rename-type/scripts/rename_type.d \
  --apply --include-docs OldType NewType
```

If `NewType` is longer than `OldType`, fix any lines flagged under
`Lines exceeding 80 chars after rename`.

### 4. Verify
Run the standard project checks after renaming:

```bash
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
ninja -C _build && meson test -C _build
```

## CLI Options Reference

- `-a, --apply`: Write changes in-place (default is dry-run).
- `--include-docs`: Also scan and rename in `.md` files.
- `--include-skills`: Also scan `.agents/skills/` files.
- `--skip-comments`: Do not replace occurrences inside comments.
- `--skip-strings`: Do not replace occurrences inside string/char literals.
- `--check-collision`: Warn if `NewType` already exists (default: `true`).
- `--json`: Output matches and warnings in JSON format.
- `-h, --help`: Display help and options.
