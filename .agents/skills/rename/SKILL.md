---
name: rename
description: >-
  Safely rename D or C types (class, struct, interface, enum, alias, typedef)
  and symbols (variable, function, method, field, property, constant, enum
  member), or rename/move D modules, updating imports, file paths, and
  meson.build. Use for any project-wide or scoped rename or module move.
---

# Rename (`rename`)

One lexer-aware D script with three modes that share comment/string handling,
match reporting, and line-length checks.

```bash
rdmd .agents/skills/rename/scripts/rename.d <mode> [options] <Old> <New>
```

| Mode     | Renames                                  | Match kinds           |
|----------|------------------------------------------|-----------------------|
| `type`   | `PascalCase` types                       | `code`                |
| `symbol` | variables, functions, members, constants | `member` `call` `bare`|
| `module` | dotted D module paths and their files    | `code` `meson`        |

All modes also report `comment`, `string`, and `doc` matches.

Every mode is a **dry run** unless `--apply` is passed. Scans cover
git-tracked files, excluding `.agents/skills/`.

## Standard Workflow

1. Preview without `--apply`; add `--include-docs` to cover Markdown such as
   `ARCHITECTURE.md`.
2. Review the warnings (see each mode below). Use `--skip-strings` or
   `--skip-comments` if those should stay unchanged.
3. Re-run with `--apply`, then fix lines flagged under
   `Lines exceeding 80 chars after rename`.
4. Verify:
   ```bash
   rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks
   ```

If modules were added, moved, or data flow changed, update `ARCHITECTURE.md`
(keep it under 250 lines).

Matching is by identifier text, not by semantics: unrelated symbols with the
same name match too, so always read the preview. A literal suffix counts as an
identifier (renaming `f` also matches the `f` in `1.0f`).

## `type` Mode

```bash
rdmd .agents/skills/rename/scripts/rename.d type OldType NewType [paths...]
rdmd .agents/skills/rename/scripts/rename.d type \
  --apply --include-docs OldType NewType
```

- **Collisions**: If `NewType` already exists in code, resolve or choose a
  different name.
- **Filenames & Modules**: If `fileHints` lists files matching the
  `snake_case` name of `OldType`, decide whether the file should move too (use
  `module` mode for D files).
- **C Wrapper Prefix Rules**: For public symbols in `yvidtrim-clibs/` or
  `yguilib/yguilib-clibs/`, preserve `<proj>_<libname>_` prefixes per
  `AGENTS.md`.

## `symbol` Mode

Narrow the scope as much as possible.

```bash
# Local variable or parameter: one file plus the function's line range
rdmd .agents/skills/rename/scripts/rename.d symbol \
  --lines 45-92 oldVar newVar source/yvidtrim/app.d

# Member: only files referencing Widget, only .field / ->field accesses
rdmd .agents/skills/rename/scripts/rename.d symbol \
  --owner Widget --member-only oldField newField

# Free function or module constant, limited to a directory
rdmd .agents/skills/rename/scripts/rename.d symbol \
  oldHelper newHelper source/yvidtrim/
```

Pass multiple pairs or searches in one call instead of shell loops:

```bash
rdmd .agents/skills/rename/scripts/rename.d symbol \
  --owner Widget --member-only --find setCaption --find setVisible

rdmd .agents/skills/rename/scripts/rename.d symbol \
  --summary --map getStats=queueStats --map setStatsEnabled=statsEnabled \
  yguilib source
```

## `module` Mode

Reports the `.d` file move (`<src>.d` -> `<dst>.d`, or `package.d`), all
`module`, `import`, and qualified references, and matching `meson.build` /
`yguilib/meson.build` entries. It takes no path arguments.

```bash
rdmd .agents/skills/rename/scripts/rename.d module \
  --include-docs yguilib.events.keyboard yguilib.events.internal.keyboard
rdmd .agents/skills/rename/scripts/rename.d module \
  --apply --include-docs \
  yguilib.events.keyboard yguilib.events.internal.keyboard
```

- **Encapsulation**: Moving a module into `internal` or across packages may
  affect `package` visibility or `yguilib` independence.
- **No `package.d` re-exports**: Never add `public import` re-exports; update
  consumers to import the moved module directly.

## Options

All modes:
- `-a, --apply`: Write changes in-place (`module` also moves the file).
- `--include-docs`: Also scan and rename in `.md` files.
- `--include-skills`: Also scan `.agents/skills/` files.
- `--skip-comments`, `--skip-strings`: Leave those occurrences unchanged.
- `--json`: Output matches and warnings in JSON format.
- `-h, --help`: Display the mode's options.

`type` and `symbol`:
- `--check-collision`: Warn if the new name already exists (default: `true`).

`symbol` only:
- `--lines <start>-<end>`: Restrict to a 1-based line range.
- `--owner <Type>`: Restrict to files referencing `<Type>` in code.
- `--member-only`: Only replace `.symbol` or `->symbol` accesses.
- `--map <Old>=<New>`: Rename pair in batch mode (repeatable).
- `--batch <file>`: Read `<Old> <New>` or `<Old>=<New>` pairs from a file.
- `--find <Symbol>`: Find occurrences without renaming (repeatable).
- `--summary`: Print counts and warnings only (omit per-match lines).

`module` only:
- `--no-move`: Update code only; do not move the file or edit `meson.build`.
- `--as-package`: Map `NewModule` to `<path>/package.d`.
