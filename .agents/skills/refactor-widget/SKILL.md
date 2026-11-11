---
name: refactor-widget
description: >-
  Audit, refactor, and verify Widget and WidgetComponent architectures,
  constructor calls, builder patterns, and test fixtures across yguilib,
  guidemo, and yvidtrim. Use this skill when modifying Widget, WidgetComponents,
  constructor signatures, or migrating unit tests to WidgetFixture.
---

# Widget Refactoring & Toolkit (`refactor-widget`)

This skill accelerates tasks modifying `Widget`, `WidgetComponents`,
`WidgetBuilder`, and widget hierarchy lifecycles (such as `Widget.addChild`,
`Widget.name`, constructor minimization, and `dumpTree`).

It provides an automated analysis script and testing fixture to prevent
widespread test breakage and ensure architectural invariants are respected.

## Core Script

The widget analyzer and auditor is implemented in D and executed via `rdmd`:

```bash
rdmd .agents/skills/refactor-widget/scripts/refactor_widget.d [options]
```

## Test Fixture Helper (`yguilib.widget.test_fixture`)

The `WidgetFixture` class (in `yguilib/source/yguilib/widget/test_fixture.d`)
provides an isolated context for creating widgets and configuring components in
unit tests without manual ID juggling or constructor coupling.

### Example: Using `WidgetFixture` in Unit Tests
```d
import yguilib.widget.test_fixture : WidgetFixture;

unittest {
  auto fix = new WidgetFixture();

  // Automatic sequential IDs, parent-child wiring
  auto root = fix.makeRoot(RectF(0, 0, 640, 480));
  auto child1 = fix.makeChild(root, RectF(10, 10, 100, 50));
  auto child2 = fix.makeChild(root, 50, 60, 200, 100);

  // Fluent component setup
  fix.withBackground(child1, ColorF(0.2f, 0.4f, 0.6f, 1.0f));
  fix.withBorder(child1, ColorF(1, 0, 0, 1), 2.0f);
  fix.withText(child1, "Label");
  fix.withFlexRow(root, 10.0f);

  // Tree utilities
  assert(WidgetFixture.countNodes(root) == 3);
  assert(WidgetFixture.findById(root, child1.uId) is child1);
  assert(WidgetFixture.isDescendantOf(child1, root));
}
```

## Standard Refactoring Workflow

When modifying `Widget` or `WidgetComponents`:

### 1. Map Call Sites and Usages
Before modifying a constructor or property, inspect all affected locations:
```bash
# High-level summary of call sites and components
rdmd .agents/skills/refactor-widget/scripts/refactor_widget.d -s

# List all Widget and WidgetBuilder call sites
rdmd .agents/skills/refactor-widget/scripts/refactor_widget.d -w

# List all WidgetComponents accesses
rdmd .agents/skills/refactor-widget/scripts/refactor_widget.d -c
```

### 2. Audit Constructor Overloading
Check classes or structs violating the single-constructor style rule:
```bash
rdmd .agents/skills/refactor-widget/scripts/refactor_widget.d -k
```

### 3. Check Test Sites Requiring Fixture Migration
Identify tests that still use raw `new Widget(...)` and migrate them to
`WidgetFixture` before changing constructor signatures:
```bash
rdmd .agents/skills/refactor-widget/scripts/refactor_widget.d -t
```

### 4. Verify Widget Invariants
Ensure no direct array manipulation (`children ~=`) or missing IDs occur:
```bash
rdmd .agents/skills/refactor-widget/scripts/refactor_widget.d -a
```

### 5. Standard Verification Suite
Run the full verification pipeline after making changes:
```bash
# 1. Line length (<= 80 chars)
rdmd .agents/skills/check-line-length/scripts/check_line_length.d

# 2. Code style (2-space, LF, opening brace)
rdmd .agents/skills/check-codestyle/scripts/check_style.d

# 3. Boundaries and encapsulation
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d

# 4. Build and test
ninja -C _build && meson test -C _build
```

## CLI Options Reference

- `-s, --summary`: Display high-level summary table of widgets and components.
- `-w, --widgets`: List all Widget and WidgetBuilder call sites with line
  numbers and categories.
- `-c, --components`: List all direct `WidgetComponents` accesses and method
  calls.
- `-k, --constructors`: Audit classes and structs with multiple constructors
  (overloading).
- `-t, --tests`: List unit tests that can be migrated to `WidgetFixture`.
- `-a, --audit`: Check Widget architectural invariants.
- `-j, --json`: Output results in structured JSON format.
- `-f, --filter <str>`: Filter scanned files by substring.
- `-h, --help`: Display help and options.
