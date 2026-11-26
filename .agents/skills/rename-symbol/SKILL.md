---
name: rename-symbol
description: >-
  Safely rename a D or C symbol (variable, function, method, field, property,
  constant, or enum member) with line-range, owner-type, member-access,
  collision, and line-length checks.
---

# Rename Symbol (`rename-symbol`)

This skill renames non-type identifiers (`OldSymbol` -> `NewSymbol`) such as
variables, parameters, functions, methods, fields, `@property` accessors,
constants, and enum members across `.d`, `.c`, `.h`, and optional `.md` files.

Use `rename-type` for `PascalCase` types and `rename-module` for dotted D
module paths.

## Core Script

```bash
rdmd .agents/skills/rename-symbol/scripts/rename_symbol.d [options] \
  <OldSymbol> <NewSymbol> [paths...]
```

By default, the script runs in **dry-run** mode and categorizes each match as
`member` (`.sym` / `->sym`), `call` (`sym(` / `sym!`), `bare`, `comment`,
`string`, or `doc`.

## Common Workflows

### 1. Local Variable or Parameter (Single File + Line Range)
Scope the rename to the enclosing function's lines to avoid touching other
functions:

```bash
rdmd .agents/skills/rename-symbol/scripts/rename_symbol.d \
  --lines 45-92 oldVar newVar source/yvidtrim/app.d
```

### 2. Method, Field, Property, or Enum Member (Owner-Scoped)
Restrict scanning to files referencing the owning type, or to `.member`
accesses:

```bash
# Preview across files referencing Widget
rdmd .agents/skills/rename-symbol/scripts/rename_symbol.d \
  --owner Widget oldField newField

# Only replace .oldField / ->oldField accesses
rdmd .agents/skills/rename-symbol/scripts/rename_symbol.d \
  --owner Widget --member-only oldField newField
```

### 3. Free Function or Module Constant
Preview across the repo (or specific directories), check collisions, then
apply:

```bash
rdmd .agents/skills/rename-symbol/scripts/rename_symbol.d \
  oldHelper newHelper source/yvidtrim/
```

### 4. Apply and Verify
```bash
rdmd .agents/skills/rename-symbol/scripts/rename_symbol.d \
  --apply [options] OldSymbol NewSymbol [paths...]

rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks
```

If modules were added, moved, or data flow changed, update `ARCHITECTURE.md`
(keep it under 250 lines).

### 5. Batch Renames & Read-Only Discovery
Avoid shell `for` loops or chained `&&` calls; pass multiple pairs directly:

```bash
# Find member usages without a dummy target
rdmd .agents/skills/rename-symbol/scripts/rename_symbol.d \
  --owner Widget --member-only --find setCaption --find setVisible

# Dry-run or apply multiple renames with concise warnings
rdmd .agents/skills/rename-symbol/scripts/rename_symbol.d \
  --summary --map getStats=queueStats --map setStatsEnabled=statsEnabled \
  yguilib source
```

## CLI Options Reference

- `-a, --apply`: Write changes in-place (default is dry-run).
- `--lines <start>-<end>`: Restrict to 1-based line range.
- `--owner <Type>`: Restrict to files referencing `<Type>` in code.
- `--member-only`: Only replace `.symbol` or `->symbol` accesses.
- `--map <Old>=<New>`: Rename pair in batch mode (repeatable).
- `--batch <file>`: Read `<Old> <New>` or `<Old>=<New>` pairs from file.
- `--find <Symbol>`: Find occurrences without renaming (repeatable).
- `--summary`: Print counts and warnings only (omit per-match lines).
- `--include-docs`: Also scan and rename in `.md` files.
- `--include-skills`: Also scan `.agents/skills/` files.
- `--skip-comments`: Do not replace inside comments.
- `--skip-strings`: Do not replace inside string/char literals.
- `--check-collision`: Warn if `NewSymbol` already exists (default: `true`).
- `--json`: Output matches and warnings in JSON format.
- `-h, --help`: Display help and options.
