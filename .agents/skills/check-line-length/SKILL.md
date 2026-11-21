---
name: check-line-length
description: >-
  Check line-length violations on git diff additions for modified, staged, or
  renamed files, or scan entire files on disk (including optional max-lines
  count checks). Use this skill when verifying that code or docs adhere to the
  80-character line width or total line-count limits.
---

# Git Diff & Full File Line Length Checker

This skill provides automated line-length and optional total line-count
verification for modified, staged, and renamed files as well as full file
scans on disk, replacing manual shell pipelines (`awk 'length > 80'`, `wc -l`).

## Core Script

The checker is implemented as a standalone D script using Phobos and executed
directly with `rdmd`:

```bash
rdmd .agents/skills/check-line-length/scripts/check_line_length.d \
  [options] [target/file...] [max-width]
```

## Features

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

## CLI Usage & Examples

### 1. Check all unstaged, staged, and renamed changes against 80 columns:
```bash
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
```

### 2. Check a specific modified file (git diff additions only):
```bash
rdmd .agents/skills/check-line-length/scripts/check_line_length.d \
  yguilib/source/yguilib/uisystem.d
```

### 3. Check an entire file on disk (all lines, replacing awk):
```bash
rdmd .agents/skills/check-line-length/scripts/check_line_length.d \
  -f .agents/skills/check-line-length/SKILL.md
```
*(Note: Untracked files on disk default to full file scan automatically).*

### 4. Check both 80-char width and total line count (replacing wc -l):
```bash
rdmd .agents/skills/check-line-length/scripts/check_line_length.d \
  -f --max-lines 249 ARCHITECTURE.md
```

### 5. Check with a custom column limit (e.g. 100 columns):
```bash
rdmd .agents/skills/check-line-length/scripts/check_line_length.d \
  -f yguilib/source/yguilib/uisystem.d 100
# or using flag:
rdmd .agents/skills/check-line-length/scripts/check_line_length.d \
  -w 100 yguilib/source/yguilib/uisystem.d
```

### 6. Check against a specific commit or staged changes only:
```bash
rdmd .agents/skills/check-line-length/scripts/check_line_length.d \
  HEAD~1 yguilib/source/yguilib/uisystem.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d --staged
```

### 7. Pipe git diff or raw file output directly:
```bash
git diff -U0 HEAD~2 | \
  rdmd .agents/skills/check-line-length/scripts/check_line_length.d

# Or check raw text from stdin:
cat somefile.txt | \
  rdmd .agents/skills/check-line-length/scripts/check_line_length.d -f
```

## Options

- `-f, --file`: Check entire file(s) on disk instead of git diff additions.
- `-w, --max-width`: Maximum visual column width (default: 80).
- `-m, --max-lines`: Maximum total line count per file (default: 0 = unlimited).
- `-t, --tab-width`: Tab stop width in columns (default: 4).
- `--staged, --cached`: Inspect staged changes only.
- `--stdin`: Force reading diff or raw lines from standard input.
- `-h, --help`: Display help and options.
