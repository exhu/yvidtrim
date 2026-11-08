# Widget Lifetime, Ownership, and Automatic Unregistration Plan

## 1. Problem Statement & Root Cause Analysis

In `yguilib/source/yguilib/widget/builder.d:316`, `WidgetBuilder.view()`
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

Currently, `yguilib` has no mechanism to trigger `unregisterViewWidget(widget)`
or any other cleanup when a widget is removed from a tree or no longer needed.

### Why D's GC Destructor (`~this()`) Cannot Solve This

1. **Strong Reference Retention (Catch-22)**:
   Registries and controllers store strong GC references to widgets:
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

### Current Structural Flaws in `Widget`

1. **Constructor Side Effects (`this(Widget parent, RectF rect)`)**:
   `new Widget(parent, rect)` immediately appends `this` to `parent.children`
   and computes `fParentView = findParentView()` *before* any components
   (`ViewComponent`, `Size`, etc.) are attached. `WidgetBuilder.build()` must
   work around this by calling `widget.update(WidgetUpdateScope.parentView)`
   after configuration completes.
2. **Unrestricted Public Graph Fields**:
   `Widget.parent` and `Widget.children` are `public` mutable fields
   (`package.d` lines 316 and 322), relying only on a comment:
   `/// it is not allowed to change after initialization by the end user`.
   Nothing enforces single-parent ownership (`TODO` at `package.d:163`) or
   intercepts child removal.
3. **Manual, One-Way Subscriptions**:
   Callers register widgets in `WidgetView.registerViewWidget`,
   `TabControlWidgetView.bindModel`, and `HoverButtonController.addButton`,
   with no unified teardown path when a page, dialog, or subtree is removed.

---

## 2. Design Goals

1. **Deterministic Main-Thread Lifecycle**:
   Widget attachment, removal, and disposal happen explicitly on the main
   thread with predictable bottom-up cleanup.
2. **Strict Single-Parent Ownership**:
   A `Widget` belongs to at most one `parent` at a time. `parent` and
   `children` are read-only properties outside `yguilib.widget`.
3. **Zero-Boilerplate Unsubscription (Inverted Cleanup)**:
   Registering a widget with a `WidgetView`, model binding, or controller
   automatically attaches a teardown hook to the `Widget`. Removing or
   disposing the widget (or any of its ancestors) automatically invokes all
   unregister/unsubscribe callbacks for the entire subtree.
4. **Fail-Fast Use-After-Dispose Protection**:
   Disposed widgets are marked `disposed` and assert on any subsequent
   mutation or re-attachment.

---

## 3. Question 1: Should `add to parent` Move Out of `Widget` Constructor?

**Yes.** Moving parent attachment out of `Widget.this()` is a foundational
improvement for both ownership safety and lifecycle hooks.

### Problems with Attaching in `this(Widget parent, RectF rect)`

```
Current Flow (Premature Publication):
  WidgetBuilder(parent, rect)
    +-- new Widget(parent, rect)
    |     +-- parent.children ~= this      <-- attached while unconfigured!
    |     +-- fParentView = findParentView() <-- ViewComponent not set yet!
    +-- .view(registry, ...)               <-- registers with WidgetView
    +-- .child(...)                        <-- children added
    +-- .build()
          +-- widget.update(parentView)    <-- fixup pass required
```

### Proposed Construction & Attachment Flow

```
Proposed Flow (Configure Then Attach):
  WidgetBuilder(parent, rect)
    +-- new Widget(rect)                   <-- detached (parent is null)
    +-- .view(registry, ...)               <-- configures ViewComponent
    +-- .child(...)                        <-- builds & attaches child to this
    +-- .build()
          +-- if (targetParent !is null)
                targetParent.addChild(widget) <-- attaches configured subtree,
                                                  resolves fParentView once,
                                                  marks layoutDirty
```

### Benefits of Separating Construction from Attachment

- **Atomic Subtree Attachment**: Composite builders (`HoverButtonBuilder`,
  `TabControlBuilder`) fully construct and configure their internal widget
  subtree before attaching the root to `parent`.
- **Single `parentView` Resolution**: When `parent.addChild(child)` is called at
  the end of `build()`, `child.components.view` and all descendant widgets are
  already present, so `updateParentViews()` and `markLayoutDirty()` run once
  cleanly.
- **Exception & Early-Return Safety**: If building a subtree aborts before
  `.build()`, no half-initialized orphan widget is left inside
  `parent.children`.
- **Symmetric Lifecycle API**: `parent.addChild(w)` and `parent.removeChild(w)`
  form a clear, symmetric ownership boundary.

---

## 4. Question 2: Restricting Widget Lifetime & Guaranteeing Unsubscribe

To ensure all `unregister` and `unsubscribe` methods run when a widget is
removed from the tree—without relying on the user to remember every
subscription—`yguilib` should combine **three mechanisms**:

1. **Encapsulated Tree Ownership & `dispose()`**
2. **Self-Unregistering Cleanup Hooks on `Widget` (Inversion of Control)**
3. **Pipeline / `WidgetSystem` Removal Notifications (`onWidgetRemoved`)**

```
                  parent.removeChild(subtreeRoot)
                         or subtreeRoot.dispose()
                                   |
                                   v
            +---------------------------------------------+
            |   Recursive Post-Order Traversal (Leaves    |
            |   First, Then Root) on Removed Subtree      |
            +---------------------------------------------+
                     |                    |
                     v                    v
     +--------------------------+  +------------------------------+
     | 1. Widget Cleanup Hooks  |  | 2. Component & System Hooks  |
     | (FIFO / LIFO delegates)  |  |                              |
     | - wv.unregisterViewWidget|  | - comp.onDetach(widget)      |
     | - tcv.unbindModel        |  | - InputSystem: clear hover / |
     | - ctrl.removeButton      |  |   pressed capture            |
     | - user custom callbacks  |  | - FocusSystem: clear focus   |
     +--------------------------+  +------------------------------+
                     |                    |
                     +---------+----------+
                               |
                               v
            +---------------------------------------------+
            | 3. Sever References & Mark Disposed         |
            | - fParent = null, fParentView = null        |
            | - fChildren = null, fCleanupHooks = null    |
            | - fState = WidgetState.disposed             |
            | (Zero external strong refs -> GC collects)  |
            +---------------------------------------------+
```

### 4.1. Widget Lifecycle States & Ownership Invariants

Add an explicit lifecycle state to `Widget`:

```d
enum WidgetState : ubyte {
  /// Constructed, not yet attached to a parent (or root of a standalone tree).
  active,
  /// Permanently removed and cleaned up; cannot be mutated or re-attached.
  disposed,
}
```

Ownership rules enforced by `Widget`:
- **`fParent` and `fChildren` are private**:
  Exposed only via `const`/`inout` read-only properties:
  ```d
  @property inout(Widget) parent() inout nothrow @safe {
    return fParent;
  }
  @property inout(Widget[]) children() inout nothrow @safe {
    return fChildren;
  }
  @property bool isDisposed() const nothrow @safe {
    return fState == WidgetState.disposed;
  }
  ```
- **Unique Parent Invariant**:
  `parent.addChild(child)` asserts:
  - `assert(!this.isDisposed, "Cannot add child to disposed widget");`
  - `assert(child !is null, "child must not be null");`
  - `assert(!child.isDisposed, "Cannot attach a disposed widget");`
  - `assert(child.parent is null, "Widget already has a parent");`
  - `assert(child !is this, "Widget cannot be its own parent");`
- **Removal Disposes by Default**:
  In retained-mode UI, removing a widget from its parent almost always means
  destroying that UI element. Therefore:
  - `parent.removeChild(child)` detaches `child` from `parent.fChildren`,
    marks `parent` layout-dirty, and calls `child.dispose()`.
  - `parent.removeAllChildren()` disposes all children and clears `fChildren`.
  - `widget.dispose()` can also be called directly on a root widget (or a
    attached widget, in which case it first removes itself from `fParent`).
  - *(Optional)* If reparenting without disposal is ever needed in the future,
    an explicit `Widget.reparent(Widget newParent)` method can move a live
    subtree without running disposal hooks.

### 4.2. Automatic Unregistration via `addCleanupHook`

Instead of forcing application code to track and call `unregisterViewWidget`,
`removeButton`, etc., `Widget` stores cleanup delegates that execute
automatically when `dispose()` runs:

```d
alias WidgetCleanupHook = void delegate(Widget w);

final class Widget {
  /// Registers a callback invoked automatically when this widget is disposed
  /// (including when removed from its parent or when an ancestor is disposed).
  void addCleanupHook(WidgetCleanupHook hook) {
    assert(!isDisposed, "Cannot add cleanup hook to disposed widget");
    assert(hook !is null, "hook must not be null");
    fCleanupHooks ~= hook;
  }
  // ...
}
```

#### How Library & User Code Uses `addCleanupHook` (The Simple Pattern)

Whenever **any** class stores a reference to a `Widget` (in an array, map, or
controller list), its `register` / `bind` / `add` method immediately attaches
the matching `unregister` / `remove` call to `widget.addCleanupHook`:

1. **`WidgetViewBase.registerViewWidget` (`widget_view.d`)**:
   ```d
   override void registerViewWidget(Widget viewWidget) {
     assert(viewWidget !is null);
     assert(!viewWidget.isDisposed);
     if (isWidgetRegistered(viewWidget)) {
       return;
     }
     viewWidgets ~= viewWidget;
     viewWidget.addCleanupHook((Widget w) {
       unregisterViewWidget(w);
     });
   }
   ```
   - This directly resolves the `TODO` at `builder.d:316`!
   - It also handles `TabControlWidgetView.bindModel(root, tracker)` because
     `TabControlWidgetView.unregisterViewWidget(w)` already calls
     `super.unregisterViewWidget(w)` and `widgetModels.remove(w)`.
   - Calling `registerViewWidget` is idempotent, and when `viewWidget` (or any
     ancestor page/card) is removed from the tree, `unregisterViewWidget` is
     guaranteed to be called automatically.

2. **`HoverButtonController.addButton` (`guidemo/hover_button.d`)**:
   ```d
   void addButton(
     Widget buttonView,
     in HoverAnimConfig animConfig = HoverAnimConfig()
   ) {
     assert(buttonView !is null && !buttonView.isDisposed);
     // ... append to entries ...
     buttonView.addCleanupHook((Widget w) {
       removeButton(w);
     });
   }

   void removeButton(Widget buttonView) {
     import std.algorithm.mutation : remove;
     entries = entries.remove!(e => e.viewWidget is buttonView);
   }
   ```
   - Now the user only calls `hoverButtonController.addButton(btn, cfg)` during
     UI construction. When `btn` or its page is removed, `removeButton(btn)`
     fires automatically—the user cannot forget to unsubscribe!

3. **`WidgetComponent.onDetach(Widget owner)` (`widget/component.d`)**:
   Add a virtual lifecycle hook on `WidgetComponent`:
   ```d
   class WidgetComponent {
     /// Called when the owning widget is disposed.
     void onDetach(Widget owner) {}
   }
   ```
   Custom components holding external resources (e.g. cached textures, timers,
   or subscriptions) clean them up in `onDetach` without needing a separate
   closure allocation.

### 4.3. Cleaning Up Internal `WidgetSystem` References (`InputSystem`, etc.)

Internal systems (`InputSystem`, `FocusSystem`, `WidgetSystemPipeline`) hold
transient pointers to widgets (`hoveredWidgets`, `pressedWidgets`,
`fLastVisibleWidgets`). If a widget is disposed mid-frame (e.g. clicking a
"Delete Tab" or "Close Dialog" button disposes the button itself during event
handling):

1. **`InputSystem` Defensive Check + Cleanup**:
   - In `InputSystem`, ignore any widget where `w.isDisposed` is true (just
     like `!w.inputEnabled`).
   - Add `override void onWidgetDisposed(Widget w)` (or check `w.isDisposed` in
     `handleMouseUp` / `notifyDepartedWidgets`) so `pressedWidgets` and
     `hoveredWidgets` immediately drop references to disposed widgets.
2. **`Window.rootWidget` Property Setter**:
   - Replace the raw public field `Widget rootWidget;` on `Window` with a
     property setter `@property void rootWidget(Widget newRoot)`.
   - When `window.rootWidget` is replaced with a different root (or `null` on
     `Window.destroy()`), the old root widget can either be disposed or
     invalidated cleanly, and `fLastVisibleWidgets` is cleared so stale widgets
     are never retained in `WidgetSystemPipeline`.

---

## 5. Proposed API Changes Summary

### 5.1. `yguilib/source/yguilib/widget/package.d` (`Widget`)

```d
alias WidgetCleanupHook = void delegate(Widget w);

enum WidgetState : ubyte {
  active,
  disposed,
}

final class Widget {
  /// Constructs a standalone widget (parent is null).
  this(RectF rect = RectF.init) {
    this.rect = rect;
  }

  /// Deprecated or internal-only compatibility overload; prefer addChild or
  /// WidgetBuilder(parent, rect).build().
  this(Widget parent, RectF rect) {
    this(rect);
    if (parent !is null) {
      parent.addChild(this);
    }
  }

  /// Attaches `child` to this widget, enforcing single-parent ownership.
  Widget addChild(Widget child) {
    assert(!isDisposed, "Cannot add child to a disposed widget");
    assert(child !is null, "child must not be null");
    assert(!child.isDisposed, "Cannot attach a disposed widget");
    assert(child.fParent is null, "child already belongs to a parent");
    assert(child !is this, "widget cannot parent itself");

    child.fParent = this;
    fChildren ~= child;
    child.updateParentViews();
    markLayoutDirty();
    child.markTreeDirty();
    return child;
  }

  /// Removes `child` from this widget and disposes the `child` subtree,
  /// invoking all registered cleanup/unregister hooks on `child` and its
  /// descendants.
  bool removeChild(Widget child) {
    if (child is null || child.fParent !is this) {
      return false;
    }
    detachChildOnly(child);
    child.dispose();
    return true;
  }

  /// Disposes and removes all children of this widget.
  void removeAllChildren() {
    while (fChildren.length > 0) {
      Widget last = fChildren[$ - 1];
      fChildren = fChildren[0 .. $ - 1];
      last.fParent = null;
      last.fParentView = null;
      last.dispose();
    }
    markLayoutDirty();
  }

  /// Registers a cleanup callback to run when this widget is disposed.
  void addCleanupHook(WidgetCleanupHook hook) {
    assert(!isDisposed, "Cannot add cleanup hook to a disposed widget");
    assert(hook !is null, "hook must not be null");
    fCleanupHooks ~= hook;
  }

  /// Recursively disposes this widget and all descendants (leaves first),
  /// running all cleanup hooks and detaching from parent if still attached.
  void dispose() {
    if (isDisposed) {
      return;
    }
    if (fParent !is null) {
      fParent.detachChildOnly(this);
    }

    // 1. Dispose children bottom-up first
    foreach_reverse (child; fChildren) {
      child.fParent = null;
      child.fParentView = null;
      child.dispose();
    }
    fChildren = null;

    // 2. Run registered cleanup hooks (LIFO order)
    foreach_reverse (hook; fCleanupHooks) {
      hook(this);
    }
    fCleanupHooks = null;

    // 3. Notify attached components
    components.notifyDetach(this);

    // 4. Mark disposed
    fParentView = null;
    fState = WidgetState.disposed;
  }

  @property inout(Widget) parent() inout nothrow @safe {
    return fParent;
  }

  @property inout(Widget[]) children() inout nothrow @safe {
    return fChildren;
  }

  @property bool isDisposed() const nothrow @safe {
    return fState == WidgetState.disposed;
  }

private:
  void detachChildOnly(Widget child) {
    import std.algorithm.mutation : remove;

    fChildren = fChildren.remove!(c => c is child);
    child.fParent = null;
    child.fParentView = null;
    markLayoutDirty();
  }

  Widget fParent;
  Widget[] fChildren;
  Widget fParentView;
  WidgetCleanupHook[] fCleanupHooks;
  WidgetState fState = WidgetState.active;
}
```

### 5.2. `yguilib/source/yguilib/widget/builder.d` (`WidgetBuilder`)

Move parent attachment from `WidgetBuilder.this()` into `WidgetBuilder.build()`:

```d
struct WidgetBuilder {
  /// Constructs a widget builder that will attach to `parent` upon `build()`.
  /// `parent` is allowed to be null.
  this(Widget parent, RectF rect) {
    targetParent = parent;
    widget = new Widget(rect);
  }

  this(RectF rect) {
    targetParent = null;
    widget = new Widget(rect);
  }

  /// Appends and configures a child widget within a scoped delegate.
  ref WidgetBuilder child(
    RectF rect,
    scope void delegate(ref WidgetBuilder) config
  ) return {
    auto b = WidgetBuilder(widget, rect);
    config(b);
    b.build();
    return this;
  }

  Widget build() {
    assert(widget !is null, "WidgetBuilder.build() called on null widget");
    if (targetParent !is null && widget.parent is null) {
      targetParent.addChild(widget);
    } else {
      widget.update(WidgetUpdateScope.parentView);
    }
    return widget;
  }

private:
  Widget targetParent;
  Widget widget;
}
```

And in `WidgetBuilder.view()` (`builder.d:312-319`):
```d
if (registry !is null) {
  if (string name = view.widgetViewName) {
    if (WidgetView wv = registry.widgetViews.getByName(name)) {
      wv.registerViewWidget(widget);
    }
  }
}
```
Because `WidgetViewBase.registerViewWidget(widget)` registers the cleanup hook
on `widget`, the `// TODO unregister on widget removal from a tree` is
completely satisfied without any extra code in `WidgetBuilder`!

### 5.3. `DataSystem` & `WidgetArrayComponent` (`data_system.d`)

Currently, `DataSystem` pools children by hiding excess widgets when
`itemsCount` shrinks (`uw.setVisible(i < c.itemsCount)`).
- When the container widget owning `WidgetArrayComponent` is disposed,
  `Widget.dispose()` automatically disposes all pooled children in
  `w.children`, running any cleanup hooks on item subviews.
- Additionally, `WidgetArrayComponent` can optionally provide a
  `bool disposeExcessWidgets = false` policy (or `shrinkPoolTo(size_t max)`)
  that calls `w.removeChild(w.children[$ - 1])` when dynamic lists want eager
  memory and subscription reclamation instead of pooling.

---

## 6. Usage Patterns & Ownership Rules for Library Users

With this API, users follow three simple rules:

1. **Rule 1 — Always Finish `WidgetBuilder` with `.build()`**:
   - Top-level builders (`WidgetBuilder(parent, rect)...build()`) attach the
     widget to `parent` inside `.build()`.
   - Nested `.child(rect, (ref b) { ... })` delegates call `b.build()`
     automatically when the delegate returns.
2. **Rule 2 — Register Cleanup Inside `register` / `add` Methods**:
   - Any controller or view registry that stores a `Widget` reference must call
     `widget.addCleanupHook((w) => this.unregister(w))` inside its registration
     method.
   - End users building UI trees never need to write manual `unregister` calls.
3. **Rule 3 — Remove Widgets Only via `removeChild` or `dispose`**:
   - Never mutate `children` or `parent` directly (enforced by the compiler via
     read-only properties).
   - If a View class caches a reference to a child widget that it later removes
     via `removeChild(w)`, it should set its cached field to `null`; any
     accidental call to `w.setCaption(...)` or `w.update()` after disposal will
     immediately trigger an `assert(!isDisposed)` failure.

---

## 7. Phased Implementation Plan

### Phase 1: Encapsulate `Widget` Graph & Lifecycle (`widget/package.d`)
- Make `fParent` and `fChildren` private with read-only `@property` getters
  `parent()` and `children()`.
- Add `WidgetState` (`active`, `disposed`), `isDisposed` property, and
  `WidgetCleanupHook` support (`addCleanupHook`).
- Add `this(RectF rect)` constructor, `addChild(Widget)`, `removeChild(Widget)`,
  `removeAllChildren()`, and `dispose()`.
- Add `assert(!isDisposed)` guards in `update()`, `setCaption()`,
  `setBackgroundColor()`, `setTextColor()`, `setBorderColor()`, and
  `setVisible()`.
- Add `void onDetach(Widget owner) {}` to `WidgetComponent` (`component.d`) and
  `notifyDetach(Widget)` in `WidgetComponents`.
- Add unit tests in `yguilib/source/yguilib/widget/package.d` verifying:
  - Single-parent ownership enforcement.
  - Bottom-up disposal order (children before parent).
  - LIFO cleanup hook execution on `removeChild`, `removeAllChildren`, and
    ancestor `dispose()`.
  - Idempotency of calling `dispose()` multiple times.

### Phase 2: Defer Attachment in `WidgetBuilder` (`widget/builder.d`)
- Update `WidgetBuilder.this(Widget parent, RectF rect)` to construct a
  detached `new Widget(rect)` and store `targetParent = parent`.
- Update `WidgetBuilder.child()` to invoke `b.build()` after `config(b)`.
- Update `WidgetBuilder.build()` to call `targetParent.addChild(widget)`.
- Audit all existing `WidgetBuilder` call sites across `yguilib`, `guidemo`,
  and `yvidtrim` to ensure `.build()` is called wherever `WidgetBuilder` is
  instantiated directly (outside `.child(...)`).

### Phase 3: Auto-Unregister in `WidgetView` & Controllers
- Update `WidgetViewBase.registerViewWidget(Widget)` in
  `yguilib/source/yguilib/widget/widget_view.d` to prevent duplicate
  registration and attach a cleanup hook calling `unregisterViewWidget(w)`.
- Remove the `// TODO unregister on widget removal from a tree` comment in
  `yguilib/source/yguilib/widget/builder.d:316`.
- Update `HoverButtonController.addButton` in `source/guidemo/hover_button.d`
  to add `removeButton(Widget)` and register it via `addCleanupHook`.
- Add unit tests in `widget_view.d`, `builder.d`, and `tabcontrol.d` verifying
  that removing a `TabControl` or view widget from its parent automatically
  unregisters it from `WidgetView` and removes its bound `ModelTracker` from
  `TabControlWidgetView.widgetModels`.

### Phase 4: Harden Internal Systems & `Window.rootWidget`
- In `yguilib/source/yguilib/widget/internal/input_system.d`, ignore disposed
  widgets and clear any `pressedWidgets` / `hoveredWidgets` entries whose
  widget is disposed.
- In `yguilib/source/yguilib/window.d`, convert `rootWidget` to a property and
  dispose the root widget tree in `Window.destroy()`.
- Update `ARCHITECTURE.md` to document the single-parent widget ownership and
  automatic cleanup hook lifecycle.

### Phase 5: Verification
- Run `ninja -C _build && meson test -C _build`.
- Run `check-codestyle`, `check-line-length`, `check-boundaries`, and
  `check-null-safety` skills.
