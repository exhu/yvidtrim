# `yguilib` Widget Package Review

```
  date    2026-11-27
  branch  main
  commit  7a96feaa25bba66718bc02d342f18c7c42932731 (fix composite_view after review)
```

Line numbers below refer to that commit.

Scope: `yguilib/source/yguilib/widget/` (13 public modules) and
`yguilib/source/yguilib/widget/internal/` (17 internal modules) — 30 modules
total.

Paths below are relative to `yguilib/source/yguilib/widget/`.
Severity: **H** high, **M** medium, **L** low.

```
  Summary
  -------
  correctness, safety & lifecycle .. 41 findings (14 H, 23 M,  4 L)
  memory allocations & perf ........ 16 findings ( 3 H, 10 M,  3 L)
  architecture & API design ........ 16 findings ( 0 H,  8 M,  8 L)
  code reuse & duplication .........  8 findings ( 0 H,  5 M,  3 L)
  codestyle & maintainability ...... 17 findings ( 0 H,  5 M, 12 L)
  tests & verification gaps ........ 16 findings ( 0 H,  7 M,  9 L)
  -----------------------------------------------------------------
  total ............................114 findings (17 H, 58 M, 39 L)
```

Architectural invariants verified: all 17 `internal/` modules use
`package(yguilib):` + `private:` with zero `public:` leaks. Static checker
warning at `system.d:148` (`priority`) is a valid `@property` getter/setter
pair (though making it mutable after registration is flagged in 3.1).

---

## Module Coverage

| Module | Lines | Role | Findings (`H/M/L`) |
|---|---:|---|---|
| `package.d` | 1,312 | `Widget`, `WidgetComponents`, `ViewComponent`, invalidation | `2H / 4M / 6L` |
| `builder.d` | 1,116 | Fluent `WidgetBuilder` for constructing widgets | `0H / 2M / 3L` |
| `component.d` | 6 | Abstract `WidgetComponent` marker base class | Clean |
| `data_components.d` | 21 | `WidgetArrayProvider` and `WidgetArrayComponent` | `0H / 0M / 2L` |
| `drawing_components.d` | 407 | `Background`, `TextLabel`, `Border`, `CustomDraw`, `DebugDraw` | `0H / 0M / 3L` |
| `input_components.d` | 141 | `Focus`, `DefaultButton`, `KeyboardEvent`, `CursorCapture`, `MouseEvent` | `0H / 2M / 2L` |
| `layout_components.d` | 376 | `SizingMode`, `Dimension`, `Insets`, `FlexContainer`, `Size`, `Anchor` | `0H / 1M / 1L` |
| `scroll_components.d` | 130 | `ScrollableArea` component & packed `AppEventViewValue` | `0H / 0M / 1L` |
| `system.d` | 325 | `WidgetSystemHost`, `SystemPhase`, `WidgetSystem`, `TwoPassWidgetSystem` | `0H / 1M / 1L` |
| `test_fixture.d` | 454 | `WidgetFixture` headless widget construction & query helpers | `0H / 2M / 3L` |
| `virtlist_components.d` | 355 | `VirtListProvider`, `VirtListChange`, `VirtListComponent` | `0H / 2M / 2L` |
| `visible.d` | 77 | `VisibleWidget`, `VisibleWidgets`, `findTopmostWithComponent` | `0H / 1M / 0L` |
| `widget_view.d` | 218 | `WidgetViewController`, `WidgetView`, `passViewEvent`, renaming | `1H / 3M / 1L` |
| `internal/collect_visible.d` | 197 | Tree visibility traversal, culling & clip-rect propagation | `1H / 2M / 1L` |
| `internal/data_system.d` | 294 | `DataSystem` (`preLayout`): syncs `WidgetArrayComponent` | `0H / 1M / 2L` |
| `internal/debug_draw_system.d` | 193 | Debug-only unclipped outline & label overlay render system | `0H / 1M / 3L` |
| `internal/focus_system.d` | 59 | `FocusSystem` (`event`, priority `-100`): planned focus stub | `0H / 0M / 2L` |
| `internal/input_system.d` | 1,436 | `InputSystem`: hit-testing, hover, press/drag, cursor capture/lock | `3H / 6M / 2L` |
| `internal/layout_anchor.d` | 228 | Out-of-flow `Anchor` positioning & dual-anchor stretching | `0H / 2M / 1L` |
| `internal/layout_axis.d` | 164 | Row/column main/cross axis geometry & margin accessors | `0H / 0M / 1L` |
| `internal/layout_content_size.d` | 212 | Intrinsic content sizing (scroll, flex, bbox, text, padding) | `1H / 3M / 1L` |
| `internal/layout_dimension.d` | 88 | Dimension mode resolution & `[min, max]` clamping | `0H / 1M / 1L` |
| `internal/layout_flex.d` | 622 | Flex fraction sizing, justification, cross-axis alignment | `1H / 3M / 1L` |
| `internal/layout_system.d` | 674 | Two-pass `LayoutSystem` orchestrating size, anchor & flex | `0H / 4M / 0L` |
| `internal/layout_text.d` | 499 | Single/multiline text wrapping, ellipsis & measurement | `1H / 3M / 1L` |
| `internal/scroll_system.d` | 291 | `ScrollableArea` offset clamping, placement & `postLayout` | `0H / 1M / 3L` |
| `internal/system_pipeline.d` | 758 | `WidgetSystemPipeline`: phase orchestration & dirty flags | `1H / 6M / 0L` |
| `internal/text_label_cache.d` | 226 | `TextLayoutCache` & `TextContentSizeCache` on `TextLabel` | `2H / 3M / 1L` |
| `internal/virtlist_system.d` | 1,542 | `VirtListSystem`: recycling, sizing, wheel scroll | `4H / 6M / 5L` |
| `internal/widget_painter.d` | 402 | `WidgetPainterSystem`: bg, clipped text/`CustomDraw`, borders | `1H / 1M / 3L` |

*(Note: the `VisibleWidgetsCollector` single-buffer aliasing bug affects both
`internal/collect_visible.d` and `internal/system_pipeline.d` and is
deduplicated as 1 `[H]` finding below.)*

---

## 1. Correctness, Safety & Lifecycle

### 1.1 [H] `VisibleWidgetsCollector` single-buffer aliasing clobbers `ctx.unclippedWidgets` before `postLayout`
`internal/collect_visible.d:27-39, 99`, `internal/system_pipeline.d:89-93, 207-254`

`VisibleWidgetsCollector` backs all calls with one `Appender!(VisibleWidget[])`.
In `runLayoutAndPostLayoutPhases`, `:231` populates `ctx.unclippedWidgets`,
then `:245` collects clipped `fLastVisibleWidgets` into the **same** buffer.
When `postLayoutSystems` run (`ScrollSystem.postLayout`), `ctx.unclippedWidgets`
contains clipped entries in `[0 .. M)` and stale leftovers in `[M .. N)`. Also,
`notifyWidgetReleased` (`:89-93`) calls `collector.clearBuffer()` while
`fLastVisibleWidgets` still slices it.

Fix: Maintain two separate buffers (`unclippedCollector` and `clippedCollector`,
or caller-owned `ReusableArray!VisibleWidget`s) so the slices never alias.

### 1.2 [H] `WidgetComponents.clear()` omits `debugDraw`
`package.d:95, 162-180`

Releasing a widget with a `DebugDrawComponent` retains that reference.

Fix: Add `debugDraw = null;` or clear all built-in fields via `static foreach`.

### 1.3 [H] `Widget.release()` leaves dangling `fParent` on existing children
`package.d:526-537`

`release()` is `public` and sets `fChildren = null;` without detaching children,
leaving each child's `fParent` pointing at the released parent.

Fix: Detach children (`c.fParent = null; c.fParentView = null;`) before
clearing, or make `release()` `package(yguilib)` with
`assert(fChildren.length == 0)`.

### 1.4 [H] `WidgetViewBase.translateEventForViewWidget` performs unchecked AA/null access
`widget_view.d:132-137`

Indexes `viewWidget.components.view.renameEvents[sourceEvent.view.eventName]`
without checking `viewWidget`, `view`, or key existence (`RangeError`/segfault).

Fix: `assert(viewWidget !is null)` and guard with `if (auto v = ...)` +
`if (auto p = eventName in v.renameEvents)`.

### 1.5 [H] `InputSystem.postLayout` un-freezes hover during `CursorCapture.lock` and skips `syncCursorCapture()`
`internal/input_system.d:63-65, 128-132, 213-218`

`refreshHover` ignores `hasCursorLock` (firing spurious hover events during
locked drags when layout changes), and `postLayout` never calls
`syncCursorCapture()`, leaving SDL capture/lock stuck if a widget is disabled
or hidden while the mouse is stationary.

Fix: Return early in `refreshHover` when `hasCursorLock` is true, and call
`syncCursorCapture()` in `postLayout`.

### 1.6 [H] `InputSystem.notifyDepartedWidgets` fires `mouseLeave` on disabled widgets
`internal/input_system.d:317-318, 351-367`

When a hovered widget becomes disabled (`inputEnabled = false`),
`notifyDepartedWidgets` omits `entry.widget.inputEnabled && !entry.widget.released`,
emitting `mouseLeave` in violation of `ARCHITECTURE.md:130-131`.

Fix: Add `entry.widget.inputEnabled && !entry.widget.released` to the guard at
`:354`.

### 1.7 [H] Hidden pressed widgets leak capture/lock; disabled presses can revive; missing `onWindowClosed`/`onUnregister`
`internal/input_system.d:189-190, 236-257, 280-308`

- `syncCursorCapture`, `dispatchMouseDrag`, and `handleMouseUp` do not check
  ancestor visibility (`isEffectivelyVisible`), so hiding a dialog mid-drag
  keeps SDL capture/lock active.
- `dispatchMouseDrag` skips stale entries without nulling `pressedWidgets[i]`,
  allowing re-enabled widgets to revive an aborted press.
- `InputSystem` does not override `onWindowClosed`/`onUnregister` to release
  active SDL capture/lock.

Fix: Check `isEffectivelyVisible(w)`, null stale `pressedWidgets[i]`, and
override `onWindowClosed`/`onUnregister` to clear state and call
`syncCursorCapture()`.

### 1.8 [H] `VirtListSystem` `mouseWheel` ignores `Widget.inputEnabled` and blocking overlays
`internal/virtlist_system.d:69-82`

Skips non-`VirtList` widgets in Z-order and never checks `w.inputEnabled`, so
disabled lists scroll and modal dialogs/panels above the list do not block
wheel events.

Fix: Check `isPointInVisibleWidget(vw, p)` first, stop on hittable non-descendant
overlays, and require `w.inputEnabled` before scrolling.

### 1.9 [H] Unguarded `idx + count` overflow in `VirtListSystem` removal handlers
`internal/virtlist_system.d:295, 322`

`applyRemoveChange` and `shiftSizeCachesRemove` compute `idx + count` without
saturating (unlike `applyUpdateChange:354-356`), risking wrap and `k - count`
underflow.

Fix: Use a shared `saturatingAdd(idx, count)` helper in all three handlers.

### 1.10 [H] `resolveFractionSizes` ignores fraction children's own main-axis margins
`internal/layout_flex.d:53-117`

`fixedSum` omits `mainMarginStart + mainMarginEnd` for fraction children,
causing them to overflow their parent by their margins (even visible in
`layout_flex.d:567-581`).

Fix: Add `fixedSum += mainMarginStart(child, isRow) + mainMarginEnd(child, isRow);`
in the `isFraction` branch and update the unittest.

### 1.11 [H] Multiline vertical overflow ellipsis silently dropped when last line is near `availW`
`internal/layout_text.d:44-46, 307-315`

When `last ~ "..."` exceeds `availW`, `buildRawLines` falls back to
`truncateWithEllipsis(r, font, last, availW)`, which hits its early-out
`measureText(last) <= availW` and returns `last` **without** `"..."`.

Fix: Add a helper (or `forceEllipsis` flag) that skips the early-out and
binary-searches for the longest prefix + `"..."` fitting `availW`.

### 1.12 [H] `TextLayoutCache` & `TextContentSizeCache` miss DPI/scale changes and font replacement
`internal/text_label_cache.d:15-47, 78-108, 162-177, 208-223`

Both caches key on unscaled `font.size` and `fontName`. When `Font.scale`
changes, `font.scaledSize` and glyph metrics change while the key stays
identical, serving stale wraps and extents.

Fix: Key on `font.id` (`ulong`) and `font.scaledSize` (`float`).

### 1.13 [H] `TextLayoutCache.isValid` fails to cache empty results
`internal/text_label_cache.d:38`

Checks `lines.length > 0` instead of `bool valid`. When `layoutTextLines`
legitimately returns `[]` (`fitCount == 0`), `isValid` is always `false`,
re-running layout and allocating on every paint frame.

Fix: Add `bool valid;` to `TextLayoutCache` (matching `TextContentSizeCache`).

### 1.14 [H] Unprotected `Canvas.save()`/`restore()` and `pushClipRect`/`popClipRect` in `WidgetPainterSystem`
`internal/widget_painter.d:106-118, 142-145`

If a `CustomDraw` delegate or text draw throws, both `Canvas`'s state stack and
`Renderer`'s `ClipStack` are left imbalanced.

Fix: Use `scope(exit) c.restore();` and `scope(exit) if (w.clipContents) r.popClipRect();`.

### 1.15 [M] Public widget & builder correctness gaps (6 findings)
- `package.d:243-264`: `Widget.addChild` cycle checks are `assert`-only (no
  runtime guard in `-release`).
- `package.d:99-122` & `visible.d:22-38`: `WidgetComponents.set/get/has!C` and
  `findTopmostWithComponent!C` silently accept built-in component types and
  look in `custom` (always missing).
- `layout_components.d:227-235`: `Size.fraction(0.0f, 1.0f)` sets `0fr` width
  instead of `auto_` (asymmetric with `hFr <= 0.0f`).
- `builder.d:791-801` & `widget_view.d:35-37, 114-116`: `registerWidgetView` /
  `registerViewWidget` do not assert non-null or deduplicate.
- `builder.d:688-731`: `virtListCount`/`virtListDirection`/etc. omit
  `fWidget.clipChildren = true` (set it inside `ensureVirtList()`).

### 1.16 [M] Layout, scroll & visibility correctness gaps (10 findings)
- `internal/collect_visible.d:42-44, 99`: `clearBuffer()` retains GC pointers
  to released widgets; switch to `ReusableArray` and zero slots.
- `internal/collect_visible.d:63-66, 70-84`: no culling against `parentClipRect`
  (scrolled-out children still collected and painted).
- `internal/layout_dimension.d:27-42`: `clampDimension` passes `NaN`/`+inf`
  through unchanged.
- `internal/layout_flex.d:72-73, 105-116`: `resolveFractionSizes` produces `NaN`
  on `+inf` weight and lacks min/max redistribution.
- `internal/layout_flex.d:224-243`: `AlignItems.stretch` (default) overwrites
  `SizingMode.fixed` cross-axis size.
- `internal/layout_system.d:94, 179-182, 211-235`: auto-height flex parents do
  not re-measure after root-to-leaf text wrapping; `childBuf` retains released
  widgets.
- `internal/layout_text.d:38, 108-130`: `wrapLine` strips indentation/spaces
  and skips whitespace-only lines; `truncateWithEllipsis` mishandles `NaN`
  width.
- `internal/scroll_system.d:76-101`: non-finite `sa.offset` unguarded when
  `clampOffset == false`.
- `internal/layout_content_size.d:141-163`: `tryCalcChildrenBoundingBox`
  ignores child margins.
- `internal/debug_draw_system.d:51-73`: `resolveEffectiveComp` /
  `resolveNextInherited` cast away `const`.

### 1.17 [M] Runtime systems correctness gaps (7 findings)
- `internal/input_system.d:146-176`: `handleMouseDown` during `hasCursorLock`
  hit-tests raw relative coords and overwrites `lastPressPos`.
- `internal/input_system.d:336-348`: `collectHovered` bubbles hover to
  ancestors with `handleInput == false`.
- `internal/system_pipeline.d:78-80, 94-96`: `notifyWindowClosed` /
  `notifyWidgetReleased` iterate `systems[]` directly (re-entrancy hazard).
- `internal/system_pipeline.d:154-170`: `updateAndRender` calls
  `window.swapBuffers()` even when `rootWidget` or `renderer` is `null`.
- `internal/virtlist_system.d:394-415, 436-449, 878-884`: stale size cache
  entries survive `itemsCount` shrinking / resetting to `0`.
- `internal/virtlist_system.d:261-263`: `applyInsertChange` anchor-shift
  heuristic breaks on multi-batch inserts into an empty list.
- `internal/data_system.d:43-45, 58-60`: unchecked `w.children[i]` after
  `provider.addWidget(w)`.

### 1.18 [L] Minor correctness edge cases (4 findings)
- `test_fixture.d:28-34`: `withUi` wastes one widget ID from `ui`.
- `internal/widget_painter.d:196-200`: zero-sized `absContentRect` passes
  `0.0f` ("unlimited") to `layoutLines`.
- `internal/virtlist_system.d:49-59, 131-135`: `detachReleasedItem` leaves
  `fVisibleItemsCount` stale and doesn't dirty parent layout.
- `internal/virtlist_system.d:1022-1023`: unchecked `size_t` -> `uint`
  truncation in `handleVirtListPostLayout`.

---

## 2. Memory Allocations & Performance

### 2.1 [H] `calcContentSize` bypasses `TextLabel.contentSizeCache`
`internal/layout_content_size.d:94-99`

`calcContentSize(Widget w, Renderer r)` calls `calcConstTextContentSize(...)`
instead of `calcTextContentSize(...)`, bypassing `contentSizeCache` on every
layout pass and re-allocating `string[]`/`FormattedTextLine[]` for every
auto-sized `TextLabel`.

Fix: Call `calcTextContentSize(...)` and remove dead `calcConstTextContentSize`.

### 2.2 [H] Per-scroll-frame GC array allocations in `VirtListSystem`
`internal/virtlist_system.d:208, 605, 616, 812`

`fillVisibleRange` allocates `VirtListActiveItem[] result` growing via `~=` and
`handleBottomUnderflow` allocates `backfill[] ~ active` on every scroll frame.

Fix: Store `fActiveItems` as `ReusableArray!VirtListActiveItem` with a reusable
scratch buffer on `VirtListSystem`.

### 2.3 [H] O(`anchorIndex`) hash lookups per layout frame in `VirtListSystem`
`internal/virtlist_system.d:451-466, 508-541`

`computeCurrentMainOffset` loops `0 .. fAnchorIndex` doing an AA lookup per
index on every layout pass (~1M hash lookups per scroll frame on a 1M-item
list).

Fix: Compute in O(`fItemMainSizes.length`) as
`fAnchorIndex * (avgMain + gap) + sum(v - avgMain)` over `k < fAnchorIndex`.

### 2.4 [M] Moderate allocation & redundant-work hotspots (10 findings)
- `package.d:256-263`: reparenting in `Widget.addChild` traverses subtree twice.
- `package.d:572-601`: `isTreeDirty`/`isTreeLayoutDirty` run full visible-tree
  DFS on every clean frame (maintain ancestor `subtreeDirty` flag for O(1)).
- `virtlist_components.d:152-173, 281`: `fPendingChanges` uses GC `~=` + `null`
  instead of `ReusableArray!VirtListChange`.
- `internal/layout_text.d:27-29, 59-84, 108-192, 237-255, 275-364`: unconditional
  `sanitizeSingleLine` `.replace()`, GC `boundaries` + `~ "..."` in binary
  search, O(N^2) `breakLongWord`, discarded `FormattedTextLine[]` in
  `measureTextContentSize`.
- `internal/layout_flex.d:22-50` & `layout_system.d:219-224`: cache-busting
  `updateFlexChildTextHeight` on unchanged row children.
- `internal/layout_system.d:179-182, 193-197, 225-234`: duplicate
  `alignChildCrossAxis` pass in stretched columns.
- `internal/virtlist_system.d:32, 662-663, 907-941`: `LayoutSystem` (priority 0)
  and `VirtListSystem` (priority 5) fight over `stretchCrossAxis` items every
  layout pass.
- `internal/system_pipeline.d:207-216, 280-316`: triple `collectVisible` on
  dirty layout frames and redundant dirty-flag clearing.

### 2.5 [L] Minor allocation nits (3 findings)
- `builder.d:22`: `WidgetBuilder` is a `final class` (allocates per builder
  chain).
- `package.d:104-107, 183-185`: `customSerializers` allocates a second AA per
  widget; combine into one entry struct.
- `internal/debug_draw_system.d:39-49`: per-widget `format` in `formatLabel`.

---

## 3. Architecture, Encapsulation & API Design

### 3.1 [M] Architectural & API gaps (8 findings)
- `system.d:77-79, 148-150`: `protected` mutable `WidgetSystem.priority` setter
  allows changing priority after `onRegister()`, breaking pipeline sort order
  (use constructor or virtual getter).
- `test_fixture.d:1-344`: public module compiled into `yguilib_lib` that
  imports `yguilib.internal.uisystem_impl`. Move to test sources or gate under
  `version (unittest)`.
- `widget_view.d:112-141`: `WidgetViewBase` omits default
  `override bool update() { return false; }`.
- `internal/layout_system.d:21-27` & `internal/widget_painter.d:19-23`: dead
  unused `CustomLayout` and `CustomWidgetPainter` interfaces.
- `internal/layout_anchor.d:9, 18` & `internal/layout_flex.d:16-18`: unnecessary
  `layout_anchor -> layout_flex` dependency via 1-line `calcContentRect`.
- `internal/input_system.d:8, 34, 39, 105, 421`: dead duplicate `FocusSystem`
  instantiated inside `InputSystem`.
- `internal/input_system.d:422`: `InputSystem.host` shadows `WidgetSystem.host`.
- `internal/system_pipeline.d:74-81`: `notifyWindowClosed` is unwired (`TODO`).

### 3.2 [L] Minor API/encapsulation nits (8 findings)
- `builder.d:411-414, 450-453`: `bgRadius`/`borderRadius` have no effect unless
  `Style.round` is also set.
- `drawing_components.d:31-33, 131-157`: inconsistent corner radius defaults
  and `Border` factory parameter order; comment says `pixels` instead of
  `logical points`.
- `package.d:454-463`: `findByName` missing `inout`.
- `package.d:282-285, 426-450`: unused `dumpSimpleToJsonValue` and 1-line
  `detachChild`.
- `internal/text_label_cache.d:138-205`: null-safety doc/code mismatch and
  mutable `FormattedTextLine[]` return aliasing cache.
- `internal/layout_content_size.d:24-34` & `internal/layout_anchor.d:11-15`:
  missing non-null assert on `szComp` and undocumented nullable params.
- `internal/focus_system.d:18-46`: unimplemented stub (tracked TODO).

---

## 4. Code Reuse & Duplication

### 4.1 [M] Duplicated helpers across `widget/` (5 findings)
- `test_fixture.d:119-339`: duplicates `Widget.findByUId`, `Widget.isChildOf`,
  and a dozen `WidgetBuilder` setters.
- `internal/layout_anchor.d:27-97`: `resolveHorizontalAnchor` and
  `resolveVerticalAnchor` are verbatim 35-line duplicates.
- `internal/layout_content_size.d:16-34, 67-91, 187-211`: duplicates
  `clampDimension`, `Widget.contentArea()`, and `calcTextContentSize`.
- `internal/text_label_cache.d:15-131`: duplicated 7-field key and `isValid`/
  `store` across both cache structs (extract `TextLayoutKey`).
- `internal/input_system.d:475-511`, `system_pipeline.d:373-409`,
  `virtlist_system.d:1076-1112`: triplicated mock `WidgetSystemHost` test
  doubles (plus `scroll_system.d:156-192`).

### 4.2 [L] Minor duplication (3 findings)
- `input_components.d`, `scroll_components.d`, `virtlist_components.d`:
  repeated `AppEventViewValue` union boilerplate.
- `internal/virtlist_system.d:137-145` & `internal/input_system.d:427-429`:
  duplicate `VisibleWidget` point hit-test helpers (move to `VisibleWidget.containsPoint`).
- `internal/scroll_system.d:156-192`: `TestScrollHost` duplicates `DummyHost`.

---

## 5. Codestyle & Maintainability

### 5.1 [M] `codestyle.md` violations (5 findings)
- `input_components.d:97-118` & `virtlist_components.d:77-98`: `pack` takes 8
  parameters (>5 limit).
- `internal/layout_system.d:6, 9, 97-104, 136-150, 200, 211-218`: overloaded
  `handleSizeComp`/`handleAnchorComp`, default `Renderer r = null`, inline
  `package(yguilib)` inside `private:`, 6-param function, test-only top imports.
- `internal/text_label_cache.d:28-204`: 7-10 parameter functions (>5 limit).
- `internal/layout_text.d:218-362`: 7-8 parameter functions, per-declaration
  `private`, 4-space import indent.
- `internal/virtlist_system.d:594-775`: 9-10 parameter functions (`fillVisibleRange`,
  `acquireAndMeasureItem`, `handleBottomUnderflow`).

### 5.2 [L] Minor style & cleanup nits (12 findings)
- Unused module-level imports in `package.d`, `drawing_components.d`,
  `test_fixture.d`, `internal/layout_axis.d`, `internal/widget_painter.d`,
  `internal/input_system.d`, `internal/focus_system.d`.
- 6-8 parameter functions in `internal/collect_visible.d:47`,
  `internal/layout_dimension.d:45`, `internal/layout_flex.d:125`.
- Mis-indented scoped imports in `layout_flex.d:32,87,230` and
  `scroll_system.d:77`; unused `Widget w` param in `virtlist_system.d:147`.
- Per-declaration `private` in `data_system.d:70` and `virtlist_system.d:1076+`;
  typo `DebugDrawCompoenent` (`drawing_components.d:182`); undocumented
  nullable params in `builder.d`/`test_fixture.d`; inconsistent `final class`
  usage across component classes.

---

## 6. Tests & Verification Gaps

### 6.1 [M] Missing unit tests for core widget modules (7 findings)
- `input_components.d:1-141`: zero `unittest` blocks.
- `widget_view.d:147-218`: `passViewEvent`, `applyViewRenaming`,
  `WidgetViewControllerBase`, and `WidgetViewBase` lifecycle untested.
- `internal/layout_content_size.d:1-212`: zero `unittest` blocks.
- `internal/text_label_cache.d:1-226`: zero `unittest` blocks.
- `internal/system_pipeline.d:430-758`: missing tests for `notifyWidgetReleased`,
  `notifyWindowClosed`, `findSystemByType`, and `ctx.unclippedWidgets` in
  `postLayout`.
- `internal/input_system.d:514-1436`: missing tests for disable-while-hovered,
  hide-while-captured/locked, `postLayout` while locked, and secondary press
  while locked.
- `internal/virtlist_system.d:1238-1542`: missing tests for wheel gating
  (disabled & overlay), empty-list cache reset, removal overflow, and
  `LayoutSystem` + `VirtListSystem` `stretchCrossAxis` interaction.

### 6.2 [L] Minor unit-test gaps (9 findings)
- `virtlist_components.d` scroll/NaN guards, `system.d` timer/release helpers,
  `package.d` `debugDraw` release & child detachment & cycles,
  `data_components.d`, `data_system.d` dirty-flag checks, `layout_text.d`
  overflow/NaN/UTF-8, `scroll_system.d` empty/NaN/anchored, `widget_painter.d`
  clip/styles/exception safety, `debug_draw_system.d` `drawHidden`/non-recursive.

---

## Prioritized Action List

- **High**
  1. Split `VisibleWidgetsCollector` into separate unclipped/clipped buffers
     (`internal/collect_visible.d`, `internal/system_pipeline.d`).
  2. Fix `calcContentSize` to use `calcTextContentSize` (`internal/layout_content_size.d`),
     fix `TextLayoutCache`/`TextContentSizeCache` keys + `bool valid`
     (`internal/text_label_cache.d`), and fix `layout_flex` fraction margins +
     `layout_text` vertical ellipsis.
  3. Fix `InputSystem` lock/hover/disable/hide/cleanup bugs
     (`internal/input_system.d`) and `VirtListSystem` wheel gating, overflow,
     O(`anchorIndex`) offset math, and per-scroll GC churn
     (`internal/virtlist_system.d`).
  4. Fix `WidgetComponents.clear` (`debugDraw`), `Widget.release` child
     detachment, `WidgetViewBase.translateEventForViewWidget` bounds/null checks,
     and `WidgetPainterSystem` `scope(exit)` guards.
- **Medium**
  5. Remove dead duplicate `FocusSystem` and shadowed `host` in `InputSystem`;
     wire `notifyWindowClosed`; fix `LayoutSystem`/`VirtListSystem`
     `stretchCrossAxis` fight and `WidgetSystemPipeline` redundant passes.
  6. Add missing unit tests for `widget_view.d`, `layout_content_size.d`,
     `text_label_cache.d`, `input_components.d`, and runtime edge cases.
- **Low**
  7. Consolidate duplicated test hosts/helpers and clean up codestyle nits.
