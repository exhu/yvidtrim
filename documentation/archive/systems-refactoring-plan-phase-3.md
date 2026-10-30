# Phase 3: Adapt Core Systems to Inherit `WidgetSystem`

Part of `documentation/systems-refactoring-plan-overview.md`.

## Goal

Refactor the four existing widget systems in
`yguilib/source/yguilib/widget/internal/` (`FocusSystem`, `InputSystem`,
`LayoutSystem`, and `WidgetPainterSystem`) to:
1. Inherit from `WidgetSystem` (or `TwoPassWidgetSystem`).
2. Initialize their read-only `priority` property using the named constants
   defined in `WidgetSystem` (`focusSystemPriority`, `inputSystemPriority`,
   `layoutSystemPriority`, `painterSystemPriority`) instead of magic numbers.
3. Implement `phases` and the corresponding `WidgetSystem` phase methods
   (`handleEvent`, `layout`, `postLayout`, `render`).
4. Decouple `InputSystem` from the full `UiSystem` interface so it accepts
   `WidgetSystemHost` (and simplify `TestUiSystem` in `input_system.d` to a
   1-method `WidgetSystemHost` stub).
5. Preserve existing helper entry points (`handleEventAndUpdateView`,
   `refreshHover`, `layoutTree`, `drawTree`) so `UiSystemController` and all
   existing unit tests continue to compile and pass without regressions.

---

## Step-by-Step Instructions

### Step 3.1: Refactor `FocusSystem`

Update `yguilib/source/yguilib/widget/internal/focus_system.d` so `FocusSystem`
inherits `WidgetSystem` with `focusSystemPriority`:

```d
module yguilib.widget.internal.focus_system;

package(yguilib):

import yguilib.events : AppEvent;
import yguilib.widget : Widget;
import yguilib.widget.system : SystemEventResult, SystemPhase,
  WidgetSystem, WidgetSystemContext;
import yguilib.widget.visible : VisibleWidget, VisibleWidgets;

final class FocusSystem : WidgetSystem {
  // TODO needs to cache widgets to map distance, detect which widget is
  // next/prev in focusing for convenient arrow/gamepad navigation
  // TODO support focus root (i.e. cycle focus only inside a subtree,
  // e.g. an active dialog)

  this() nothrow @safe {
    super(focusSystemPriority);
  }

  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.event;
  }

  override SystemEventResult handleEvent(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    const bool updated = handleEventAndUpdateView(event, ctx.visibleWidgets);
    return SystemEventResult(false, updated);
  }

  /// returns true on focus change
  bool handleEventAndUpdateView(in AppEvent event, VisibleWidgets widgets) {
    // TODO focus on mouse click
    // TODO focus on tab, shift-tab
    return false;
  }
}
```

### Step 3.2: Refactor `InputSystem`

In `yguilib/source/yguilib/widget/internal/input_system.d`:
1. Replace `import yguilib.uisystem : UiSystem;` with:
   ```d
   import yguilib.widget.system : SystemEventResult, SystemPhase,
     WidgetSystem, WidgetSystemContext, WidgetSystemHost;
   ```
2. Update `final class InputSystem` to inherit `WidgetSystem` and initialize its
   priority with `inputSystemPriority`:
   ```d
   final class InputSystem : WidgetSystem {
     this(WidgetSystemHost host) {
       assert(host !is null);
       super(inputSystemPriority);
       this.host = host;
       this.focusSystem = new FocusSystem;
     }

     invariant {
       assert(host !is null);
       assert(focusSystem !is null);
     }

     override @property SystemPhase phases() const nothrow @safe {
       return SystemPhase.event | SystemPhase.postLayout;
     }

     override void onRegister(WidgetSystemHost newHost) {
       if (newHost !is null) {
         host = newHost;
       }
     }

     override SystemEventResult handleEvent(
       in AppEvent event,
       ref WidgetSystemContext ctx
     ) {
       const bool updateView = handleEventAndUpdateView(
         event,
         ctx.visibleWidgets
       );
       return SystemEventResult(false, updateView);
     }

     override void postLayout(ref WidgetSystemContext ctx) {
       refreshHover(ctx.visibleWidgets);
     }
   ```
3. Change `uiSystem.sendAppEvent(event);` in `passEvent` to
   `host.sendAppEvent(event);`, and rename the private field `UiSystem uiSystem`
   to `WidgetSystemHost host`.
4. Also change the parameter of `handleEventAndUpdateView` from `AppEvent event`
   to `in AppEvent event` so it can be called directly from `handleEvent(in
   AppEvent event, ...)`.
5. In `version (unittest)`, simplify `TestUiSystem` to implement
   `WidgetSystemHost` instead of `UiSystem`:
   ```d
   version (unittest) {
     class TestUiSystem : WidgetSystemHost {
       AppEvent[] sentEvents;
       override void sendAppEvent(AppEvent ev) {
         sentEvents ~= ev;
       }
     }
   }
   ```
6. Add a `unittest` verifying `inputSys.priority ==
   WidgetSystem.inputSystemPriority`, `inputSys.phases == (SystemPhase.event |
   SystemPhase.postLayout)`, and calling `inputSys.handleEvent(ev, ctx)` and
   `inputSys.postLayout(ctx)`.

### Step 3.3: Refactor `LayoutSystem`

In `yguilib/source/yguilib/widget/internal/layout_system.d`:
1. Import `SystemPhase`, `TwoPassWidgetSystem`, `WidgetSystemContext` from
   `yguilib.widget.system`:
   ```d
   import yguilib.widget.system : SystemPhase, TwoPassWidgetSystem,
     WidgetSystemContext;
   ```
2. Update `final class LayoutSystem` to inherit `TwoPassWidgetSystem` with
   `layoutSystemPriority`:
   ```d
   final class LayoutSystem : TwoPassWidgetSystem {
     this() nothrow @safe {
       super(layoutSystemPriority);
     }

     override @property SystemPhase phases() const nothrow @safe {
       return SystemPhase.layout;
     }

     override void layout(ref WidgetSystemContext ctx) {
       if (ctx.root is null || !ctx.root.visible ||
           ctx.unclippedWidgets.length == 0) {
         return;
       }
       runTwoPass(ctx.unclippedWidgets, ctx);
     }

     override void processLeafToRoot(
       ref VisibleWidget vw,
       ref WidgetSystemContext ctx
     ) {
       handleSizeComp(vw, ctx.renderer);
     }

     override void processRootToLeaf(
       ref VisibleWidget vw,
       ref WidgetSystemContext ctx
     ) {
       handleAnchorComp(vw);
       handleFlexContainerComp(vw, ctx.renderer);
     }
   ```
3. Update `layoutTree(Widget root, Renderer r, VisibleWidgets visibleWidgets)`
   so it delegates the two-pass traversal to `layout(ctx)` while keeping the
   standalone `oldRectBuf` snapshot and `dirty` / `layoutDirty` update for
   direct callers (such as existing unit tests and `UiSystemController` until
   Phase 5):
   ```d
     /// expects visibleWidgets to include clipped children as well
     void layoutTree(Widget root, Renderer r, VisibleWidgets visibleWidgets) {
       assert(root !is null);
       assert(r !is null);
       assert(visibleWidgets !is null);

       if (!root.visible || visibleWidgets.length == 0) {
         return;
       }

       oldRectBuf.clear();
       foreach (ref vw; visibleWidgets) {
         oldRectBuf ~= vw.widget.rect;
       }
       const RectF[] oldRects = oldRectBuf[];

       WidgetSystemContext ctx;
       ctx.root = root;
       ctx.renderer = r;
       ctx.unclippedWidgets = visibleWidgets;
       layout(ctx);

       // Mark dirty if rect changed, and reset layoutDirty
       foreach (size_t i, ref vw; visibleWidgets) {
         if (vw.widget.rect != oldRects[i]) {
           vw.widget.dirty = true;
         }
         vw.widget.layoutDirty = false;
       }
       root.layoutDirty = false;
     }
   ```
   *(Note: `layout(ctx)` itself does NOT clear `layoutDirty`, allowing
   `WidgetSystemPipeline` in Phase 4 to run multiple `SystemPhase.layout`
   systems before syncing dirty flags.)*
4. Add a `unittest` verifying `ls.priority ==
   WidgetSystem.layoutSystemPriority` and `ls.phases == SystemPhase.layout`.

### Step 3.4: Refactor `WidgetPainterSystem`

In `yguilib/source/yguilib/widget/internal/widget_painter.d`:
1. Import `SystemPhase`, `WidgetSystem`, `WidgetSystemContext` from
   `yguilib.widget.system`:
   ```d
   import yguilib.widget.system : SystemPhase, WidgetSystem,
     WidgetSystemContext;
   ```
2. Update `final class WidgetPainterSystem` to inherit `WidgetSystem` with
   `painterSystemPriority`:
   ```d
   final class WidgetPainterSystem : WidgetSystem {
     this() nothrow @safe {
       super(painterSystemPriority);
     }

     override @property SystemPhase phases() const nothrow @safe {
       return SystemPhase.render;
     }

     override void render(ref WidgetSystemContext ctx) {
       if (ctx.renderer is null || ctx.visibleWidgets.length == 0) {
         return;
       }
       drawWidgets(ctx.visibleWidgets, ctx.renderer);
     }

     void drawTree(VisibleWidgets widgets, Renderer r) {
       assert(widgets !is null);
       assert(r !is null);

       drawWidgets(widgets, r);
       foreach (ref vw; widgets) {
         vw.widget.dirty = false;
       }
     }
   ```
3. In `drawWidget(Widget w, in RectF absRect, Renderer r)`, remove `w.dirty =
   false;` from the end of `drawWidget` and move it into `drawTree` (as shown
   above). This ensures:
   - `painter.render(ctx)` does **not** clear `w.dirty`, so subsequent
     `SystemPhase.render` systems in `WidgetSystemPipeline` can still inspect
     `w.dirty` before the pipeline clears it at the end of the render phase.
   - Direct callers of `painter.drawTree(widgets, r)` (including existing unit
     tests and `UiSystemController` prior to Phase 5) still have `w.dirty`
     cleared just as before.
4. Add verification in `widget_painter.d`'s `unittest` that `painter.priority ==
   WidgetSystem.painterSystemPriority` and `painter.phases ==
   SystemPhase.render`.

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
