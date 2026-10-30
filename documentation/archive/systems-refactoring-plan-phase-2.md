# Phase 2: `WidgetSystem` Base Class, Priority Constants & Context

Part of `documentation/systems-refactoring-plan-overview.md`.

## Goal

Create a dedicated public module `yguilib.widget.system`
(`yguilib/source/yguilib/widget/system.d`) defining:
- `WidgetSystemHost` (inheriting `EventControl` from `yguilib.uisystem`)
- `SystemPhase` bitmask enum
- `SystemEventResult` struct
- `WidgetSystemContext` struct
- `WidgetSystem` abstract base class with:
  - Named priority constants (`focusSystemPriority`, `inputSystemPriority`,
    `layoutSystemPriority`, `painterSystemPriority`, `defaultPriority`)
  - Read-only `@property int priority() const nothrow @safe`
  - Phase bitmask property, registration/window lifecycle hooks, phase entry
    points, and `traverseRootToLeaf` / `traverseLeafToRoot` helpers
- `TwoPassWidgetSystem` abstract convenience subclass

Also update `UiSystem` in `yguilib/source/yguilib/uisystem.d` to inherit
`WidgetSystemHost` (which already inherits `EventControl`).

---

## Step-by-Step Instructions

### Step 2.1: Create `yguilib/source/yguilib/widget/system.d`

Create `yguilib/source/yguilib/widget/system.d` with the following contents,
respecting `codestyle.md` (2-space indent, max 80 chars/line, public before
protected before private):

```d
module yguilib.widget.system;

import yguilib.events : AppEvent;
import yguilib.render : Renderer;
import yguilib.uisystem : EventControl;
import yguilib.widget : Widget;
import yguilib.widget.visible : VisibleWidget, VisibleWidgets;
import yguilib.window : Window;

/// Narrow host interface providing UI-system services needed by WidgetSystems.
/// Exposes `sendAppEvent` via `EventControl`.
interface WidgetSystemHost : EventControl {
}

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

/// Shared per-window context passed to WidgetSystem lifecycle methods.
struct WidgetSystemContext {
  /// Host interface; allowed to be null in isolated unit tests.
  WidgetSystemHost host;
  /// Target window; allowed to be null in headless unit tests.
  Window window;
  /// Root widget of the window's widget tree; allowed to be null when empty.
  Widget root;
  /// Window renderer; allowed to be null in layout/input unit tests.
  Renderer renderer;
  /// Visible widgets collected with parent clipping (for event, postLayout,
  /// and render phases).
  VisibleWidgets visibleWidgets;
  /// Visible widgets collected without parent clipping (for layout phase).
  VisibleWidgets unclippedWidgets;
}

/// Base class for all internal and user-defined systems that process
/// the Widget tree.
abstract class WidgetSystem {
  /// Priority constant for FocusSystem (runs before InputSystem in event
  /// phase).
  enum int focusSystemPriority = -100;
  /// Priority constant for InputSystem.
  enum int inputSystemPriority = 0;
  /// Priority constant for LayoutSystem.
  enum int layoutSystemPriority = 0;
  /// Priority constant for WidgetPainterSystem.
  enum int painterSystemPriority = 0;
  /// Default priority for user-defined systems when not specified.
  enum int defaultPriority = 0;

  /// Constructs a WidgetSystem with the given execution priority.
  /// Lower priority values run earlier within the same phase.
  this(int priority = defaultPriority) nothrow @safe {
    fPriority = priority;
  }

  /// Read-only priority within a phase (lower runs earlier).
  @property int priority() const nothrow @safe {
    return fPriority;
  }

  /// Bitmask of SystemPhase values this system is active in.
  @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.none;
  }

  /// Called once when the system is registered with the pipeline.
  /// `host` is allowed to be null in isolated tests.
  void onRegister(WidgetSystemHost host) {}

  /// Called once when the system is unregistered from the pipeline.
  void onUnregister() {}

  /// Called when a window is closed/removed so systems with per-window state
  /// can clean up entries keyed by `window` or `window.id`.
  void onWindowClosed(Window window) {}

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

private:
  int fPriority = defaultPriority;
}

/// Convenience base class for systems that perform a bottom-up (leaf-to-root)
/// pass followed by a top-down (root-to-leaf) pass over `VisibleWidgets`.
abstract class TwoPassWidgetSystem : WidgetSystem {
  this(int priority = defaultPriority) nothrow @safe {
    super(priority);
  }

  void beginPass(ref WidgetSystemContext ctx) {}
  void processLeafToRoot(ref VisibleWidget vw, ref WidgetSystemContext ctx) {}
  void processRootToLeaf(ref VisibleWidget vw, ref WidgetSystemContext ctx) {}
  void endPass(ref WidgetSystemContext ctx) {}

protected:
  final void runTwoPass(
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

### Step 2.2: Add Unit Tests to `yguilib/source/yguilib/widget/system.d`

At the bottom of `yguilib/source/yguilib/widget/system.d`, add unit tests
covering:
1. Default priority (`WidgetSystem.defaultPriority == 0`) and named priority
   constants (`focusSystemPriority`, `inputSystemPriority`,
   `layoutSystemPriority`, `painterSystemPriority`), plus custom priority passed
   to `super(priority)` and read back via the read-only `.priority` property.
2. Default no-op behavior of `onRegister`, `onUnregister`, `onWindowClosed`,
   `handleEvent`, `preLayout`, `layout`, `postLayout`, and `render`.
3. `traverseRootToLeaf` and `traverseLeafToRoot` visitation order over a 3-node
   `VisibleWidgets` slice.
4. `TwoPassWidgetSystem.runTwoPass` execution order (`beginPass` ->
   `processLeafToRoot` in reverse order -> `processRootToLeaf` in forward order
   -> `endPass`).

### Step 2.3: Update `UiSystem` in `yguilib/source/yguilib/uisystem.d`

In `yguilib/source/yguilib/uisystem.d`:
1. Import `WidgetSystemHost` from `yguilib.widget.system`.
2. Update `interface UiSystem` to inherit `WidgetSystemHost` (since
   `WidgetSystemHost : EventControl`, `UiSystem` remains an `EventControl` as
   well):
   ```d
   module yguilib.uisystem;
   import yguilib.controller : Controller;
   import yguilib.events : AppEvent;
   import yguilib.widget : Widget, WidgetViewController;
   import yguilib.widget.system : WidgetSystemHost;
   import yguilib.window : Window;

   interface ControllerStack {
     void popController();
     void pushController(Controller c);
     void pushModalController(Controller c);

     void registerWidgetViewController(WidgetViewController c);
     void unregisterWidgetViewController(WidgetViewController c);
   }

   interface FocusControl {
     void popFocusRoot();
     void pushFocusRoot(Widget w);
   }

   interface EventControl {
     void sendAppEvent(AppEvent ev);
   }

   /// Manages Controllers, Messaging, Windows
   interface UiSystem : ControllerStack, WidgetSystemHost, FocusControl {
     @property Window mainWindow();
     void mainEventLoop();
   }
   ```

### Step 2.4: Register `system.d` in `yguilib/meson.build`

In `yguilib/meson.build`, add `'source/yguilib/widget/system.d'` to
`yguilib_src` in alphabetical order:

```meson
  'source/yguilib/widget/layout_components.d',
  'source/yguilib/widget/package.d',
  'source/yguilib/widget/system.d',
  'source/yguilib/widget/visible.d',
  'source/yguilib/window.d',
```

---

## Verification

Run the following commands and ensure zero errors or warnings:

```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
```
