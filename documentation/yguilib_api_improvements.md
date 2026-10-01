# yguilib API Improvements & Helpers: guidemo Case Study

This document analyzes ergonomic friction points identified during the review of
`source/guidemo/guidemoapp.d` and its accompanying UI code (`view.d`,
`layout_painter_page.d`, `textlabel_page.d`, `controller.d`), outlining
concrete API enhancements and helper utilities for `yguilib`.

---

## 1. Widget Construction & Component Attachment Boilerplate

### Current Pain Point
Instantiating and configuring even simple widgets (such as chips, buttons, or
labels) requires 6-10 lines of allocations and manual component field
assignments:

```d
auto c1 = new Widget(chipsRow, RectF(0, 0, 108, 48));
auto szC1 = new Size;
szC1.padding = Insets(6, 8, 6, 8);
c1.components.size = szC1;
c1.components.background = new Background(
  ColorF(0.18f, 0.35f, 0.60f, 1.0f),
  Background.Style.rect
);
c1.components.border = new Border(
  ColorF(0.40f, 0.70f, 1.0f, 1.0f),
  Border.Style.rect
);
c1.components.border.width = 2.0f;
c1.components.textLabel = new TextLabel(
  "Rect Style",
  ColorF(1.0f, 1.0f, 1.0f, 1.0f)
);
```

### Proposed Solutions

1. **Fluent Method-Chaining Decorators on `Widget`:**
   Add chaining methods returning `this` to assemble components concisely:
   ```d
   auto c1 = new Widget(chipsRow, RectF(0, 0, 108, 48))
     .withPadding(Insets(6, 8, 6, 8))
     .withBackground(ColorF(0.18f, 0.35f, 0.60f, 1.0f), Background.Style.rect)
     .withBorder(ColorF(0.40f, 0.70f, 1.0f, 1.0f), 2.0f)
     .withText("Rect Style", ColorF(1.0f, 1.0f, 1.0f, 1.0f));
   ```

2. **Constructors for `Size` and `Border`:**
   - Add parameterised constructor overloads on `Size`:
     `this(Dimension w, Dimension h, Insets padding = Insets.init)`
     and `this(Insets padding)`.
   - Add a full constructor to `Border`:
     `this(ColorF color, float width = 1.0f, Style style = Style.rect, `
     `float cornerRadius = 0.0f)`.

---

## 2. Declarative Tree Composition & Hierarchy Scoping

### Current Pain Point
Every child widget requires passing the `parent` pointer explicitly in
`new Widget(parent, ...)`. Deep hierarchies in page builders become imperative,
repetitive, and hard to scan visually.

### Proposed Solutions

1. **Scoped Child Builder:**
   Allow passing a delegate to configure nested child hierarchies:
   ```d
   parent.addChild(RectF(12, 36, 581, 60), (Widget row) {
     row.asFlexRow(gap: 8.0f);
     row.addChild(RectF(0, 0, 108, 48), (Widget chip) {
       chip.withText("Rect Style", Colors.white);
     });
   });
   ```

2. **Convenience Layout Factory Functions:**
   Provide factory wrappers for common layouts:
   - `flexRow(Widget parent, float gap, JustifyContent justify, ...)`
   - `flexColumn(Widget parent, float gap, ...)`

---

## 3. Hit-Testing & Interactive Event Routing

### Current Pain Point
In `controller.d`, mouse click handling on tab buttons relies on hard-coded
screen-coordinate ranges:

```d
if (ev.kind == AppEvent.Kind.mouseButtonDown) {
  if (ev.y >= 20.0f && ev.y <= 52.0f) {
    if (ev.x >= 840.0f && ev.x <= 1025.0f) {
      model.activePage = 0;
      consumed = true;
    }
  }
}
```
Magic numbers break whenever layout offsets, window sizes, or DPI scaling change.

### Proposed Solutions

1. **Widget Geometry Hit-Testing:**
   Expose hit-testing methods on `Widget`:
   - `bool containsPoint(PointF windowPoint) const`
   - `Widget hitTest(PointF windowPoint)` (traversing children top-to-bottom)

2. **Callback-Driven Action / Click Dispatching:**
   Support direct click/action callbacks on widgets:
   ```d
   tab1Btn.onClick(() {
     auto m = tracker.edit();
     m.activePage = 0;
     tracker.commit(m);
   });
   ```
   Let `AppEvent` mouse routing delegate through the hit widget tree rather than
   requiring manual coordinate checks in the controller.

---

## 4. Reactive View Synchronization & Auto-Dirtying

### Current Pain Point
Synchronizing UI state in `view.update()` requires repetitive null-checking,
old-vs-new value comparison, and manual `widget.update()` calls:

```d
if (statusLabel !is null && statusLabel.components.textLabel !is null) {
  const string statusStr = formatStatusString(m);
  if (statusLabel.components.textLabel.caption != statusStr) {
    statusLabel.components.textLabel.caption = statusStr;
    statusLabel.update();
  }
}
```
Forgetting `widget.update()` causes stale visuals without any warning.

### Proposed Solutions

1. **Self-Dirtying Property Mutators on Components:**
   Add setters that automatically compare values and trigger `markDirty()`:
   ```d
   statusLabel.setCaption(statusStr); // no-op if unchanged, marks dirty if changed
   ```

2. **Declarative State Binding with `ModelTracker`:**
   Enable widgets to bind to model extractors:
   ```d
   statusLabel.bindText!DemoModel(tracker, (const m) => formatStatusString(m));
   ```
   During `view.update()`, bound properties re-evaluate automatically when
   `tracker.update()` detects a version increment.

---

## 5. Application Entry Point & Controller Coupling

### Current State
In `guidemoapp.d`:
```d
void main() {
  auto window = new Window(1280, 720, "yguilib feature demo - guidemo");
  auto app = new App(window);
  app.run(new DemoController(app));
}
```
The controller constructor currently reaches deeply into app internals:
`app.ui.getMainWindow().view = view.getRootWidget();`.

### Proposed Solutions
- Provide `app.setRootView(Widget root)` on `App` or allow `Controller.rootView`
  to be queried cleanly by `App.run()`.
- Add convenience starter: `App.run(window, (app) => new DemoController(app))`.
