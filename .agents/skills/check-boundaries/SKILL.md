---
name: check-boundaries
description: >-
  Verify architectural boundaries, module encapsulation, yguilib independence,
  and domain facade constraints across yvidtrim and yguilib.
---

# Architecture & Boundary Checker

This skill verifies and protects architectural boundaries and encapsulation
rules defined in
[codestyle.md](file:///home/yur/agy-projects/yvidtrim/codestyle.md) and
[AGENTS.md](file:///home/yur/agy-projects/yvidtrim/AGENTS.md).

## Core Script

The boundary validator is implemented in D and executed via `rdmd`:

```bash
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d [options]
```

## Boundaries Enforced

1. **`yguilib` Independence**:
   Ensures that `yguilib/` (both D code and C wrapper code) never imports or
   depends on `source/yvidtrim` or `yvidtrim-clibs`.
2. **Internal Encapsulation**:
   Ensures files inside any `internal/` subdirectory do not declare `public:`
   sections or inline `public` declarations. Implementation details must be
   `package(<root_pkg>):` or `private:`.
3. **No Umbrella Root Imports**:
   Verifies that top-level monolithic `package.d` files re-exporting all
   subsystems do not exist.
4. **Domain Facade Rule**:
   Verifies that multi-module subsystems provide a `package.d` facade, and that
   isolated single modules are not unnecessarily placed in standalone
   package directories unless encapsulating `internal/` modules.
5. **Private C Wrapper Abstraction**:
   Ensures D code only imports wrapper modules under `clibs/` and does not
   bypass private C wrappers.

## CLI Usage

### Check All Boundaries
```bash
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
```

## Options

- `-h`, `--help`: Display help and options.
