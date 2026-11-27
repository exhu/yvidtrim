/**
 * virtlist.d - Reusable model-driven composite VirtList control combining a
 * VirtListComponent viewport with main-axis and cross-axis Scrollbars.
 */
module yguilib.controls.virtlist;

import std.algorithm.comparison : clamp, max, min;
import std.math.rounding : round;
import std.typecons : Nullable;
import yguilib.controller : HandleResult;
import yguilib.controls.common : emitViewValueEvent, findWidgetView, orDefault,
  registerWidgetViewPair;
import yguilib.controls.composite_view : bindCompositeModel,
  ensureDefaultModelTracker, ensureViewWidgetRegistered, findEntry,
  findOwningView, entryField, resolveBuilderRegistry, assignBuilderModel,
  assignBuilderTracker, updateCompositeEntries;
import yguilib.controls.internal.axis : Axis;
import yguilib.controls.scrollbars : ScrollbarBuilder, ScrollbarModel,
  ScrollbarStyle, ScrollbarWidgetView, scrollbarWidgetViewName;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker, VersionedModel;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiRegistry, UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.layout_components : AlignItems, FlexDirection, Insets,
  JustifyContent;
import yguilib.widget.virtlist_components : VirtListChange, VirtListComponent,
  VirtListProvider;
import yguilib.widget.widget_view : WidgetViewBase, WidgetViewControllerBase;

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

/// Default main-axis size in logical points for unmeasured `VirtList` items.
enum defaultVirtListItemMainSize = 48.0f;

/// Default step increment in logical points for the cross-axis scrollbar.
enum defaultVirtListCrossStep = 24.0f;

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

  /// Returns a `VirtListModel` initialized with `initialItemsCount` items.
  static VirtListModel withCount(size_t initialItemsCount) {
    auto m = new VirtListModel();
    m.itemsCount = initialItemsCount;
    return m;
  }

  /// Inserts `count` items at `index` (clamped to `itemsCount`) and records an
  /// incremental insert change.
  void insertItems(size_t index, size_t count) {
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
    fHasPendingScrollIndex = true;
    pendingScrollIndex = index;
  }

package(yguilib):
  bool hasPendingChanges() const nothrow @safe @nogc {
    return pendingChanges.length > 0;
  }

  bool hasPendingScrollIndex() const nothrow @safe @nogc {
    return fHasPendingScrollIndex;
  }

  VirtListChange[] takePendingChanges() {
    VirtListChange[] res = pendingChanges;
    pendingChanges = null;
    return res;
  }

  Nullable!size_t takePendingScrollIndex() {
    if (!fHasPendingScrollIndex) {
      return Nullable!size_t.init;
    }
    const size_t index = pendingScrollIndex;
    fHasPendingScrollIndex = false;
    return Nullable!size_t(index);
  }

private:
  VirtListChange[] pendingChanges;
  bool fHasPendingScrollIndex = false;
  size_t pendingScrollIndex = 0;
}

/// Visual styling and layout configuration for a `VirtList` composite control.
struct VirtListStyle {
  float scrollbarThickness = 18.0f;
  float scrollbarGap = 4.0f;
  float itemGap = 4.0f;
  float defaultItemMainSize = defaultVirtListItemMainSize;
  float cornerRadius = 6.0f;
  Insets viewportPadding = Insets.all(4.0f);
  ColorF viewportBg = ColorF(0.08f, 0.10f, 0.13f, 1.0f);
  ColorF viewportBorder = ColorF(0.24f, 0.30f, 0.40f, 1.0f);
  ColorF cornerBg = ColorF(0.10f, 0.12f, 0.15f, 1.0f);
  ColorF cornerBorder = ColorF(0.20f, 0.23f, 0.29f, 1.0f);
  ScrollbarStyle scrollbarStyle;
}

/// Main and cross scrollbar trackers passed when registering a `VirtList`.
struct VirtListScrollTrackers {
  ModelTracker!ScrollbarModel main;
  ModelTracker!ScrollbarModel cross;
}

/// Parameters for registering a constructed `VirtList` with
/// `VirtListWidgetView`. `mainScrollbar`, `crossScrollbar`, and `cornerBox`
/// may be null in minimal test configurations.
struct VirtListRegistration {
  Widget viewport = null;
  Widget mainScrollbar = null;
  Widget crossScrollbar = null;
  Widget cornerBox = null;
  FlexDirection direction = FlexDirection.column;
  string eventName = defaultVirtListEventName;

  /// Sets the viewport widget.
  ref VirtListRegistration withViewport(Widget vp) return {
    viewport = vp;
    return this;
  }

  /// Sets the main-axis scrollbar widget.
  ref VirtListRegistration withMainScrollbar(Widget sb) return {
    mainScrollbar = sb;
    return this;
  }

  /// Sets the cross-axis scrollbar widget.
  ref VirtListRegistration withCrossScrollbar(Widget sb) return {
    crossScrollbar = sb;
    return this;
  }

  /// Sets the corner box widget.
  ref VirtListRegistration withCornerBox(Widget cb) return {
    cornerBox = cb;
    return this;
  }

  /// Sets the main-axis layout direction.
  ref VirtListRegistration withDirection(FlexDirection dir) return {
    direction = dir;
    return this;
  }

  /// Sets the emitted position-change event name.
  ref VirtListRegistration withEventName(string name) return {
    eventName = name;
    return this;
  }
}

/// Internal bookkeeping entry tracking one composite `VirtList` instance.
private final class VirtListEntry {
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
  void registerVirtList(
    Widget viewWidget,
    ref ModelTracker!VirtListModel tracker,
    ref VirtListScrollTrackers scrollTrackers,
    in VirtListRegistration reg
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    ensureViewWidgetRegistered(this, viewWidget);
    removeScrollbarMappings(viewWidget);
    auto entry = new VirtListEntry(
      tracker, scrollTrackers.main, scrollTrackers.cross
    );
    entry.viewport = cast(Widget) reg.viewport;
    entry.mainScrollbar = cast(Widget) reg.mainScrollbar;
    entry.crossScrollbar = cast(Widget) reg.crossScrollbar;
    entry.cornerBox = cast(Widget) reg.cornerBox;
    entry.direction = reg.direction;
    entry.eventName = orDefault(reg.eventName, defaultVirtListEventName);
    entries[viewWidget] = entry;
    addScrollbarMappings(viewWidget, entry);
    syncModelToViewport(entry);
  }

  /// Associates a `ModelTracker!VirtListModel` with a registered or newly built
  /// `VirtList` root widget.
  void bindModel(Widget viewWidget, ref ModelTracker!VirtListModel tracker) {
    assert(viewWidget !is null, "viewWidget must not be null");
    ensureViewWidgetRegistered(this, viewWidget);
    if (auto entry = findEntry(entries, viewWidget)) {
      entry.tracker = ModelTracker!VirtListModel.from(tracker);
      syncModelToViewport(entry);
      entry.viewDirty = true;
      return;
    }
    bindNewEntryFromTree(viewWidget, tracker);
  }

  /// Associates a `VirtListModel` instance with `viewWidget`.
  void bindModelWithModel(Widget viewWidget, VirtListModel model) {
    bindCompositeModel(this, viewWidget, model);
  }

  override void unregisterViewWidget(Widget viewWidget) {
    removeScrollbarMappings(viewWidget);
    entries.remove(viewWidget);
    super.unregisterViewWidget(viewWidget);
  }

  /// Returns the `VirtListComponent` viewport widget for `viewWidget`, or null
  /// if not registered.
  Widget viewport(Widget viewWidget) {
    return entryField!"viewport"(entries, viewWidget);
  }

  /// Returns the main-axis `Scrollbar` widget for `viewWidget`, or null.
  Widget mainScrollbar(Widget viewWidget) {
    return entryField!"mainScrollbar"(entries, viewWidget);
  }

  /// Returns the cross-axis `Scrollbar` widget for `viewWidget`, or null.
  Widget crossScrollbar(Widget viewWidget) {
    return entryField!"crossScrollbar"(entries, viewWidget);
  }

  /// Returns the configured external view event name for `viewWidget`, or
  /// null if not registered.
  string eventName(Widget viewWidget) {
    return entryField!"eventName"(entries, viewWidget);
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
    auto entry = findEntry(entries, viewWidget);
    return entry !is null && entry.mainScrollbar is scrollbarWidget;
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
    auto entry = findEntry(entries, viewWidget);
    if (entry is null) {
      return false;
    }
    const float defMain = defaultItemMainSize(entry);
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
      defaultVirtListCrossStep
    );
    return updateModelMetrics(entry, val);
  }

  /// Applies a main-axis scroll offset emitted by the main `Scrollbar`.
  bool applyMainScrollOffset(Widget viewWidget, long value) {
    return applyScrollOffset(viewWidget, value, true);
  }

  /// Applies a cross-axis scroll offset emitted by the cross `Scrollbar`.
  bool applyCrossScrollOffset(Widget viewWidget, long value) {
    return applyScrollOffset(viewWidget, value, false);
  }

  override bool update() {
    return updateCompositeEntries(entries, (VirtListEntry entry) {
      return syncModelToViewport(entry);
    });
  }

package(yguilib):
  UiRegistry registry = null;

private:
  struct VirtListParts {
    Widget viewport;
    Widget mainScrollbar;
    Widget crossScrollbar;
    Widget cornerBox;
    FlexDirection dir = FlexDirection.column;
  }

  VirtListEntry[Widget] entries;
  Widget[Widget] scrollbarToRoot;

  bool applyScrollOffset(Widget viewWidget, long value, bool isMain) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto entry = findEntry(entries, viewWidget);
    if (entry is null || entry.viewport is null ||
        entry.viewport.components.virtList is null) {
      return false;
    }
    auto vc = entry.viewport.components.virtList;
    if (isMain) {
      vc.scrollToMainOffset(cast(float) value);
    } else {
      vc.requestCrossOffset(cast(float) value);
    }
    entry.viewport.update(WidgetUpdateScope.layout);
    entry.viewDirty = true;
    return true;
  }

  void addScrollbarMappings(Widget viewWidget, VirtListEntry entry) {
    if (entry.mainScrollbar !is null) {
      scrollbarToRoot[entry.mainScrollbar] = viewWidget;
    }
    if (entry.crossScrollbar !is null) {
      scrollbarToRoot[entry.crossScrollbar] = viewWidget;
    }
  }

  void removeScrollbarMappings(Widget viewWidget) {
    if (auto entry = findEntry(entries, viewWidget)) {
      if (entry.mainScrollbar !is null) {
        scrollbarToRoot.remove(entry.mainScrollbar);
      }
      if (entry.crossScrollbar !is null) {
        scrollbarToRoot.remove(entry.crossScrollbar);
      }
    }
  }

  void bindNewEntryFromTree(
    Widget viewWidget,
    ref ModelTracker!VirtListModel tracker
  ) {
    auto parts = findVirtListParts(viewWidget);
    auto mainTracker = ModelTracker!ScrollbarModel(new ScrollbarModel());
    auto crossTracker = ModelTracker!ScrollbarModel(new ScrollbarModel());
    if (auto sbv = findWidgetView!ScrollbarWidgetView(
        registry, scrollbarWidgetViewName
      )) {
      if (parts.mainScrollbar !is null) {
        sbv.bindModel(parts.mainScrollbar, mainTracker);
      }
      if (parts.crossScrollbar !is null) {
        sbv.bindModel(parts.crossScrollbar, crossTracker);
      }
    }
    auto scrollTrackers = VirtListScrollTrackers(mainTracker, crossTracker);
    auto reg = VirtListRegistration()
      .withViewport(parts.viewport)
      .withMainScrollbar(parts.mainScrollbar)
      .withCrossScrollbar(parts.crossScrollbar)
      .withCornerBox(parts.cornerBox)
      .withDirection(parts.dir)
      .withEventName(defaultVirtListEventName);
    registerVirtList(viewWidget, tracker, scrollTrackers, reg);
  }

  static float defaultItemMainSize(VirtListEntry entry) {
    if (entry.viewport !is null &&
        entry.viewport.components.virtList !is null) {
      return entry.viewport.components.virtList.defaultItemMainSize;
    }
    return defaultVirtListItemMainSize;
  }

  static void syncScrollbarTracker(
    ref ModelTracker!ScrollbarModel sbTracker,
    float contentExtent,
    float viewportExtent,
    float offset,
    float stepFloat
  ) {
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
    editable.updateMetrics(0, newMax, newVis, newStep, newVal);
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
    const auto m = entry.tracker.model;
    const bool hasChanges = m.hasPendingChanges();
    const bool hasScroll = m.hasPendingScrollIndex();
    const size_t targetCount = m.itemsCount;
    const bool countChanged = (vc.itemsCount != targetCount);
    if (!hasChanges && !hasScroll && !countChanged) {
      return false;
    }

    VirtListChange[] changes = null;
    Nullable!size_t scrollIdx;
    if (hasChanges || hasScroll) {
      auto mutModel = entry.tracker.edit();
      changes = mutModel.takePendingChanges();
      scrollIdx = mutModel.takePendingScrollIndex();
      entry.tracker.commit(mutModel);
    }

    applyChangesToComponent(vc, changes, targetCount, countChanged);
    if (!scrollIdx.isNull) {
      vc.scrollToIndex(scrollIdx.get());
    }
    entry.viewport.update(WidgetUpdateScope.layout);
    return true;
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

  static VirtListParts findVirtListParts(Widget viewWidget) {
    VirtListParts parts;
    if (viewWidget is null || viewWidget.children.length < 2) {
      return parts;
    }
    Widget topRow = viewWidget.children[0];
    Widget bottomRow = viewWidget.children[1];
    Widget rightBar = (topRow.children.length >= 2)
      ? topRow.children[1]
      : null;
    Widget bottomBar = (bottomRow.children.length >= 1)
      ? bottomRow.children[0]
      : null;
    parts.viewport = (topRow.children.length >= 1) ? topRow.children[0] : null;
    parts.cornerBox = (bottomRow.children.length >= 2)
      ? bottomRow.children[1]
      : null;
    if (parts.viewport !is null &&
        parts.viewport.components.virtList !is null) {
      parts.dir = parts.viewport.components.virtList.direction;
    }
    parts.mainScrollbar =
      (parts.dir == FlexDirection.column) ? rightBar : bottomBar;
    parts.crossScrollbar =
      (parts.dir == FlexDirection.column) ? bottomBar : rightBar;
    return parts;
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

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind != AppEvent.Kind.view || ev.view.viewWidget is null) {
      return super.handleEvent(ev);
    }

    if (auto vlv = findOwningView!VirtListWidgetView(
        views, ev.view.viewWidget
      )) {
      const RootEventResult rootRes = handleRootEvent(vlv, ev);
      if (rootRes.handled) {
        const auto res = rootRes.needModelUpdate
          ? HandleResult.Result.update
          : HandleResult.Result.updateView;
        return HandleResult(res, true);
      }
      return super.handleEvent(ev);
    }

    foreach (v; views) {
      if (auto vlv = cast(VirtListWidgetView) v) {
        if (handleOwnedScrollbarEvent(vlv, ev)) {
          return HandleResult(HandleResult.Result.updateView, true);
        }
      }
    }
    return super.handleEvent(ev);
  }

private:
  struct RootEventResult {
    bool handled;
    bool needModelUpdate;
  }

  bool routeScrollEvent(
    VirtListWidgetView vlv,
    Widget root,
    AppEvent ev
  ) {
    const string evName = ev.view.eventName;
    if (evName == virtListMainScrollEvent) {
      vlv.applyMainScrollOffset(root, cast(long) ev.view.value[0]);
      return true;
    }
    if (evName == virtListCrossScrollEvent) {
      vlv.applyCrossScrollOffset(root, cast(long) ev.view.value[0]);
      return true;
    }
    return false;
  }

  RootEventResult handleRootEvent(VirtListWidgetView vlv, AppEvent ev) {
    if (ev.view.eventName == virtListMetricsChangedEvent) {
      auto val = VirtListComponent.AppEventViewValue.fromRaw(ev.view.value);
      if (vlv.handleMetricsChanged(ev.view.viewWidget, val)) {
        emitViewValueEvent(
          uiSystem,
          vlv.eventName(ev.view.viewWidget),
          ev.view.viewWidget,
          cast(ulong) val.firstVisibleIndex
        );
      }
      return RootEventResult(true, true);
    }
    return RootEventResult(
      routeScrollEvent(vlv, ev.view.viewWidget, ev), false
    );
  }

  bool handleOwnedScrollbarEvent(VirtListWidgetView vlv, AppEvent ev) {
    Widget vlRoot = vlv.findRootForScrollbar(ev.view.viewWidget);
    if (vlRoot is null) {
      return false;
    }
    return routeScrollEvent(vlv, vlRoot, ev);
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
    assignBuilderModel(listTracker, m);
    return this;
  }

  /// Binds an existing `ModelTracker!VirtListModel`.
  ref VirtListBuilder modelTracker(
    ref ModelTracker!VirtListModel tracker
  ) return {
    assignBuilderTracker(listTracker, tracker);
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
    registry = resolveBuilderRegistry(ui, registry);
    ensureDefaultModelTracker(listTracker, () => new VirtListModel());

    const string rootName = orDefault(widgetName, "virtList");
    const string targetEvent = orDefault(eventName, defaultVirtListEventName);
    string[string] renameMap = [
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
      .viewEvents(renameMap)
      .viewName(virtListWidgetViewName)
      .build();

    buildAndRegisterParts(BuildPartsParams(
      ui, registry, root, rootName, rect, targetEvent
    ));
    return root;
  }

private:
  struct BuildPartsParams {
    UiSystem ui;
    UiRegistry registry;
    Widget root;
    string rootName;
    RectF rect;
    string targetEvent;
  }

  struct RowSpec {
    string suffix;
    float width;
    float height;
    float gap;
    bool fixedHeightMode = false;
  }

  struct ScrollbarSpec {
    string name;
    FlexDirection dir;
    float thickness;
    float mainLen;
    string eventName;
  }

  float effItemSize() const {
    return (customDefaultItemSize > 0.0f)
      ? customDefaultItemSize
      : cfg.defaultItemMainSize;
  }

  void buildAndRegisterParts(BuildPartsParams p) {
    const float thickness = max(4.0f, cfg.scrollbarThickness);
    const float sbGap = max(0.0f, cfg.scrollbarGap);
    const float topH = max(1.0f, p.rect.height - thickness - sbGap);
    const float vpW = max(1.0f, p.rect.width - thickness - sbGap);

    Widget topRow = buildRow(p.ui, p.root, p.rootName, RowSpec(
      "TopRow", p.rect.width, topH, sbGap, false
    ));
    Widget viewport = buildViewport(p.ui, topRow, p.rootName, vpW, topH);

    const long mainStep = max(1L, cast(long) round(effItemSize()));
    auto mainTracker = makeScrollTracker(mainStep);
    auto crossTracker = makeScrollTracker(cast(long) defaultVirtListCrossStep);
    const bool isColumn = (listDirection == FlexDirection.column);

    Widget rightBar = buildScrollbar(
      p.ui, p.registry, topRow,
      isColumn ? mainTracker : crossTracker,
      ScrollbarSpec(
        p.rootName ~ "VScroll", FlexDirection.column, thickness, topH,
        isColumn ? virtListMainScrollEvent : virtListCrossScrollEvent
      )
    );
    Widget bottomRow = buildRow(p.ui, p.root, p.rootName, RowSpec(
      "BottomRow", p.rect.width, thickness, sbGap, true
    ));
    Widget bottomBar = buildScrollbar(
      p.ui, p.registry, bottomRow,
      isColumn ? crossTracker : mainTracker,
      ScrollbarSpec(
        p.rootName ~ "HScroll", FlexDirection.row, thickness, vpW,
        isColumn ? virtListCrossScrollEvent : virtListMainScrollEvent
      )
    );
    Widget cornerBox = buildCornerBox(p.ui, bottomRow, p.rootName, thickness);

    p.root.update(WidgetUpdateScope.parentView);
    auto scrollTrackers = VirtListScrollTrackers(mainTracker, crossTracker);
    auto reg = VirtListRegistration()
      .withViewport(viewport)
      .withMainScrollbar(isColumn ? rightBar : bottomBar)
      .withCrossScrollbar(isColumn ? bottomBar : rightBar)
      .withCornerBox(cornerBox)
      .withDirection(listDirection)
      .withEventName(p.targetEvent);
    registerBuiltVirtList(p.registry, p.root, scrollTrackers, reg);
  }

  Widget buildRow(
    UiSystem ui,
    Widget root,
    string rootName,
    in RowSpec spec
  ) {
    auto b = WidgetBuilder.make(ui)
      .parent(root)
      .name(rootName ~ spec.suffix)
      .rect(RectF(0, 0, spec.width, spec.height))
      .fractionWidth(1.0f)
      .minWidth(1.0f);
    if (spec.fixedHeightMode) {
      b.fixedHeight(spec.height);
    } else {
      b.fractionHeight(1.0f).minHeight(1.0f);
    }
    return b
      .flexRow()
      .gap(spec.gap)
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
      .virtListCount(listTracker.get.model.itemsCount)
      .virtListDirection(listDirection)
      .virtListGap(effGap)
      .virtListStretchCross(stretchCross)
      .onVirtListMetricsChanged(virtListMetricsChangedEvent)
      .build();
    vp.components.virtList.defaultItemMainSize = effItemSize();
    return vp;
  }

  Widget buildScrollbar(
    UiSystem ui,
    UiRegistry registry,
    Widget parent,
    ref ModelTracker!ScrollbarModel tracker,
    in ScrollbarSpec spec
  ) {
    const Axis ax = Axis.of(spec.dir);
    const RectF sbRect = ax.isRow
      ? RectF(0, 0, spec.mainLen, spec.thickness)
      : RectF(0, 0, spec.thickness, spec.mainLen);
    ScrollbarBuilder sb;
    Widget bar = sb
      .name(spec.name)
      .modelTracker(tracker)
      .event(spec.eventName)
      .direction(spec.dir)
      .thickness(spec.thickness)
      .style(cfg.scrollbarStyle)
      .build(ui, parent, sbRect, registry);
    auto sz = ax.fillMainFixedCross(spec.thickness);
    if (ax.isRow) {
      sz.minWidth = 1.0f;
    } else {
      sz.minHeight = 1.0f;
    }
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

  static ModelTracker!ScrollbarModel makeScrollTracker(long step) {
    auto m = new ScrollbarModel()
      .withRange(0, 0)
      .withValue(0)
      .withVisibleSize(1)
      .withStepSize(step);
    return ModelTracker!ScrollbarModel(m);
  }

  void registerBuiltVirtList(
    UiRegistry registry,
    Widget root,
    ref VirtListScrollTrackers scrollTrackers,
    VirtListRegistration reg
  ) {
    if (auto vlv = findWidgetView!VirtListWidgetView(
        registry, virtListWidgetViewName
      )) {
      vlv.registerVirtList(root, listTracker.get, scrollTrackers, reg);
    }
  }

  Nullable!(ModelTracker!VirtListModel) listTracker;
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
  auto ctrl = registerWidgetViewPair!(
    VirtListWidgetView,
    VirtListWidgetViewController
  )(ui);
  if (auto vlv = findWidgetView!VirtListWidgetView(
      ui, virtListWidgetViewName
    )) {
    vlv.registry = ui;
  }
  return ctrl;
}

version (unittest) {
  import yguilib.app : App;
  import yguilib.controller : DefaultController;
  import yguilib.controls.scrollbars : registerScrollbars,
    ScrollbarWidgetView;
  import yguilib.controls.testing : calcAbsRect, verifyAllNamed;
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.timercontrol : TimerId, invalidTimerId;
  import yguilib.timers : TimerMode;
  import yguilib.widget.layout_components : Dimension, SizingMode;

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
      if (w.components.textLabel !is null) {
        w.components.textLabel.caption = format("Item #%d", index);
      }
      w.update(WidgetUpdateScope.layout);
    }

    override void onWidgetRecycled(Widget w) {
      recycleCount++;
    }
  }

  void runVirtListPipelineTest() {
    auto app = App.makeAppWithTitleWh("virtlist_test", 400, 300);
    auto ui = app.ui;
    ui.pushController(registerScrollbars(ui));
    ui.pushController(registerVirtList(ui));

    auto vlView = cast(VirtListWidgetView)
      ui.widgetViews.findByName(virtListWidgetViewName);
    auto sbView = cast(ScrollbarWidgetView)
      ui.widgetViews.findByName("ScrollbarWidgetView");
    assert(vlView !is null && sbView !is null);

    auto model = VirtListModel.withCount(10000);
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
    app.withRootWidget(vlRoot);

    Widget vp = vlView.viewport(vlRoot);
    Widget mainSb = vlView.mainScrollbar(vlRoot);
    Widget crossSb = vlView.crossScrollbar(vlRoot);
    assert(vp !is null && mainSb !is null && crossSb !is null);

    auto testCtrl = new PipelineTestController(ui, tracker);
    testCtrl.vlView = vlView;
    testCtrl.sbView = sbView;
    testCtrl.vlRoot = vlRoot;
    testCtrl.vp = vp;
    testCtrl.mainSb = mainSb;
    testCtrl.crossSb = crossSb;
    testCtrl.provider = provider;
    ui.pushController(testCtrl);
    app.run();
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

    this(UiSystem ui, ref ModelTracker!VirtListModel tracker) {
      assert(ui !is null, "ui must not be null");
      super(ui);
      this.tracker = ModelTracker!VirtListModel.from(tracker);
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

    override bool onTimer(TimerId id, float dt) {
      if (id == invalidTimerId || id != timerId) {
        return false;
      }
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
        stopTimer(timerId);
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
      Widget thumb = sbView.thumb(mainSb);
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
      Widget crossInc = sbView.incButton(crossSb);
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
      timerId = startTimer(1, TimerMode.repeat);
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
    ui.widgetViews.findByName(virtListWidgetViewName);
  assert(vlView !is null);
  assert(
    ui.widgetViewControllers.findByName(virtListWidgetViewControllerName)
      is ctrl
  );

  auto vModel = VirtListModel.withCount(50);
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
  assert(vlView.viewport(vList).components.virtList.gap == 6.0f);
  assert(
    vlView.viewport(vList).components.virtList.defaultItemMainSize == 52.0f
  );
  assert(vlView.viewport(vList).components.virtList.stretchCrossAxis);

  // Horizontal mode places cross scrollbar in topRow and main in bottomRow
  auto hModel = VirtListModel.withCount(30);
  auto hProvider = new DemoTestRowProvider(ui);
  VirtListBuilder hb;
  Widget hList = hb
    .name("hList")
    .model(hModel)
    .provider(hProvider)
    .direction(FlexDirection.row)
    .build(ui, null, RectF(0, 0, 420, 220), null);
  verifyAllNamed(hList);
  Widget hMainSb = vlView.mainScrollbar(hList);
  Widget hCrossSb = vlView.crossScrollbar(hList);
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
  assert(vlView.viewport(vList).components.virtList.itemsCount == 51);

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

// Covers bindModel on existing and unregistered trees, VirtListModel boundary
// mutations, and controller super.handleEvent fallback.
unittest {
  auto ui = new UiSystemImpl(null);
  auto sbCtrl = registerScrollbars(ui);
  auto vlCtrl = registerVirtList(ui);
  auto vlView = cast(VirtListWidgetView)
    ui.widgetViews.findByName(virtListWidgetViewName);
  auto sbView = cast(ScrollbarWidgetView)
    ui.widgetViews.findByName(scrollbarWidgetViewName);
  assert(vlView !is null && sbView !is null);

  // 1. VirtListModel boundary mutations
  auto bm = VirtListModel.withCount(5);
  bm.insertItems(100, 2); // clamps index to 5 -> count 7
  assert(bm.itemsCount == 7);
  bm.insertItems(0, 0); // no-op
  assert(bm.itemsCount == 7);
  bm.removeItems(10, 3); // out of bounds -> no-op
  assert(bm.itemsCount == 7);
  bm.removeItems(5, 10); // clamps to 2 removed -> count 5
  assert(bm.itemsCount == 5);
  bm.updateItems(10, 2); // out of bounds -> no-op
  bm.updateItems(3, 10); // clamps to 2
  assert(bm.hasPendingChanges());

  // 2. Controller super.handleEvent fallback for unrecognized view event
  VirtListBuilder b;
  Widget listRoot = b
    .name("boundList")
    .model(VirtListModel.withCount(10))
    .build(ui, null, RectF(0, 0, 320, 240), null);
  auto unknownEv = ViewAppEventBuilder("unrelatedListEvent")
    .widget(listRoot)
    .viewWidget(listRoot)
    .build();
  auto hr = vlCtrl.handleEvent(unknownEv);
  assert(hr.result == HandleResult.Result.nothing);
  assert(!hr.consume);

  // 3. Rebinding existing registered VirtList syncs new model count
  auto reboundModel = VirtListModel.withCount(42);
  auto reboundTracker = ModelTracker!VirtListModel(reboundModel);
  vlView.bindModel(listRoot, reboundTracker);
  assert(vlView.viewport(listRoot).components.virtList.itemsCount == 42);

  // 4. Unregistered tree bindModel binds scrollbar trackers to ScrollbarView
  vlView.unregisterViewWidget(listRoot);
  assert(!vlView.isWidgetRegistered(listRoot));
  auto treeModel = VirtListModel.withCount(25);
  auto treeTracker = ModelTracker!VirtListModel(treeModel);
  vlView.bindModel(listRoot, treeTracker);
  assert(vlView.isWidgetRegistered(listRoot));
  assert(vlView.viewport(listRoot).components.virtList.itemsCount == 25);

  Widget mainSb = vlView.mainScrollbar(listRoot);
  assert(mainSb !is null);
  // Metrics feedback updates the newly bound main scrollbar model & arrow state
  auto metricsEv = ViewAppEventBuilder(virtListMetricsChangedEvent)
    .widget(listRoot)
    .viewWidget(listRoot)
    .valueArray(VirtListComponent.AppEventViewValue.pack(
      VirtListComponent.PackParams(1000.0f, 200.0f, 0.0f, 100.0f, 100.0f,
        0.0f, 0, 5)
    ).raw)
    .build();
  vlCtrl.handleEvent(metricsEv);
  assert(sbCtrl.updateView());
  assert(sbView.incButton(mainSb).inputEnabled);

  ui.releaseWidget(listRoot);
}
