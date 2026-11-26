---
name: check-boundaries
description: >-
  Verify architectural boundaries, module encapsulation, yguilib independence,
  and domain facade constraints across yvidtrim and yguilib.
---

# Architecture & Boundary Checker

This skill verifies and protects architectural boundaries and encapsulation
rules defined in
[codestyle.md](../../../codestyle.md) and
[AGENTS.md](../../../AGENTS.md).

## Core Script

The boundary validator is implemented in D and executed via `rdmd`:

```bash
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d [options]
```

## Boundaries Enforced

1. **`yguilib` Independence**:
   Ensures that `yguilib/` (both D code and C wrapper code) never imports or
   depends on `yvidtrim` or `guidemo` (`source/yvidtrim`, `source/guidemo`,
   or `yvidtrim-clibs`).
2. **Internal Encapsulation**:
   Ensures files inside any `internal/` subdirectory do not declare `public:`
   sections or inline `public` declarations. Implementation details must be
   `package(<root_pkg>):` or `private:`.
3. **No Umbrella Root Imports & No `public import` Re-exports**:
   Verifies that top-level monolithic `package.d` files do not exist and no D
   module uses `public import` to re-export symbols from other modules.
4. **Package Directory Rule**:
   Ensures isolated single modules are not unnecessarily placed in standalone
   `package.d` directories unless encapsulating `internal/` modules;
   multi-module packages do not require `package.d`.
5. **Private C Wrapper Abstraction**:
   Ensures D code only imports wrapper modules under `clibs/` and does not
   bypass private C wrappers.
6. **`ARCHITECTURE.md` Size Limit**:
   Verifies that `ARCHITECTURE.md` remains under 250 lines per `AGENTS.md`.

## CLI Usage

### Check All Boundaries
```bash
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
```

## Options

- `-h`, `--help`: Display help and options.
