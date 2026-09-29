---
name: check-null-safety
description: >-
  Audit D constructor assertions, reference type invariants, and C wrapper
  NULL documentation conventions defined in codestyle.md.
---

# Null Safety & Contract Auditor

This skill audits D and C sources to enforce the null handling conventions
and invariants defined in
[codestyle.md](file:///home/yur/agy-projects/yvidtrim/codestyle.md).

## Core Script

The auditor is implemented in D and executed via `rdmd`:

```bash
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d \
  [options] [files...]
```

## Contracts Audited

1. **D Constructor Non-Null Assertions**:
   By default, reference types (classes and interfaces) and raw pointers passed
   into constructors cannot be null. Constructors accepting these types must
   include `assert(arg !is null)`, unless explicitly documented with
   `@nullable` or `allowed to be null`.
2. **D Class & Struct Invariants**:
   Recommends class/struct invariants with `assert(field !is null)` for
   persistent non-null fields rather than repetitive null checks throughout
   methods.
3. **C Wrapper NULL Documentation**:
   Functions declared in private C wrapper headers (`yvidtrim-clibs/*.h` and
   `yguilib/yguilib-clibs/*.h`) accepting or returning pointer types must have
   doc comments explicitly stating whether `NULL` is valid or undefined.

## CLI Usage

### Audit All Project Files
```bash
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
```

### Audit Specific Files
```bash
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d \
  yguilib/source/yguilib/app.d yguilib/yguilib-clibs/yguilib_sdl3.h
```

## Options

- `-h`, `--help`: Display help and options.
