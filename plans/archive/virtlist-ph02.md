# Phase 2: Composite `VirtList` Control (`source/guidemo/virtlist.d`)

Implement the model-driven `VirtList` composite control in
`source/guidemo/virtlist.d` combining a `VirtListComponent` viewport with
main-axis and cross-axis `Scrollbar` controls (`guidemo.scrollbars`), following
the `TabControl` pattern (`source/guidemo/tabcontrol.d`).

## Rules & Conventions
- Adhere to `codestyle.md`: 2-space indent, LF, max 80 chars/line, opening `{`
  on same line, visibility sections (`public:`, `private:`), no overloaded
  functions/methods, no default parameter values, no consecutive capital letters,
  non-null assertions in constructors, `invariant` blocks, functions `<= ~50`
  lines.
- Every `WidgetBuilder.make` / `.child` chain must specify `.name(...)` and
  `.rect(...)` (verified by `define_gui_widget.d --audit`).

## Tasks

### 1. Define Model, Style, and Constants in `source/guidemo/virtlist.d`
- Module `guidemo.virtlist`.
- Internal event names:
  - `enum virtListMetricsChangedEvent = "virtListMetricsChanged";`
  - `enum virtListMainScrollEvent = "virtListMainScroll";`
  - `enum virtListCrossScrollEvent = "virtListCrossScroll";`
  - `enum defaultVirtListEventName = "virtListChanged";`
  - `enum virtListWidgetViewName = "VirtListWidgetView";`
  - `enum virtListWidgetViewControllerName = "VirtListWidgetViewController";`
- `final class VirtListModel : VersionedModel`:
  - `size_t itemsCount = 0;`
  - `size_t firstVisibleIndex = 0;`
  - `size_t visibleItemsCount = 0;`
  - `float scrollOffsetMain = 0.0f;`
  - `float scrollOffsetCross = 0.0f;`
  - `this()` and `this(size_t initialItemsCount)`
  - Mutation helpers:
    - `void insertItems(size_t index, size_t count)` — updates `itemsCount`
      and records `VirtListChange(VirtListChange.Kind.insert, index, count)`.
    - `void removeItems(size_t index, size_t count)` — clamps count, updates
      `itemsCount`, and records `VirtListChange(VirtListChange.Kind.remove, index, actual)`.
    - `void updateItems(size_t index, size_t count)` — records
      `VirtListChange(VirtListChange.Kind.update, index, count)` so existing
      rows re-bind and re-measure dynamically.
    - `void updateItem(size_t index)` — calls `updateItems(index, 1)`.
    - `void requestScrollToIndex(size_t index)` — stores pending scroll jump.
  - `package(guidemo):` helpers `takePendingChanges()` and
    `takePendingScrollIndex(out size_t index)` so `VirtListWidgetView` forwards
    recorded mutations cleanly to `VirtListComponent`.
- `struct VirtListStyle`:
  - `float scrollbarThickness = 18.0f;`
  - `float scrollbarGap = 4.0f;`
  - `float itemGap = 4.0f;`
  - `float defaultItemMainSize = 48.0f;`
  - `float cornerRadius = 6.0f;`
  - `Insets viewportPadding = Insets.all(4.0f);`
  - `ColorF viewportBg = ColorF(0.08f, 0.10f, 0.13f, 1.0f);`
  - `ColorF viewportBorder = ColorF(0.24f, 0.30f, 0.40f, 1.0f);`
  - `ColorF cornerBg = ColorF(0.10f, 0.12f, 0.15f, 1.0f);`
  - `ColorF cornerBorder = ColorF(0.20f, 0.23f, 0.29f, 1.0f);`
  - `ScrollbarStyle scrollbarStyle;`

### 2. Implement `VirtListWidgetView` and `VirtListWidgetViewController`
- `final class VirtListEntry`:
  - `ModelTracker!VirtListModel tracker;`
  - `ModelTracker!ScrollbarModel mainScrollTracker;`
  - `ModelTracker!ScrollbarModel crossScrollTracker;`
  - `Widget viewport;`
  - `Widget mainScrollbar;`
  - `Widget crossScrollbar;`
  - `Widget cornerBox;`
  - `FlexDirection direction;`
  - `string eventName;`
  - `bool viewDirty = false;`
- `final class VirtListWidgetView : WidgetViewBase`:
  - `registerVirtList(...)`, `bindModel(...)`, `bindModelWithModel(...)`,
    `unregisterViewWidget(...)`
  - Accessors: `getViewport`, `getMainScrollbar`, `getCrossScrollbar`,
    `getEventName`.
  - `handleMetricsChanged(Widget viewWidget, in VirtListComponent.AppEventViewValue val)`:
    - Updates `mainScrollTracker` (`max = max(0, round(totalMainSize - viewportMainSize))`,
      `visibleSize = max(1, round(viewportMainSize))`,
      `stepSize = max(1, round(defaultItemMainSize))`,
      `value = round(mainOffset)`).
    - Updates `crossScrollTracker` (`max = max(0, round(maxCrossSize - viewportCrossSize))`,
      `visibleSize = max(1, round(viewportCrossSize))`,
      `stepSize = 24`, `value = round(crossOffset)`).
    - Updates `VirtListModel` (`firstVisibleIndex`, `visibleItemsCount`,
      `scrollOffsetMain`, `scrollOffsetCross`) and reports whether visible
      position/count changed for external event emission.
  - `applyMainScrollOffset(Widget viewWidget, long value)` ->
    `viewport.components.virtList.scrollToMainOffset(cast(float) value)` +
    `viewport.update(WidgetUpdateScope.layout)`.
  - `applyCrossScrollOffset(Widget viewWidget, long value)` ->
    `viewport.components.virtList.setCrossOffset(cast(float) value)` +
    `viewport.update(WidgetUpdateScope.layout)`.
  - `override bool update()`:
    - Syncs `entry.tracker.update()`: forwards `takePendingChanges()`,
      `takePendingScrollIndex()`, and `itemsCount` to `VirtListComponent` and
      calls `viewport.update(WidgetUpdateScope.layout)`.
- `final class VirtListWidgetViewController : WidgetViewControllerBase`:
  - Reacts to `virtListMetricsChangedEvent`, `virtListMainScrollEvent`, and
    `virtListCrossScrollEvent`.
  - Emits the configured external `eventName` with `firstVisibleIndex` in
    `AppEvent.view.value[0]` when visible location changes.

### 3. Implement `VirtListBuilder` and `registerVirtList`
- `struct VirtListBuilder`:
  - Fluent methods: `.name(...)`, `.model(...)`, `.modelTracker(...)`,
    `.provider(...)`, `.event(...)`, `.direction(...)`, `.gap(...)`,
    `.defaultItemSize(...)`, `.stretchCrossAxis(...)`, `.style(...)`.
  - `Widget build(UiSystem ui, Widget parent, RectF rect, UiRegistry registry)`:
    - Builds root container with `ViewComponent` (`viewEvents` renaming
      `virtListMetricsChangedEvent`, `virtListMainScrollEvent`,
      `virtListCrossScrollEvent`; `viewName(virtListWidgetViewName)`).
    - For `FlexDirection.column` (vertical list):
      - Root is `flexColumn`; top row (`flexRow`, `fractionWidth(1)`,
        `fractionHeight(1)`) holds `viewport` (`fractionWidth(1)`,
        `fractionHeight(1)`) and `mainScrollbar` (`FlexDirection.column`, fixed
        width `thickness`); bottom row (`flexRow`, `fractionWidth(1)`, fixed
        height `thickness`) holds `crossScrollbar` (`FlexDirection.row`,
        `fractionWidth(1)`) and `cornerBox` (fixed `thickness x thickness`).
    - For `FlexDirection.row` (horizontal list):
      - Root is `flexColumn`; top row (`flexRow`, `fractionWidth(1)`,
        `fractionHeight(1)`) holds `viewport` (`fractionWidth(1)`,
        `fractionHeight(1)`) and `crossScrollbar` (`FlexDirection.column`,
        fixed width `thickness`); bottom row (`flexRow`, `fractionWidth(1)`,
        fixed height `thickness`) holds `mainScrollbar` (`FlexDirection.row`,
        `fractionWidth(1)`) and `cornerBox` (fixed `thickness x thickness`).
    - Registers built parts with `VirtListWidgetView`.
- `VirtListWidgetViewController registerVirtList(UiSystem ui)`.

### 4. Wire `meson.build` and Add `unittest` Block in `source/guidemo/virtlist.d`
- Add `source/guidemo/virtlist.d` to `guidemo_lib_src` and add a standalone
  `virtlist_test` executable & test target in `meson.build` (linking
  `source/guidemo/virtlist.d`, `source/guidemo/scrollbars.d`, and
  `source/guidemo/test_main.d`).
- Unit test verifying:
  - Recursive `verifyAllNamed` on built vertical & horizontal `VirtList`.
  - Full `WidgetSystemPipeline` layout/scroll/recycle across 10,000 items.
  - Main-axis & cross-axis scrollbar synchronization and thumb dragging.
  - `VirtListModel.insertItems`, `removeItems`, and `updateItem` preserving
    anchor position and reflowing resized rows.
  - `ui.releaseWidget` unregisters cleanly.

## Verification (Phase 2)
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d --audit
```
