---
name: manage-assets
description: >-
  Audit asset placement in assets/<package_name>/, verify string import
  existence, and generate D string import boilerplate for embedded resources.
---

# Asset Manager & String Import Generator

This skill manages static assets (shaders, fonts, images) and automates
D string imports according to
[codestyle.md](file:///home/yur/agy-projects/yvidtrim/codestyle.md).

## Core Script

The asset manager is implemented in D and executed via `rdmd`:

```bash
rdmd .agents/skills/manage-assets/scripts/manage_assets.d [options]
```

## Conventions Enforced

1. **Asset Directory Hierarchy**:
   All static assets meant for compilation via D string imports must be placed
   under `assets/<package_name>/...` (e.g. `assets/yguilib/shaders/` or
   `yguilib/assets/yguilib/shaders/`). This prevents name collisions when a
   program and a library use identically named assets.
2. **String Import Integrity**:
   Verifies that all `import("...")` expressions in `assets.d` or
   `internal/assets.d` refer to real files that exist on disk.
3. **Meson String Import Directories**:
   Verifies that `d_import_dirs` in `meson.build` points to the asset roots so
   the D compiler can resolve string imports.

## CLI Usage

### Audit Assets & Imports
```bash
rdmd .agents/skills/manage-assets/scripts/manage_assets.d --check
```

### Preview String Import Generation for a Package
```bash
rdmd .agents/skills/manage-assets/scripts/manage_assets.d \
  --generate yguilib --dry-run
```

### Generate `internal/assets.d`
```bash
rdmd .agents/skills/manage-assets/scripts/manage_assets.d --generate yguilib
```

## Options

- `--check`: Audit asset placement and string import existence.
- `--generate <pkg>`: Generate `internal/assets.d` for the package.
- `--dry-run`: Preview generated code without writing to disk.
- `-h`, `--help`: Display help and options.
