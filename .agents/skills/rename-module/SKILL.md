---
name: rename-module
description: >-
  Rename or move a D module (including changing package depth such as
  a.b.util to a.b.internal.util), updating module declarations, imports,
  qualified references, .d file paths, and meson.build entries.
---

# Rename Module (`rename-module`)

This skill renames or moves a D module (`OldModule` -> `NewModule`) across
the repository, handling dotted module paths, `.d` file relocation, and
`meson.build` source lists.

## Core Script

```bash
rdmd .agents/skills/rename-module/scripts/rename_module.d [options] \
  <OldModule> <NewModule>
```

By default, the script runs in **dry-run** mode and reports:
- The `.d` file move (`<src>.d` -> `<dst>.d`, or `package.d`)
- All `module`, `import`, and qualified references across `.d` files
- Matching entries in `meson.build` / `yguilib/meson.build`

## Standard Workflow

### 1. Preview Changes (Dry-Run)
```bash
rdmd .agents/skills/rename-module/scripts/rename_module.d \
  yguilib.events.keyboard yguilib.events.internal.keyboard
```

Include Markdown docs (e.g. `ARCHITECTURE.md`) in the preview:
```bash
rdmd .agents/skills/rename-module/scripts/rename_module.d \
  --include-docs yguilib.events.keyboard yguilib.events.internal.keyboard
```

### 2. Review Architectural & Visibility Impact
- **Encapsulation / Boundaries**: Moving a module into `internal` or across
  packages may affect `package` visibility or `yguilib` independence.
- **`ARCHITECTURE.md`**: Per `AGENTS.md`, update `ARCHITECTURE.md` if the
  directory structure or module topology changed.
- **`package.d` re-exports**: If a parent `package.d` publicly imports the
  moved module, verify its `public import` remains valid.

### 3. Apply and Verify
```bash
rdmd .agents/skills/rename-module/scripts/rename_module.d \
  --apply --include-docs \
  yguilib.events.keyboard yguilib.events.internal.keyboard

rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
ninja -C _build && meson test -C _build
```

## CLI Options Reference

- `-a, --apply`: Apply edits, update `meson.build`, and move the `.d` file.
- `--no-move`: Update `module`/`import`/code only without moving the file or
  editing `meson.build`.
- `--as-package`: Map `NewModule` to `<path>/package.d`.
- `--include-docs`: Also scan and rename in `.md` files.
- `--include-skills`: Also scan `.agents/skills/` files.
- `--skip-comments`: Do not replace inside comments.
- `--skip-strings`: Do not replace inside string/char literals.
- `--json`: Output results and move plan in JSON format.
- `-h, --help`: Display help and options.
