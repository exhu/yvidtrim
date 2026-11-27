module yguilib.widget.virtlist_components;

import std.math.traits : isFinite;
import yguilib.allochelpers : ReusableArray;
import yguilib.events : AppEvent;
import yguilib.widget : Widget;
import yguilib.widget.component : AppEventViewValueMixin, WidgetComponent;
import yguilib.widget.layout_components : FlexDirection;

/// Provider interface supplying a single reusable item widget template and
/// data binding callbacks for a virtualized list (`VirtListComponent`).
interface VirtListProvider {
  /// Creates a single reusable item widget attached to `parent`.
  /// Heterogeneous row types are implemented by switching child subtree
  /// visibility inside `updateWidgetAt`.
  Widget createWidget(Widget parent);

  /// Binds row/column data for `index` to `w`.
  void updateWidgetAt(Widget w, size_t index);

  /// Notifies the provider that `w` left the visible area and entered the
  /// recycle cache so active animations or timers for `w` can be stopped.
  void onWidgetRecycled(Widget w);
}

/// Incremental dataset mutation record processed by `VirtListSystem`.
struct VirtListChange {
  enum Kind : ubyte {
    insert,
    remove,
    update,
  }

  Kind kind;
  size_t index;
  size_t count;
}

/// Runtime entry representing one active visible item widget.
package(yguilib) struct VirtListActiveItem {
  size_t index;
  Widget widget;
  float mainOffset;
  float mainSize;
  float crossSize;
  bool needsRebind;
}

/// Virtualized list viewport component supporting vertical and horizontal
/// scrolling with single-template widget recycling and variable item sizes.
final class VirtListComponent : WidgetComponent {
  /// Parameter struct for `AppEventViewValue.pack`.
  struct PackParams {
    float totalMainSize = 0.0f;
    float viewportMainSize = 0.0f;
    float mainOffset = 0.0f;
    float maxCrossSize = 0.0f;
    float viewportCrossSize = 0.0f;
    float crossOffset = 0.0f;
    uint firstVisibleIndex = 0;
    uint visibleCount = 0;

    PackParams* withTotalMainSize(float v) {
      totalMainSize = v;
      return &this;
    }

    PackParams* withViewportMainSize(float v) {
      viewportMainSize = v;
      return &this;
    }

    PackParams* withMainOffset(float v) {
      mainOffset = v;
      return &this;
    }

    PackParams* withMaxCrossSize(float v) {
      maxCrossSize = v;
      return &this;
    }

    PackParams* withViewportCrossSize(float v) {
      viewportCrossSize = v;
      return &this;
    }

    PackParams* withCrossOffset(float v) {
      crossOffset = v;
      return &this;
    }

    PackParams* withFirstVisibleIndex(uint v) {
      firstVisibleIndex = v;
      return &this;
    }

    PackParams* withVisibleCount(uint v) {
      visibleCount = v;
      return &this;
    }
  }

  /// Packed payload stored in `AppEvent.ViewData.value` when
  /// `metricsChangedEvent` is emitted.
  union AppEventViewValue {
    mixin AppEventViewValueMixin!();
    struct {
      float totalMainSize;
      float viewportMainSize;
      float mainOffset;
      float maxCrossSize;
      float viewportCrossSize;
      float crossOffset;
      uint firstVisibleIndex;
      uint visibleCount;
    }

    /// Constructs from `PackParams`.
    static AppEventViewValue pack(in PackParams p) {
      AppEventViewValue val;
      val.raw = 0;
      val.totalMainSize = p.totalMainSize;
      val.viewportMainSize = p.viewportMainSize;
      val.mainOffset = p.mainOffset;
      val.maxCrossSize = p.maxCrossSize;
      val.viewportCrossSize = p.viewportCrossSize;
      val.crossOffset = p.crossOffset;
      val.firstVisibleIndex = p.firstVisibleIndex;
      val.visibleCount = p.visibleCount;
      return val;
    }
  }

  this() {}

  /// Sets the item widget provider (`p` is allowed to be null).
  VirtListComponent withProvider(VirtListProvider p) {
    this.provider = p;
    return this;
  }

  /// Sets the main-axis layout direction.
  VirtListComponent withDirection(FlexDirection dir) {
    this.direction = dir;
    return this;
  }

  /// Sets spacing between items along the main axis.
  VirtListComponent withGap(float g) {
    this.gap = g;
    return this;
  }

  /// Sets the estimated main-axis size for unmeasured items.
  VirtListComponent withDefaultItemMainSize(float sz) {
    this.defaultItemMainSize = sz;
    return this;
  }

  /// Sets whether non-fixed items stretch to fill the viewport cross axis.
  VirtListComponent withStretchCrossAxis(bool stretch) {
    this.stretchCrossAxis = stretch;
    return this;
  }

  /// Sets total logical item count.
  VirtListComponent withItemsCount(size_t count) {
    this.itemsCount = count;
    return this;
  }

  /// Sets optional view event name emitted when layout metrics change.
  /// (`eventName` is allowed to be null/empty).
  VirtListComponent withMetricsChangedEvent(string eventName) {
    this.metricsChangedEvent = eventName;
    return this;
  }

  /// Records insertion of `count` items starting at `index`.
  void recordInsert(size_t index, size_t count) {
    if (count == 0) {
      return;
    }
    fPendingChanges.push(
      VirtListChange(VirtListChange.Kind.insert, index, count)
    );
  }

  /// Records removal of `count` items starting at `index`.
  void recordRemove(size_t index, size_t count) {
    if (count == 0) {
      return;
    }
    fPendingChanges.push(
      VirtListChange(VirtListChange.Kind.remove, index, count)
    );
  }

  /// Records content/size update for `count` items starting at `index`.
  void recordUpdate(size_t index, size_t count) {
    if (count == 0) {
      return;
    }
    fPendingChanges.push(
      VirtListChange(VirtListChange.Kind.update, index, count)
    );
  }

  /// Requests relative scroll along the main axis in logical points.
  void scrollByMain(float deltaPx) {
    if (isFinite(deltaPx)) {
      fPendingMainDelta += deltaPx;
    }
  }

  /// Requests scrolling to `targetOffsetPx` along the main axis.
  void scrollToMainOffset(float targetOffsetPx) {
    fHasTargetMainOffset = true;
    fTargetMainOffset = isFinite(targetOffsetPx) ? targetOffsetPx : 0.0f;
    fHasTargetIndex = false;
    fPendingMainDelta = 0.0f;
  }

  /// Requests scrolling so `index` is aligned at the viewport start (clamped).
  void scrollToIndex(size_t index) {
    fHasTargetIndex = true;
    fTargetIndex = index;
    fHasTargetMainOffset = false;
    fPendingMainDelta = 0.0f;
  }

  /// Requests scrolling to `offsetPx` along the cross axis.
  void requestCrossOffset(float offsetPx) {
    fCrossOffsetTarget = isFinite(offsetPx) ? offsetPx : 0.0f;
  }

  /// Index of the first active item at the viewport start.
  @property size_t anchorIndex() const nothrow @safe {
    return fAnchorIndex;
  }

  /// Main-axis pixel offset of the anchor item relative to viewport start.
  @property float anchorOffset() const nothrow @safe {
    return fAnchorOffset;
  }

  /// Number of currently visible/active items.
  @property size_t visibleItemsCount() const nothrow @safe {
    return fVisibleItemsCount;
  }

  /// Number of active item widgets currently bound and visible.
  @property size_t activeWidgetsCount() const nothrow @safe {
    return fActiveItems.length;
  }

  /// Number of recycled hidden item widgets waiting in the free pool.
  @property size_t pooledWidgetsCount() const nothrow @safe {
    return fFreePool.length;
  }

  /// Estimated/exact total content size along the main axis.
  @property float totalMainSize() const nothrow @safe {
    return fTotalMainSize;
  }

  /// Content area extent along the main axis.
  @property float viewportMainSize() const nothrow @safe {
    return fViewportMainSize;
  }

  /// Effective scroll offset along the main axis.
  @property float mainOffset() const nothrow @safe {
    return fMainOffset;
  }

  /// Maximum measured cross-axis size across items.
  @property float maxCrossSize() const nothrow @safe {
    return fMaxCrossSize;
  }

  /// Content area extent along the cross axis.
  @property float viewportCrossSize() const nothrow @safe {
    return fViewportCrossSize;
  }

  /// Effective scroll offset along the cross axis.
  @property float crossOffset() const nothrow @safe {
    return fCrossOffset;
  }

  /// Provider supplying reusable item widgets and data binding.
  VirtListProvider provider;
  /// Layout direction: `column` (vertical) or `row` (horizontal).
  FlexDirection direction = FlexDirection.column;
  /// Gap between adjacent items along the main axis.
  float gap = 4.0f;
  /// Default estimated main-axis size for unmeasured items.
  float defaultItemMainSize = 48.0f;
  /// When true, stretches non-fixed item cross size to viewport cross size.
  bool stretchCrossAxis = false;
  /// Total number of items in the dataset.
  size_t itemsCount = 0;
  /// When true, invalidates size cache and rebinds all active items.
  bool modelChanged = false;
  /// Optional view event name emitted in `postLayout` when metrics change.
  string metricsChangedEvent;

package(yguilib):
  ReusableArray!VirtListActiveItem fActiveItems;
  ReusableArray!Widget fFreePool;
  float[size_t] fItemMainSizes;
  float[size_t] fItemCrossSizes;
  double fKnownMainSizesSum = 0.0;
  ReusableArray!VirtListChange fPendingChanges;
  size_t fLastItemsCount = 0;

  float fPendingMainDelta = 0.0f;
  bool fHasTargetMainOffset = false;
  float fTargetMainOffset = 0.0f;
  bool fHasTargetIndex = false;
  size_t fTargetIndex = 0;
  float fCrossOffsetTarget = 0.0f;
  float fLastViewportCross = -1.0f;

  size_t fAnchorIndex = 0;
  float fAnchorOffset = 0.0f;
  size_t fVisibleItemsCount = 0;
  float fTotalMainSize = 0.0f;
  float fViewportMainSize = 0.0f;
  float fMainOffset = 0.0f;
  float fMaxCrossSize = 0.0f;
  float fViewportCrossSize = 0.0f;
  float fCrossOffset = 0.0f;

  float fLastEmittedTotalMainSize = -1.0f;
  float fLastEmittedViewportMainSize = -1.0f;
  float fLastEmittedMainOffset = -1.0f;
  float fLastEmittedMaxCrossSize = -1.0f;
  float fLastEmittedViewportCrossSize = -1.0f;
  float fLastEmittedCrossOffset = -1.0f;
  uint fLastEmittedFirstVisible = uint.max;
  uint fLastEmittedVisibleCount = uint.max;
}

unittest {
  auto vc = new VirtListComponent()
    .withDirection(FlexDirection.row)
    .withGap(8.0f)
    .withDefaultItemMainSize(64.0f)
    .withStretchCrossAxis(true)
    .withItemsCount(100)
    .withMetricsChangedEvent("virtMetrics");

  assert(vc.direction == FlexDirection.row);
  assert(vc.gap == 8.0f);
  assert(vc.defaultItemMainSize == 64.0f);
  assert(vc.stretchCrossAxis);
  assert(vc.itemsCount == 100);
  assert(vc.metricsChangedEvent == "virtMetrics");

  vc.recordInsert(2, 3);
  vc.recordRemove(5, 1);
  vc.recordUpdate(1, 4);
  vc.recordInsert(0, 0);
  vc.recordRemove(0, 0);
  vc.recordUpdate(0, 0);
  assert(vc.fPendingChanges.length == 3);
  assert(vc.fPendingChanges[0].kind == VirtListChange.Kind.insert);
  assert(vc.fPendingChanges[0].index == 2);
  assert(vc.fPendingChanges[0].count == 3);
  assert(vc.fPendingChanges[1].kind == VirtListChange.Kind.remove);
  assert(vc.fPendingChanges[1].index == 5);
  assert(vc.fPendingChanges[1].count == 1);
  assert(vc.fPendingChanges[2].kind == VirtListChange.Kind.update);
  assert(vc.fPendingChanges[2].index == 1);
  assert(vc.fPendingChanges[2].count == 4);

  // Scroll & NaN/Inf guards
  vc.scrollByMain(12.0f);
  vc.scrollByMain(float.nan);
  vc.scrollByMain(float.infinity);
  vc.scrollByMain(-float.infinity);
  assert(vc.fPendingMainDelta == 12.0f);

  vc.scrollToMainOffset(float.nan);
  assert(vc.fHasTargetMainOffset);
  assert(vc.fTargetMainOffset == 0.0f);
  assert(!vc.fHasTargetIndex);
  assert(vc.fPendingMainDelta == 0.0f);

  vc.scrollByMain(5.0f);
  vc.scrollToIndex(7);
  assert(vc.fHasTargetIndex);
  assert(vc.fTargetIndex == 7);
  assert(!vc.fHasTargetMainOffset);
  assert(vc.fPendingMainDelta == 0.0f);

  vc.requestCrossOffset(42.0f);
  assert(vc.fCrossOffsetTarget == 42.0f);
  vc.requestCrossOffset(float.nan);
  assert(vc.fCrossOffsetTarget == 0.0f);
  vc.requestCrossOffset(float.infinity);
  assert(vc.fCrossOffsetTarget == 0.0f);

  VirtListComponent.PackParams pp;
  pp.withTotalMainSize(1200.5f)
    .withViewportMainSize(300.0f)
    .withMainOffset(140.25f)
    .withMaxCrossSize(450.0f)
    .withViewportCrossSize(200.0f)
    .withCrossOffset(32.5f)
    .withFirstVisibleIndex(17)
    .withVisibleCount(6);
  auto packed = VirtListComponent.AppEventViewValue.pack(pp);
  auto unpacked = VirtListComponent.AppEventViewValue.fromRaw(packed.raw);
  assert(unpacked.totalMainSize == 1200.5f);
  assert(unpacked.viewportMainSize == 300.0f);
  assert(unpacked.mainOffset == 140.25f);
  assert(unpacked.maxCrossSize == 450.0f);
  assert(unpacked.viewportCrossSize == 200.0f);
  assert(unpacked.crossOffset == 32.5f);
  assert(unpacked.firstVisibleIndex == 17);
  assert(unpacked.visibleCount == 6);
}
