---
name: search-code
description: >-
  Search D/C sources, docs, and skills using regex or whole-word patterns
  with project-aware excludes (_build, _bench, .git, archive) and zero-match
  verification. Use instead of raw grep/rg shell pipelines.
---

# Search Code (`search-code`)

This skill searches project files using regex or whole-word patterns with
project-aware exclusions (`_build`, `_bench`, `.git`, `archive`), replacing raw
`grep`/`rg` shell pipelines and `! grep ... && echo` wrappers.

## Core Script

```bash
rdmd .agents/skills/search-code/scripts/search_code.d [options] [paths...]
```

When `[paths...]` is omitted, searches `source`, `yguilib/source`,
`yguilib/examples`, `yguilib/benchmarks`, `yvidtrim-clibs`, and
`yguilib/yguilib-clibs`. Add `--include-docs`, `--include-skills`, or
`--include-plans` to include `documentation/`, `.agents/skills/`, or `plans/`
in the default roots. Root files such as `meson.build` and `ARCHITECTURE.md`
are searched only when passed as paths. A path that does not exist is an
error (exit `2`).

## Features

- **Project-Aware Excludes**: Automatically skips `_build/`, `_bench/`, `.git/`,
  `.dub/`, `.cache/`, `subprojects/`, binary files, and `archive/` directories
  (unless `--include-archive` is passed).
- **Multi-Pattern Search**: Repeat `-e` / `--pattern` to match any of several
  patterns in one run without shell `&&` chains.
- **Whole-Word Mode**: `-w` / `--word` wraps each pattern in identifier word
  boundaries.
- **Zero-Match Verification**: `--expect-none` prints `0 matches (OK).` and
  exits `0` only when no matches exist (exits `1` otherwise).
- **Concise Output**: `--count` prints per-file and total counts;
  `--max-matches` caps printed lines; `--json` outputs structured results.

## CLI Usage

### 1. Search Default Source Roots with Multiple Patterns
```bash
rdmd .agents/skills/search-code/scripts/search_code.d \
  -e '\b(get|set)[A-Z]' -e '\bisModal\b'
```

### 2. Verify Zero Matches (Replacing `! grep ... && echo "NO HITS"`)
```bash
rdmd .agents/skills/search-code/scripts/search_code.d \
  --expect-none -e '\bsetCaption\b'
```

### 3. Whole-Word Search Including Docs, Skills, and Plans
```bash
rdmd .agents/skills/search-code/scripts/search_code.d \
  --word --include-docs --include-skills --include-plans modal
```

### 4. Count Matches or Emit JSON
```bash
rdmd .agents/skills/search-code/scripts/search_code.d \
  --count -e 'WidgetUpdateScope' source/ yguilib/source/
```

## Options

- `-e, --pattern <regex>`: Regex pattern to search (repeatable).
- `-w, --word`: Match whole identifier words only (`\b...\b`).
- `-i, --ignore-case`: Case-insensitive regex matching.
- `--include-docs`: Include `documentation/` in default roots.
- `--include-skills`: Include `.agents/skills/` in default roots.
- `--include-plans`: Include `plans/` in default roots.
- `--include-archive`: Do not skip `archive/` directories.
- `--expect-none`: Exit `1` if any match is found (`0` if none).
- `--count`: Print per-file and total match counts only.
- `--max-matches <N>`: Stop printing match lines after `N` hits (`0` = all).
- `--json`: Output matches in JSON format.
- `-h, --help`: Display help and options.
