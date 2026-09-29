---
name: check-codestyle
description: >-
  Verify and enforce formatting, brace placement, indentation, visibility
  sections, file naming, and import scoping rules from codestyle.md for D and C
  code.
---

# Code Style Checker

This skill provides static analysis to enforce the styling and syntax
conventions specified in
[codestyle.md](file:///home/yur/agy-projects/yvidtrim/codestyle.md).

## Core Script

The checker is implemented in D and executed via `rdmd`:

```bash
rdmd .agents/skills/check-codestyle/scripts/check_style.d [options] [files...]
```

## Checks Enforced

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

## CLI Usage

### Check Unstaged Changes (Git Diff Additions)
```bash
rdmd .agents/skills/check-codestyle/scripts/check_style.d
```

### Check Staged Changes
```bash
rdmd .agents/skills/check-codestyle/scripts/check_style.d --staged
```

### Scan Specific Files or Directories
```bash
rdmd .agents/skills/check-codestyle/scripts/check_style.d \
  source/yvidtrim/app.d yguilib/source/yguilib/
```

### Scan the Entire Project
```bash
rdmd .agents/skills/check-codestyle/scripts/check_style.d --all
```

## Options

- `--diff`: Check unstaged git diff additions (default).
- `--staged`, `--cached`: Check staged git diff additions.
- `--all`: Scan all tracked source files on disk.
- `--max-func-lines <N>`: Maximum allowable function length (default: 50).
- `-h`, `--help`: Display help and options.
