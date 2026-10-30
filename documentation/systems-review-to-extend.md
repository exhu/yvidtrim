# Widget Tree Systems Review & Extensibility Plan

This document analyzes `InputSystem`, `LayoutSystem`, and `WidgetPainterSystem`
in `yguilib`, examines how they are orchestrated in `UiSystemController`, and
proposes a unified `WidgetSystem` base class and pipeline architecture. The
goal is to support any number of internal and user-defined systems that process
the `Widget` tree in a uniform, extensible way.

---

## 1. Analysis of Existing Widget Tree Systems

Currently, `yguilib` implements three primary systems under
`yguilib/source/yguilib/widget/internal/` (plus a skeletal `FocusSystem` and a
shared `VisibleWidgetsCollector` utility).

### 1.1 `InputSystem` (`yguilib.widget.internal.input_system`)
- **Primary Class**: `final class InputSystem`
- **Role**: Routes raw mouse and keyboard `AppEvent`s to hit widgets, manages
  pressed-widget capture and hover state (`hoveredWidgets`), translates
  widget-level component events (`MouseEvent`, `KeyboardEvent`) into `ViewData`
  events, bubbles them through `ViewComponent.renameEvents`, and dispatches
  them via `UiSystem.sendAppEvent`.
- **Dependencies & State**:
  - Holds references to `UiSystem` and `FocusSystem`.
  - Stateful across frames and events: `hoveredWidgets`, `hoverScratch`,
    `pressedWidgets[maxMouseButtons]`, `lastMousePos`, `hasLastMousePos`.
- **Entry Points**:
  - `bool handleEventAndUpdateView(AppEvent event, VisibleWidgets widgets)`:
    Called during the event-dispatch phase. Traverses `widgets` in reverse
    (leaf-to-root / top-to-bottom Z-order) for hit testing, then walks up
    `parent` / `parentView` chains for hover hierarchy and view event renaming.
  - `void refreshHover(VisibleWidgets widgets)`: Called immediately after
    layout recalculation and clipped visibility collection to emit `mouseEnter`
    and `mouseLeave` when widget geometry shifts under a stationary cursor.
- **Components Inspected**:
  `w.components.mouseEvent`, `w.components.keyboardEvent`, `w.components.view`,
  `w.inputEnabled`.

### 1.2 `LayoutSystem` (`yguilib.widget.internal.layout_system`)
- **Primary Class**: `final class LayoutSystem`
- **Role**: Computes widget sizes and parent-relative positions (`Widget.rect`)
  according to `Size`, `Anchor`, `FlexContainer`, `Border`, and `TextLabel`
  components.
- **Dependencies & State**:
  - Requires `Widget root`, `Renderer r` (for text measurement), and
    `VisibleWidgets` (collected with `ignoreClipChildren = true`).
  - Uses reusable scratch buffers (`Appender!(Widget[]) childBuf`,
    `Appender!(RectF[]) oldRectBuf`) to avoid per-frame GC allocations.
- **Entry Points**:
  - `void layoutTree(Widget root, Renderer r, VisibleWidgets visibleWidgets)`
- **Traversal & Lifecycle**:
  1. Snapshots `vw.widget.rect` into `oldRectBuf`.
  2. **Leaf-to-Root Pass** (`foreach_reverse`): Calls `handleSizeComp(vw, r)`
     to compute intrinsic/auto and fixed dimensions bottom-up.
  3. **Root-to-Leaf Pass** (`foreach`): Calls `handleAnchorComp(vw)` and
     `handleFlexContainerComp(vw, r)` to arrange children top-down.
  4. **Dirty Propagation**: Compares new `w.rect` against `oldRects[i]`; sets
     `w.dirty = true` if geometry changed, and clears `layoutDirty = false`.
- **Existing Extension Hook**:
  Defines an unimplemented `interface CustomLayout` with `handleLeafToRoot` and
  `handleRootToLeaf` hooks.

### 1.3 `WidgetPainterSystem` (`yguilib.widget.internal.widget_painter`)
- **Primary Class**: `final class WidgetPainterSystem` (in `widget_painter.d`)
- **Role**: Renders visible widgets to the window's `Renderer` in back-to-front
  order, applying parent clip rects and content clip rects.
- **Dependencies & State**:
  - Stateless across frames. Requires `VisibleWidgets` (collected with
    `ignoreClipChildren = false`) and `Renderer r`.
- **Entry Points**:
  - `void drawTree(VisibleWidgets widgets, Renderer r)`
- **Traversal & Lifecycle**:
  - **Root-to-Leaf Pass** (`foreach (ref vw; widgets)`):
    1. Pushes `vw.clipRect` if `vw.hasClip`.
    2. Draws `Background` (`drawBackground`).
    3. Computes `absContentRect`, pushes clip if `w.clipContents`.
    4. Draws `TextLabel` (`drawTextLabel`).
    5. Pops content clip if `w.clipContents`.
    6. Draws `Border` (`drawBorder`).
    7. Resets `w.dirty = false`.
    8. Pops `vw.clipRect` if `vw.hasClip`.
- **Existing Extension Hook**:
  Defines an unimplemented `interface CustomWidgetPainter` (`drawBackground`,
  `drawContent`, `drawBorder`) and `CustomDraw` component in
  `drawing_components.d`.

### 1.4 Supporting Infrastructure: `VisibleWidgetsCollector`
- Flattens the `Widget` hierarchy via pre-order depth-first traversal into a
  contiguous `VisibleWidget[]` slice (`widget`, `absRect`, `hasClip`,
  `clipRect`), culling invisible (`!w.visible`) or off-screen subtrees.
- Because `VisibleWidgets` is in pre-order (root-to-leaf, back-to-front):
  - Forward iteration (`foreach`) visits **Root-to-Leaf** (parent before child,
    back-to-front draw order).
  - Reverse iteration (`foreach_reverse`) visits **Leaf-to-Root** (child before
    parent, front-to-back hit-test order).

---

## 2. Current Usage & Orchestration

All three systems are owned and invoked directly by `UiSystemController`
(`yguilib/source/yguilib/internal/uisystem_controller.d`), which sits at the
bottom of the `ControllerStack` in `UiSystemImpl`:

```text
+-----------------------------------------------------------------------+
|                           UiSystemImpl                                |
|  ControllerStack: [ UserControllers..., UiSystemController (base) ]   |
+------------------------------------+----------------------------------+
                                     |
                                     v
+-----------------------------------------------------------------------+
|                        UiSystemController                             |
|                                                                       |
|  1. Event Phase: handleEvent(AppEvent ev)                             |
|     +-- updateUiLayer / WindowRedraw -> returns Result.updateView     |
|     +-- inputSystem.handleEventAndUpdateView(ev, lastVisibleWidgets)  |
|                                                                       |
|  2. Update & Render Phase: updateView()                               |
|     +-- updateLayout() [if rootWidget.isTreeLayoutDirty()]            |
|     |   +-- collectVisible(root, renderer, ignoreClipChildren: true)  |
|     |   +-- layoutSystem.layoutTree(root, renderer, visibleWidgets)   |
|     |   +-- collectVisible(root, renderer, ignoreClipChildren: false) |
|     |   +-- inputSystem.refreshHover(lastVisibleWidgets)              |
|     |                                                                 |
|     +-- renderFrame() [if rootWidget.isTreeDirty()]                   |
|         +-- painterSystem.drawTree(lastVisibleWidgets, renderer)      |
|         +-- mainWindow.swapBuffers()                                  |
+-----------------------------------------------------------------------+
```

### Key Observations & Current Limitations
1. **Hardcoded Pipeline in `UiSystemController`**:
   `UiSystemController` instantiates `LayoutSystem`, `WidgetPainterSystem`, and
   `InputSystem` as concrete private fields and calls ad-hoc methods on each
   (`handleEventAndUpdateView`, `layoutTree`, `refreshHover`, `drawTree`).
2. **Inconsistent Signatures & Context**:
   Each system takes a different subset of `(UiSystem, Window, Widget root,
   Renderer, VisibleWidgets, AppEvent)`.
3. **Closed Component Set**:
   `WidgetComponents` is a fixed struct in `yguilib.widget`. User-defined
   systems cannot attach custom per-widget data or components without modifying
   `yguilib`.
4. **Conflated Dirty Flags**:
   `LayoutSystem` clears `w.layoutDirty` inside `layoutTree`, and
   `WidgetPainterSystem` clears `w.dirty` inside `drawWidget`. If a second
   layout or post-render system runs after them, the dirty flags are already
   cleared.
5. **No Registration Mechanism**:
   Neither `UiSystem` nor `Window` exposes an API to register additional widget
   systems (e.g., animations, accessibility, tooltips, data-binding sync, debug
   overlays, or custom layout/paint passes).

---

## 3. Common Patterns & Unified Processing Model

Despite different domain tasks, all widget tree systems share a common
structural model:

```text
+-------------------+--------------------+--------------------+----------------+
| Aspect            | InputSystem        | LayoutSystem       | PainterSystem  |
+-------------------+--------------------+--------------------+----------------+
| Primary Input     | VisibleWidgets,    | VisibleWidgets     | VisibleWidgets |
|                   | AppEvent           | (unclipped), root  | (clipped)      |
+-------------------+--------------------+--------------------+----------------+
| Services Used     | UiSystem           | Renderer           | Renderer       |
+-------------------+--------------------+--------------------+----------------+
| Traversal         | Leaf-to-Root +     | 1. Leaf-to-Root    | Root-to-Leaf   |
|                   | ancestor walk      | 2. Root-to-Leaf    |                |
+-------------------+--------------------+--------------------+----------------+
| Execution Trigger | On AppEvent &      | When               | When           |
|                   | Post-Layout        | isTreeLayoutDirty  | isTreeDirty    |
+-------------------+--------------------+--------------------+----------------+
| Side Effects      | Sends AppEvent,    | Mutates w.rect,    | Calls Renderer,|
|                   | updates hover      | marks w.dirty      | clears w.dirty |
+-------------------+--------------------+--------------------+----------------+
```

### Lifecycle Phases of a Frame / Step
Every widget system operates in one or more well-defined execution phases:
1. **`event` Phase**: Triggered when an `AppEvent` reaches the widget layer.
   Systems can inspect or consume the event and request a view update
   (e.g., `InputSystem`, `FocusSystem`, shortcut/hotkey systems).
2. **`update` / `preLayout` Phase**: Runs before layout calculation (e.g.,
   model-binding synchronization, animation interpolation, state transitions
   that may mark `layoutDirty` or `dirty`).
3. **`layout` Phase**: Computes widget geometry using unclipped visible widgets
   (e.g., `LayoutSystem`, custom constraint solvers, sticky headers).
4. **`postLayout` Phase**: Reacts to finalized geometry after clipped
   `VisibleWidgets` are collected (e.g., `InputSystem.refreshHover`, scroll
   bounds clamping, spatial index building, tooltip positioning).
5. **`render` Phase**: Draws visual representation using clipped
   `VisibleWidgets` and `Renderer` (e.g., `WidgetPainterSystem`, custom canvas
   painters, debug bounds/FPS overlay systems).

---

## 4. Proposed Architecture & Common Interface

### 4.1 Execution Context (`WidgetSystemContext`)
Instead of passing varying parameter lists, pass a unified context struct to
all system hooks:

```d
module yguilib.widget.system;

import yguilib.events : AppEvent;
import yguilib.render : Renderer;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.visible : VisibleWidget, VisibleWidgets;
import yguilib.window : Window;

/// Shared context passed to WidgetSystem lifecycle methods.
struct WidgetSystemContext {
  UiSystem uiSystem;
  Window window;
  Widget root;
  Renderer renderer;
  /// Visible widgets collected with clipping (for input/postLayout/render).
  VisibleWidgets visibleWidgets;
  /// Visible widgets collected without parent clipping (for layout).
  VisibleWidgets unclippedWidgets;
}
```
*(Note: `VisibleWidget` and `VisibleWidgets` should be publicly aliased or moved
from `yguilib.widget.internal.collect_visible` to `yguilib.widget` so
user-defined systems can inspect absolute rects and clip rects.)*

### 4.2 Base Class: `WidgetSystem`
Provide an abstract base class with no-op default methods so concrete systems
only override the phases they participate in, plus helper traversal templates:

```d
/// Flags indicating which pipeline phases a WidgetSystem participates in.
enum SystemPhase : uint {
  none       = 0,
  event      = 1 << 0,
  preLayout  = 1 << 1,
  layout     = 1 << 2,
  postLayout = 1 << 3,
  render     = 1 << 4,
}

/// Result of handling an AppEvent in a WidgetSystem.
struct SystemEventResult {
  bool consumed;
  bool requestUpdateView;
}

/// Base class for all internal and user-defined systems that process
/// the Widget tree.
abstract class WidgetSystem {
  /// Priority within a phase (lower runs earlier; default 0).
  int priority = 0;

  /// Bitmask of SystemPhase values this system active in.
  @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.none;
  }

  /// Called once when the system is registered with the pipeline.
  void onRegister(UiSystem uiSystem) {}

  /// Called once when the system is unregistered.
  void onUnregister() {}

  /// Phase 1: Handle incoming AppEvent.
  SystemEventResult handleEvent(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    return SystemEventResult(false, false);
  }

  /// Phase 2: Pre-layout update (animations, bindings, state sync).
  void preLayout(ref WidgetSystemContext ctx) {}

  /// Phase 3: Layout calculation (sizing and positioning).
  void layout(ref WidgetSystemContext ctx) {}

  /// Phase 4: Post-layout reaction (hover refresh, spatial indexing).
  void postLayout(ref WidgetSystemContext ctx) {}

  /// Phase 5: Rendering (drawing widgets, overlays, diagnostics).
  void render(ref WidgetSystemContext ctx) {}

protected:
  /// Helper: Root-to-leaf (back-to-front) iteration over a widget list.
  static void traverseRootToLeaf(alias Fn)(VisibleWidgets widgets) {
    foreach (ref vw; widgets) {
      Fn(vw);
    }
  }

  /// Helper: Leaf-to-root (front-to-back) iteration over a widget list.
  static void traverseLeafToRoot(alias Fn)(VisibleWidgets widgets) {
    foreach_reverse (ref vw; widgets) {
      Fn(vw);
    }
  }
}
```

### 4.3 Specialized Two-Pass Base Class (Optional Convenience)
For systems like `LayoutSystem` that naturally perform a bottom-up pass followed
by a top-down pass over `VisibleWidgets`:

```d
abstract class TwoPassWidgetSystem : WidgetSystem {
  void beginPass(ref WidgetSystemContext ctx) {}
  void processLeafToRoot( ref VisibleWidget vw, ref WidgetSystemContext ctx) {}
  void processRootToLeaf( ref VisibleWidget vw, ref WidgetSystemContext ctx) {}
  void endPass(ref WidgetSystemContext ctx) {}

  protected final void runTwoPass(
    VisibleWidgets widgets,
    ref WidgetSystemContext ctx
  ) {
    beginPass(ctx);
    foreach_reverse (ref vw; widgets) {
      processLeafToRoot(vw, ctx);
    }
    foreach (ref vw; widgets) {
      processRootToLeaf(vw, ctx);
    }
    endPass(ctx);
  }
}
```

---

## 5. Supporting User-Defined Components on `Widget`

For user-defined systems to be truly useful, users must be able to attach custom
`Component` subclasses to `Widget` instances without modifying `yguilib`.

Currently, `Widget.components` is a fixed `WidgetComponents` struct. We can
preserve fast direct field access for built-in components while adding a
dynamic component lookup for custom systems:

```d
struct WidgetComponents {
  // Built-in fast-path components (unchanged):
  FlexContainer flexContainer;
  Size size;
  Anchor anchor;
  Background background;
  TextLabel textLabel;
  Border border;
  CustomDraw customDraw;
  ViewComponent view;
  Focus focus;
  DefaultButton defaultButton;
  KeyboardEvent keyboardEvent;
  MouseEvent mouseEvent;

  // Extension storage for user-defined Component subclasses:
  private Component[TypeInfo_Class] custom;

  /// Attach or replace a user-defined component of type C.
  void set(C : Component)(C comp) {
    custom[typeid(C)] = comp;
  }

  /// Retrieve a user-defined component of type C (or null if absent).
  inout(C) get(C : Component)() inout {
    if (auto p = typeid(C) in custom) {
      return cast(inout(C))*p;
    }
    return null;
  }
}
```
This keeps zero-overhead field access for internal systems (`w.components.size`)
while allowing user systems to query `w.components.get!TooltipComponent()`.

---

## 6. Refactoring Existing Systems & Orchestration

### 6.1 Refactoring the Three Core Systems

1. **`InputSystem : WidgetSystem`**
   - `phases`: `SystemPhase.event | SystemPhase.postLayout`
   - `handleEvent(event, ctx)`: Delegates to existing
     `handleEventAndUpdateView(event, ctx.visibleWidgets)`.
   - `postLayout(ctx)`: Delegates to `refreshHover(ctx.visibleWidgets)`.

2. **`LayoutSystem : TwoPassWidgetSystem` (or `WidgetSystem`)**
   - `phases`: `SystemPhase.layout`
   - `layout(ctx)`: Runs the leaf-to-root (`handleSizeComp`) and root-to-leaf
     (`handleAnchorComp`, `handleFlexContainerComp`) passes on
     `ctx.unclippedWidgets`.
   - **Dirty Flag Separation**: Instead of `LayoutSystem` immediately clearing
     `layoutDirty` inside its own loop, `LayoutSystem` only marks
     `vw.widget.dirty = true` when `vw.widget.rect != oldRects[i]`. The pipeline
     manager clears `layoutDirty` after *all* `SystemPhase.layout` systems have
     completed.
   - **Fine-Grained Extension vs. Full System**: `CustomLayout` plugins can
     either be registered on `LayoutSystem` for per-widget hooks, or implemented
     as standalone `WidgetSystem`s running in `SystemPhase.layout` after
     `LayoutSystem` (priority > 0).

3. **`WidgetPainterSystem : WidgetSystem`**
   - `phases`: `SystemPhase.render`
   - `render(ctx)`: Iterates `ctx.visibleWidgets` and draws background, content,
     and border using `ctx.renderer`.
   - **Dirty Flag Separation**: The pipeline manager clears `w.dirty = false`
     after *all* `SystemPhase.render` systems have completed, so subsequent
     render systems (e.g., a custom effect or debug overlay system) can still
     inspect `w.dirty` if needed.

### 6.2 Pipeline Manager (`WidgetSystemPipeline`)

Extract system orchestration from `UiSystemController` into a dedicated
`WidgetSystemPipeline` (owned by `UiSystemImpl` or `UiSystemController` and
exposed via `UiSystem` interface):

```text
+-----------------------------------------------------------------------+
|                        WidgetSystemPipeline                           |
|                                                                       |
|  Registered Systems (sorted by priority per phase):                   |
|    [event]      : FocusSystem (-10), InputSystem (0), UserShortcuts   |
|    [preLayout]  : BindingSyncSystem (-10), UserAnimationSystem (0)    |
|    [layout]     : LayoutSystem (0), UserCustomLayoutSystem (10)       |
|    [postLayout] : InputSystem (0), UserTooltipSystem (10)             |
|    [render]     : WidgetPainterSystem (0), UserDebugOverlay (100)     |
+-----------------------------------------------------------------------+
```

#### Frame Update Flow in `WidgetSystemPipeline.updateAndRender(Window win)`:
1. Build `WidgetSystemContext ctx` for `win` (`rootWidget`, `renderer`,
   `lastVisibleWidgets`).
2. **Pre-Layout Phase**:
   Run all `SystemPhase.preLayout` systems. (They may mutate components and call
   `w.update(...)`, setting `layoutDirty` or `dirty`).
3. **Layout & Post-Layout Phases** (if `root.isTreeLayoutDirty()` or
   `lastVisibleWidgets.length == 0`):
   - Collect `ctx.unclippedWidgets = collector.collectVisible(root, r, true)`.
   - Snapshot `oldRects` for `ctx.unclippedWidgets`.
   - Run all `SystemPhase.layout` systems (`LayoutSystem`, etc.).
   - Mark `vw.widget.dirty = true` for any widget whose `rect` changed; clear
     `layoutDirty = false` across the tree.
   - Collect `ctx.visibleWidgets = collector.collectVisible(root, r, false)`.
   - Cache `lastVisibleWidgets = ctx.visibleWidgets`.
   - Run all `SystemPhase.postLayout` systems (`InputSystem.postLayout`, etc.).
4. **Render Phase** (if `root.isTreeDirty()`):
   - Run all `SystemPhase.render` systems (`WidgetPainterSystem`, etc.).
   - Clear `w.dirty = false` across rendered widgets.
   - Call `win.swapBuffers()`.

### 6.3 Public Registration API on `UiSystem`
In `yguilib/source/yguilib/uisystem.d`, expose system management so user
applications can register custom systems:

```d
interface WidgetSystemControl {
  void registerWidgetSystem(WidgetSystem system);
  void unregisterWidgetSystem(WidgetSystem system);
  T findWidgetSystem(T : WidgetSystem)();
}

interface UiSystem : ControllerStack, EventControl, FocusControl,
                     WidgetSystemControl {
  @property Window mainWindow();
  void mainEventLoop();
}
```

---

## 7. Concrete Example: User-Defined System

With this architecture, an application can define a custom system (e.g., a
`DebugBoundsSystem` or `PulseAnimationSystem`) without touching `yguilib`
internals:

```d
class DebugHoverHighlightSystem : WidgetSystem {
  this() {
    priority = 100; // Run after WidgetPainterSystem (priority 0)
  }

  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.render;
  }

  override void render(ref WidgetSystemContext ctx) {
    traverseRootToLeaf!((ref VisibleWidget vw) {
      if (vw.widget.inputEnabled) {
        ctx.renderer.drawRect(
          vw.absRect, 1.0f, ColorF(0.0f, 1.0f, 0.0f, 0.4f)
        );
      }
    })(ctx.visibleWidgets);
  }
}

// In application setup:
app.ui.registerWidgetSystem(new DebugHoverHighlightSystem());
```

---

## 8. Step-by-Step Refactoring Plan

1. **Expose Visibility Types (`yguilib.widget`)**:
   - Expose `VisibleWidget` and `VisibleWidgets` in `yguilib.widget` (or
     `yguilib.widget.system`) while keeping `VisibleWidgetsCollector`
     `package(yguilib)`.
2. **Add Custom Component Map to `WidgetComponents`**:
   - Add `set!C(C comp)` and `get!C()` to `WidgetComponents` in
     `yguilib/source/yguilib/widget/package.d` with unit tests.
3. **Create `yguilib.widget.system` Module**:
   - Define `SystemPhase`, `SystemEventResult`, `WidgetSystemContext`,
     `WidgetSystem`, and `TwoPassWidgetSystem`.
4. **Implement `WidgetSystemPipeline`
   (`yguilib.widget.internal.system_pipeline`)**:
   - Manage ordered lists of `WidgetSystem` instances per `SystemPhase`.
   - Centralize `VisibleWidgetsCollector` calls and post-phase `layoutDirty` /
     `dirty` flag clearing.
5. **Refactor `LayoutSystem`, `WidgetPainterSystem`, and `InputSystem`**:
   - Inherit from `WidgetSystem`.
   - Adapt `layoutTree`, `drawTree`, `handleEventAndUpdateView`, and
     `refreshHover` to implement the `WidgetSystem` overrides (keeping existing
     methods as thin wrappers or `package(yguilib)` helpers so existing unit
     tests continue to pass without churn).
6. **Update `UiSystem` & `UiSystemController`**:
   - Add `registerWidgetSystem` / `unregisterWidgetSystem` to `UiSystem` and
     `UiSystemImpl`.
   - Replace hardcoded calls in `UiSystemController` with
     `pipeline.handleEvent(ev)` and `pipeline.updateAndRender()`.
7. **Verify & Test**:
   - Add unit tests for custom user-defined systems across `event`, `preLayout`,
     `layout`, `postLayout`, and `render` phases, verifying execution order and
     dirty flag propagation.
   - Run `ninja -C _build && meson test -C _build`.
