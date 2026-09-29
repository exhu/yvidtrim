---
name: inspect-tree
description: >-
  Inspect project directory trees to identify D modules with declared module
  names, C wrapper sources and headers, build configurations, and markdown
  documentation. Use this skill when exploring directories (such as
  source/guidemo/ or yguilib/) instead of raw find or shell pipelines.
---

# Project Tree & File Classifier (`inspect-tree`)

This skill provides fast, structured file and directory inspection
tailored for the `yvidtrim` and `yguilib` codebase. It categorizes files and
extracts metadata (e.g., declared D module names, package facades, internal
modules, C wrapper headers/tests, Meson build configs, and documentation
titles) to replace ad-hoc `find` and `ls` shell commands.

## Core Script

The inspector is implemented in D using Phobos and executed directly via `rdmd`:

```bash
rdmd .agents/skills/inspect-tree/scripts/inspect_tree.d [options] [path...]
```

## Features

- **D Module Detection**: Locates `.d` files and extracts their declared
  `module <name>;` statement. Identifies module roles:
  - `[package facade]`: Subsystem entry points (`package.d`).
  - `[internal]`: Hidden implementation modules (`internal/...`).
  - `[test]`: Unit test files (`*_test.d` or in `test/`).
  - `[module]`: Standard D modules.
- **C/C++ File Classification**: Identifies `.c`, `.h`, `.cpp`, `.hpp` files,
  distinguishing headers, sources, and wrapper tests (`*_test.c`).
- **Build Configuration Discovery**: Locates `meson.build`, `meson.options`,
  `subprojects/*.wrap`, and `dub.json` files with project context.
- **Documentation Indexing**: Finds `*.md`, `*.adoc`, and text documents,
  extracting top-level titles for quick context scanning.
- **Clean Filtering**: Ignores build outputs (`_build/`, `.dub/`, `.git/`,
  `.cache/`) by default.
- **Multiple Output Formats**: Supports categorized lists, summary tables,
  hierarchical paths, and structured JSON output.

## CLI Usage & Examples

### 1. Inspect a specific directory (e.g., `source/guidemo/`):
```bash
rdmd .agents/skills/inspect-tree/scripts/inspect_tree.d source/guidemo/
```

### 2. Find only D modules in a directory or whole project:
```bash
# In guidemo:
rdmd .agents/skills/inspect-tree/scripts/inspect_tree.d -d source/guidemo/

# Across the whole project:
rdmd .agents/skills/inspect-tree/scripts/inspect_tree.d -d
```

### 3. Identify all C wrapper sources, headers, and tests:
```bash
rdmd .agents/skills/inspect-tree/scripts/inspect_tree.d -c
```

### 4. Locate all build configuration files (Meson & Dub):
```bash
rdmd .agents/skills/inspect-tree/scripts/inspect_tree.d -b
```

### 5. Index documentation files and titles:
```bash
rdmd .agents/skills/inspect-tree/scripts/inspect_tree.d -m
```

### 6. View a project summary table:
```bash
rdmd .agents/skills/inspect-tree/scripts/inspect_tree.d -s
```

### 7. Output structured JSON for automation:
```bash
rdmd .agents/skills/inspect-tree/scripts/inspect_tree.d -j source/guidemo/
```

## Options Reference

- `-d, --d-modules`: Filter and list D source modules with module names.
- `-c, --c-files`: Filter and list C/C++ source and header files.
- `-b, --build-configs`: Filter build configs (`meson.build`, `dub.json`).
- `-m, --docs`: Filter and list documentation files (`*.md`, `*.adoc`, `*.txt`).
- `-t, --tree`: Display file list in a concise hierarchy format.
- `-s, --summary`: Display high-level summary counts table only.
- `-j, --json`: Output structured JSON array.
- `-a, --all`: Include ignored directories (`_build/`, `.git/`, `.cache/`).
- `--max-depth <N>`: Maximum directory recursion depth (default: 20).
- `-h, --help`: Display help and usage options.
