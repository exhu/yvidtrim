# ph09: `widget` Core Entity, Pipeline, Collector, Painter & View

Overview: `plans/yguilib-review-fixes.md`.
Review: `documentation/yguilib-review-report-widget.md` (commit `7a96feaa`).
Paths below are relative to `yguilib/source/yguilib/widget/`.

Goal: Address core `widget/` findings (`1.1`-`1.4`, `1.14`-`1.18`,
`2.4`-`2.5`, `3.1`-`3.2`, `4.1`-`4.2`, `5.1`-`5.2`, `6.1`-`6.2` excluding
`InputSystem`, layout/scroll, and `VirtListSystem` which are in ph10-ph12).

## Files

- `package.d`, `builder.d`, `data_components.d`, `drawing_components.d`,
  `input_components.d`, `layout_components.d`, `scroll_components.d`,
  `system.d`, `test_fixture.d`, `visible.d`, `widget_view.d`
- `internal/collect_visible.d`, `internal/system_pipeline.d`,
  `internal/widget_painter.d`, `internal/data_system.d`,
  `internal/debug_draw_system.d`, `internal/focus_system.d`

## Steps

1. **`VisibleWidgetsCollector` dual buffers & culling (`1.1`, `1.16`, `5.2`)**:
   - Use two separate `ReusableArray!VisibleWidget` buffers (`unclippedBuf`
     and `clippedBuf`) so `ctx.unclippedWidgets` and `fLastVisibleWidgets`
     never alias; zero slots on `clearBuffer()` (`1.1`, `1.16`).
   - Cull widgets whose `absRect` does not intersect `parentClipRect` when
     `parentHasClip` (`1.16`).
   - Group >5-param helper (`5.2`).
2. **`Widget` & `WidgetComponents` (`1.2`, `1.3`, `1.15`, `2.4`, `2.5`, `3.2`, `5.2`)**:
   - Clear `debugDraw` in `WidgetComponents.clear()` (via `static foreach`),
     reject built-in component types in `set/get/has!C` and
     `findTopmostWithComponent!C`, merge `customSerializers` into one entry
     struct (`1.2`, `1.15`, `2.5`).
   - Detach children (`c.fParent = null; c.fParentView = null;`) in
     `Widget.release()` (or restrict to `package(yguilib)` with empty-children
     assert) (`1.3`).
   - Add runtime cycle guard & single-pass reparenting in `Widget.addChild`
     (`1.15`, `2.4`); maintain O(1) `subtreeDirty`/`subtreeLayoutDirty` flags
     (`2.4`); add `inout` on `findByName` (`3.2`); remove unused
     `dumpSimpleToJsonValue` & 1-line `detachChild` (`3.2`); prune unused
     imports (`5.2`).
3. **`WidgetView` & `WidgetBuilder` (`1.4`, `1.15`, `3.1`, `3.2`, `5.2`)**:
   - Guard `WidgetViewBase.translateEventForViewWidget` (`assert(viewWidget !is
     null)`, `view !is null`, `in renameEvents`) (`1.4`); add default
     `override bool update() { return false; }` (`3.1`); assert non-null and
     deduplicate in `registerWidgetView`/`registerViewWidget` (`1.15`).
   - In `builder.d`: set `fWidget.clipChildren = true` in `ensureVirtList()`
     (`1.15`), document `bgRadius`/`borderRadius` `Style.round` requirement
     and nullable params (`3.2`, `5.2`).
4. **`WidgetPainterSystem` & `WidgetSystemPipeline` (`1.14`, `1.17`, `1.18`, `2.4`, `3.1`, `5.2`)**:
   - Use `scope(exit)` for `c.restore()` and `r.popClipRect()` (`1.14`),
     guard zero-sized `absContentRect` (`1.18`), remove dead
     `CustomWidgetPainter` (`3.1`), prune unused imports (`5.2`).
   - In `system_pipeline.d`: snapshot `systems[]` in `notifyWindowClosed` and
     `notifyWidgetReleased`, skip `swapBuffers()` when `rootWidget` or
     `renderer` is `null` (`1.17`), eliminate triple `collectVisible` &
     redundant dirty clears (`2.4`).
   - Make `WidgetSystem.priority` immutable after construction (constructor
     or virtual getter) (`3.1`).
5. **Components, `DataSystem`, `DebugDrawSystem` & `test_fixture` (`1.15`-`1.17`, `3.1`, `4.1`-`4.2`, `5.1`-`5.2`)**:
   - Fix `Size.fraction(0.0f, 1.0f)` symmetry (`1.15`).
   - Add `VisibleWidget.containsPoint(PointF)` (`4.2`); share
     `AppEventViewValue` union helper (`4.2`); use param struct for 8-param
     `input_components.pack` (`5.1`).
   - `DataSystem`: check `w.children` bounds after `provider.addWidget(w)`
     (`1.17`), fix `private` section (`5.2`).
   - `DebugDrawSystem`: remove `const` casts (`1.16`), avoid per-widget
     `format` (`2.5`), fix `DebugDrawCompoenent` typo (`5.2`).
   - Gate `test_fixture.d` under `version (unittest):` + `package(yguilib):`
     (`3.1`), deduplicate `Widget`/`WidgetBuilder` wrappers (`4.1`), fix
     wasted widget ID (`1.18`), and add a shared `MockWidgetSystemHost`
     (`4.1`) for `system_pipeline` (and ph10-ph12).
6. **Tests (`6.1`, `6.2`)**:
   - Add unit tests for `input_components.d`, `widget_view.d`,
     `system_pipeline.d` (`notifyWidgetReleased`, `notifyWindowClosed`,
     `findSystemByType`, `ctx.unclippedWidgets` in `postLayout`), `package.d`,
     `data_components.d`, `data_system.d`, `widget_painter.d`, and
     `debug_draw_system.d`.

## Verification

- `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`
