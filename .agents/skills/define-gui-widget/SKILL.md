---
name: define-gui-widget
description: >-
  Define, scaffold, and audit GUI widgets, composite controls, and views using
  WidgetBuilder, custom fluent builders, ViewComponent event routing,
  ModelTracker synchronization, and ECS WidgetComponents. Use this skill when
  constructing new GUI items, pages, views, or reusable widgets in yvidtrim,
  guidemo, or yguilib.
---

# Defining GUI Widgets & Views (`define-gui-widget`)

This skill guides the construction of GUI hierarchies, reusable composite
widgets, and ECS-style interactive controls in `yguilib`, `guidemo`, and
`yvidtrim`.

It provides:
1. Architectural selection rules (Inline View vs. Composite `WidgetView` vs.
   ECS `WidgetSystem`).
2. `WidgetBuilder` conventions and layout/invalidation invariants.
3. An automated D CLI tool (`define_gui_widget.d`) to **audit** existing
   `WidgetBuilder` chains (e.g., missing `.name(...)` or `.rect(...)` calls)
   and **scaffold** new fluent widget builders with headless unit tests.

---

## Core Helper Script

Run the helper script via `rdmd`:

```bash
# Audit all WidgetBuilder chains and custom *Builder structs
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d --audit

# List all custom *Builder structs and WidgetBuilder chains across the repo
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d --list

# Preview scaffolding for a new reusable widget (tiers: inline, view, system)
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d \
  --scaffold TransportBar --module yvidtrim.transport_bar --tier view --dry-run
```

---

## Choosing the Right GUI Construction Tier

Before writing code, select the pattern that matches the control's lifecycle:

```
+-----------------------------------------------------------------------------+
|                         Need to define a GUI item?                          |
+--------------------------------------+--------------------------------------+
                                       |
         +-----------------------------+-----------------------------+
         v                             v                             v
+-----------------+           +-----------------+           +-----------------+
| Tier 1: Inline  |           | Tier 2: View &  |           | Tier 3: ECS     |
| View Hierarchy  |           | Controller      |           | WidgetSystem    |
+-----------------+           +-----------------+           +-----------------+
| One-off header, |           | Reusable multi- |           | Single-node     |
| status bar, or  |           | node control    |           | visual/input    |
| page section    |           | with internal   |           | behavior across |
| bound to page   |           | child events &  |           | many instances  |
| ModelTracker.   |           | model state.    |           | (60 FPS anims). |
+-----------------+           +-----------------+           +-----------------+
| Example:        |           | Example:        |           | Example:        |
| DemoView.       |           | TabControl      |           | AnimatedHover-  |
| buildHeader()   |           | (tabcontrol.d)  |           | ButtonSystem    |
+-----------------+           +-----------------+           +-----------------+
```

### Tier 1: Inline View Composition (`WidgetBuilder`)
Use for structural sections (headers, footers, cards, panels) inside a View or
Page class (see `source/guidemo/view.d`).
- Construct widgets with `WidgetBuilder.make(ui)`.
- Store references only to widgets mutated in `update()`.
- Synchronize state in `View.update()` using `ModelTracker!M.update()`.

### Tier 2: Reusable Composite Widget (`*Builder` + `WidgetView`)
Use for multi-widget controls that encapsulate child widgets, translate child
events, or synchronize dynamic children via `WidgetArrayProvider` or
`ScrollableArea` (see `source/guidemo/tabcontrol.d`).
- Define a `*Style` or `*Config` struct for visual defaults.
- Define a fluent `*Builder` struct with `build(UiSystem ui, Widget parent,
  RectF rect, UiRegistry registry = null)`.
- Attach `.viewEvents(renameMap)` and `.viewName(widgetViewName)` to the root
  widget so child `MouseEvent` triggers bubble up and get translated by
  `WidgetView`.
- Register the shared `WidgetView` and `WidgetViewController` once at startup.

### Tier 3: ECS-Style Widget (`*Component` + `WidgetSystem`)
Use when behavior or animation applies to single-node widgets automatically
without manual controller registration (see
`source/guidemo/hover_button_system.d`).
- Define `final class MyComponent : WidgetComponent`.
- Attach via `WidgetBuilder.make(ui)...component(new MyComponent(...))`.
- Process visible widgets with the component in a `WidgetSystem` across
  `SystemPhase.event | SystemPhase.preLayout | SystemPhase.postLayout`.

---

## `WidgetBuilder` Rules & Invariants

Every widget constructed via `WidgetBuilder` (`yguilib.widget.builder`) must
follow these rules:

1. **Always Name Every Widget (`.name("...")`)**:
   - Every widget in a view tree must have a non-empty, descriptive `camelCase`
     name (e.g., `.name("header")`, `.name("headerTitleBox")`).
   - Composite builders should derive child names from the root name (e.g.,
     `rootName ~ "LeftBtn"`, `rootName ~ "Viewport"`).
   - Unit tests verify this invariant recursively with `verifyAllNamed(root)`.

2. **Use `UiSystem` for ID Allocation**:
   - Always start chains with `WidgetBuilder.make(ui)`.
   - Use `.child((WidgetBuilder b) { ... })` or `.children(...)` for nested
     children (the `UiSystem` context propagates automatically).

3. **Pair Geometry with Explicit Sizing in Flex Containers**:
   - Call `.pos(...)`, `.size(...)`, `.bounds(...)`, or `.rect(...)` when
     setting geometry explicitly.
   - Inside `.flexRow()` or `.flexColumn()` parents, explicitly specify
     the child's sizing mode:
     - `.fixedSize(w, h)` / `.fixedWidth(w)` / `.fixedHeight(h)` for fixed
       pixel dimensions.
     - `.autoSize()` for text labels or shrink-wrapped containers.
     - `.fractionWidth(wFr)` / `.fractionHeight(hFr)` to fill remaining flex
       space (often paired with `.minWidth(1.0f)` / `.minHeight(1.0f)` for
       scrollable viewports).

4. **Use Correct `WidgetUpdateScope` When Mutating Widgets**:
   - `WidgetBuilder.build()` automatically calls
     `widget.update(WidgetUpdateScope.parentView)`.
   - In `View.update()`:
     - Use `Widget.setCaption(...)`, `setBackgroundColor(...)`,
       `setBorderColor(...)`, `setTextColor(...)` (which trigger the minimum
       required scope automatically).
     - When toggling visibility (`setVisible(v)`) or changing layout properties
       (`rect.width`, `flexContainer.alignItems`), call
       `container.update(WidgetUpdateScope.layout)`.

5. **Threading & Null Safety**:
   - Never construct or mutate widgets outside the main thread.
   - Enforce `assert(ui !is null)` and `assert(parent !is null)` (unless
     `parent` or `registry` is explicitly documented as nullable for headless
     tests).
   - Add `invariant { assert(root !is null); }` on View/Page classes.

---

## Standard Patterns & Code Templates

### Pattern 1: View Section Method (like `DemoView.buildHeader`)
```d
void buildHeader(UiRegistry registry) {
  auto header = WidgetBuilder.make(ui)
    .parent(view)
    .name("header")
    .pos(20, 12)
    .fixedSize(1240, 48)
    .paddingVh(0, 14)
    .flexRow()
    .gap(12.0f)
    .justify(JustifyContent.start)
    .alignItems(AlignItems.center)
    .roundBg(ColorF(0.11f, 0.13f, 0.17f, 1.0f))
    .bgRadius(6.0f)
    .border(ColorF(0.22f, 0.25f, 0.32f, 1.0f))
    .borderWidth(1.0f)
    .build();

  auto titleBox = WidgetBuilder.make(ui)
    .parent(header)
    .name("headerTitleBox")
    .flexColumn()
    .gap(2.0f)
    .justify(JustifyContent.center)
    .alignItems(AlignItems.start)
    .autoSize()
    .build();

  WidgetBuilder.make(ui)
    .parent(titleBox)
    .name("headerTitle")
    .autoSize()
    .text("Title Text")
    .textColor(ColorF(1.0f, 1.0f, 1.0f, 1.0f))
    .fontSize(16.0f)
    .build();
}
```

### Pattern 2: Fluent Custom Widget Builder (`*Builder`)
```d
struct MyWidgetStyle {
  float width = 120.0f;
  float height = 32.0f;
  float cornerRadius = 6.0f;
  ColorF bg = ColorF(0.18f, 0.20f, 0.25f, 1.0f);
  ColorF border = ColorF(0.30f, 0.35f, 0.45f, 1.0f);
  ColorF text = ColorF(0.95f, 0.95f, 0.95f, 1.0f);
}

struct MyWidgetBuilder {
  ref MyWidgetBuilder name(string wName) return {
    widgetName = wName;
    return this;
  }

  ref MyWidgetBuilder style(in MyWidgetStyle s) return {
    cfg = s;
    return this;
  }

  ref MyWidgetBuilder event(string evName) return {
    actionEvent = evName;
    return this;
  }

  /// Builds the widget tree. `parent` and `registry` may be null in tests.
  Widget build(
    UiSystem ui,
    Widget parent,
    RectF rect,
    UiRegistry registry = null
  ) {
    assert(ui !is null, "ui must not be null");
    const string rootName = widgetName.length > 0 ? widgetName : "myWidget";

    return WidgetBuilder.make(ui)
      .parent(parent)
      .name(rootName)
      .rect(rect)
      .fixedSize(cfg.width, cfg.height)
      .roundBg(cfg.bg)
      .bgRadius(cfg.cornerRadius)
      .border(cfg.border)
      .borderWidth(1.0f)
      .text(rootName)
      .textColor(cfg.text)
      .fontSize(13.0f)
      .textAlign(TextLabel.Alignment.center)
      .onMouseDown(actionEvent)
      .build();
  }

private:
  MyWidgetStyle cfg;
  string widgetName = null;
  string actionEvent = "myWidgetAction";
}
```

### Pattern 3: Headless Unit Test for Widget Construction
Always include a `unittest` block verifying layout components and widget names:
```d
unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.layout_components : SizingMode;

  auto ui = new UiSystemImpl(null);
  MyWidgetBuilder b;
  auto root = b
    .name("testControl")
    .build(ui, null, RectF(0, 0, 120, 32));

  assert(root !is null);
  assert(root.name == "testControl");
  assert(root.components.size !is null);
  assert(root.components.size.width.mode == SizingMode.fixed);

  void verifyAllNamed(Widget w) {
    assert(w.name.length > 0, "Widget missing name");
    foreach (child; w.children) {
      verifyAllNamed(child);
    }
  }
  verifyAllNamed(root);
}
```

---

## Verification Workflow

After defining or modifying a GUI widget or view, run:

```bash
# 1. Audit WidgetBuilder chains (checks .name() and .rect() on every builder)
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d --audit

# 2. Check 80-char line length
rdmd .agents/skills/check-line-length/scripts/check_line_length.d

# 3. Check D code style & null safety
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d

# 4. Check architectural boundaries
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d

# 5. Build and run unit tests
ninja -C _build && meson test -C _build
```

---

## CLI Options Reference (`define_gui_widget.d`)

- `-a, --audit`: Scan `WidgetBuilder.make` and `.child(` chains to verify every
  widget sets `.name(...)` and `.rect(...)`.
- `-l, --list`: List all custom `*Builder` structs and `WidgetBuilder` call
  sites across `yguilib`, `guidemo`, and `yvidtrim`.
- `-s, --scaffold <WidgetName>`: Generate a new widget module with a
  `*Style` struct, fluent `*Builder`, and headless `unittest`.
- `-t, --tier <inline|view|system>`: Select the architectural template when
  scaffolding (default: `inline`).
- `-m, --module <pkg.mod>`: D module name for scaffolding (e.g.,
  `yvidtrim.transport_bar`).
- `-o, --output <path>`: Output file path for scaffolding (derived from module
  name if omitted).
- `-d, --dry-run`: Print generated code to stdout without writing to disk.
- `-f, --filter <substr>`: Filter scanned files by path substring.
- `-h, --help`: Show usage information.
