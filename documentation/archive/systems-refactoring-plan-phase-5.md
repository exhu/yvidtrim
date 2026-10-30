# Phase 5: Wire `UiSystem`, `UiSystemImpl` & `UiSystemController`

Part of `documentation/systems-refactoring-plan-overview.md`.

## Goal

1. Expose `WidgetSystemControl` (`registerWidgetSystem`,
   `unregisterWidgetSystem`, and `findWidgetSystem!T`) on `UiSystem` in
   `yguilib/source/yguilib/uisystem.d`.
2. Instantiate `WidgetSystemPipeline` in `UiSystemImpl` with the default
   built-in systems (`FocusSystem`, `InputSystem`, `LayoutSystem`,
   `WidgetPainterSystem`) registered at construction time, and implement
   `WidgetSystemControl`.
3. Refactor `UiSystemController`
   (`yguilib/source/yguilib/internal/uisystem_controller.d`) to delegate widget
   event handling and frame updates/rendering to `WidgetSystemPipeline` instead
   of hardcoding `LayoutSystem`, `WidgetPainterSystem`, `InputSystem`, and
   `VisibleWidgetsCollector`.
4. Add end-to-end integration tests verifying user-defined systems registered
   via `ui.registerWidgetSystem(...)`.

---

## Step-by-Step Instructions

### Step 5.1: Add `WidgetSystemControl` to `yguilib/source/yguilib/uisystem.d`

In `yguilib/source/yguilib/uisystem.d`:
1. Import `WidgetSystem` alongside `WidgetSystemHost` from
   `yguilib.widget.system`.
2. Define `interface WidgetSystemControl` and add it to `interface UiSystem`:
   ```d
   module yguilib.uisystem;
   import yguilib.controller : Controller;
   import yguilib.events : AppEvent;
   import yguilib.widget : Widget, WidgetViewController;
   import yguilib.widget.system : WidgetSystem, WidgetSystemHost;
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

   /// Interface for registering and querying WidgetSystems on UiSystem.
   interface WidgetSystemControl {
     void registerWidgetSystem(WidgetSystem system);
     void unregisterWidgetSystem(WidgetSystem system);
     T findWidgetSystem(T : WidgetSystem)() {
       return cast(T)findWidgetSystemByType(typeid(T));
     }

   protected:
     WidgetSystem findWidgetSystemByType(TypeInfo_Class type);
   }

   /// Manages Controllers, Messaging, Windows, and WidgetSystems.
   interface UiSystem : ControllerStack, WidgetSystemHost, FocusControl,
     WidgetSystemControl {
     @property Window mainWindow();
     void mainEventLoop();
   }
   ```
   *(Note: Because D interfaces cannot have virtual template methods, a final
   template method `findWidgetSystem(T : WidgetSystem)()` on
   `WidgetSystemControl` delegating to the virtual `findWidgetSystemByType`
   method allows callers to write `ui.findWidgetSystem!MySystem()` directly on a
   `UiSystem` interface reference.)*

### Step 5.2: Add `findSystemByType` to `WidgetSystemPipeline`

In `yguilib/source/yguilib/widget/internal/system_pipeline.d`, add a
non-template lookup method alongside `findSystem!T`:

```d
  /// Finds the first registered system matching `type` (or null if none).
  WidgetSystem findSystemByType(TypeInfo_Class type) {
    assert(type !is null);
    foreach (s; systems) {
      if (typeid(s) is type) {
        return s;
      }
    }
    return null;
  }
```

### Step 5.3: Refactor `UiSystemController` to Use `WidgetSystemPipeline`

Update `yguilib/source/yguilib/internal/uisystem_controller.d` to accept
`WidgetSystemPipeline` and delegate `updateView()` and `handleEvent()` to it:

```d
module yguilib.internal.uisystem_controller;

package(yguilib):

import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.uisystem : UiSystem;
import yguilib.widget : WidgetUpdateScope;
import yguilib.widget.internal.system_pipeline : WidgetSystemPipeline;
import yguilib.widget.system : SystemEventResult;

// TODO support multiple windows
final class UiSystemController : DefaultController {
  this(UiSystem uiSystem, WidgetSystemPipeline pipeline) {
    assert(uiSystem !is null);
    assert(pipeline !is null);
    super(uiSystem);
    this.pipeline = pipeline;
  }

  invariant {
    assert(pipeline !is null);
  }

  override bool update() {
    return false;
  }

  /// Actual layout, post-layout, and rendering of the whole app is here.
  override bool updateView() {
    import std.logger : trace;
    trace("render");
    pipeline.updateAndRender(uiSystem.mainWindow);
    // false because we are the ui system layer
    return false;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.updateUiLayer) {
      return HandleResult(HandleResult.Result.updateView);
    }
    if (handleWindowEvent(ev)) {
      return HandleResult(HandleResult.Result.updateView);
    }
    const SystemEventResult sysRes = pipeline.handleEvent(
      ev,
      uiSystem.mainWindow
    );
    if (sysRes.requestUpdateView) {
      return HandleResult(HandleResult.Result.updateView, sysRes.consumed);
    }
    if (sysRes.consumed) {
      return HandleResult(HandleResult.Result.nothing, true);
    }
    return super.handleEvent(ev);
  }

private:
  bool isMainWindowEvent(uint windowId) {
    return (windowId == 0 || uiSystem.mainWindow.id == 0 ||
      windowId == uiSystem.mainWindow.id);
  }

  bool handleWindowEvent(in AppEvent event) {
    if (uiSystem.mainWindow is null) {
      return false;
    }
    if (!event.isWindowEvent()) {
      return false;
    }

    if (isMainWindowEvent(event.window.windowId)) {
      uiSystem.mainWindow.handleWindowEvent(event);
      if (uiSystem.mainWindow.rootWidget !is null &&
          event.isWindowRedrawEvent()) {
        uiSystem.mainWindow.rootWidget.update(WidgetUpdateScope.all);
        return true;
      }
    }
    return false;
  }

  WidgetSystemPipeline pipeline;
}
```

### Step 5.4: Update `UiSystemImpl`

In `yguilib/source/yguilib/internal/uisystem_impl.d`:
1. Import `FocusSystem`, `WidgetSystemPipeline`, and `WidgetSystem`.
2. In `this(Window w)` (note: `w` is allowed to be null in headless tests;
   ensure doc comment states `w` is allowed to be null):
   - Instantiate `pipeline = new WidgetSystemPipeline(this);`.
   - Register the built-in systems:
     ```d
     pipeline.registerSystem(new FocusSystem());
     pipeline.registerSystem(new InputSystem(this));
     pipeline.registerSystem(new LayoutSystem());
     pipeline.registerSystem(new WidgetPainterSystem());
     ```
3. Implement `WidgetSystemControl`:
   ```d
   override void registerWidgetSystem(WidgetSystem system) {
     assert(system !is null);
     pipeline.registerSystem(system);
   }

   override void unregisterWidgetSystem(WidgetSystem system) {
     assert(system !is null);
     pipeline.unregisterSystem(system);
   }

   protected override WidgetSystem findWidgetSystemByType(TypeInfo_Class type) {
     return pipeline.findSystemByType(type);
   }
   ```
4. In `mainEventLoop()`, pass `pipeline` to `new UiSystemController(this,
   pipeline)`:
   ```d
   pushController(new UiSystemController(this, pipeline));
   ```
5. Expose a `package(yguilib) @property WidgetSystemPipeline systemPipeline()`
   accessor on `UiSystemImpl` if helpful for tests.

### Step 5.5: Enable Dirty Gating & Custom System Tests in `uisystem_impl.d`

In `yguilib/source/yguilib/internal/uisystem_impl.d`:
1. Replace the `version(none)` blocks in the `test_dirty_gating` unittest (lines
   852-886) with active assertions using
   `ui.systemPipeline.updateAndRender(win)` (or
   `UiSystemController.updateView()`), verifying:
   - First pass runs layout and render, clearing both `isTreeLayoutDirty()` and
     `isTreeDirty()`.
   - Second pass with clean flags skips layout and render.
   - `root.update(WidgetUpdateScope.visuals)` marks only `dirty` (not
     `layoutDirty`), and `updateAndRender` runs render without re-running
     layout.
2. Add a new `unittest` in `uisystem_impl.d` testing end-to-end registration of
   a custom `WidgetSystem` via `ui.registerWidgetSystem(customSys)` and lookup
   via `ui.findWidgetSystem!CustomTestSystem()`, verifying that custom
   components attached via `w.components.set(new CustomComp(...))` are processed
   during the frame update loop.

---

## Verification

Run the full verification suite:

```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
```
