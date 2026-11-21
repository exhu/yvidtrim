/**
 * virtlist.d - Reusable model-driven composite VirtList control combining a
 * VirtListComponent viewport with main-axis and cross-axis Scrollbars.
 */
module guidemo.virtlist;

import std.math.rounding : round;
import guidemo.scrollbars : ScrollbarBuilder, ScrollbarModel, ScrollbarStyle;
import yguilib.controller : HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.builder : ViewAppEventBuilder;
import yguilib.model : ModelTracker, VersionedModel;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiRegistry, UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.layout_components : AlignItems, Dimension, FlexDirection,
  Insets, JustifyContent, Size, SizingMode;
import yguilib.widget.virtlist_components : VirtListChange, VirtListComponent,
  VirtListProvider;
import yguilib.widget.widget_view : WidgetView, WidgetViewBase,
  WidgetViewControllerBase;

/// Internal view event emitted by `VirtListSystem` when metrics change.
enum virtListMetricsChangedEvent = "virtListMetricsChanged";

/// Internal view event emitted by the main-axis `Scrollbar`.
enum virtListMainScrollEvent = "virtListMainScroll";

/// Internal view event emitted by the cross-axis `Scrollbar`.
enum virtListCrossScrollEvent = "virtListCrossScroll";

/// Default external view event emitted when visible position/count changes.
enum defaultVirtListEventName = "virtListChanged";

/// Registered name of `VirtListWidgetView` in `UiRegistry`.
enum virtListWidgetViewName = "VirtListWidgetView";

/// Registered name of `VirtListWidgetViewController` in `UiRegistry`.
enum virtListWidgetViewControllerName = "VirtListWidgetViewController";

/**
 * Versioned model tracking item count, visible window metrics, and incremental
 * dataset mutations (`insertItems`, `removeItems`, `updateItems`,
 * `updateItem`) plus `requestScrollToIndex`.
 */
final class VirtListModel : VersionedModel {
  /// Total number of logical items in the dataset.
  size_t itemsCount = 0;
  /// Index of the first currently visible item.
  size_t firstVisibleIndex = 0;
  /// Number of currently visible items.
  size_t visibleItemsCount = 0;
  /// Current effective main-axis scroll offset in logical points.
  float scrollOffsetMain = 0.0f;
  /// Current effective cross-axis scroll offset in logical points.
  float scrollOffsetCross = 0.0f;

  /// Constructs an empty `VirtListModel`.
  this() {
  }

  /// Constructs a `VirtListModel` with `initialItemsCount` items.
  this(size_t initialItemsCount) {
    this.itemsCount = initialItemsCount;
  }

  /// Inserts `count` items at `index` (clamped to `itemsCount`) and records an
  /// incremental insert change.
  void insertItems(size_t index, size_t count) {
    import std.algorithm.comparison : min;
    if (count == 0) {
      return;
    }
    const size_t clampedIdx = min(index, itemsCount);
    itemsCount += count;
    pendingChanges ~= VirtListChange(
      VirtListChange.Kind.insert, clampedIdx, count
    );
  }

  /// Removes up to `count` items starting at `index` and records an
  /// incremental remove change.
  void removeItems(size_t index, size_t count) {
    import std.algorithm.comparison : min;
    if (count == 0 || index >= itemsCount) {
      return;
    }
    const size_t actual = min(count, itemsCount - index);
    itemsCount -= actual;
    pendingChanges ~= VirtListChange(
      VirtListChange.Kind.remove, index, actual
    );
  }

  /// Marks up to `count` existing items starting at `index` dirty for re-bind
  /// and dynamic re-measurement.
  void updateItems(size_t index, size_t count) {
    import std.algorithm.comparison : min;
    if (count == 0 || index >= itemsCount) {
      return;
    }
    const size_t actual = min(count, itemsCount - index);
    pendingChanges ~= VirtListChange(
      VirtListChange.Kind.update, index, actual
    );
  }

  /// Marks a single item at `index` dirty for re-bind and re-measurement.
  void updateItem(size_t index) {
    updateItems(index, 1);
  }

  /// Requests scrolling so `index` becomes the first visible item.
  void requestScrollToIndex(size_t index) {
    hasPendingScrollIndex = true;
    pendingScrollIndex = index;
  }

package(guidemo):
  VirtListChange[] takePendingChanges() {
    VirtListChange[] res = pendingChanges;
    pendingChanges = null;
    return res;
  }

  bool takePendingScrollIndex(out size_t index) {
    if (!hasPendingScrollIndex) {
      return false;
    }
    index = pendingScrollIndex;
    hasPendingScrollIndex = false;
    return true;
  }

private:
  VirtListChange[] pendingChanges;
  bool hasPendingScrollIndex = false;
  size_t pendingScrollIndex = 0;
}

/// Visual styling and layout configuration for a `VirtList` composite control.
struct VirtListStyle {
  float scrollbarThickness = 18.0f;
  float scrollbarGap = 4.0f;
  float itemGap = 4.0f;
  float defaultItemMainSize = 48.0f;
  float cornerRadius = 6.0f;
  Insets viewportPadding = Insets.all(4.0f);
  ColorF viewportBg = ColorF(0.08f, 0.10f, 0.13f, 1.0f);
  ColorF viewportBorder = ColorF(0.24f, 0.30f, 0.40f, 1.0f);
  ColorF cornerBg = ColorF(0.10f, 0.12f, 0.15f, 1.0f);
  ColorF cornerBorder = ColorF(0.20f, 0.23f, 0.29f, 1.0f);
  ScrollbarStyle scrollbarStyle;
}

/// Internal bookkeeping entry tracking one composite `VirtList` instance.
final class VirtListEntry {
  ModelTracker!VirtListModel tracker;
  ModelTracker!ScrollbarModel mainScrollTracker;
  ModelTracker!ScrollbarModel crossScrollTracker;
  Widget viewport;
  Widget mainScrollbar;
  Widget crossScrollbar;
  Widget cornerBox;
  FlexDirection direction;
  string eventName;
  bool viewDirty = false;

  /// Constructs an entry from trackers for the list and its two scrollbars.
  this(
    ref ModelTracker!VirtListModel tracker,
    ref ModelTracker!ScrollbarModel mainScrollTracker,
    ref ModelTracker!ScrollbarModel crossScrollTracker
  ) {
    this.tracker = ModelTracker!VirtListModel.from(tracker);
    this.mainScrollTracker =
      ModelTracker!ScrollbarModel.from(mainScrollTracker);
    this.crossScrollTracker =
      ModelTracker!ScrollbarModel.from(crossScrollTracker);
  }
}

/**
 * WidgetView managing registered `VirtList` root widgets, synchronizing
 * `VirtListModel` mutations to `VirtListComponent`, updating main/cross
 * `ScrollbarModel` trackers on layout metrics feedback, and applying scrollbar
 * offsets back to the viewport.
 */
final class VirtListWidgetView : WidgetViewBase {
  /// Registers a fully constructed `VirtList` composite and its subparts.
  /// `mainScrollbar`, `crossScrollbar`, and `cornerBox` are allowed to be null
  /// in minimal test configurations.
  void registerVirtList(
    Widget viewWidget,
    ref ModelTracker!VirtListModel tracker,
    ref ModelTracker!ScrollbarModel mainScrollTracker,
    ref ModelTracker!ScrollbarModel crossScrollTracker,
    Widget viewport,
    Widget mainScrollbar,
    Widget crossScrollbar,
    Widget cornerBox,
    FlexDirection direction,
    string eventName
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    if (!isWidgetRegistered(viewWidget)) {
      registerViewWidget(viewWidget);
    }
    removeScrollbarMappings(viewWidget);
    auto entry = new VirtListEntry(
      tracker, mainScrollTracker, crossScrollTracker
    );
    entry.viewport = viewport;
    entry.mainScrollbar = mainScrollbar;
    entry.crossScrollbar = crossScrollbar;
    entry.cornerBox = cornerBox;
    entry.direction = direction;
    entry.eventName = (eventName.length > 0)
      ? eventName
      : defaultVirtListEventName;
    entries[viewWidget] = entry;
    addScrollbarMappings(viewWidget, entry);
    syncModelToViewport(entry);
  }

  /// Associates a `ModelTracker!VirtListModel` with a registered or newly built
  /// `VirtList` root widget.
  void bindModel(Widget viewWidget, ref ModelTracker!VirtListModel tracker) {
    assert(viewWidget !is null, "viewWidget must not be null");
    if (!isWidgetRegistered(viewWidget)) {
      registerViewWidget(viewWidget);
    }
    if (auto pEntry = viewWidget in entries) {
      pEntry.tracker = ModelTracker!VirtListModel.from(tracker);
      syncModelToViewport(*pEntry);
      pEntry.viewDirty = true;
      return;
    }
    bindNewEntryFromTree(viewWidget, tracker);
  }

  /// Associates a `VirtListModel` instance with `viewWidget`.
  void bindModelWithModel(Widget viewWidget, VirtListModel model) {
    assert(viewWidget !is null, "viewWidget must not be null");
    assert(model !is null, "model must not be null");
    auto tracker = ModelTracker!VirtListModel(model);
    bindModel(viewWidget, tracker);
  }

  override void unregisterViewWidget(Widget viewWidget) {
    removeScrollbarMappings(viewWidget);
    entries.remove(viewWidget);
    super.unregisterViewWidget(viewWidget);
  }

  /// Returns the `VirtListComponent` viewport widget for `viewWidget`, or null
  /// if not registered.
  Widget getViewport(Widget viewWidget) {
    if (auto p = viewWidget in entries) {
      return p.viewport;
    }
    return null;
  }

  /// Returns the main-axis `Scrollbar` widget for `viewWidget`, or null.
  Widget getMainScrollbar(Widget viewWidget) {
    if (auto p = viewWidget in entries) {
      return p.mainScrollbar;
    }
    return null;
  }

  /// Returns the cross-axis `Scrollbar` widget for `viewWidget`, or null.
  Widget getCrossScrollbar(Widget viewWidget) {
    if (auto p = viewWidget in entries) {
      return p.crossScrollbar;
    }
    return null;
  }

  /// Returns the configured external view event name for `viewWidget`, or
  /// null if not registered.
  string getEventName(Widget viewWidget) {
    if (auto p = viewWidget in entries) {
      return p.eventName;
    }
    return null;
  }

  /// Looks up the owning `VirtList` root widget for `scrollbarWidget`, or
  /// returns null if not owned by any registered `VirtList`.
  Widget findRootForScrollbar(Widget scrollbarWidget) {
    if (scrollbarWidget is null) {
      return null;
    }
    if (auto pRoot = scrollbarWidget in scrollbarToRoot) {
      return *pRoot;
    }
    return null;
  }

  /// Returns true if `scrollbarWidget` is the main-axis scrollbar of
  /// `viewWidget`.
  bool isMainScrollbar(Widget viewWidget, Widget scrollbarWidget) {
    if (auto p = viewWidget in entries) {
      return p.mainScrollbar is scrollbarWidget;
    }
    return false;
  }

  override void translateEventForViewWidget(
    ref AppEvent sourceEvent,
    Widget viewWidget
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    super.translateEventForViewWidget(sourceEvent, viewWidget);
  }

  /**
   * Synchronizes main/cross `ScrollbarModel` trackers and `VirtListModel`
   * visible metrics from a `virtListMetricsChanged` event payload.
   * Returns true if `firstVisibleIndex` or `visibleItemsCount` changed.
   */
  bool handleMetricsChanged(
    Widget viewWidget,
    in VirtListComponent.AppEventViewValue val
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto pEntry = viewWidget in entries;
    if (pEntry is null) {
      return false;
    }
    auto entry = *pEntry;
    const float defMain = getDefaultItemMainSize(entry);
    syncScrollbarTracker(
      entry.mainScrollTracker,
      val.totalMainSize,
      val.viewportMainSize,
      val.mainOffset,
      defMain
    );
    syncScrollbarTracker(
      entry.crossScrollTracker,
      val.maxCrossSize,
      val.viewportCrossSize,
      val.crossOffset,
      24.0f
    );
    return updateModelMetrics(entry, val);
  }

  /// Applies a main-axis scroll offset emitted by the main `Scrollbar`.
  bool applyMainScrollOffset(Widget viewWidget, long value) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto pEntry = viewWidget in entries;
    if (pEntry is null || pEntry.viewport is null ||
        pEntry.viewport.components.virtList is null) {
      return false;
    }
    auto entry = *pEntry;
    entry.viewport.components.virtList.scrollToMainOffset(cast(float) value);
    entry.viewport.update(WidgetUpdateScope.layout);
    entry.viewDirty = true;
    return true;
  }

  /// Applies a cross-axis scroll offset emitted by the cross `Scrollbar`.
  bool applyCrossScrollOffset(Widget viewWidget, long value) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto pEntry = viewWidget in entries;
    if (pEntry is null || pEntry.viewport is null ||
        pEntry.viewport.components.virtList is null) {
      return false;
    }
    auto entry = *pEntry;
    entry.viewport.components.virtList.setCrossOffset(cast(float) value);
    entry.viewport.update(WidgetUpdateScope.layout);
    entry.viewDirty = true;
    return true;
  }

  override bool update() {
    bool anyUpdated = false;
    foreach (w, entry; entries) {
      if (entry.tracker.update()) {
        if (syncModelToViewport(entry)) {
          anyUpdated = true;
        }
      }
      if (entry.viewDirty) {
        entry.viewDirty = false;
        anyUpdated = true;
      }
    }
    return anyUpdated;
  }

private:
  VirtListEntry[Widget] entries;
  Widget[Widget] scrollbarToRoot;

  void addScrollbarMappings(Widget viewWidget, VirtListEntry entry) {
    if (entry.mainScrollbar !is null) {
      scrollbarToRoot[entry.mainScrollbar] = viewWidget;
    }
    if (entry.crossScrollbar !is null) {
      scrollbarToRoot[entry.crossScrollbar] = viewWidget;
    }
  }

  void removeScrollbarMappings(Widget viewWidget) {
    if (auto pEntry = viewWidget in entries) {
      if (pEntry.mainScrollbar !is null) {
        scrollbarToRoot.remove(pEntry.mainScrollbar);
      }
      if (pEntry.crossScrollbar !is null) {
        scrollbarToRoot.remove(pEntry.crossScrollbar);
      }
    }
  }

  void bindNewEntryFromTree(
    Widget viewWidget,
    ref ModelTracker!VirtListModel tracker
  ) {
    Widget vp, mainSb, crossSb, corner;
    FlexDirection dir = FlexDirection.column;
    findVirtListParts(viewWidget, vp, mainSb, crossSb, corner, dir);
    auto mainTracker = ModelTracker!ScrollbarModel(new ScrollbarModel());
    auto crossTracker = ModelTracker!ScrollbarModel(new ScrollbarModel());
    registerVirtList(
      viewWidget, tracker, mainTracker, crossTracker,
      vp, mainSb, crossSb, corner, dir, defaultVirtListEventName
    );
  }

  static float getDefaultItemMainSize(VirtListEntry entry) {
    if (entry.viewport !is null &&
        entry.viewport.components.virtList !is null) {
      return entry.viewport.components.virtList.defaultItemMainSize;
    }
    return 48.0f;
  }

  static void syncScrollbarTracker(
    ref ModelTracker!ScrollbarModel sbTracker,
    float contentExtent,
    float viewportExtent,
    float offset,
    float stepFloat
  ) {
    import std.algorithm.comparison : clamp, max;
    const long newMax = max(
      0L, cast(long) round(contentExtent - viewportExtent)
    );
    const long newVis = max(1L, cast(long) round(viewportExtent));
    const long newStep = max(1L, cast(long) round(stepFloat));
    const long newVal = clamp(cast(long) round(offset), 0L, newMax);

    const auto m = sbTracker.model;
    if (m.min == 0 && m.max == newMax && m.visibleSize == newVis &&
        m.stepSize == newStep && m.value == newVal) {
      return;
    }
    auto editable = sbTracker.edit();
    editable.min = 0;
    editable.max = newMax;
    editable.visibleSize = newVis;
    editable.stepSize = newStep;
    editable.value = newVal;
    sbTracker.commit(editable);
  }

  static bool updateModelMetrics(
    VirtListEntry entry,
    in VirtListComponent.AppEventViewValue val
  ) {
    const size_t newFirst = cast(size_t) val.firstVisibleIndex;
    const size_t newVisCount = cast(size_t) val.visibleCount;
    const float newMainOff = val.mainOffset;
    const float newCrossOff = val.crossOffset;
    const auto m = entry.tracker.model;
    const bool visibleChanged = (
      m.firstVisibleIndex != newFirst ||
      m.visibleItemsCount != newVisCount
    );
    if (!visibleChanged && m.scrollOffsetMain == newMainOff &&
        m.scrollOffsetCross == newCrossOff) {
      return false;
    }
    auto editable = entry.tracker.edit();
    editable.firstVisibleIndex = newFirst;
    editable.visibleItemsCount = newVisCount;
    editable.scrollOffsetMain = newMainOff;
    editable.scrollOffsetCross = newCrossOff;
    entry.tracker.commit(editable);
    return visibleChanged;
  }

  static bool syncModelToViewport(VirtListEntry entry) {
    if (entry.viewport is null ||
        entry.viewport.components.virtList is null) {
      return false;
    }
    auto vc = entry.viewport.components.virtList;
    auto mutModel = cast(VirtListModel) entry.tracker.model;
    VirtListChange[] changes = mutModel.takePendingChanges();
    size_t scrollIdx = 0;
    const bool hasScrollIdx = mutModel.takePendingScrollIndex(scrollIdx);
    const bool countChanged = (vc.itemsCount != mutModel.itemsCount);

    applyChangesToComponent(vc, changes, mutModel.itemsCount, countChanged);
    if (hasScrollIdx) {
      vc.scrollToIndex(scrollIdx);
    }
    if (changes.length > 0 || countChanged || hasScrollIdx) {
      entry.viewport.update(WidgetUpdateScope.layout);
      return true;
    }
    return false;
  }

  static void applyChangesToComponent(
    VirtListComponent vc,
    in VirtListChange[] changes,
    size_t itemsCount,
    bool countChanged
  ) {
    foreach (ref ch; changes) {
      final switch (ch.kind) {
      case VirtListChange.Kind.insert:
        vc.recordInsert(ch.index, ch.count);
        break;
      case VirtListChange.Kind.remove:
        vc.recordRemove(ch.index, ch.count);
        break;
      case VirtListChange.Kind.update:
        vc.recordUpdate(ch.index, ch.count);
        break;
      }
    }
    if (countChanged) {
      vc.itemsCount = itemsCount;
      if (changes.length == 0) {
        vc.modelChanged = true;
      }
    }
  }

  static void findVirtListParts(
    Widget viewWidget,
    out Widget viewport,
    out Widget mainScrollbar,
    out Widget crossScrollbar,
    out Widget cornerBox,
    out FlexDirection dir
  ) {
    dir = FlexDirection.column;
    if (viewWidget is null || viewWidget.children.length < 2) {
      return;
    }
    Widget topRow = viewWidget.children[0];
    Widget bottomRow = viewWidget.children[1];
    Widget rightBar = (topRow.children.length >= 2)
      ? topRow.children[1]
      : null;
    Widget leftBar = (bottomRow.children.length >= 2)
      ? bottomRow.children[0]
      : null;
    viewport = (topRow.children.length >= 1) ? topRow.children[0] : null;
    cornerBox = (bottomRow.children.length >= 2)
      ? bottomRow.children[1]
      : null;
    if (viewport !is null && viewport.components.virtList !is null) {
      dir = viewport.components.virtList.direction;
    }
    mainScrollbar = (dir == FlexDirection.column) ? rightBar : leftBar;
    crossScrollbar = (dir == FlexDirection.column) ? leftBar : rightBar;
  }
}

/**
 * WidgetViewController reacting to `virtListMetricsChanged`,
 * `virtListMainScroll`, and `virtListCrossScroll` events, synchronizing
 * scrollbars and emitting the configured external `VirtList` event when the
 * visible item range changes.
 */
final class VirtListWidgetViewController : WidgetViewControllerBase {
  /// Constructs `VirtListWidgetViewController`.
  this(UiSystem uiSystem) {
    assert(uiSystem !is null, "uiSystem must not be null");
    super(uiSystem);
  }

  override bool update() {
    return true;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind != AppEvent.Kind.view || ev.view.viewWidget is null) {
      return super.handleEvent(ev);
    }
    foreach (v; views) {
      auto vlv = cast(VirtListWidgetView) v;
      if (vlv is null) {
        continue;
      }
      if (v.isWidgetRegistered(ev.view.viewWidget)) {
        bool needModelUpdate = false;
        if (handleRootEvent(vlv, ev, needModelUpdate)) {
          const auto res = needModelUpdate
            ? HandleResult.Result.update
            : HandleResult.Result.updateView;
          return HandleResult(res, true);
        }
        return super.handleEvent(ev);
      }
      if (handleOwnedScrollbarEvent(vlv, ev)) {
        return HandleResult(HandleResult.Result.updateView, true);
      }
    }
    return super.handleEvent(ev);
  }

private:
  bool handleRootEvent(
    VirtListWidgetView vlv,
    AppEvent ev,
    out bool needModelUpdate
  ) {
    const string evName = ev.view.eventName;
    if (evName == virtListMetricsChangedEvent) {
      auto val = VirtListComponent.AppEventViewValue.fromRaw(ev.view.value);
      if (vlv.handleMetricsChanged(ev.view.viewWidget, val)) {
        emitVisibleChanged(vlv, ev.view.viewWidget, val.firstVisibleIndex);
      }
      needModelUpdate = true;
      return true;
    }
    if (evName == virtListMainScrollEvent) {
      vlv.applyMainScrollOffset(ev.view.viewWidget, cast(long) ev.view.value[0]);
      return true;
    }
    if (evName == virtListCrossScrollEvent) {
      vlv.applyCrossScrollOffset(
        ev.view.viewWidget, cast(long) ev.view.value[0]
      );
      return true;
    }
    return false;
  }

  bool handleOwnedScrollbarEvent(VirtListWidgetView vlv, AppEvent ev) {
    Widget vlRoot = vlv.findRootForScrollbar(ev.view.viewWidget);
    if (vlRoot is null) {
      return false;
    }
    const string evName = ev.view.eventName;
    if (evName == virtListMainScrollEvent) {
      vlv.applyMainScrollOffset(vlRoot, cast(long) ev.view.value[0]);
      return true;
    }
    if (evName == virtListCrossScrollEvent) {
      vlv.applyCrossScrollOffset(vlRoot, cast(long) ev.view.value[0]);
      return true;
    }
    return false;
  }

  void emitVisibleChanged(
    VirtListWidgetView vlv,
    Widget viewWidget,
    uint firstVisibleIndex
  ) {
    const string targetEvent = vlv.getEventName(viewWidget);
    if (targetEvent.length == 0) {
      return;
    }
    auto outEv = ViewAppEventBuilder(targetEvent)
      .widget(viewWidget)
      .viewWidget(viewWidget)
      .value(cast(ulong) firstVisibleIndex)
      .build();
    uiSystem.sendAppEvent(outEv);
  }
}

/**
 * Fluent builder constructing a composite `VirtList` widget tree (viewport +
 * main-axis and cross-axis `Scrollbar`s + corner box) and registering it with
 * `VirtListWidgetView` via `UiRegistry`.
 */
struct VirtListBuilder {
  /// Sets the root widget name.
  ref VirtListBuilder name(string controlName) return {
    widgetName = controlName;
    return this;
  }

  /// Binds a `VirtListModel` instance.
  ref VirtListBuilder model(VirtListModel m) return {
    assert(m !is null, "m must not be null");
    listTracker = ModelTracker!VirtListModel(m);
    hasModel = true;
    return this;
  }

  /// Binds an existing `ModelTracker!VirtListModel`.
  ref VirtListBuilder modelTracker(
    ref ModelTracker!VirtListModel tracker
  ) return {
    listTracker = ModelTracker!VirtListModel.from(tracker);
    hasModel = true;
    return this;
  }

  /// Sets the item widget provider (`p` is allowed to be null).
  ref VirtListBuilder provider(VirtListProvider p) return {
    listProvider = p;
    return this;
  }

  /// Sets the external view event name emitted when visible range changes.
  ref VirtListBuilder event(string customEventName) return {
    eventName = customEventName;
    return this;
  }

  /// Sets the main-axis layout direction (`column` or `row`).
  ref VirtListBuilder direction(FlexDirection dir) return {
    listDirection = dir;
    return this;
  }

  /// Sets spacing between list items along the main axis.
  ref VirtListBuilder gap(float g) return {
    customItemGap = g;
    return this;
  }

  /// Sets the estimated main-axis size for unmeasured items.
  ref VirtListBuilder defaultItemSize(float sz) return {
    customDefaultItemSize = sz;
    return this;
  }

  /// Enables or disables stretching non-fixed item cross size to viewport.
  ref VirtListBuilder stretchCrossAxis(bool stretch) return {
    stretchCross = stretch;
    return this;
  }

  /// Sets visual styling and sizing configuration.
  ref VirtListBuilder style(in VirtListStyle s) return {
    cfg = s;
    return this;
  }

  /**
   * Builds the `VirtList` composite widget tree.
   *
   * Params:
   *   ui = Active `UiSystem` (must not be null).
   *   parent = Parent widget (allowed to be null in isolated tests).
   *   rect = Initial rectangle of the `VirtList` root container.
   *   registry = `UiRegistry` used to look up `VirtListWidgetView` and
   *     `ScrollbarWidgetView` (defaults to `ui` when null).
   */
  Widget build(
    UiSystem ui,
    Widget parent,
    RectF rect,
    UiRegistry registry
  ) {
    assert(ui !is null, "ui must not be null");
    if (registry is null) {
      registry = ui;
    }
    if (!hasModel) {
      listTracker = ModelTracker!VirtListModel(new VirtListModel());
      hasModel = true;
    }

    const string rootName = (widgetName.length > 0) ? widgetName : "virtList";
    const string targetEvent = (eventName.length > 0)
      ? eventName
      : defaultVirtListEventName;
    const string[string] renameMap = [
      virtListMetricsChangedEvent: virtListMetricsChangedEvent,
      virtListMainScrollEvent: virtListMainScrollEvent,
      virtListCrossScrollEvent: virtListCrossScrollEvent,
    ];

    Widget root = WidgetBuilder.make(ui)
      .parent(parent)
      .name(rootName)
      .rect(rect)
      .flexColumn()
      .gap(cfg.scrollbarGap)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.stretch)
      .viewEvents(renameMap.dup)
      .viewName(virtListWidgetViewName)
      .build();

    buildAndRegisterParts(ui, registry, root, rootName, rect, targetEvent);
    return root;
  }

private:
  void buildAndRegisterParts(
    UiSystem ui,
    UiRegistry registry,
    Widget root,
    string rootName,
    RectF rect,
    string targetEvent
  ) {
    import std.algorithm.comparison : max;
    const float thickness = max(4.0f, cfg.scrollbarThickness);
    const float sbGap = max(0.0f, cfg.scrollbarGap);
    const float topH = max(1.0f, rect.height - thickness - sbGap);
    const float vpW = max(1.0f, rect.width - thickness - sbGap);

    Widget topRow = buildTopRow(ui, root, rootName, rect.width, topH, sbGap);
    Widget viewport = buildViewport(ui, topRow, rootName, vpW, topH);

    auto mainTracker = createMainScrollTracker();
    auto crossTracker = createCrossScrollTracker();
    const bool isColumn = (listDirection == FlexDirection.column);

    Widget rightBar = buildVerticalScrollbar(
      ui, registry, topRow, rootName, thickness, topH,
      isColumn ? mainTracker : crossTracker,
      isColumn ? virtListMainScrollEvent : virtListCrossScrollEvent
    );
    Widget bottomRow = buildBottomRow(
      ui, root, rootName, rect.width, thickness, sbGap
    );
    Widget bottomBar = buildHorizontalScrollbar(
      ui, registry, bottomRow, rootName, vpW, thickness,
      isColumn ? crossTracker : mainTracker,
      isColumn ? virtListCrossScrollEvent : virtListMainScrollEvent
    );
    Widget cornerBox = buildCornerBox(ui, bottomRow, rootName, thickness);

    root.update(WidgetUpdateScope.parentView);
    Widget mainSb = isColumn ? rightBar : bottomBar;
    Widget crossSb = isColumn ? bottomBar : rightBar;
    registerBuiltVirtList(
      registry, root, mainTracker, crossTracker,
      viewport, mainSb, crossSb, cornerBox, targetEvent
    );
  }

  Widget buildTopRow(
    UiSystem ui,
    Widget root,
    string rootName,
    float w,
    float h,
    float sbGap
  ) {
    return WidgetBuilder.make(ui)
      .parent(root)
      .name(rootName ~ "TopRow")
      .rect(RectF(0, 0, w, h))
      .fractionWidth(1.0f)
      .fractionHeight(1.0f)
      .minWidth(1.0f)
      .minHeight(1.0f)
      .flexRow()
      .gap(sbGap)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.stretch)
      .build();
  }

  Widget buildViewport(
    UiSystem ui,
    Widget topRow,
    string rootName,
    float w,
    float h
  ) {
    const float effGap = (customItemGap >= 0.0f) ? customItemGap : cfg.itemGap;
    const float effItemSize = (customDefaultItemSize > 0.0f)
      ? customDefaultItemSize
      : cfg.defaultItemMainSize;
    Widget vp = WidgetBuilder.make(ui)
      .parent(topRow)
      .name(rootName ~ "Viewport")
      .rect(RectF(0, 0, w, h))
      .fractionWidth(1.0f)
      .fractionHeight(1.0f)
      .minWidth(1.0f)
      .minHeight(1.0f)
      .padding(cfg.viewportPadding)
      .roundBg(cfg.viewportBg)
      .bgRadius(cfg.cornerRadius)
      .border(cfg.viewportBorder)
      .borderWidth(1.0f)
      .virtList(listProvider)
      .virtListCount(listTracker.model.itemsCount)
      .virtListDirection(listDirection)
      .virtListGap(effGap)
      .virtListStretchCross(stretchCross)
      .onVirtListMetricsChanged(virtListMetricsChangedEvent)
      .build();
    vp.components.virtList.defaultItemMainSize = effItemSize;
    return vp;
  }

  Widget buildBottomRow(
    UiSystem ui,
    Widget root,
    string rootName,
    float w,
    float thickness,
    float sbGap
  ) {
    return WidgetBuilder.make(ui)
      .parent(root)
      .name(rootName ~ "BottomRow")
      .rect(RectF(0, 0, w, thickness))
      .fractionWidth(1.0f)
      .fixedHeight(thickness)
      .minWidth(1.0f)
      .flexRow()
      .gap(sbGap)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.stretch)
      .build();
  }

  Widget buildVerticalScrollbar(
    UiSystem ui,
    UiRegistry registry,
    Widget topRow,
    string rootName,
    float thickness,
    float h,
    ref ModelTracker!ScrollbarModel tracker,
    string sbEvent
  ) {
    ScrollbarBuilder sb;
    Widget bar = sb
      .name(rootName ~ "VScroll")
      .modelTracker(tracker)
      .event(sbEvent)
      .direction(FlexDirection.column)
      .thickness(thickness)
      .style(cfg.scrollbarStyle)
      .build(ui, topRow, RectF(0, 0, thickness, h), registry);
    auto sz = new Size();
    sz.width = Dimension(thickness, SizingMode.fixed);
    sz.height = Dimension(1.0f, SizingMode.fraction);
    sz.minHeight = 1.0f;
    bar.components.size = sz;
    return bar;
  }

  Widget buildHorizontalScrollbar(
    UiSystem ui,
    UiRegistry registry,
    Widget bottomRow,
    string rootName,
    float w,
    float thickness,
    ref ModelTracker!ScrollbarModel tracker,
    string sbEvent
  ) {
    ScrollbarBuilder sb;
    Widget bar = sb
      .name(rootName ~ "HScroll")
      .modelTracker(tracker)
      .event(sbEvent)
      .direction(FlexDirection.row)
      .thickness(thickness)
      .style(cfg.scrollbarStyle)
      .build(ui, bottomRow, RectF(0, 0, w, thickness), registry);
    auto sz = new Size();
    sz.width = Dimension(1.0f, SizingMode.fraction);
    sz.height = Dimension(thickness, SizingMode.fixed);
    sz.minWidth = 1.0f;
    bar.components.size = sz;
    return bar;
  }

  Widget buildCornerBox(
    UiSystem ui,
    Widget bottomRow,
    string rootName,
    float thickness
  ) {
    return WidgetBuilder.make(ui)
      .parent(bottomRow)
      .name(rootName ~ "Corner")
      .rect(RectF(0, 0, thickness, thickness))
      .fixedSize(thickness, thickness)
      .roundBg(cfg.cornerBg)
      .bgRadius(cfg.scrollbarStyle.cornerRadius)
      .border(cfg.cornerBorder)
      .borderWidth(1.0f)
      .build();
  }

  ModelTracker!ScrollbarModel createMainScrollTracker() {
    import std.algorithm.comparison : max;
    const float effItemSize = (customDefaultItemSize > 0.0f)
      ? customDefaultItemSize
      : cfg.defaultItemMainSize;
    const long step = max(1L, cast(long) round(effItemSize));
    auto m = new ScrollbarModel()
      .withRange(0, 0)
      .withValue(0)
      .withVisibleSize(1)
      .withStepSize(step);
    return ModelTracker!ScrollbarModel(m);
  }

  ModelTracker!ScrollbarModel createCrossScrollTracker() {
    auto m = new ScrollbarModel()
      .withRange(0, 0)
      .withValue(0)
      .withVisibleSize(1)
      .withStepSize(24);
    return ModelTracker!ScrollbarModel(m);
  }

  void registerBuiltVirtList(
    UiRegistry registry,
    Widget root,
    ref ModelTracker!ScrollbarModel mainTracker,
    ref ModelTracker!ScrollbarModel crossTracker,
    Widget viewport,
    Widget mainSb,
    Widget crossSb,
    Widget cornerBox,
    string targetEvent
  ) {
    if (registry is null) {
      return;
    }
    if (WidgetView wv = registry.widgetViews.getByName(
        virtListWidgetViewName
      )) {
      if (auto vlv = cast(VirtListWidgetView) wv) {
        vlv.registerVirtList(
          root, listTracker, mainTracker, crossTracker,
          viewport, mainSb, crossSb, cornerBox, listDirection, targetEvent
        );
      }
    }
  }

  ModelTracker!VirtListModel listTracker;
  bool hasModel = false;
  VirtListProvider listProvider = null;
  string eventName = defaultVirtListEventName;
  FlexDirection listDirection = FlexDirection.column;
  float customItemGap = -1.0f;
  float customDefaultItemSize = 0.0f;
  bool stretchCross = false;
  VirtListStyle cfg;
  string widgetName = null;
}

/**
 * Registers a shared `VirtListWidgetView` and `VirtListWidgetViewController`
 * into `ui` and links them together.
 */
VirtListWidgetViewController registerVirtList(UiSystem ui) {
  assert(ui !is null, "ui must not be null");
  auto view = new VirtListWidgetView();
  auto ctrl = new VirtListWidgetViewController(ui);
  ctrl.registerWidgetView(view);
  ui.widgetViews.register(view.getWidgetViewName(), view);
  ui.widgetViewControllers.register(ctrl.getControllerName(), ctrl);
  return ctrl;
}

version (unittest) {
  import guidemo.scrollbars : registerScrollbars, ScrollbarWidgetView;
  import yguilib.app : App;
  import yguilib.controller : DefaultController;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.timers : invalidTimerId, TimerId, TimerMode;
  import yguilib.widget.drawing_components : TextLabel;

private:
  final class DemoTestRowProvider : VirtListProvider {
    UiSystem ui;
    size_t createCount = 0;
    size_t updateCount = 0;
    size_t recycleCount = 0;
    float[size_t] mainOverrides;
    float[size_t] crossOverrides;
    bool isRow = false;

    this(UiSystem ui) {
      assert(ui !is null, "ui must not be null");
      this.ui = ui;
    }

    invariant {
      assert(ui !is null);
    }

    override Widget createWidget(Widget parent) {
      createCount++;
      return WidgetBuilder.make(ui)
        .parent(parent)
        .name("demoVirtRow")
        .rect(RectF(0, 0, 220, 40))
        .fixedSize(220, 40)
        .text("row")
        .build();
    }

    override void updateWidgetAt(Widget w, size_t index) {
      import std.format : format;
      updateCount++;
      const float mainSz = (index in mainOverrides)
        ? mainOverrides[index]
        : 40.0f;
      const float crossSz = (index in crossOverrides)
        ? crossOverrides[index]
        : 220.0f;
      if (w.components.size !is null) {
        if (isRow) {
          w.components.size.width = Dimension(mainSz, SizingMode.fixed);
          w.components.size.height = Dimension(crossSz, SizingMode.fixed);
        } else {
          w.components.size.width = Dimension(crossSz, SizingMode.fixed);
          w.components.size.height = Dimension(mainSz, SizingMode.fixed);
        }
      }
      w.setCaption(format("Item #%d", index));
      w.update(WidgetUpdateScope.layout);
    }

    override void onWidgetRecycled(Widget w) {
      recycleCount++;
    }
  }

  RectF calcAbsRect(Widget w) {
    float x = w.rect.x;
    float y = w.rect.y;
    for (Widget p = w.parent; p !is null; p = p.parent) {
      x += p.rect.x;
      y += p.rect.y;
    }
    return RectF(x, y, w.rect.width, w.rect.height);
  }

  void verifyAllNamed(Widget w) {
    assert(w !is null);
    assert(w.name.length > 0, "Widget missing name");
    foreach (child; w.children) {
      verifyAllNamed(child);
    }
  }

  void runVirtListPipelineTest() {
    auto app = App.makeAppWithTitleWh("virtlist_test", 400, 300);
    auto ui = app.ui;
    ui.pushController(registerScrollbars(ui));
    ui.pushController(registerVirtList(ui));

    auto vlView = cast(VirtListWidgetView)
      ui.widgetViews.getByName(virtListWidgetViewName);
    auto sbView = cast(ScrollbarWidgetView)
      ui.widgetViews.getByName("ScrollbarWidgetView");
    assert(vlView !is null && sbView !is null);

    auto model = new VirtListModel(10000);
    auto tracker = ModelTracker!VirtListModel(model);
    auto provider = new DemoTestRowProvider(ui);
    provider.crossOverrides[0] = 600.0f;

    VirtListBuilder b;
    Widget vlRoot = b
      .name("pipelineList")
      .modelTracker(tracker)
      .provider(provider)
      .event("myListChanged")
      .direction(FlexDirection.column)
      .gap(4.0f)
      .defaultItemSize(40.0f)
      .build(ui, null, RectF(0, 0, 400, 300), ui);
    verifyAllNamed(vlRoot);
    ui.mainWindow().rootWidget = vlRoot;

    Widget vp = vlView.getViewport(vlRoot);
    Widget mainSb = vlView.getMainScrollbar(vlRoot);
    Widget crossSb = vlView.getCrossScrollbar(vlRoot);
    assert(vp !is null && mainSb !is null && crossSb !is null);

    auto testCtrl = new PipelineTestController(ui);
    testCtrl.vlView = vlView;
    testCtrl.sbView = sbView;
    testCtrl.vlRoot = vlRoot;
    testCtrl.vp = vp;
    testCtrl.mainSb = mainSb;
    testCtrl.crossSb = crossSb;
    testCtrl.tracker = ModelTracker!VirtListModel.from(tracker);
    testCtrl.provider = provider;
    app.run(testCtrl);
    assert(testCtrl.completed);
    ui.releaseWidget(vlRoot);
    assert(!vlView.isWidgetRegistered(vlRoot));
  }

  final class PipelineTestController : DefaultController {
    VirtListWidgetView vlView;
    ScrollbarWidgetView sbView;
    Widget vlRoot;
    Widget vp;
    Widget mainSb;
    Widget crossSb;
    ModelTracker!VirtListModel tracker;
    DemoTestRowProvider provider;
    int stage = 0;
    int retries = 0;
    bool completed = false;
    size_t externalEvents = 0;
    TimerId timerId = invalidTimerId;

    this(UiSystem ui) {
      assert(ui !is null, "ui must not be null");
      super(ui);
    }

    override HandleResult handleEvent(AppEvent ev) {
      if (ev.kind == AppEvent.Kind.view &&
          ev.view.eventName == "myListChanged") {
        externalEvents++;
        advanceStage();
        return HandleResult(HandleResult.Result.nothing, false);
      }
      if (ev.kind == AppEvent.Kind.user && ev.user.eventId == 700) {
        return HandleResult(HandleResult.Result.quit, true);
      }
      return super.handleEvent(ev);
    }

    override bool tick(float dt) {
      if (stage == 2) {
        if (tracker.model.scrollOffsetCross <= 0.0f) {
          retries++;
          assert(retries < 30, "Timed out waiting for cross scroll offset");
          return false;
        }
        retries = 0;
        const size_t anchorBefore = vp.components.virtList.anchorIndex;
        auto m = tracker.edit();
        m.insertItems(0, 5);
        m.removeItems(1, 2);
        m.updateItem(anchorBefore + 3);
        provider.mainOverrides[anchorBefore + 3] = 88.0f;
        tracker.commit(m);
        stage = 3;
        uiSystem.sendAppEvent(AppEvent.makeNoRepeat(AppEvent.Kind.update));
        return false;
      }
      if (stage == 3) {
        const auto vc = vp.components.virtList;
        if (vc.itemsCount != 10003) {
          retries++;
          assert(retries < 30, "Timed out waiting for VirtList layout update");
          return false;
        }
        assert(tracker.model.itemsCount == 10003);
        assert(vc.anchorIndex >= 50);
        completed = true;
        uiSystem.stopTimer(timerId);
        uiSystem.sendAppEvent(AppEvent.userEvent(AppEvent.UserData(700)));
      }
      return false;
    }

    void advanceStage() {
      if (stage == 0) {
        assert(tracker.model.firstVisibleIndex == 0);
        assert(tracker.model.visibleItemsCount > 0);
        assert(vp.components.virtList.activeWidgetsCount <= 10);
        assert(provider.createCount <= 10);
        stage = 1;
        dragMainThumb();
      } else if (stage == 1) {
        assert(tracker.model.firstVisibleIndex > 50);
        assert(provider.recycleCount > 0);
        assert(provider.createCount <= 12);
        stage = 2;
        testCrossScrollAndMutations();
      }
    }

    void dragMainThumb() {
      Widget thumb = sbView.getThumb(mainSb);
      const RectF tr = calcAbsRect(thumb);
      const float sx = tr.x + tr.width * 0.5f;
      const float sy = tr.y + tr.height * 0.5f;
      uiSystem.sendAppEvent(AppEvent.mouseEvent(
        AppEvent.Kind.mouseButtonDown,
        AppEvent.MouseData(1, sx, sy, 1, 0.0f, 0.0f, 1, true, 1)
      ));
      uiSystem.sendAppEvent(AppEvent.mouseEvent(
        AppEvent.Kind.mouseMotion,
        AppEvent.MouseData(1, sx, sy + 40.0f, 1, 0.0f, 40.0f, 0, false, 0)
      ));
      uiSystem.sendAppEvent(AppEvent.mouseEvent(
        AppEvent.Kind.mouseButtonUp,
        AppEvent.MouseData(1, sx, sy + 40.0f, 0, 0.0f, 0.0f, 1, false, 1)
      ));
    }

    void testCrossScrollAndMutations() {
      Widget crossInc = sbView.getIncButton(crossSb);
      const RectF cr = calcAbsRect(crossInc);
      const float cx = cr.x + cr.width * 0.5f;
      const float cy = cr.y + cr.height * 0.5f;
      uiSystem.sendAppEvent(AppEvent.mouseEvent(
        AppEvent.Kind.mouseButtonDown,
        AppEvent.MouseData(1, cx, cy, 1, 0.0f, 0.0f, 1, true, 1)
      ));
      uiSystem.sendAppEvent(AppEvent.mouseEvent(
        AppEvent.Kind.mouseButtonUp,
        AppEvent.MouseData(1, cx, cy, 0, 0.0f, 0.0f, 1, false, 1)
      ));
      timerId = uiSystem.startControllerTimer(this, 1, TimerMode.repeat);
    }
  }
}

// Verifies vertical & horizontal VirtList construction, naming, scrollbar
// routing, model mutations, and clean widget release headlessly.
unittest {
  auto ui = new UiSystemImpl(null);
  ui.pushController(registerScrollbars(ui));
  auto ctrl = registerVirtList(ui);

  auto vlView = cast(VirtListWidgetView)
    ui.widgetViews.getByName(virtListWidgetViewName);
  assert(vlView !is null);
  assert(
    ui.widgetViewControllers.getByName(virtListWidgetViewControllerName)
      is ctrl
  );

  auto vModel = new VirtListModel(50);
  auto vTracker = ModelTracker!VirtListModel(vModel);
  auto vProvider = new DemoTestRowProvider(ui);

  VirtListBuilder vb;
  Widget vList = vb
    .name("vList")
    .modelTracker(vTracker)
    .provider(vProvider)
    .direction(FlexDirection.column)
    .gap(6.0f)
    .defaultItemSize(52.0f)
    .stretchCrossAxis(true)
    .build(ui, null, RectF(0, 0, 420, 320), null);
  verifyAllNamed(vList);
  assert(vlView.isWidgetRegistered(vList));
  assert(vlView.getViewport(vList).components.virtList.gap == 6.0f);
  assert(
    vlView.getViewport(vList).components.virtList.defaultItemMainSize == 52.0f
  );
  assert(vlView.getViewport(vList).components.virtList.stretchCrossAxis);

  // Horizontal mode places cross scrollbar in topRow and main in bottomRow
  auto hModel = new VirtListModel(30);
  auto hProvider = new DemoTestRowProvider(ui);
  VirtListBuilder hb;
  Widget hList = hb
    .name("hList")
    .model(hModel)
    .provider(hProvider)
    .direction(FlexDirection.row)
    .build(ui, null, RectF(0, 0, 420, 220), null);
  verifyAllNamed(hList);
  Widget hMainSb = vlView.getMainScrollbar(hList);
  Widget hCrossSb = vlView.getCrossScrollbar(hList);
  assert(hMainSb.components.flexContainer.direction == FlexDirection.row);
  assert(hCrossSb.components.flexContainer.direction == FlexDirection.column);

  // Scrollbar-emitted scroll event routes to owning VirtList viewport
  auto sbEv = ViewAppEventBuilder(virtListMainScrollEvent)
    .widget(hMainSb)
    .viewWidget(hMainSb)
    .value(240)
    .build();
  auto hr = ctrl.handleEvent(sbEv);
  assert(hr.consume);
  assert(hr.result == HandleResult.Result.updateView);

  // Model insert/remove/update/scrollToIndex synchronization
  auto mEdit = vTracker.edit();
  mEdit.insertItems(2, 4);
  mEdit.removeItems(10, 3);
  mEdit.updateItem(5);
  mEdit.requestScrollToIndex(20);
  vTracker.commit(mEdit);
  assert(ctrl.updateView());
  assert(vlView.getViewport(vList).components.virtList.itemsCount == 51);

  ui.releaseWidget(vList);
  ui.releaseWidget(hList);
  assert(!vlView.isWidgetRegistered(vList));
  assert(!vlView.isWidgetRegistered(hList));
}

// Full WidgetSystemPipeline test across 10,000 items, thumb drag, cross
// scrollbar click, and incremental insert/remove/update reflow.
unittest {
  runVirtListPipelineTest();
}
