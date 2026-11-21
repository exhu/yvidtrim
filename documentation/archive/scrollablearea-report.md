# ScrollableArea Component & System Placement and Layout Analysis

## 1. Where to Place the Component and System

Following the existing structure in `yguilib/source/yguilib/widget/`:

### Component (`ScrollableArea`)
- **Option A (New module — recommended if adding scrollbars/policies/state)**:
  Create `yguilib/source/yguilib/widget/scroll_components.d`, matching the
  domain-split pattern of:
  - `layout_components.d`
  - `drawing_components.d`
  - `input_components.d`
  - `data_components.d`
- **Option B (Existing module)**:
  If `ScrollableArea` is just a lightweight layout/offset component without
  extra types, it can live in
  `yguilib/source/yguilib/widget/layout_components.d`.
- **Integration**:
  Add a field for it in `WidgetComponents` inside
  `yguilib/source/yguilib/widget/package.d` (and optionally builder helpers in
  `WidgetBuilder` in `yguilib/source/yguilib/widget/builder.d`).

### System (`ScrollSystem`)
- Introduce a new internal module
  `yguilib/source/yguilib/widget/internal/scroll_system.d` with
  `package(yguilib):` visibility, alongside:
  - `data_system.d`
  - `focus_system.d`
  - `input_system.d`
  - `layout_system.d`
- Register the system in `UiSystemImpl.this()` in
  `yguilib/source/yguilib/internal/uisystem_impl.d` and add the new `.d`
  file(s) to `yguilib_src` in `yguilib/meson.build` (and update
  `ARCHITECTURE.md`).

---

## 2. Layout of Clipped Components and `visibleWidgets` Collection

**Summary**: Parent boundary clipping (`Widget.clipChildren`) is ignored during
layout, so parent-clipped widgets are included. However, **window viewport
culling** (`Renderer.isOnScreen`) currently runs before layout and will filter
out widgets whose pre-layout bounds fall outside the window viewport.

### A. Parent Boundary Clipping (`Widget.clipChildren`) Is Not a Problem
- In `WidgetSystemPipeline.runLayoutAndPostLayoutPhases`
  (`yguilib/source/yguilib/widget/internal/system_pipeline.d`), the pipeline
  collects `ctx.unclippedWidgets` with `ignoreClipChildren = true`:
  ```d
  ctx.unclippedWidgets = collector.collectVisible(
    ctx.root,
    ctx.renderer,
    true
  );
  ```
- Even when `ignoreClipChildren = false`,
  `VisibleWidgetsCollector.collectVisiblePrivate`
  (`yguilib/source/yguilib/widget/internal/collect_visible.d`) does **not**
  cull children outside `parentClipRect`—it only records `hasClip` and
  `clipRect` on `VisibleWidget` for `WidgetPainterSystem` and
  `InputSystem.isHit`.

### B. Window Viewport Culling (`Renderer.isOnScreen`) Excludes Off-Window
- In `VisibleWidgetsCollector.collectVisiblePrivate`
  (`yguilib/source/yguilib/widget/internal/collect_visible.d`):
  ```d
  const RectF absRect = RectF(absX, absY, w.rect.width, w.rect.height);
  if (!Renderer.isOnScreen(absRect, vw, vh)) {
    return;
  }
  ```
- This check runs **even when `ignoreClipChildren = true`**, using each
  widget's **pre-layout `rect`**.
- If a child (or subtree) inside a `ScrollableArea` overflows past the
  **window dimensions** `(0, 0, vw, vh)`—or was scrolled off-window on a
  previous frame, or initialized with `width == 0` / `height == 0`—
  `collectVisible` drops it and its descendants from `ctx.unclippedWidgets`.
- **What breaks in `LayoutSystem` when a child is dropped from
  `ctx.unclippedWidgets`**:
  - **Bottom-up pass (`processLeafToRoot`)**: `handleSizeComp` is never called
    on the culled child or its descendants, so their `Size` components
    (auto/fixed dimensions) are not evaluated before the parent container
    measures and arranges them.
  - **Top-down pass (`processRootToLeaf`)**: Although an on-screen parent's
    `handleFlexContainerComp` iterates `w.children` directly, any culled
    child's own `handleFlexContainerComp` and `handleAnchorComp` will **not**
    be called because that child is missing from `ctx.unclippedWidgets`.
- **Fix**: When collecting `ctx.unclippedWidgets` for layout
  (`ignoreClipChildren == true`),
  `VisibleWidgetsCollector.collectVisiblePrivate` should skip the
  `Renderer.isOnScreen(absRect, vw, vh)` check so all `w.visible` widgets
  participate in layout regardless of whether they are currently inside the
  window bounds.

### C. Timing of Scroll Offsets vs. `LayoutSystem` and `collectVisible`
- `handleFlexContainerComp` and `handleAnchorComp` reset child `rect.x` and
  `rect.y` relative to `w.getContentArea()` on every layout pass.
- After `layoutSystems` finish,
  `WidgetSystemPipeline.runLayoutAndPostLayoutPhases` immediately runs
  `collector.collectVisible(ctx.root, ctx.renderer, false)` to compute the
  final `absRect` and `clipRect` for `postLayout`, `render`, and `event`
  phases:
  ```
  collectVisible(ignoreClipChildren = true)  --> ctx.unclippedWidgets
    │
    ▼
  layoutSystems.layout(ctx)
    ├─► LayoutSystem (priority 0): computes Size, Anchor, FlexContainer
    └─► ScrollSystem (priority > 0): applies scroll offsets to child rects
    │
    ▼
  collectVisible(ignoreClipChildren = false) --> ctx.visibleWidgets
    │
    ▼
  postLayout -> render -> event hit-testing (using final absRect & clipRect)
  ```
- Therefore, any scroll offset adjustment to `child.rect` must happen **before**
  that second `collectVisible` call (e.g., in `SystemPhase.layout` with
  `priority > layoutSystemPriority`, or inside `LayoutSystem` itself).
