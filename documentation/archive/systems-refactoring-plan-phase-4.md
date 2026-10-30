# Phase 4: Implement `WidgetSystemPipeline`

Part of `documentation/systems-refactoring-plan-overview.md`.

## Goal

Create a dedicated internal module `yguilib.widget.internal.system_pipeline`
(`yguilib/source/yguilib/widget/internal/system_pipeline.d`) that implements
`WidgetSystemPipeline` to:
1. Manage registration, unregistration, and typed lookup (`findSystem!T`) of
   `WidgetSystem` instances.
2. Maintain phase-specific lists sorted in stable ascending order of
   `system.priority`.
3. Orchestrate the five execution phases (`event`, `preLayout`, `layout`,
   `postLayout`, `render`) for a window or headless test context.
4. Centralize `VisibleWidgetsCollector` invocations and post-phase
   `layoutDirty` / `dirty` flag synchronization.

---

## Step-by-Step Instructions

### Step 4.1: Create `yguilib/source/yguilib/widget/internal/system_pipeline.d`

Create `yguilib/source/yguilib/widget/internal/system_pipeline.d` with
`package(yguilib):` visibility:

```d
module yguilib.widget.internal.system_pipeline;

package(yguilib):

import std.array : Appender;
import yguilib.events : AppEvent;
import yguilib.render : Renderer;
import yguilib.render.render_types : RectF;
import yguilib.widget : Widget;
import yguilib.widget.internal.collect_visible : VisibleWidgetsCollector;
import yguilib.widget.system : SystemEventResult, SystemPhase,
  WidgetSystem, WidgetSystemContext, WidgetSystemHost;
import yguilib.widget.visible : VisibleWidget, VisibleWidgets;
import yguilib.window : Window;

/// Orchestrates registered WidgetSystems across event, preLayout, layout,
/// postLayout, and render phases.
final class WidgetSystemPipeline {
  this(WidgetSystemHost host) {
    assert(host !is null);
    this.host = host;
    this.collector = new VisibleWidgetsCollector;
  }

  invariant {
    assert(host !is null);
    assert(collector !is null);
  }

  /// Registers a system, inserts it in priority order, and calls onRegister.
  void registerSystem(WidgetSystem system) {
    assert(system !is null);
    foreach (s; systems) {
      if (s is system) {
        return;
      }
    }
    insertSorted(systems, system);
    rebuildPhaseLists();
    system.onRegister(host);
  }

  /// Unregisters a system and calls onUnregister.
  void unregisterSystem(WidgetSystem system) {
    assert(system !is null);
    size_t removeIdx = systems.length;
    foreach (i, s; systems) {
      if (s is system) {
        removeIdx = i;
        break;
      }
    }
    if (removeIdx == systems.length) {
      return;
    }
    foreach (i; removeIdx .. systems.length - 1) {
      systems[i] = systems[i + 1];
    }
    systems = systems[0 .. $ - 1];
    rebuildPhaseLists();
    system.onUnregister();
  }

  /// Finds the first registered system of type T (or null if none).
  T findSystem(T : WidgetSystem)() {
    foreach (s; systems) {
      if (auto match = cast(T)s) {
        return match;
      }
    }
    return null;
  }

  /// Notifies all registered systems that a window has closed.
  void notifyWindowClosed(Window window) {
    assert(window !is null);
    foreach (s; systems) {
      s.onWindowClosed(window);
    }
  }

  /// Returns the cached clipped visible widgets from the last layout pass.
  @property VisibleWidgets lastVisibleWidgets() {
    return fLastVisibleWidgets;
  }

  /// Dispatches an AppEvent through all SystemPhase.event systems in priority
  /// order. Stops early if a system sets `result.consumed = true`.
  /// Note: `window` is allowed to be null in headless unit tests.
  SystemEventResult handleEvent(in AppEvent event, Window window = null) {
    WidgetSystemContext ctx = makeContext(window);
    SystemEventResult aggregate;

    foreach (s; eventSystems) {
      const SystemEventResult res = s.handleEvent(event, ctx);
      if (res.requestUpdateView) {
        aggregate.requestUpdateView = true;
      }
      if (res.consumed) {
        aggregate.consumed = true;
        break;
      }
    }
    return aggregate;
  }

  /// Runs preLayout, layout (if tree layout is dirty), postLayout, and render
  /// (if tree is dirty) for `window`, followed by `window.swapBuffers()`.
  void updateAndRender(Window window) {
    if (window is null) {
      return;
    }
    if (window.rootWidget !is null && window.renderer !is null) {
      updateAndRenderTree(window, window.rootWidget, window.renderer);
    }
    window.swapBuffers();
  }

  /// Runs preLayout, layout, postLayout, and render on an explicit `(root, r)`
  /// pair without calling `window.swapBuffers()`. Useful for unit testing.
  /// `window` is allowed to be null.
  void updateAndRenderTree(Window window, Widget root, Renderer r) {
    assert(root !is null);
    assert(r !is null);

    WidgetSystemContext ctx;
    ctx.host = host;
    ctx.window = window;
    ctx.root = root;
    ctx.renderer = r;
    ctx.visibleWidgets = fLastVisibleWidgets;

    runPreLayoutPhase(ctx);
    runLayoutAndPostLayoutPhases(ctx);
    runRenderPhase(ctx);
  }

private:
  WidgetSystemContext makeContext(Window window) {
    WidgetSystemContext ctx;
    ctx.host = host;
    ctx.window = window;
    if (window !is null) {
      ctx.root = window.rootWidget;
      ctx.renderer = window.renderer;
    }
    ctx.visibleWidgets = fLastVisibleWidgets;
    return ctx;
  }

  void runPreLayoutPhase(ref WidgetSystemContext ctx) {
    foreach (s; preLayoutSystems) {
      s.preLayout(ctx);
    }
  }

  void runLayoutAndPostLayoutPhases(ref WidgetSystemContext ctx) {
    if (!ctx.root.isTreeLayoutDirty() && fLastVisibleWidgets.length > 0) {
      return;
    }

    ctx.unclippedWidgets = collector.collectVisible(
      ctx.root,
      ctx.renderer,
      true
    );

    snapshotRects(ctx.unclippedWidgets);

    foreach (s; layoutSystems) {
      s.layout(ctx);
    }

    syncDirtyAfterLayout(ctx.root, ctx.unclippedWidgets);

    fLastVisibleWidgets = collector.collectVisible(
      ctx.root,
      ctx.renderer,
      false
    );
    ctx.visibleWidgets = fLastVisibleWidgets;

    foreach (s; postLayoutSystems) {
      s.postLayout(ctx);
    }
  }

  void runRenderPhase(ref WidgetSystemContext ctx) {
    if (!ctx.root.isTreeDirty()) {
      return;
    }

    foreach (s; renderSystems) {
      s.render(ctx);
    }

    clearDirtyAfterRender(ctx.root, ctx.visibleWidgets);
  }

  void snapshotRects(VisibleWidgets widgets) {
    oldRectBuf.clear();
    foreach (ref vw; widgets) {
      oldRectBuf ~= vw.widget.rect;
    }
  }

  void syncDirtyAfterLayout(Widget root, VisibleWidgets unclipped) {
    const RectF[] oldRects = oldRectBuf[];
    foreach (size_t i, ref vw; unclipped) {
      if (i < oldRects.length && vw.widget.rect != oldRects[i]) {
        vw.widget.dirty = true;
      }
      vw.widget.layoutDirty = false;
    }
    clearTreeLayoutDirty(root);
  }

  static void clearTreeLayoutDirty(Widget w) {
    if (w is null || !w.visible) {
      return;
    }
    w.layoutDirty = false;
    foreach (child; w.children) {
      clearTreeLayoutDirty(child);
    }
  }

  static void clearDirtyAfterRender(Widget root, VisibleWidgets visible) {
    foreach (ref vw; visible) {
      vw.widget.dirty = false;
    }
    clearTreeDirty(root);
  }

  static void clearTreeDirty(Widget w) {
    if (w is null || !w.visible) {
      return;
    }
    w.dirty = false;
    foreach (child; w.children) {
      clearTreeDirty(child);
    }
  }

  static void insertSorted(ref WidgetSystem[] list, WidgetSystem item) {
    size_t insertPos = list.length;
    foreach (i, existing; list) {
      if (item.priority < existing.priority) {
        insertPos = i;
        break;
      }
    }
    list ~= item;
    for (size_t i = list.length - 1; i > insertPos; --i) {
      list[i] = list[i - 1];
    }
    list[insertPos] = item;
  }

  void rebuildPhaseLists() {
    eventSystems = filterByPhase(SystemPhase.event);
    preLayoutSystems = filterByPhase(SystemPhase.preLayout);
    layoutSystems = filterByPhase(SystemPhase.layout);
    postLayoutSystems = filterByPhase(SystemPhase.postLayout);
    renderSystems = filterByPhase(SystemPhase.render);
  }

  WidgetSystem[] filterByPhase(SystemPhase phase) {
    WidgetSystem[] res;
    foreach (s; systems) {
      if ((s.phases & phase) != 0) {
        res ~= s;
      }
    }
    return res;
  }

  WidgetSystemHost host;
  VisibleWidgetsCollector collector;
  VisibleWidgets fLastVisibleWidgets;
  Appender!(RectF[]) oldRectBuf;

  WidgetSystem[] systems;
  WidgetSystem[] eventSystems;
  WidgetSystem[] preLayoutSystems;
  WidgetSystem[] layoutSystems;
  WidgetSystem[] postLayoutSystems;
  WidgetSystem[] renderSystems;
}
```

### Step 4.2: Add Unit Tests to `system_pipeline.d`

At the bottom of `yguilib/source/yguilib/widget/internal/system_pipeline.d`,
add comprehensive unit tests covering:
1. **Priority Sorting & Registration Lifecycle**:
   - Register systems with priorities `10`, `WidgetSystem.focusSystemPriority`
     (`-100`), `0`, and `-10`.
   - Verify `onRegister` is called with `host`, systems execute in ascending
     priority order (`-100`, `-10`, `0`, `10`), `findSystem!T` locates
     registered systems, and `unregisterSystem` calls `onUnregister` and stops
     further invocations.
2. **Event Phase Consumption & View Update Aggregation**:
   - Register two event systems: first returns `requestUpdateView = true,
     consumed = false`; second returns `consumed = true`; third should not be
     called because the second consumed the event.
   - Verify `pipeline.handleEvent(ev)` returns `SystemEventResult(true, true)`.
3. **Full Frame Pipeline & Dirty Flag Separation**:
   - Create an SDL3 window and `Renderer` (matching existing tests in
     `widget_painter.d`), register `LayoutSystem`, `InputSystem`,
     `WidgetPainterSystem`, plus custom systems in `preLayout`, `layout`
     (priority `10`), `postLayout` (priority `10`), and `render` (priority
     `100`).
   - Verify that during `layout`, the custom layout system runs after
     `LayoutSystem` and before `layoutDirty` is cleared.
   - Verify that during `render`, the custom render system runs after
     `WidgetPainterSystem` while `w.dirty` is still `true`, and `w.dirty` is
     cleared after all `render` systems finish.
   - Verify that a subsequent `updateAndRenderTree` call when neither
     `isTreeLayoutDirty()` nor `isTreeDirty()` is true skips `layout`,
     `postLayout`, and `render` (while still running `preLayout`).

### Step 4.3: Register `system_pipeline.d` in `yguilib/meson.build`

In `yguilib/meson.build`, add
`'source/yguilib/widget/internal/system_pipeline.d'` to `yguilib_src` in
alphabetical order:

```meson
  'source/yguilib/widget/internal/layout_text.d',
  'source/yguilib/widget/internal/system_pipeline.d',
  'source/yguilib/widget/internal/text_label_cache.d',
  'source/yguilib/widget/internal/widget_painter.d',
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
