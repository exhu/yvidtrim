# Phase 1: `yguilib` `VirtListComponent` and `VirtListSystem`

Implement the core virtual list component, provider interface, change tracking,
layout/recycling system, and `WidgetBuilder`/`UiSystemImpl` integration inside
`yguilib`.

## Rules & Conventions
- Adhere to `codestyle.md`: 2-space indent, LF, max 80 chars/line, opening `{`
  on same line, lowercase filenames, visibility sections (`public:`,
  `package(yguilib):`, `private:`), no overloaded functions/methods, no default
  parameter values, no consecutive capital letters, non-null assertions in
  constructors, `invariant` blocks, functions `<= ~50` lines.
- Maintain `yguilib` independence (no imports from `yvidtrim` or `guidemo`).
- Internal modules under `yguilib/source/yguilib/widget/internal/` must use
  `package(yguilib):` (never `public:`).

## Tasks

### 1. Create `yguilib/source/yguilib/widget/virtlist_components.d`
- Define `interface VirtListProvider`:
  - `Widget createWidget(Widget parent);`
    Creates a single reusable item widget attached to `parent`. Heterogeneous
    row types are implemented by switching child subtree visibility inside
    `updateWidgetAt`.
  - `void updateWidgetAt(Widget w, size_t index);`
    Binds row/column data for `index` to `w`.
  - `void onWidgetRecycled(Widget w);`
    Notifies the provider that `w` left the visible area and entered the
    recycle cache so active animations/timers for `w` can be stopped.
- Define `struct VirtListChange`:
  - `enum Kind : ubyte { insert, remove, update }`
  - `Kind kind; size_t index; size_t count;`
- Define `final class VirtListComponent : WidgetComponent`:
  - Nested `union AppEventViewValue` (32 bytes matching
    `ulong[AppEvent.ViewData.valueSize]`) with:
    - `float totalMainSize;`
    - `float viewportMainSize;`
    - `float mainOffset;`
    - `float maxCrossSize;`
    - `float viewportCrossSize;`
    - `float crossOffset;`
    - `uint firstVisibleIndex;`
    - `uint visibleCount;`
    - `static AppEventViewValue fromRaw(...)` and `static AppEventViewValue pack(...)`
      (following `ScrollableArea.AppEventViewValue`).
  - Public configuration & state fields:
    - `VirtListProvider provider;`
    - `FlexDirection direction = FlexDirection.column;`
    - `float gap = 4.0f;`
    - `float defaultItemMainSize = 48.0f;`
    - `bool stretchCrossAxis = false;`
    - `size_t itemsCount = 0;`
    - `bool modelChanged = false;`
    - `string metricsChangedEvent;`
  - Public fluent/mutation methods (no overloads, no default args):
    - `VirtListComponent withProvider(VirtListProvider p)`
    - `VirtListComponent withDirection(FlexDirection dir)`
    - `VirtListComponent withGap(float g)`
    - `VirtListComponent withDefaultItemMainSize(float sz)`
    - `VirtListComponent withStretchCrossAxis(bool stretch)`
    - `VirtListComponent withItemsCount(size_t count)`
    - `VirtListComponent withMetricsChangedEvent(string eventName)`
    - `void recordInsert(size_t index, size_t count)`
    - `void recordRemove(size_t index, size_t count)`
    - `void recordUpdate(size_t index, size_t count)`
    - `void scrollByMain(float deltaPx)`
    - `void scrollToMainOffset(float targetOffsetPx)`
    - `void scrollToIndex(size_t index)`
    - `void setCrossOffset(float offsetPx)`
  - Read-only `@property` accessors backed by `package(yguilib):` fields:
    - `anchorIndex`, `anchorOffset`, `visibleItemsCount`, `activeWidgetsCount`,
      `pooledWidgetsCount`, `totalMainSize`, `viewportMainSize`, `mainOffset`,
      `maxCrossSize`, `viewportCrossSize`, `crossOffset`.
  - `package(yguilib):` runtime state (`ActiveItem[] activeItems`,
    `Widget[] freePool`, `float[size_t] itemMainSizes`,
    `float[size_t] itemCrossSizes`, `double knownMainSizesSum`,
    `VirtListChange[] pendingChanges`, `float pendingMainDelta`,
    `bool hasTargetMainOffset`, `float targetMainOffset`,
    `bool hasTargetIndex`, `size_t targetIndex`, `float crossOffsetTarget`,
    `float lastViewportCross`, `lastEmitted*` fields for change detection).
  - Include unit tests verifying `AppEventViewValue` packing/unpacking and
    change recording.

### 2. Update `yguilib/source/yguilib/widget/system.d`, `package.d`, and `builder.d`
- In `system.d`: add `enum int virtListSystemPriority = 5;` to `WidgetSystem`.
- In `package.d`:
  - Import `VirtListComponent` in `WidgetComponents` and add field
    `VirtListComponent virtList;`.
  - Clear `virtList = null;` in `WidgetComponents.clear()`.
- In `builder.d`:
  - Import `VirtListComponent`, `VirtListProvider` from
    `yguilib.widget.virtlist_components`.
  - Add helper `ensureVirtList()` and builder methods:
    - `WidgetBuilder virtList(VirtListProvider provider)` (sets
      `fWidget.clipChildren = true; ensureVirtList().provider = provider;`)
    - `WidgetBuilder virtListCount(size_t count)`
    - `WidgetBuilder virtListDirection(FlexDirection dir)`
    - `WidgetBuilder virtListGap(float gap)`
    - `WidgetBuilder virtListStretchCross(bool stretch)`
    - `WidgetBuilder onVirtListMetricsChanged(string eventName)`
    - `WidgetBuilder virtListComponent(VirtListComponent comp)`

### 3. Create `yguilib/source/yguilib/widget/internal/virtlist_system.d`
- `package(yguilib):` visibility.
- `final class VirtListSystem : WidgetSystem`:
  - `this(WidgetSystemHost host)` (allows `null` in isolated tests),
    `setPriority(virtListSystemPriority)`.
  - `phases`: `SystemPhase.event | SystemPhase.layout | SystemPhase.postLayout`.
  - `onRegister` / `onWidgetReleased(Widget w)` (clears runtime pools/state if
    `w.components.virtList !is null`).
  - `handleEvent(in AppEvent event, ref WidgetSystemContext ctx)`:
    - Handle `AppEvent.Kind.mouseWheel`: find top-most visible widget in
      `ctx.visibleWidgets` with `w.components.virtList !is null` whose
      `absRect` (and `clipRect` if `hasClip`) contains `(mouseX, mouseY)`.
    - Apply wheel scroll (`event.wheel.y` / `event.wheel.x`, scaled by
      `defaultItemMainSize`), call `w.update(WidgetUpdateScope.layout)`, and
      return `SystemEventResult(true, false)`.
  - `layout(ref WidgetSystemContext ctx)`:
    - Iterate `ctx.unclippedWidgets`; for each widget with
      `w.components.virtList !is null`, call `handleVirtListLayout(w, ctx.renderer)`.
    - Inside `handleVirtListLayout(Widget w, Renderer r)`:
      1. Enforce `w.clipChildren = true`. Read `contentArea = w.getContentArea()`
         for `viewportMain` and `viewportCross`.
      2. Apply `pendingChanges` in order:
         - `Kind.insert`: shift cached sizes & `activeItems` indices `>= idx`
           by `+count`. If `idx <= anchorIndex` and `itemsCount > count`,
           `anchorIndex += count`.
         - `Kind.remove`: delete cached sizes in `[idx .. idx + count)`, shift
           cached sizes & `activeItems` indices `>= idx + count` by `-count`,
           mark active items in `[idx .. idx + count)` invalid (`index = size_t.max`),
           and adjust `anchorIndex` (preserving item if `idx + count <= anchorIndex`,
           otherwise clamping to `min(idx, itemsCount - 1)` with `anchorOffset = 0`).
         - `Kind.update`: remove cached sizes in `[idx .. idx + count)` and mark
           matching `activeItems` with `needsRebind = true`.
      3. Handle `modelChanged` (clear size cache, mark all `activeItems` with
         `needsRebind = true`, clear `modelChanged = false`) and cross-axis
         viewport resize (clear size cache when `abs(viewportCross - lastViewportCross) > 0.5f`).
      4. If `itemsCount == 0` or `provider is null` or viewport `<= 0`: recycle
         all active items (hiding them and calling `provider.onWidgetRecycled`),
         reset metrics, and return.
      5. Clamp `anchorIndex < itemsCount`, apply `hasTargetIndex`,
         `hasTargetMainOffset` (local delta if `<= 2 * viewportMain`, ratio
         jump otherwise), and `pendingMainDelta`.
      6. Advance/rewind `(anchorIndex, anchorOffset)` across measured sizes +
         `gap`, using `avgMainSize` fast-forward when `abs(anchorOffset) > viewportMain * 2`.
      7. Fill visible range `[anchorIndex .. )` while `currPos < viewportMain`:
         - Acquire widget from previous `activeItems` (if index matches and valid),
           or pop from `freePool` (with `assumeSafeAppend()`), or call
           `provider.createWidget(w)`.
         - Ensure `itemWidget.visible = true`.
         - Call `provider.updateWidgetAt(itemWidget, idx)` if newly bound or
           `needsRebind`.
         - Measure item subtree (`measureItemSubtree`) if size not cached or
           `itemWidget.isTreeLayoutDirty()` is true, updating `itemMainSizes`,
           `knownMainSizesSum`, and `itemCrossSizes`.
         - Mark `itemWidget.dirty = true` if newly bound/moved.
      8. Handle bottom underflow if `currIdx == itemsCount` and `currPos < viewportMain`
         (shift active items down, backfill above `anchorIndex`, clamp if total
         content < viewportMain).
      9. Recycle unclaimed items from previous `activeItems`: set `visible = false`,
         push to `freePool`, and call `provider.onWidgetRecycled(oldItem.widget)`.
     10. Compute `mainOffset`, `totalMainSize`, `maxCrossSize`, clamp `crossOffset`,
         and assign final `rect.x`/`rect.y` for every active item relative to
         `contentArea` (offsetting cross axis by `-crossOffset`).
  - `measureItemSubtree(Widget itemWidget, Renderer r, float viewportCross, bool isRow, bool stretchCrossAxis)`:
    - Bottom-up traversal of visible nodes in `itemWidget` calling
      `LayoutSystem.handleSizeComp(node, r)`.
    - If `stretchCrossAxis` and cross size is not fixed, set cross size to
      clamped `viewportCross`.
    - Top-down traversal of visible nodes calling `LayoutSystem.handleAnchorComp`
      and `LayoutSystem.handleFlexContainerComp`.
    - If `itemWidget` has `auto_` main sizing, re-run `LayoutSystem.handleSizeComp`
      for its main dimension (preserving stretched cross size if `stretchCrossAxis`).
  - `postLayout(ref WidgetSystemContext ctx)`:
    - For each visible `VirtListComponent`, emit `metricsChangedEvent` via
      `passViewEvent` when metrics changed.

### 4. Wire `UiSystemImpl` and `yguilib/meson.build`
- Register `new VirtListSystem(this)` in `yguilib/source/yguilib/internal/uisystem_impl.d`.
- Add `virtlist_components.d` and `virtlist_system.d` to `yguilib_src` in
  `yguilib/meson.build`.

### 5. Unit Tests in `virtlist_system.d`
- Single-template creation & recycling (`createWidget` count bounded to visible
  capacity, `freePool` reuse, `onWidgetRecycled` invoked when scrolling away).
- Heterogeneous row subtrees and variable sizes, including oversized items
  exceeding viewport on both main and cross axes, verifying smooth pixel-offset
  scrolling.
- Dynamic `recordUpdate` and `isTreeLayoutDirty()` on an existing active row,
  verifying re-bind, re-measurement, reflow of subsequent rows, and recycling
  of pushed-out trailing rows.
- Dynamic `recordInsert` and `recordRemove` above/at/below `anchorIndex`
  preserving visible anchor item and `anchorOffset`.
- Horizontal (`FlexDirection.row`) mode and `mouseWheel` scrolling.

## Verification (Phase 1)
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d --audit
```
