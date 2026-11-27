# `yguilib` Controls Package Review

```
  date    2026-11-27
  branch  main
  commit  7a96feaa25bba66718bc02d342f18c7c42932731 (fix composite_view after review)
```

Line numbers below refer to that commit.

Scope: `yguilib/source/yguilib/controls/` (9 modules) and
`yguilib/source/yguilib/controls/internal/` (2 modules) — 11 modules total.

Paths below are relative to `yguilib/source/yguilib/controls/`.
Severity: **H** high, **M** medium, **L** low.

```
  Summary
  -------
  correctness, safety & lifecycle .. 25 findings (11 H,  8 M,  6 L)
  memory allocations & perf ........  5 findings ( 0 H,  3 M,  2 L)
  architecture & API design ........  5 findings ( 0 H,  2 M,  3 L)
  code reuse & duplication .........  3 findings ( 0 H,  1 M,  2 L)
  codestyle & maintainability ...... 10 findings ( 0 H,  4 M,  6 L)
  tests & verification gaps ........  9 findings ( 0 H,  6 M,  3 L)
  -----------------------------------------------------------------
  total ............................ 57 findings (11 H, 24 M, 22 L)
```

Static baseline note: `check_style.d` flagged `tabcontrol.d:424` (60-line
function), `tabcontrol.d:603` (overloaded `revealActiveTab`), and
`virtlist.d:77` (multiple constructors) — all confirmed below.

---

## Module Coverage

| Module | Lines | Role | Findings (`H/M/L`) |
|---|---:|---|---|
| `button.d` | 1,136 | Push button component, builder, built-in `ButtonSystem` | `4H / 3M / 3L` |
| `common.d` | 343 | Shared `WidgetColors`, `ButtonFace`, view/event helpers | `0H / 0M / 2L` |
| `composite_view.d` | 366 | Free helpers for composite views, entries, builders | Clean |
| `hover_button_system.d` | 738 | ECS `AnimatedHoverButtonComponent`, builder, system | `3H / 3M / 3L` |
| `scrollbars.d` | 1,380 | Composite horizontal/vertical `Scrollbar` | `0H / 4M / 6L` |
| `tabcontrol.d` | 1,577 | Model-driven scrollable `TabControl` | `2H / 7M / 6L` |
| `testing.d` | 140 | `version(unittest)` helpers & mock hosts | `0H / 0M / 2L` |
| `tooltip.d` | 1,232 | ECS `Tooltip`, `TooltipLayerComponent`, `TooltipSystem` | `0H / 4M / 3L` |
| `virtlist.d` | 1,322 | Virtualized list composite with main/cross scrollbars | `1H / 4M / 5L` |
| `internal/axis.d` | 147 | `package(yguilib)` `Axis` X/Y projection helper | Clean |
| `internal/button_support.d` | 426 | Shared button config/mixin, `ActiveWidgets`, `PressTracker` | `1H / 2M / 3L` |

---

## 1. Correctness, Safety & Lifecycle

### 1.1 [H] `ButtonSystem.syncEnabledStates` runs in `postLayout`, skipped on `WidgetUpdateScope.visuals`
`button.d:332-334, 387-388, 473-482`

Callers are instructed (`button.d:29-36`) to toggle `Widget.inputEnabled` and
call `update(WidgetUpdateScope.visuals)`, which sets `dirty` without
`layoutDirty`. However, `WidgetSystemPipeline.runLayoutAndPostLayoutPhases`
skips `postLayout` when `!root.isTreeLayoutDirty()`, so disabled colors and
mid-press cancellation do not apply until an unrelated layout pass occurs.

Fix: Add `SystemPhase.preLayout` to `ButtonSystem.phases` and run
`syncEnabledStates(ctx)` in `preLayout`.

### 1.2 [H] Disabling a pressed/repeating button leaves `repeatTimerId` and `press.pressed` active
`button.d:387-403, 473-482`

`syncEnabledStates` calls `comp.syncEnabled(vw.widget)` -> `resetPress(w)`,
which resets component fields but leaves `w` in `activeButtons`, `press.pressed`
pointing at `w`, and `repeatTimerId` running until its next fire.

Fix: When `comp.syncEnabled` resets a disabled button, remove it from
`activeButtons`, clear `press.end()`, call `stopRepeat()`, and stop
`animTimerId` if idle.

### 1.3 [H] Second `mouseButtonDown` orphans prior pressed button
`button.d:499-523`

If `press.pressed` is already non-null and a new `mouseButtonDown` arrives on
another button (or misses), `press.begin(hit)` overwrites `press.pressed`
without un-pressing the prior button or stopping its repeat timer.

Fix: Before handling a new press, if `press.pressed !is null && press.pressed !is hit`,
un-press the prior button, track it to animate back, clear `press.end()`, and
call `stopRepeat()`.

### 1.4 [H] `ButtonSystem.handleWindowMouseLeave` keeps `press.pressed` and `repeatTimerId` alive
`button.d:525-536, 560-567`

Because `ButtonSystem` does not acquire cursor capture, releasing outside the
window never delivers `mouseButtonUp`. A repeating button's timer keeps firing
indefinitely (breaking 0% CPU idle sleep), and re-entering the button with no
button held causes phantom re-press and repeat.

Fix: Cancel `press.pressed` and call `stopRepeat()` in `handleWindowMouseLeave`.

### 1.5 [H] `AnimatedHoverButtonSystem` ignores `Widget.inputEnabled`
`hover_button_system.d:251-351, 373-388`

Disabled hover buttons (`inputEnabled = false`) still hover, animate, press,
and emit `actionEvent`, violating `ARCHITECTURE.md:130-131`.

Fix: Guard motion/press/release/step handlers on `w.inputEnabled` and reset
interaction state when a tracked button becomes disabled.

### 1.6 [H] Press-tracking bugs in `AnimatedHoverButtonSystem`
`hover_button_system.d:293-351`

- `handleWindowMouseLeave` clears `hoveredWidget` but never `press.pressed`.
- `handleMouseButtonDown` overwrites an existing `press.pressed` without
  un-pressing the prior button.
- Dragging off a pressed button clears `isPressed`, and dragging back on sets
  `isHovered = true` without restoring `isPressed = true`.

Fix: Clear `press.pressed` in `handleWindowMouseLeave` and on new
`mouseButtonDown`; restore `comp.isPressed = (hoveredWidget is press.pressed)`
on re-entry.

### 1.7 [H] Hover pulse latch stuck at `hoverProgress = 1.0f` on large `dt`
`hover_button_system.d:397-410, 434-439`

When `isHovered == false` and `hoverPulsePending == true`, `hoverForward` is
cached as `const bool` (`true`) at `:400`. If `dt >= 1 / fadeSpeed` (~0.286s),
`stepTowards` reaches `1.0f` in one tick, `:407` clears `hoverPulsePending`,
and `:436` checks `!isAtTarget(hoverForward)` with stale `hoverForward == true`
(`false`), stopping the timer with the button stuck at `1.0f`.

Fix: Recompute `const nextHoverForward = comp.isHovered || comp.hoverPulsePending;`
after `:410` before computing `isHoverBusy`.

### 1.8 [H] `PressTracker.hitTest` ignores `Widget.handleInput` occlusion
`internal/button_support.d:262-264`

Calls `findTopmostWithComponent!C(ctx.visibleWidgets, p)`, which skips
overlapping widgets lacking component `C` even when `handleInput == true`.
Buttons behind modal backdrops, popups, or scrollbars can be hovered/clicked
through the occluding widget.

Fix: Hit-test the topmost visible widget with `handleInput == true` first, and
return it only if `vw.widget.components.has!C()`.

### 1.9 [H] Stale `TabsModel` in `TabButtonsProvider` after `bindModel`
`tabcontrol.d:276-285` (and `:127-188, 1097`)

Re-binding a new `TabsModel` via `TabControlWidgetView.bindModel` updates
`entry.tracker` and `widgetArray.itemsCount`, but `TabButtonsProvider` still
holds the old `const(TabsModel)`, asserting on `index < model.tabNames.length`
if the new model has more tabs or rendering stale captions otherwise.

Fix: Add a `package(yguilib)` `bindModel(const(TabsModel))` on
`TabButtonsProvider` and update it in `TabControlWidgetView.bindModel`.

### 1.10 [H] `TabControlWidgetViewController` treats any unrecognized view event as a tab click
`tabcontrol.d:867-895`

After checking scroll events, `handleEvent` unconditionally calls
`tcv.selectTab(...)` for any other view event targeting `tabRoot` instead of
falling through to `super.handleEvent(ev)`.

Fix: Store the configured `eventName` on `TabControlEntry`, match
`eventName == tcv.eventName(ev.view.viewWidget)`, and return
`super.handleEvent(ev)` for all other events.

### 1.11 [H] `VirtListWidgetView.bindModel` creates orphaned `ScrollbarModel`s
`virtlist.d:400-412` (and `:238-248`)

For an unregistered tree, `bindNewEntryFromTree` allocates fresh
`ModelTracker!ScrollbarModel` instances that are never bound to
`parts.mainScrollbar`/`parts.crossScrollbar` in `ScrollbarWidgetView`, so
subsequent metric updates never reach the visible scrollbars.

Fix: Bind the created trackers to the scrollbars via `ScrollbarWidgetView`, or
document/restrict `bindModel` on unregistered trees.

### 1.12 [M] Drag state desync in `Scrollbar` on model/layout change mid-drag
`scrollbars.d:557-576, 688-710`

- If `m.range()` drops to `0` mid-drag, disabling `entry.thumb.inputEnabled`
  can prevent `mouseUp` and leave `entry.isDragging` stuck `true`.
- In `reportOnReleaseOnly` mode, `syncEntryVisuals` mid-drag overwrites
  `entry.currentThumbOffset` with uncommitted `m.value`, snapping the thumb.

Fix: Clear `entry.isDragging = false` when `tm.range == 0`; preserve the visual
drag offset when `entry.isDragging && m.reportOnReleaseOnly`.

### 1.13 [M] Fallback `bindModel` hardcodes `FlexDirection.row` in `Scrollbar` and `TabControl`
`scrollbars.d:277-293`, `tabcontrol.d:287-308`

Breaks vertical instances bound via unregistered-root discovery.

Fix: Read `viewWidget.components.flexContainer.direction` (defaulting to `row`).

### 1.14 [M] `TabControl.translateEventForViewWidget` defaults unknown child to tab `0`
`tabcontrol.d:351-369`

If `sourceEvent.view.widget` is not in `container.children`, `tabIndex` stays
`0` and fires a click on tab 0.

Fix: Track `bool found` and bail / use `size_t.max` when not found.

### 1.15 [M] `TooltipSystem` incomplete cleanup on `onUnregister` and host switch
`tooltip.d:309-323`

`onUnregister` does not hide an active popup or clear `fCachedLayer`/
`fCachedPopup`; host-switching `onRegister` stops timers without resetting
`fState`/`fActiveTarget`, leaving the state machine wedged.

Fix: Hide `fCachedPopup`, clear cached refs, and call `resetToIdle()` in both
`onUnregister()` and host-switching `onRegister()`.

### 1.16 [M] `VirtListWidgetView` casts away `const` and drains model queue
`virtlist.d:478-482`

`cast(VirtListModel)` in `syncModelToViewport` bypasses `ModelTracker`
single-writer discipline and loses pending changes if multiple views observe
one model.

Fix: Route mutations through `entry.tracker.edit()` or use a monotonic change
sequence cursor per entry.

### 1.17 [M] `cleanInvisibleButtons` skips settled hovered/pressed hover buttons
`hover_button_system.d:357-371`

Once a fade button settles at `1.0f`, it is removed from `activeButtons`.
Hiding it clears `hoveredWidget`/`press.pressed` without calling
`comp.resetToNormal`, leaving it stuck hovered when shown again.

Fix: Call `comp.resetToNormal` on `hoveredWidget` and `press.pressed` before
clearing them.

### 1.18 [M] `ButtonSystem.onTimer` does not verify `id == animTimerId`
`button.d:376-385`

Any timer ID other than `repeatTimerId` falls through to `stepActiveButtons`.

Fix: Guard with `if (id != invalidTimerId && id == animTimerId)`.

### 1.19 [M] Missing non-null assertions in `internal/button_support.d`
`internal/button_support.d:109-112, 127-130, 298-310`

`size(Size)`, `anchor(Anchor)`, and `emitButtonAction(target, ...)` document
non-null requirements without `assert(... !is null)`.

### 1.20 [L] Minor edge cases across `controls/`
- `scrollbars.d:606`: `cast(double)(range + vis)` can overflow `long` before
  widening; cast operands before adding.
- `tabcontrol.d:384-395`: `selectTab` copies `ModelTracker` by value instead of
  operating on `entry.tracker`.
- `virtlist.d:532-534`: `findVirtListParts` requires `bottomRow.children.length >= 2`
  to read child 0 (and names it `leftBar`).
- `button.d:171-175, 255-259`: `applySink` increases height if
  `basePadding.bottom < sinkPx`; `ButtonBuilder.build` does not assert
  `repeat.intervalMs > 0` or `sinkPx >= 0`.
- `hover_button_system.d:204-213`: `onTimer` does not check `id == animTimerId`.
- `internal/button_support.d:241-250`: `ActiveWidgets.removeInvisible` calls
  `onRemoved(w)` before `items.removeAt(i)`.

---

## 2. Memory Allocations & Performance

### 2.1 [M] Full widget-tree traversal on every `mouseMotion` when no tooltip layer exists
`tooltip.d:461, 710-764`

Every `mouseMotion` calls `discoverLayer(ctx)`, scanning `visibleWidgets`,
`unclippedWidgets`, and recursively walking `ctx.root` when no
`TooltipLayerComponent` is present.

Fix: Run `discoverLayer` lazily in `preLayout`/`handleDelayTimer` or cache a
negative lookup invalidated on `preLayout`.

### 2.2 [M] Per-update GC `format()` allocation in `TabButtonsProvider.updateWidgetAt`
`tabcontrol.d:171`

`w.name = format("tabButton_%d", index);` allocates on every `activeTab` change.

Fix: Only format `w.name` when the tab is newly created or its index changed.

### 2.3 [M] Redundant O(N) `visibleWidgets` scan on every `mouseMotion` in `AnimatedHoverButtonSystem`
`hover_button_system.d:256, 274, 281, 499-515`

`press.hitTest` scans `visibleWidgets` backwards, then `updateCursorNorm` scans
it forwards again for the same `absRect`.

Fix: Return `Nullable!VisibleWidget` from hit-testing and pass `absRect`
directly.

### 2.4 [L] Redundant `.dup` on local `renameMap` AA in composite builders
`scrollbars.d:862, 880`, `tabcontrol.d:979, 1003`, `virtlist.d:732, 746`

Declaring `const string[string] renameMap` and passing `renameMap.dup`
allocates two AAs per build. Use mutable `string[string]` and pass directly.

### 2.5 [L] Zero-duration tooltip fade still starts a 60 FPS timer
`tooltip.d:557-558, 642-646`

Fast-path `fadeInDuration <= 0.0f` / `fadeOutDuration <= 0.0f` directly to
`visible` / `finishHiding`.

---

## 3. Architecture, Encapsulation & API Design

### 3.1 [M] `internal/` leak via public aliases and `ButtonBuilderCommon` mixin
`internal/button_support.d:28, 46-185`

`package(yguilib)` `ButtonBaseConfig` is publicly aliased as `ButtonConfig`
(`button.d:68`) and `HoverButtonConfig` (`hover_button_system.d:47`), and
`ButtonBuilderCommon` mixes internal fields and `makeButtonBase` into public
builder structs as `public`.

Fix: Move `ButtonBaseConfig` to `common.d` and mark internal mixin fields/
helpers `private:` or `package(yguilib):`.

### 3.2 [M] `TooltipSystem.ensureHost` silently mutates `host` outside `onRegister`
`tooltip.d:665-669`

Can start timers on a host that never registered the system, bypassing
`onUnregister` lifecycle guarantees.

Fix: Require `onRegister(host)` before timer use.

### 3.3 [L] Internal `*Entry` classes are `public`
`scrollbars.d:210`, `tabcontrol.d:191`, `virtlist.d:171`

Mark `ScrollbarEntry`, `TabControlEntry`, and `VirtListEntry` `private` (or
`package(yguilib)`).

### 3.4 [L] `TooltipLayerBuilder` exposes mutable public fields
`tooltip.d:101-104, 189-192`

Move `config` and `widgetName` to `private:` and use fluent setters in
`createTooltipLayer`.

### 3.5 [L] Unnecessary `ref` on `WidgetBuilder` class parameter
`common.d:90-95`, `internal/button_support.d:188`

`WidgetBuilder` is a `final class`, not a struct; `ref` prevents passing rvalue
builders. Change `ref WidgetBuilder b` to `WidgetBuilder b`.

---

## 4. Code Reuse & Duplication

### 4.1 [M] Duplicated animation timer lifecycle & active-button stepping
`button.d:336-351, 419-436, 569-582`,
`hover_button_system.d:170-183, 233-249, 353-355, 373-388`

Both systems duplicate `onRegister`/`onUnregister`/`ensureAnimTimer`/
`stopAnimTimer` and reverse `activeButtons` stepping loops.

Fix: Extract a shared `package(yguilib)` helper in `internal/button_support.d`.

### 4.2 [L] Duplicated arrow button enable/disable helper
`scrollbars.d:712-729`, `tabcontrol.d:827-844`

Extract `setWidgetInputEnabled(Widget w, bool enabled)` into `common.d`.

### 4.3 [L] Duplicated `mouseEv` test helper in `button.d`
`button.d:633-640, 866-873, 1016-1023`

Move into `testing.d` or a single file-private helper.

---

## 5. Codestyle & Maintainability

### 5.1 [M] `TabControlWidgetView.handleScrollChanged` exceeds 50 lines (63 lines)
`tabcontrol.d:421-483`

Extract the overflow branch (`:456-482`) into a private helper.

### 5.2 [M] Overloaded `revealActiveTab` in `tabcontrol.d`
`tabcontrol.d:489, 603`

Rename the private helper at `:603` to `revealActiveTabForEntry`.

### 5.3 [M] Multiple constructors on `VirtListModel`
`virtlist.d:73, 77`

Keep `this()` and replace `this(size_t)` with `static VirtListModel withCount(size_t)`.

### 5.4 [M] Functions with `> 5` parameters in composite controls
`scrollbars.d:244-254, 897-1050`, `tabcontrol.d:225-271, 1019-1131`,
`virtlist.d:207-218, 761-966`

18 functions across these three files take 6 to 10 parameters (`codestyle.md`
§2 limit is 5). Group parts/options into small parameter structs.

### 5.5 [L] Minor codestyle, doc, and dead-code nits
- `hover_button_system.d:81, 510`: dead field `cursorNormY`; `stepComponent`
  (`:390-440`) is 51 lines; nullable `parent` undocumented (`:134, 146`);
  module docstring references `guidemo`'s `hover_button.d`.
- `scrollbars.d`, `tabcontrol.d`, `virtlist.d`: undocumented nullable returns/
  params on part accessors; repeated function-scoped `std.algorithm.comparison`
  and `std.math.algebraic` imports across 3-6 functions per file.
- `tooltip.d:411`: hardcoded `8.0f` flip gap instead of a `TooltipStyle` field.
- `testing.d:33`: unnecessary `cast(Widget)` dropping `const` in `calcAbsRect`.

---

## 6. Tests & Verification Gaps

### 6.1 [M] Missing pipeline-level and edge-case tests in `button.d` & `hover_button_system.d`
`button.d:755-793, 1008-1135`, `hover_button_system.d:524-737`

Direct `sys.postLayout(ctx)` calls masked the `WidgetUpdateScope.visuals` bug.
Missing tests for: disabling repeating buttons, second `mouseButtonDown`,
`windowMouseLeave` while pressed, `inputEnabled == false` hover buttons,
`cleanInvisibleButtons` on settled hover buttons, and large-`dt` pulse ticks.

### 6.2 [M] Missing coverage in `tabcontrol.d`, `virtlist.d`, `scrollbars.d`, `tooltip.d`
- `tabcontrol.d:1155-1577`: `bindModel` rebinding, fallback to
  `super.handleEvent`, vertical mode, 0 tabs, unknown child translation.
- `virtlist.d:1240-1322`: `bindModel` on existing/unregistered trees,
  `VirtListModel` boundary mutations, controller `super.handleEvent` fallback.
- `scrollbars.d:1081-1380`: `range == 0` disabled state, `bindModel` (incl.
  vertical), external `ModelTracker` commits, mid-drag `reportOnReleaseOnly`;
  split monolithic 298-line unittest.
- `tooltip.d:835-1232`: `postLayout` hiding on invisible/obstructed target,
  target-A -> target-B handoff, `onUnregister`/host-switch cleanup, 0-duration
  fade.

### 6.3 [L] Minor test helper gaps in `common.d`, `button_support.d`, `testing.d`
- `common.d:206-256`: `applyColors` untested on live/released widgets.
- `internal/button_support.d:313-426`: `.size()`, `.autoSize()`, `.anchor()`
  untested.
- `testing.d:79-87`: `DummyWidgetSystemHost.startTimer` drops `intervalMs` and
  `mode`.

---

## Prioritized Action List

- **High**
  1. Fix `PressTracker.hitTest` to respect `handleInput` occlusion
     (`internal/button_support.d:262-264`).
  2. Move `ButtonSystem.syncEnabledStates` to `preLayout`, stop repeat timers
     on disable/leave/new press (`button.d`).
  3. Enforce `inputEnabled`, fix press tracking, and fix large-`dt` pulse latch
     in `AnimatedHoverButtonSystem` (`hover_button_system.d`).
  4. Fix `TabButtonsProvider` rebind (`tabcontrol.d:276-285`), `TabControl`
     controller `super.handleEvent` fallback (`tabcontrol.d:867-895`), and
     `VirtListWidgetView.bindModel` scrollbar binding (`virtlist.d:400-412`).
- **Medium**
  5. Fix `TooltipSystem` `mouseMotion` full-tree scan and `onUnregister`/host
     switch cleanup (`tooltip.d`).
  6. Fix `Scrollbar` mid-drag desync (`scrollbars.d`) and `ButtonBaseConfig`/
     `ButtonBuilderCommon` encapsulation leak (`internal/button_support.d`).
  7. Resolve confirmed `codestyle.md` issues (`tabcontrol.d`, `virtlist.d`) and
     add missing pipeline/edge-case tests.
- **Low**
  8. Extract shared animation/arrow helpers and clean up minor nits.
