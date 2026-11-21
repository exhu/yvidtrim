# Widget Lifetime, Ownership, and Automatic Unregistration Plan

## 1. Problem Statement & Root Cause Analysis

In `yguilib/source/yguilib/widget/builder.d:336`, `WidgetBuilder.view()`
registers a widget with a named `WidgetView` in `UiRegistry`:

```d
if (registry !is null) {
  if (string name = view.widgetViewName) {
    if (WidgetView wv = registry.widgetViews.getByName(name)) {
      wv.registerViewWidget(widget);
      // TODO unregister on widget removal from a tree
    }
  }
}
```

Currently, `yguilib` has no automated mechanism to trigger
`unregisterViewWidget(widget)` or any other cleanup when a widget is removed
from a tree or no longer needed.

### 1.1. Why D's GC Destructor (`~this()`) Cannot Solve This

1. **Strong Reference Retention (Catch-22)**:
   Registries, controllers, and internal systems store strong GC references:
   - `WidgetViewBase.viewWidgets` (`Widget[]`)
   - `TabControlWidgetView.widgetModels` (`ModelTracker!TabsModel[Widget]`)
   - `HoverButtonController.entries` (`ButtonEntry[]` holding `Widget`)
   - `InputSystem.hoveredWidgets` and `InputSystem.pressedWidgets`
   - `WidgetSystemPipeline.fLastVisibleWidgets` (`VisibleWidget[]`)
   As long as a widget remains registered in any of these containers, the GC
   considers the `Widget` reachable and will **never** collect it—even if it is
   detached from `parent.children`.
2. **Threading & GC Finalizer Restrictions**:
   By architectural invariant (`ARCHITECTURE.md`), all GUI state and widget
   mutations must happen on the main thread. D class finalizers (`~this()`) run
   non-deterministically on arbitrary threads during GC sweeps and cannot
   safely mutate GC-backed slices or associative arrays (causing
   `InvalidMemoryOperationError`).

### 1.2. Status of Structural Flaws from Earlier Plan Versions

An earlier version of this plan identified several structural flaws in
`Widget`. A review against recent commits shows that several of these have
already been resolved:

1. **Constructor Side Effects (`this(Widget parent, RectF rect)`)**:
   - **STATUS: RESOLVED** in commit `3ba31cb`.
   - `Widget` now has only a single constructor:
     `this(uint uId) { this.uId = uId; }` (with `@disable this();`).
   - It no longer takes `parent` or `rect`. Constructing a `Widget` does not
     mutate any parent widget or trigger layout passes.
2. **Unrestricted Public Graph Fields**:
   - **STATUS: RESOLVED** in commit `3ba31cb`.
   - `fParent` and `fChildren` are private fields in
     `yguilib/source/yguilib/widget/package.d`. They are accessed via read-only
     properties:
     ```d
     @property inout(Widget) parent() inout { return fParent; }
     @property inout(Widget[]) children() inout { return fChildren; }
     ```
   - `addChild(Widget w)`, `removeChild(Widget w)`, and `detachChild(Widget w)`
     enforce single-parent ownership, prevent self-parenting
     (`assert(w !is this)`), and prevent ancestor cycles
     (`assert(!isChildOf(w))`).
3. **Manual, One-Way Subscriptions**:
   - **STATUS: RESOLVED**.
   - Resolved via `UiSystem.releaseWidget(Widget w)` and `Widget.release()`.
     `UiSystem.releaseWidget` traverses the widget hierarchy bottom-up,
     unregisters widgets from `WidgetView` instances, notifies active
     controllers via `onWidgetReleased(Widget)`, purges `InputSystem` caches,
     clears window root widget references, and invokes `w.release()` to detach
     and clear internal component references.

---

## 2. Design Goals

1. **Deterministic Main-Thread Lifecycle**:
   Widget detachment, disposal, and unregistration happen explicitly on the
   main thread with predictable subtree cleanup.
2. **Strict Single-Parent Ownership & Safe Reparenting**:
   A `Widget` belongs to at most one `parent` at a time (already enforced by
   `addChild`). Reparenting a live widget to another parent must be safe and
   must not accidentally destroy the widget.
3. **Zero-Boilerplate Unregistration**:
   Registering a widget with a `WidgetView`, model binding, or controller
   must either automatically unregister upon widget removal/disposal, or be
   tracked centrally by the system.
4. **Clean Root and Detached Subtree Semantics**:
   Subtrees temporarily detached (e.g. inactive tab pages, pooled widgets)
   must not conflict with Window root widgets.
5. **Protection Against Dangling / Use-After-Disposal References**:
   Disposed widgets must fail-fast on mutation and be purged from internal
   system caches (`InputSystem`, `WidgetSystemPipeline`).

---

## 3. Architecture: Resolved Baseline vs. Open Decisions

### 3.1. What Has Landed in the Codebase
- `Widget` constructor only assigns `uId`.
- `parent.addChild(child)` explicitly attaches child widgets.
- `addChild` automatically handles reparenting: if `child` already has a
  parent, it detaches `child` from the previous parent before attaching to
  the new one:
  ```d
  if (w.fParent is this) return;
  if (w.fParent !is null) {
    w.fParent.detachChild(w);
  }
  w.fParent = this;
  fChildren ~= w;
  ```
- `WidgetBuilder` is constructed with `this(uint uId)` and uses fluent methods
  `.parent(Widget)`, `.rect(RectF)`, and `.child(uint childId, ...)`.

---

## 4. Architectural Decisions and Implemented Solutions

The following issues were evaluated and resolved:

### Decision 1: Tree Detachment vs. Destruction (`removeChild` vs `release`)
*Resolution:* **Option 1A (Explicit separate `release()` / `releaseWidget()`)**.
- `removeChild(w)` / `detachChild(w)` only unlinks `w` from its parent,
  supporting reparenting without destroying widget state or triggering disposal.
- `w.release()` clears the widget's own internal fields and components.
- Complete subtree destruction and cross-system unregistration is explicitly
  driven by `UiSystem.releaseWidget(Widget w)`.

### Decision 2: Where Cleanup Logic Lives (`Widget` vs `UiSystem`)
*Resolution:* **Option 2B (Centralized in `UiSystem.releaseWidget(Widget w)`)**.
- `UiSystem.releaseWidget(Widget w)` traverses the hierarchy bottom-up
  (post-order traversal), recursively releasing children first.
- For each widget, it unregisters from all registered `WidgetView` instances,
  notifies active controllers via `onWidgetReleased(Widget w)`, clears
  pipeline/input system caches (`InputSystem.onWidgetReleased`), and sets
  `window.rootWidget` to null if releasing the root widget.
- Individual `Widget.release()` is restricted to clearing its own fields
  (`fChildren = null`, `components.clear()`, detaching from parent, and setting
  `fReleased = true`).
- Zero delegate/closure memory overhead per widget.

### Decision 3: Window Root Widget & Detached State
*Resolution:* **Tracked via `fMainWindow.rootWidget`**.
- When `UiSystem.releaseWidget(w)` is called, it checks if
  `fMainWindow.rootWidget is w` and nulls it out.
- Widgets with `parent is null` can safely exist detached or as root widgets
  until explicitly released.

### Decision 4: Lifecycle Hook Behavior During Controller/View Teardown
*Question:* When a controller or page is destroyed, who initiates
unregistration?
- If the controller is popped from `ControllerStack`, should it unregister its
  associated views and widgets?
- Or does the widget tree own the lifetime, and popping a controller leaves the
  widget tree alive for another controller to bind?

### Decision 4: Lifecycle Hook Behavior During Controller/View Teardown
*Question:* When a controller or page is destroyed, who initiates
unregistration?
- If the controller is popped from `ControllerStack`, should it unregister its
  associated views and widgets?
- Or does the widget tree own the lifetime, and popping a controller leaves the
  widget tree alive for another controller to bind?

---

## 5. Comparative Architectural Flows

```
=============================================================================
Option A: Widget-Autonomous Disposal (Delegates on Widget)
=============================================================================

                 caller invokes: widget.dispose()
                                |
                                v
               +----------------------------------+
               | Recursive Post-Order Traversal   |
               | (Children First, Then This)      |
               +----------------------------------+
                                |
               +----------------+----------------+
               |                                 |
               v                                 v
   +-----------------------+         +-----------------------+
   | Execute Cleanup Hooks |         | Component Detach      |
   | - wv.unregisterView   |         | - comp.onDetach(w)    |
   | - ctrl.removeButton   |         +-----------------------+
   | - tcv.unbindModel     |                     |
   +-----------------------+                     |
               |                                 |
               +----------------+----------------+
                                |
                                v
               +----------------------------------+
               | Sever Graph References           |
               | - fParent = null, fChildren=null |
               | - fState = WidgetState.disposed  |
               | - GC collects once unlinked      |
               +----------------------------------+

=============================================================================
Option B: Centralized UiSystem Release (Subsystem Registry Cleanup)
=============================================================================

              caller invokes: uiSystem.releaseWidget(w)
                                |
                                v
               +----------------------------------+
               | UiSystem Subtree Traversal       |
               +----------------------------------+
                                |
               +----------------+----------------+
               |                                 |
               v                                 v
   +-----------------------+         +-----------------------+
   | UiSystem Registries   |         | Pipeline & Systems    |
   | - For each WidgetView |         | - InputSystem: clear  |
   |   unreg if registered |         |   hover/pressed refs  |
   | - For each Controller |         | - Clear last visible  |
   |   unreg if registered |         |   pipeline caches     |
   +-----------------------+         +-----------------------+
                                |
                                v
               +----------------------------------+
               | Detach & Invalidate              |
               | - parent.detachChild(w)          |
               | - mark w.isDisposed = true       |
               +----------------------------------+
```

---

## 6. Revised Proposed API Adjustments

### 6.1. `Widget` State and Ownership (`widget/package.d`)

Regardless of whether Option A or Option B is chosen:

```d
enum WidgetState : ubyte {
  active,
  disposed,
}

final class Widget {
  // Existing:
  @disable this();
  this(uint uId) { this.uId = uId; }

  @property inout(Widget) parent() inout { return fParent; }
  @property inout(Widget[]) children() inout { return fChildren; }
  @property bool isDisposed() const nothrow @safe {
    return fState == WidgetState.disposed;
  }

  // Existing methods:
  void addChild(Widget w);
  bool removeChild(Widget w);
  void detachChild(Widget w);

  // Proposed additions:
  void dispose(); // (Or uiSystem.releaseWidget(w))

  // Guards on mutations:
  // assert(!isDisposed, "Cannot mutate a disposed widget");
}
```

### 6.2. `WidgetViewBase` Unregistration Pattern (`widget_view.d`)

`WidgetViewBase` already implements `unregisterViewWidget(Widget viewWidget)`.

If using cleanup hooks (Option A):
```d
override void registerViewWidget(Widget viewWidget) {
  assert(viewWidget !is null);
  if (isWidgetRegistered(viewWidget)) {
    return;
  }
  viewWidgets ~= viewWidget;
  viewWidget.addCleanupHook((Widget w) {
    unregisterViewWidget(w);
  });
}
```

If using centralized `UiSystem` (Option B):
`UiSystem.releaseWidget(w)` calls `wv.unregisterViewWidget(w)` for all
registered views where `wv.isWidgetRegistered(w)` is true.

### 6.3. `HoverButtonController` Cleanup

Add explicit `removeButton(Widget viewWidget)` to `HoverButtonController`:
```d
void removeButton(Widget viewWidget) {
  import std.algorithm.mutation : remove;
  entries = entries.remove!(e => e.viewWidget is viewWidget);
}
```
Depending on Decision 2, this is called either via `buttonView.addCleanupHook`
or by `UiSystem.releaseWidget`.

### 6.4. `DataSystem` & `WidgetArrayComponent`

Currently, `DataSystem` pools children by toggling visibility when `itemsCount`
shrinks (`uw.setVisible(i < c.itemsCount)`).
- When a container widget owning `WidgetArrayComponent` is disposed or
  released, all pooled children in `w.children` are disposed/released bottom-up.
- `WidgetArrayComponent` can optionally support eager reclamation
  (`shrinkPoolTo(size_t max)`) calling `w.removeChild(w.children[$ - 1])`
  when dynamic lists want immediate memory and binding unregistration instead
  of pooling.

---

## 7. Status Matrix & Next Steps

| Task / Feature | Status | Notes |
| :--- | :--- | :--- |
| Constructor `this(uint uId)` | **DONE** | In `3ba31cb`. |
| Private `fParent`, `fChildren` | **DONE** | In `3ba31cb`. |
| Single-parent check in `addChild` | **DONE** | In `3ba31cb`. |
| Reparenting in `addChild` | **DONE** | In `3ba31cb`. |
| Decision 1: Detach vs disposal | **DONE** | Resolved Option 1A. |
| Decision 2: Hooks vs `UiSystem` | **DONE** | Resolved Option 2B. |
| Decision 3: Window root marker | **DONE** | Handled in `releaseWidget`. |
| `HoverButtonController.removeButton`| **DONE** | Implemented. |
| `WidgetView` automated unregister | **DONE** | `UiSystem.releaseWidget`. |
| `InputSystem` purge disposed | **DONE** | `onWidgetReleased`. |

---

## 8. Phased Implementation Plan

### Phase 1: Alignment on Architectural Decisions
- **DONE**: Resolved Option 1A (detach vs release) and Option 2B (centralized
  `UiSystem.releaseWidget`).

### Phase 2: Core Lifetime API (`yguilib.widget` & `yguilib.uisystem`)
- **DONE**: Added `Widget.release()` and `released` property.
- **DONE**: Added defensive / assertion checks in `addChild`, `update`,
  `setCaption`, `setBackgroundColor`, `setTextColor`, `setBorderColor`,
  `setVisible`, and `setScrollOffset`.
- **DONE**: Added `WidgetComponents.clear()`.

### Phase 3: Automated View & Controller Unregistration
- **DONE**: Added `unregisterViewWidget(Widget)` to `WidgetViewController` and
  `WidgetViewControllerBase`.
- **DONE**: Added `onWidgetReleased(Widget)` to `Controller` and
  `WidgetViewControllerBase`.
- **DONE**: Added `removeButton(Widget)` and `onWidgetReleased(Widget)` in
  `HoverButtonController`.
- **DONE**: Implemented `UiSystem.releaseWidget(Widget w)` with post-order
  traversal, view unregistration, and controller notification.

### Phase 4: System Hardening & Window Teardown
- **DONE**: Updated `InputSystem.onWidgetReleased` to clear hovered and pressed
  widget references.
- **DONE**: Cleared window root widget reference when releasing window root.
- **DONE**: Cleared collector scratch buffer in pipeline.

### Phase 5: Verification & Skill Checks
- **DONE**: Unit tests for `Widget.release`, `UiSystem.releaseWidget`,
  `HoverButtonController`, `AnimatedHoverButtonSystem`, and
  `TabControlWidgetView`.
- **DONE**: Passed build and test suites.
