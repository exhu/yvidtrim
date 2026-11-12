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
   - **STATUS: OPEN**.
   - Callers register widgets in `WidgetView.registerViewWidget`,
     `TabControlWidgetView.bindModel`, and `HoverButtonController.addButton`,
     with no automated teardown path when a page, tab, or subtree is removed.

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

## 4. Open Architectural Questions Requiring User Decisions

The following issues are confusing, have conflicting trade-offs, or were
explicitly noted in `TODO.md` as needing architectural decisions:

### Decision 1: Tree Detachment vs. Destruction (`removeChild` vs `dispose`)
*Question:* Should removing a widget from its parent (`removeChild`)
automatically dispose/destroy it, or should detachment and disposal be separate
operations?

- **The Conflict:**
  The initial plan stated:
  `parent.removeChild(child)` detaches `child` and calls `child.dispose()`.
  However, in commit `3ba31cb`, `addChild` explicitly supports reparenting:
  ```d
  if (w.fParent !is null) {
    w.fParent.detachChild(w);
  }
  ```
  If `removeChild` / `detachChild` automatically calls `dispose()`, then:
  1. Reparenting a widget (e.g. moving a tab, dragging a widget, or
     re-docking a panel) would destroy the widget while moving it!
  2. Temporary removal (e.g. hiding/caching views, dynamic virtual list
     scrolling, or swapping tab pages) would destroy widget state and bindings.
- **Alternatives to Decide:**
  - **Option 1A (Explicit separate `dispose()` / `release()`):**
    `removeChild(w)` / `detachChild(w)` only unlinks `w` from its parent.
    A separate `w.dispose()` (or `ui.releaseWidget(w)`) explicitly tears down
    the subtree and unregisters it.
  - **Option 1B (Distinct `detachChild` vs `destroyChild`):**
    `detachChild(w)` unlinks without disposal (for reparenting/caching).
    `destroyChild(w)` / `removeChild(w)` unlinks AND disposes `w`.
  - **Option 1C (Unregister on tree detach, re-register on attach):**
    Detaching a widget unregisters it from active controllers/views; re-adding
    it re-registers. (Note: this requires widgets to retain registration
    metadata or dynamic lifecycle events).

### Decision 2: Where Should Cleanup Logic Live? (`Widget` Hooks vs `UiSystem`)
*Question:* As noted in `TODO.md`:
`UiSystem.releaseWidget(w) instead of hooks and handlers in the Widget itself?`

- **Option 2A (Cleanup Hooks inside `Widget`):**
  Add `fCleanupHooks` array of delegates (`void delegate(Widget w)`) to
  `Widget`. Whenever a view or controller registers a widget, it attaches an
  unregistration callback to `widget.addCleanupHook(...)`.
  - *Pros:* Fully decoupled; `Widget` knows how to clean itself up without
    needing a reference to `UiSystem` or registries.
  - *Cons:* Every widget carries delegate array overhead; closures allocate GC
    memory for delegates; requires careful ordering.
- **Option 2B (Centralized in `UiSystem.releaseWidget(Widget w)`):**
  Since `UiSystem` already owns `ObjectRegistry!WidgetView`,
  `ObjectRegistry!WidgetViewController`, `InputSystem`, and assigns `uId`,
  `UiSystem.releaseWidget(w)` (or `destroyWidget(w)`) traverses the subtree and
  unregisters all matching `Widget` / `uId` entries from registries, views, and
  systems directly.
  - *Pros:* Zero per-widget memory overhead (no delegate slices on `Widget`);
    no closure allocations; centralized control matching `ARCHITECTURE.md`.
  - *Cons:* Widgets cannot be disposed without access to `UiSystem` (though in
    practice, UI widgets are always tied to a `UiSystem`).
- **Option 2C (Hybrid: Component `onDetach` + System Unregistration):**
  `WidgetComponent` provides virtual `void onDetach(Widget owner) {}` for
  component-owned resources, while `UiSystem` handles cross-cutting controller
  and view unregistration.

### Decision 3: Window Root Widget & Detached State (The "Root Marker" Question)
*Question:* As noted in `TODO.md`:
`root marker for Window root widget? (to allow to exist with null parent)`

- Both a `Window` root widget and a freshly created / detached widget have
  `parent is null`.
- If system routines or assertions treat `parent is null` as an orphan or
  detached widget, how should a valid window root be identified?
- **Alternatives to Decide:**
  - Check `window.rootWidget is w` or maintain a pointer in `UiSystem`.
  - Explicit boolean flag or component on the root widget (e.g. `isWindowRoot`
    or `WindowRootComponent`).
  - `Window` registers its root widget with `UiSystem` upon assignment.

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
| Decision 1: Detach vs disposal | **PENDING** | Awaiting user decision. |
| Decision 2: Hooks vs `UiSystem` | **PENDING** | Awaiting user decision. |
| Decision 3: Window root marker | **PENDING** | Awaiting user decision. |
| `HoverButtonController.removeButton`| **PENDING** | Needs implementation. |
| `WidgetView` automated unregister | **PENDING** | Resolves `builder.d:336`. |
| `InputSystem` purge disposed | **PENDING** | Clear stale hover/press. |

---

## 8. Phased Implementation Plan

### Phase 1: Alignment on Architectural Decisions
- Align with project owner on:
  1. Detach vs Disposal semantics (Option 1A vs 1B).
  2. Cleanup model: `Widget.addCleanupHook` vs `UiSystem.releaseWidget`
     (Option 2A vs 2B).
  3. Window root identification strategy.

### Phase 2: Core Lifetime API (`yguilib.widget` or `yguilib.uisystem`)
- Add `WidgetState` (`active`, `disposed`) and `isDisposed` property to
  `Widget`.
- Implement `dispose()` (Option A) or `UiSystem.releaseWidget()` (Option B).
- Add `assert(!isDisposed)` guards in `update()`, `setCaption()`,
  `setBackgroundColor()`, `setTextColor()`, `setBorderColor()`, and
  `setVisible()`.
- Add `void onDetach(Widget owner) {}` to `WidgetComponent` (`component.d`).

### Phase 3: Automated View & Controller Unregistration
- Implement auto-unregistration in `WidgetViewBase` (resolving `builder.d:336`).
- Add `removeButton(Widget)` in `HoverButtonController`.
- Verify `TabControlWidgetView.unregisterViewWidget` properly cleans up
  `widgetModels`.

### Phase 4: System Hardening & Window Teardown
- Update `InputSystem` to ignore disposed widgets and clear stale
  `pressedWidgets` and `hoveredWidgets`.
- In `Window.destroy()`, ensure root widget tree is cleanly disposed/released.
- Clear `WidgetSystemPipeline.fLastVisibleWidgets` on root widget replacement.

### Phase 5: Verification & Skill Checks
- Unit tests verifying:
  - Reparenting without accidental disposal.
  - Subtree teardown bottom-up.
  - Automatic unregistration from `WidgetView` and `HoverButtonController`.
  - Disposed widget mutation assertion guards.
- Run `ninja -C _build && meson test -C _build`.
- Run `check-codestyle`, `check-line-length`, `check-boundaries`, and
  `check-null-safety` skills.
