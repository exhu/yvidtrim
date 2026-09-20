---
name: check-line-length
description: >-
  Check line-length violations on git diff additions for modified or staged
  files, or scan entire files directly on disk. Use this skill when verifying
  that code changes adhere to the 80-character (or specified) line length limit.
---

# Git Diff & Full File Line Length Checker

This skill provides automated line-length verification for newly added or
modified code lines directly from git diffs, as well as full file scans on disk
to replace manual shell pipelines (such as `awk 'length > 80 ...'`).

## Core Script

The checker is implemented as a standalone D script using Phobos and can be
executed directly using `rdmd`:

```bash
rdmd .agents/skills/check-line-length/scripts/check_line_length.d \
  [options] [target/file...] [max-width]
```

## Features

- **Direct git diff integration**: Runs `git diff -U0` automatically or reads
  from standard input if piped.
- **Full file scanning**: Scans entire files on disk using `-f` / `--file`, or
  automatically for untracked files, replacing `awk 'length > 80'`.
- **Accurate line tracking**: Parses unified diff hunk headers
  (`@@ -a,b +c,d @@`) to report the exact line numbers in the target files.
- **Tab stop expansion**: Converts tab characters (`\t`) to visual column stops
  (default: 4 columns).
- **Human-readable violation output**:
  `filePath:line: [length/limit] line content`
- **Automation-friendly exit codes**: Returns exit code `1` if any line exceeds
  the limit, or `0` if all checked lines are compliant.

## CLI Usage & Examples

### 1. Check all unstaged modified files against 80 columns:
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

### 4. Check with a custom column limit (e.g. 100 columns):
```bash
rdmd .agents/skills/check-line-length/scripts/check_line_length.d \
  -f yguilib/source/yguilib/uisystem.d 100
# or using flag:
rdmd .agents/skills/check-line-length/scripts/check_line_length.d \
  -w 100 yguilib/source/yguilib/uisystem.d
```

### 5. Check against a specific commit or range:
```bash
rdmd .agents/skills/check-line-length/scripts/check_line_length.d \
  HEAD~1 yguilib/source/yguilib/uisystem.d
```

### 6. Check staged changes:
```bash
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
- `-t, --tab-width`: Tab stop width in columns (default: 4).
- `--staged, --cached`: Inspect staged changes instead of unstaged changes.
- `--stdin`: Force reading diff or raw lines from standard input.
- `-h, --help`: Display help and options.
