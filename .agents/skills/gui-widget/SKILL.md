---
name: gui-widget
description: >-
  Define, scaffold, refactor, and audit GUI widgets, composite controls, and
  views (WidgetBuilder, fluent builders, ViewComponent event routing,
  ModelTracker sync, ECS WidgetComponents). Use when constructing new widgets,
  pages, or views, when changing Widget, WidgetComponents, or constructor
  signatures, or when moving yguilib tests to WidgetFixture.
---

# GUI Widgets & Views (`gui-widget`)

This skill covers building and refactoring GUI hierarchies, reusable composite
widgets, and ECS-style interactive controls in `yguilib`, `guidemo`, and
`yvidtrim`: tier selection, `WidgetBuilder` rules, templates, refactoring
workflow, and one D CLI tool.

---

## Core Helper Script

```bash
# Default: summary plus audit
rdmd .agents/skills/gui-widget/scripts/gui_widget.d

# Audit invariants and builder chains; list custom *Builder structs
rdmd .agents/skills/gui-widget/scripts/gui_widget.d --audit --list

# Preview scaffolding for a new reusable widget (tiers: inline, view, system)
rdmd .agents/skills/gui-widget/scripts/gui_widget.d \
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
Page class (see `source/guidemo/view.d`), and for simple clickable buttons that
do not need hover/press animations (configure `.roundBg(...)`,
`.roundBorder(...)`, `.text(...)`, `.textAlign(TextLabel.Alignment.center)`, and
`.onMouseDown(...)` or `.onMouseUp(...)` directly on `WidgetBuilder`, without
registering `AnimatedHoverButtonSystem`).
- Construct widgets with `WidgetBuilder.make(ui)`.
- Store references only to widgets mutated in `update()`.
- Synchronize state in `View.update()` using `ModelTracker!M.update()`.
- Create `ModelTracker!M` and `View` before the `Controller`, pass `tracker`
  explicitly to both `View` and `Controller`, and call
  `app.withRootWidget(view.rootWidget())` in `main()`. Controllers never
  create their View or touch `App`/`Window` (keeping them testable with
  `makeHeadlessUiSystem()`).

### Tier 2: Reusable Composite Widget (`*Builder` + `WidgetView`)
Use for multi-widget controls that encapsulate child widgets, translate child
events, or synchronize dynamic children via `WidgetArrayProvider` or
`ScrollableArea` (see `yguilib/source/yguilib/controls/tabcontrol.d`).
- Define a `*Style` or `*Config` struct for visual defaults.
- Define a fluent `*Builder` struct with
  `build(UiSystem ui, Widget parent, RectF rect)` (no default parameter
  values; see `codestyle.md`).
- Attach `.viewEvents(renameMap)` and `.viewName(widgetViewName)` to the root
  widget so child `MouseEvent` triggers bubble up and get translated by
  `WidgetView`.
- Register the shared `WidgetView` and `WidgetViewController` once at startup.

### Tier 3: ECS-Style Widget (`*Component` + `WidgetSystem`)
Use when behavior or animation applies to single-node widgets automatically
without manual controller registration (see
`yguilib/source/yguilib/controls/hover_button_system.d`).
- Define `final class MyComponent : WidgetComponent`.
- Attach via `WidgetBuilder.make(ui)...component(new MyComponent(...))`.
- Process visible widgets with the component in a `WidgetSystem` across
  `SystemPhase.event | SystemPhase.preLayout | SystemPhase.postLayout`
  (plus `SystemPhase.update` for non-timed Phase 2a `update(ctx)` work).
- For 60 FPS animations, register an owner-bound timer via `startTimer(16,
  TimerMode.repeat)` (or `host.startTimer(this, 16, TimerMode.repeat)`),
  step animations in `onTimer(ctx, id, dt)`, stop it with `stopTimer` when
  idle, and never request inline per-`mouseMotion` renders (latch sub-frame
  hover pulses if hover-animated).

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
   - In `View.update()` or `onTimer` animations, assign fields directly and call
     `widget.update(scope)` (guarding with `!=` in hot paths or every-frame
     syncs):
     - `components.textLabel.caption = v` -> `WidgetUpdateScope.content`
     - `components.background.color = v`, `components.border.color = v`,
       `components.textLabel.color = v`, `inputEnabled = v` ->
       `WidgetUpdateScope.visuals`
     - Toggling `visible = v`, `components.scrollableArea.offset = v`, or
       changing geometry/layout properties (`rect.x/y/width/height`,
       `flexContainer.alignItems`) -> `WidgetUpdateScope.layout`. Never use
       `WidgetUpdateScope.visuals` after mutating `rect`: `visuals` does not
       set `layoutDirty`, leaving cached `VisibleWidget.absRect` stale in
       `WidgetSystemPipeline` until an unrelated layout pass (e.g. scrolling).

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

  /// Builds the widget tree. `parent` may be null in tests.
  Widget build(UiSystem ui, Widget parent, RectF rect) {
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
  import yguilib.uisystem : makeHeadlessUiSystem;
  import yguilib.widget.layout_components : SizingMode;

  auto ui = makeHeadlessUiSystem();
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

## Refactoring `Widget` and `WidgetComponents`

Applies to changes in `Widget`, `WidgetComponents`, `WidgetBuilder`, and
hierarchy lifecycles (`Widget.addChild`, `Widget.name`, constructors,
`dumpTree`).

```bash
# 1. Map affected call sites before changing a constructor or property
rdmd .agents/skills/gui-widget/scripts/gui_widget.d --summary --widgets
rdmd .agents/skills/gui-widget/scripts/gui_widget.d --components

# 2. Find types with more than one constructor
rdmd .agents/skills/gui-widget/scripts/gui_widget.d --constructors

# 3. Find tests that still call `new Widget(...)` directly
rdmd .agents/skills/gui-widget/scripts/gui_widget.d --tests
```

### `WidgetFixture` (inside `yguilib` only)

`WidgetFixture` (`yguilib/source/yguilib/widget/test_fixture.d`) creates
widgets and configures components in unit tests without manual ID juggling or
constructor coupling. It is declared `version (unittest):` and
`package(yguilib):`, so `guidemo` and `yvidtrim` tests cannot import it; they
use `makeHeadlessUiSystem()` with `WidgetBuilder`. Migrate `yguilib` hits from
`--tests` before changing constructor signatures.

```d
import yguilib.render.render_types : ColorF, RectF;
import yguilib.widget.drawing_components : Background;
import yguilib.widget.layout_components : AlignItems, JustifyContent;
import yguilib.widget.test_fixture : WidgetFixture;

unittest {
  auto fix = new WidgetFixture();

  // Automatic sequential IDs, parent-child wiring
  auto root = fix.makeRootWithRect(RectF(0, 0, 640, 480));
  auto child1 = fix.makeChildWithRect(root, RectF(10, 10, 100, 50));
  auto child2 = fix.makeChildWithBounds(root, 50, 60, 200, 100);

  // Component setup (all arguments are explicit)
  fix.withBackground(
    child1, ColorF(0.2f, 0.4f, 0.6f, 1.0f), Background.Style.rect, 0.0f
  );
  fix.withBorder(child1, ColorF(1, 0, 0, 1), 2.0f);
  fix.withText(child1, "Label", ColorF(1, 1, 1, 1));
  fix.withFlexRow(root, 10.0f, JustifyContent.start, AlignItems.stretch);

  // Tree utilities
  assert(WidgetFixture.countNodes(root) == 3);
  assert(WidgetFixture.findById(root, child1.uId) is child1);
  assert(WidgetFixture.isChildOf(child1, root));
}
```

---

## Verification Workflow

After defining or modifying a GUI widget or view, run:

```bash
# 1. Audit widget invariants and WidgetBuilder chains
rdmd .agents/skills/gui-widget/scripts/gui_widget.d --audit

# 2. Static checks, then build and run unit tests
rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks
```

If modules were added, moved, or data flow changed, update `ARCHITECTURE.md`
(keep it under 250 lines).

---

## CLI Options Reference (`gui_widget.d`)

With no query flag, runs `--summary --audit`. Scans `yguilib/source`,
`yguilib/examples`, and `source`.

- `-a, --audit`: Check invariants (no `new Widget()`, no external
  `.children ~=`); violations exit `1`. Also warns about production builder
  chains without `.name(...)` or geometry (`.rect`, `.bounds`, `.pos`,
  `.size`, `.fixedSize`); warnings do not fail. The geometry check is a text
  heuristic.
- `-l, --list`: List custom `*Builder` structs and count builder chains.
- `-s, --summary`: Summary table of widgets and components.
- `-w, --widgets`: List `Widget` and `WidgetBuilder` call sites.
- `-c, --components`: List direct `WidgetComponents` accesses.
- `-k, --constructors`: List types with multiple constructors.
- `-t, --tests`: List unit tests that call `new Widget(...)` directly.
- `-j, --json`: Print summary counts as JSON (ignores other query flags).
- `-f, --filter <substr>`: Filter scanned files by path substring.
- `--scaffold <WidgetName>`: Generate a widget module with a `*Style` struct,
  fluent `*Builder`, and headless `unittest`. Add the new file to
  `meson.build`.
- `--tier <inline|view|system>`: Scaffold template (default: `inline`).
- `-m, --module <pkg.mod>`: D module name for scaffolding.
- `-o, --output <path>`: Output path (derived from the module if omitted).
- `-d, --dry-run`: Print generated code without writing to disk.
- `-h, --help`: Show usage information.
