module yguilib.widget.internal.virtlist_system;

package(yguilib):

import std.math : abs;
import std.math.traits : isFinite;
import yguilib.allochelpers : ReusableArray, SmallBuffer;
import yguilib.events : AppEvent;
import yguilib.events.builder : ViewAppEventBuilder;
import yguilib.render : Renderer;
import yguilib.render.render_types : PointF, RectF;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.internal.layout_axis : crossSize, assignCrossSize;
import yguilib.widget.internal.layout_dimension : clampDimension;
import yguilib.widget.internal.layout_flex : updateFlexChildTextHeight;
import yguilib.widget.internal.layout_system : LayoutSystem;
import yguilib.widget.layout_components : FlexDirection, Size, SizingMode;
import yguilib.widget.system : SystemEventResult, SystemPhase, WidgetSystem,
  WidgetSystemContext, WidgetSystemHost;
import yguilib.widget.virtlist_components : VirtListActiveItem, VirtListChange,
  VirtListComponent;
import yguilib.widget.visible : VisibleWidget, VisibleWidgets;
import yguilib.widget.widget_view : passViewEvent;

/// Layout, recycling, and wheel-scrolling system for `VirtListComponent`.
final class VirtListSystem : WidgetSystem {
  /// Constructs VirtListSystem. `host` is allowed to be null in isolated
  /// tests.
  this(WidgetSystemHost host) {
    fHost = host;
    fLayoutSystem = new LayoutSystem();
  }

  override @property int priority() const nothrow @safe {
    return virtListSystemPriority;
  }

  invariant {
    assert(fLayoutSystem !is null);
  }

  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.event | SystemPhase.layout | SystemPhase.postLayout;
  }

  override void onRegister(WidgetSystemHost newHost) {
    if (newHost !is null) {
      fHost = newHost;
    }
  }

  override void onWidgetReleased(Widget w) {
    if (w is null) {
      return;
    }
    if (w.components.virtList !is null) {
      clearComponentRuntime(w.components.virtList);
    }
    if (w.parent !is null && w.parent.components.virtList !is null) {
      detachReleasedItem(w.parent.components.virtList, w.parent, w);
    }
  }

  override SystemEventResult handleEvent(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    if (event.kind != AppEvent.Kind.mouseWheel) {
      return SystemEventResult(false, false);
    }
    const PointF p = PointF(event.wheel.mouseX, event.wheel.mouseY);
    size_t listIdx = size_t.max;
    Widget listWidget = null;
    foreach_reverse (i, ref vw; ctx.visibleWidgets) {
      Widget w = vw.widget;
      if (w is null || w.components.virtList is null || !vw.containsPoint(p)) {
        continue;
      }
      listIdx = i;
      listWidget = w;
      break;
    }
    if (listWidget is null || !listWidget.inputEnabled) {
      return SystemEventResult(false, false);
    }
    foreach_reverse (j; listIdx + 1 .. ctx.visibleWidgets.length) {
      const ref VisibleWidget ov = ctx.visibleWidgets[j];
      const Widget ow = ov.widget;
      if (ow is null || !ow.handleInput || !ov.containsPoint(p)) {
        continue;
      }
      if (ow !is listWidget && !ow.isChildOf(listWidget)) {
        return SystemEventResult(false, false);
      }
    }
    if (applyWheelEvent(listWidget.components.virtList, event)) {
      listWidget.update(WidgetUpdateScope.layout);
      return SystemEventResult(true, false);
    }
    return SystemEventResult(false, false);
  }

  override void layout(ref WidgetSystemContext ctx) {
    if (ctx.root is null || !ctx.root.visible ||
        ctx.unclippedWidgets.length == 0) {
      return;
    }
    foreach (ref vw; ctx.unclippedWidgets) {
      Widget w = vw.widget;
      if (w is null || w.components.virtList is null) {
        continue;
      }
      handleVirtListLayout(w, ctx.renderer);
    }
  }

  override void postLayout(ref WidgetSystemContext ctx) {
    if (ctx.root is null || !ctx.root.visible) {
      return;
    }
    VisibleWidgets targets = ctx.visibleWidgets.length > 0
      ? ctx.visibleWidgets
      : ctx.unclippedWidgets;
    if (targets.length == 0) {
      return;
    }

    WidgetSystemHost activeHost = ctx.host !is null ? ctx.host : fHost;
    foreach (ref vw; targets) {
      Widget w = vw.widget;
      if (w is null || w.components.virtList is null) {
        continue;
      }
      handleVirtListPostLayout(w, activeHost);
    }
  }

private:
  static size_t saturatingAdd(size_t a, size_t b) nothrow @safe pure {
    return (a <= size_t.max - b) ? a + b : size_t.max;
  }

  static void clearComponentRuntime(VirtListComponent vc) {
    vc.fActiveItems.releaseMemory();
    vc.fFreePool.releaseMemory();
    vc.fItemMainSizes.clear();
    vc.fItemCrossSizes.clear();
    vc.fKnownMainSizesSum = 0.0;
    vc.fPendingChanges.releaseMemory();
    vc.fLastItemsCount = 0;
  }

  static void detachReleasedItem(
    VirtListComponent vc,
    Widget listWidget,
    Widget w
  ) {
    vc.fFreePool.compact((const ref Widget item) => item !is w);
    vc.fActiveItems.compact(
      (const ref VirtListActiveItem item) => item.widget !is w
    );
    vc.fVisibleItemsCount = vc.fActiveItems.length;
    if (!listWidget.released) {
      listWidget.update(WidgetUpdateScope.layout);
    }
  }

  static bool applyWheelEvent(
    VirtListComponent vc,
    in AppEvent event
  ) {
    import std.algorithm.comparison : max;
    const float step = max(16.0f, vc.defaultItemMainSize);
    bool changed = false;

    if (vc.direction == FlexDirection.column) {
      if (event.wheel.y != 0.0f) {
        vc.scrollByMain(-event.wheel.y * step);
        changed = true;
      }
      if (event.wheel.x != 0.0f) {
        vc.requestCrossOffset(vc.crossOffset + event.wheel.x * 24.0f);
        changed = true;
      }
    } else {
      if (event.wheel.x != 0.0f) {
        vc.scrollByMain(event.wheel.x * step);
        changed = true;
      } else if (event.wheel.y != 0.0f) {
        vc.scrollByMain(-event.wheel.y * step);
        changed = true;
      }
    }
    return changed;
  }

  void handleVirtListLayout(Widget w, Renderer r) {
    import std.algorithm.comparison : max;
    VirtListComponent vc = w.components.virtList;
    assert(vc !is null);

    w.clipChildren = true;
    const bool isRow = vc.direction == FlexDirection.row;
    const RectF contentArea = w.contentArea();
    const float viewportMain = isRow ? contentArea.width : contentArea.height;
    const float viewportCross = isRow ? contentArea.height : contentArea.width;
    vc.fViewportMainSize = viewportMain;
    vc.fViewportCrossSize = viewportCross;

    applyPendingChanges(vc);
    pruneStaleSizeCaches(vc);
    handleInvalidations(vc, viewportCross);
    vc.fLastItemsCount = vc.itemsCount;

    if (vc.itemsCount == 0 || vc.provider is null ||
        viewportMain <= 0.0f || viewportCross <= 0.0f) {
      recycleAllAndReset(vc);
      return;
    }

    const float gap = max(0.0f, vc.gap);
    const double avgMain = computeAvgMainSize(vc);
    applyScrollRequests(vc, viewportMain, avgMain, gap);
    normalizeAnchor(vc, viewportMain, avgMain, gap);

    VirtListActiveItem[] prevActive = vc.fActiveItems[];
    SmallBuffer!(bool, 32) claimedBuf;
    claimedBuf.fillWith(prevActive.length, false);

    VirtListPass pass;
    pass.listWidget = w;
    pass.vc = vc;
    pass.renderer = r;
    pass.viewportMain = viewportMain;
    pass.viewportCross = viewportCross;
    pass.isRow = isRow;
    pass.gap = gap;
    pass.prevActive = prevActive;
    pass.claimed = claimedBuf[];

    fNextActiveBuf.clear();
    fillVisibleRange(pass, fNextActiveBuf);
    handleBottomUnderflow(pass, fNextActiveBuf);
    trimLeadingOffscreen(vc, gap, fNextActiveBuf);
    recycleUnclaimed(pass);

    vc.fActiveItems.swapWith(fNextActiveBuf);
    fNextActiveBuf.clear();
    finalizeMetricsAndPositions(
      vc, contentArea, isRow, gap, viewportCross
    );
  }

  static void applyPendingChanges(VirtListComponent vc) {
    if (vc.fPendingChanges.length == 0) {
      return;
    }
    foreach (ref ch; vc.fPendingChanges[]) {
      final switch (ch.kind) {
      case VirtListChange.Kind.insert:
        applyInsertChange(vc, ch.index, ch.count);
        break;
      case VirtListChange.Kind.remove:
        applyRemoveChange(vc, ch.index, ch.count);
        break;
      case VirtListChange.Kind.update:
        applyUpdateChange(vc, ch.index, ch.count);
        break;
      }
    }
    vc.fPendingChanges.clear();
    if (vc.fItemMainSizes.length == 0 || vc.fKnownMainSizesSum < 0.0) {
      vc.fKnownMainSizesSum = 0.0;
    }
  }

  static void applyInsertChange(
    VirtListComponent vc,
    size_t idx,
    size_t count
  ) {
    if (count == 0) {
      return;
    }
    shiftSizeCachesInsert(vc, idx, count);
    foreach (ref item; vc.fActiveItems[]) {
      if (item.index != size_t.max && item.index >= idx) {
        item.index += count;
      }
    }
    if (vc.fLastItemsCount > 0 && idx <= vc.fAnchorIndex &&
        vc.itemsCount > count) {
      vc.fAnchorIndex += count;
    }
  }

  static void shiftSizeCachesInsert(
    VirtListComponent vc,
    size_t idx,
    size_t count
  ) {
    float[size_t] nextMain;
    float[size_t] nextCross;
    foreach (k, v; vc.fItemMainSizes) {
      const size_t nk = k >= idx ? k + count : k;
      nextMain[nk] = v;
    }
    foreach (k, v; vc.fItemCrossSizes) {
      const size_t nk = k >= idx ? k + count : k;
      nextCross[nk] = v;
    }
    vc.fItemMainSizes = nextMain;
    vc.fItemCrossSizes = nextCross;
  }

  static void applyRemoveChange(
    VirtListComponent vc,
    size_t idx,
    size_t count
  ) {
    import std.algorithm.comparison : min;
    if (count == 0) {
      return;
    }
    shiftSizeCachesRemove(vc, idx, count);
    const size_t endIdx = saturatingAdd(idx, count);
    foreach (ref item; vc.fActiveItems[]) {
      if (item.index == size_t.max) {
        continue;
      }
      if (item.index >= idx && item.index < endIdx) {
        item.index = size_t.max;
      } else if (item.index >= endIdx) {
        item.index -= count;
      }
    }
    if (vc.itemsCount == 0) {
      vc.fAnchorIndex = 0;
      vc.fAnchorOffset = 0.0f;
    } else if (endIdx < size_t.max && endIdx <= vc.fAnchorIndex) {
      vc.fAnchorIndex -= count;
    } else if (idx <= vc.fAnchorIndex) {
      vc.fAnchorIndex = min(idx, vc.itemsCount - 1);
      vc.fAnchorOffset = 0.0f;
    }
  }

  static void shiftSizeCachesRemove(
    VirtListComponent vc,
    size_t idx,
    size_t count
  ) {
    const size_t endIdx = saturatingAdd(idx, count);
    float[size_t] nextMain;
    float[size_t] nextCross;
    double sum = 0.0;
    foreach (k, v; vc.fItemMainSizes) {
      if (k >= idx && k < endIdx) {
        continue;
      }
      const size_t nk = k >= endIdx ? k - count : k;
      nextMain[nk] = v;
      sum += v;
    }
    foreach (k, v; vc.fItemCrossSizes) {
      if (k >= idx && k < endIdx) {
        continue;
      }
      const size_t nk = k >= endIdx ? k - count : k;
      nextCross[nk] = v;
    }
    vc.fItemMainSizes = nextMain;
    vc.fItemCrossSizes = nextCross;
    vc.fKnownMainSizesSum = sum;
  }

  static void applyUpdateChange(
    VirtListComponent vc,
    size_t idx,
    size_t count
  ) {
    if (count == 0) {
      return;
    }
    const size_t endIdx = saturatingAdd(idx, count);
    SmallBuffer!(size_t, 32) toRemove;
    foreach (k; vc.fItemMainSizes.byKey) {
      if (k >= idx && k < endIdx) {
        toRemove.push(k);
      }
    }
    foreach (k; toRemove[]) {
      vc.fKnownMainSizesSum -= vc.fItemMainSizes[k];
      vc.fItemMainSizes.remove(k);
      vc.fItemCrossSizes.remove(k);
    }
    foreach (ref item; vc.fActiveItems[]) {
      if (item.index != size_t.max && item.index >= idx &&
          item.index < endIdx) {
        item.needsRebind = true;
      }
    }
  }

  static void pruneStaleSizeCaches(VirtListComponent vc) {
    if (vc.itemsCount == 0) {
      if (vc.fItemMainSizes.length > 0 || vc.fItemCrossSizes.length > 0) {
        vc.fItemMainSizes.clear();
        vc.fItemCrossSizes.clear();
        vc.fKnownMainSizesSum = 0.0;
      }
      return;
    }
    if (vc.itemsCount >= vc.fLastItemsCount) {
      return;
    }
    SmallBuffer!(size_t, 32) staleMain;
    foreach (k; vc.fItemMainSizes.byKey) {
      if (k >= vc.itemsCount) {
        staleMain.push(k);
      }
    }
    foreach (k; staleMain[]) {
      vc.fKnownMainSizesSum -= vc.fItemMainSizes[k];
      vc.fItemMainSizes.remove(k);
    }
    SmallBuffer!(size_t, 32) staleCross;
    foreach (k; vc.fItemCrossSizes.byKey) {
      if (k >= vc.itemsCount) {
        staleCross.push(k);
      }
    }
    foreach (k; staleCross[]) {
      vc.fItemCrossSizes.remove(k);
    }
    if (vc.fItemMainSizes.length == 0 || vc.fKnownMainSizesSum < 0.0) {
      vc.fKnownMainSizesSum = 0.0;
    }
  }

  static void handleInvalidations(VirtListComponent vc, float viewportCross) {
    if (vc.modelChanged) {
      vc.fItemMainSizes.clear();
      vc.fItemCrossSizes.clear();
      vc.fKnownMainSizesSum = 0.0;
      foreach (ref item; vc.fActiveItems[]) {
        item.needsRebind = true;
      }
      vc.modelChanged = false;
    } else if (vc.fLastViewportCross >= 0.0f &&
        abs(viewportCross - vc.fLastViewportCross) > 0.5f) {
      vc.fItemMainSizes.clear();
      vc.fItemCrossSizes.clear();
      vc.fKnownMainSizesSum = 0.0;
    }
    vc.fLastViewportCross = viewportCross;
  }

  static void recycleAllAndReset(VirtListComponent vc) {
    foreach (ref item; vc.fActiveItems[]) {
      if (item.widget !is null) {
        item.widget.visible = false;
        vc.fFreePool.push(item.widget);
        if (vc.provider !is null) {
          vc.provider.onWidgetRecycled(item.widget);
        }
      }
    }
    vc.fActiveItems.clear();
    vc.fAnchorIndex = 0;
    vc.fAnchorOffset = 0.0f;
    vc.fVisibleItemsCount = 0;
    vc.fTotalMainSize = 0.0f;
    vc.fMainOffset = 0.0f;
    vc.fMaxCrossSize = 0.0f;
    vc.fCrossOffset = 0.0f;
    vc.fPendingMainDelta = 0.0f;
    vc.fHasTargetMainOffset = false;
    vc.fHasTargetIndex = false;
  }

  static double computeAvgMainSize(in VirtListComponent vc) {
    import std.algorithm.comparison : max;
    if (vc.fItemMainSizes.length > 0) {
      return max(1.0, vc.fKnownMainSizesSum / vc.fItemMainSizes.length);
    }
    return max(1.0, cast(double) vc.defaultItemMainSize);
  }

  static float estimatedItemMainSize(
    in VirtListComponent vc,
    size_t idx,
    double avgMain
  ) {
    if (auto p = idx in vc.fItemMainSizes) {
      return *p;
    }
    return cast(float) avgMain;
  }

  static float estimateTotalMainSize(
    in VirtListComponent vc,
    double avgMain,
    float gap
  ) {
    const size_t n = vc.itemsCount;
    if (n == 0) {
      return 0.0f;
    }
    const size_t known = vc.fItemMainSizes.length;
    const size_t unknown = n > known ? n - known : 0;
    const double gaps = n > 1 ? cast(double) gap * (n - 1) : 0.0;
    return cast(float) (vc.fKnownMainSizesSum + unknown * avgMain + gaps);
  }

  static float computeCurrentMainOffset(
    in VirtListComponent vc,
    double avgMain,
    float gap
  ) {
    double acc = cast(double) vc.fAnchorIndex * (avgMain + gap);
    foreach (k, v; vc.fItemMainSizes) {
      if (k < vc.fAnchorIndex) {
        acc += cast(double) v - avgMain;
      }
    }
    const double res = acc - vc.fAnchorOffset;
    return res > 0.0 ? cast(float) res : 0.0f;
  }

  static void applyScrollRequests(
    VirtListComponent vc,
    float viewportMain,
    double avgMain,
    float gap
  ) {
    import std.algorithm.comparison : max, min;
    if (vc.fAnchorIndex >= vc.itemsCount) {
      vc.fAnchorIndex = vc.itemsCount - 1;
      vc.fAnchorOffset = 0.0f;
    }
    if (vc.fHasTargetIndex) {
      vc.fHasTargetIndex = false;
      vc.fAnchorIndex = min(vc.fTargetIndex, vc.itemsCount - 1);
      vc.fAnchorOffset = 0.0f;
    }
    if (vc.fHasTargetMainOffset) {
      vc.fHasTargetMainOffset = false;
      const float estTotal = estimateTotalMainSize(vc, avgMain, gap);
      const float maxScroll = max(0.0f, estTotal - viewportMain);
      float target = vc.fTargetMainOffset;
      if (!isFinite(target) || target < 0.0f) {
        target = 0.0f;
      } else if (target > maxScroll) {
        target = maxScroll;
      }
      const float currOff = computeCurrentMainOffset(vc, avgMain, gap);
      const float delta = target - currOff;
      if (abs(delta) <= viewportMain * 2.0f) {
        vc.fAnchorOffset -= delta;
      } else {
        jumpToMainOffset(vc, target, avgMain, gap);
      }
    }
    if (isFinite(vc.fPendingMainDelta) && vc.fPendingMainDelta != 0.0f) {
      vc.fAnchorOffset -= vc.fPendingMainDelta;
    }
    vc.fPendingMainDelta = 0.0f;
  }

  static void jumpToMainOffset(
    VirtListComponent vc,
    float targetOff,
    double avgMain,
    float gap
  ) {
    if (targetOff <= 0.0f) {
      vc.fAnchorIndex = 0;
      vc.fAnchorOffset = 0.0f;
      return;
    }
    if (vc.fItemMainSizes.length == 0) {
      const double step = avgMain + gap;
      size_t idx = cast(size_t) (targetOff / step);
      if (idx >= vc.itemsCount) {
        idx = vc.itemsCount - 1;
      }
      vc.fAnchorIndex = idx;
      vc.fAnchorOffset = -cast(float) (targetOff - idx * step);
      return;
    }
    double acc = 0.0;
    size_t idx = 0;
    while (idx + 1 < vc.itemsCount) {
      const double step = estimatedItemMainSize(vc, idx, avgMain) + gap;
      if (acc + step > targetOff) {
        break;
      }
      acc += step;
      idx++;
    }
    vc.fAnchorIndex = idx;
    vc.fAnchorOffset = -cast(float) (targetOff - acc);
  }

  static void normalizeAnchor(
    VirtListComponent vc,
    float viewportMain,
    double avgMain,
    float gap
  ) {
    const double stepEst = avgMain + gap;
    if (vc.fAnchorOffset < -viewportMain * 2.0f &&
        vc.fAnchorIndex + 1 < vc.itemsCount) {
      const double skipPx = -vc.fAnchorOffset - viewportMain;
      const size_t skipCount = cast(size_t) (skipPx / stepEst);
      const size_t maxSkip = vc.itemsCount - 1 - vc.fAnchorIndex;
      const size_t actualSkip = skipCount < maxSkip ? skipCount : maxSkip;
      if (actualSkip > 0) {
        vc.fAnchorIndex += actualSkip;
        vc.fAnchorOffset += cast(float) (actualSkip * stepEst);
      }
    } else if (vc.fAnchorOffset > viewportMain * 2.0f && vc.fAnchorIndex > 0) {
      const double skipPx = vc.fAnchorOffset - viewportMain;
      const size_t skipCount = cast(size_t) (skipPx / stepEst);
      const size_t actualSkip = skipCount < vc.fAnchorIndex
        ? skipCount
        : vc.fAnchorIndex;
      if (actualSkip > 0) {
        vc.fAnchorIndex -= actualSkip;
        vc.fAnchorOffset -= cast(float) (actualSkip * stepEst);
      }
    }

    while (vc.fAnchorIndex + 1 < vc.itemsCount) {
      const float step = estimatedItemMainSize(
        vc, vc.fAnchorIndex, avgMain
      ) + gap;
      if (vc.fAnchorOffset + step > 0.0f) {
        break;
      }
      vc.fAnchorOffset += step;
      vc.fAnchorIndex++;
    }
    while (vc.fAnchorOffset > 0.0f && vc.fAnchorIndex > 0) {
      vc.fAnchorIndex--;
      const float step = estimatedItemMainSize(
        vc, vc.fAnchorIndex, avgMain
      ) + gap;
      vc.fAnchorOffset -= step;
    }
    if (vc.fAnchorIndex == 0 && vc.fAnchorOffset > 0.0f) {
      vc.fAnchorOffset = 0.0f;
    }
  }

  struct VirtListPass {
    Widget listWidget;
    VirtListComponent vc;
    Renderer renderer;
    float viewportMain = 0.0f;
    float viewportCross = 0.0f;
    bool isRow = false;
    float gap = 0.0f;
    VirtListActiveItem[] prevActive;
    bool[] claimed;
  }

  void fillVisibleRange(
    ref VirtListPass pass,
    ref ReusableArray!VirtListActiveItem outActive
  ) {
    size_t currIdx = pass.vc.fAnchorIndex;
    float currPos = pass.vc.fAnchorOffset;

    while (currIdx < pass.vc.itemsCount && currPos < pass.viewportMain) {
      VirtListActiveItem entry = acquireAndMeasureItem(pass, currIdx, currPos);
      if (entry.widget is null) {
        break;
      }
      outActive.push(entry);
      currPos += entry.mainSize + pass.gap;
      currIdx++;
    }
  }

  struct MeasuredItemSize {
    float main;
    float cross;
  }

  struct AcquiredItem {
    Widget widget;
    bool newlyBound;
    bool needsRebind;
  }

  VirtListActiveItem acquireAndMeasureItem(
    ref VirtListPass pass,
    size_t idx,
    float pos
  ) {
    AcquiredItem acquired = acquireItemWidget(pass, idx);
    Widget itemWidget = acquired.widget;
    if (itemWidget is null) {
      return VirtListActiveItem.init;
    }

    VirtListComponent vc = pass.vc;
    if (!itemWidget.visible) {
      itemWidget.visible = true;
    }
    if (acquired.newlyBound || acquired.needsRebind) {
      vc.provider.updateWidgetAt(itemWidget, idx);
    }

    const bool cached = (idx in vc.fItemMainSizes) !is null;
    const bool dirtyLayout = itemWidget.isTreeLayoutDirty();
    const bool crossChanged = cached && vc.stretchCrossAxis &&
      crossSize(itemWidget, pass.isRow) != vc.fItemCrossSizes[idx];

    MeasuredItemSize measured;
    if (!cached || acquired.newlyBound || acquired.needsRebind ||
        dirtyLayout || crossChanged) {
      measureItemSubtree(
        itemWidget, pass.renderer, pass.viewportCross, pass.isRow,
        vc.stretchCrossAxis
      );
      measured = cacheMeasuredItemSize(vc, itemWidget, idx, pass.isRow);
    } else {
      measured = MeasuredItemSize(
        vc.fItemMainSizes[idx],
        vc.fItemCrossSizes[idx]
      );
    }

    if (acquired.newlyBound || acquired.needsRebind || dirtyLayout) {
      itemWidget.dirty = true;
    }
    return VirtListActiveItem(
      idx, itemWidget, pos, measured.main, measured.cross, false
    );
  }

  static MeasuredItemSize cacheMeasuredItemSize(
    VirtListComponent vc,
    Widget itemWidget,
    size_t idx,
    bool isRow
  ) {
    import std.algorithm.comparison : max;
    const float measuredMain = max(
      0.0f,
      isRow ? itemWidget.rect.width : itemWidget.rect.height
    );
    const float measuredCross = max(
      0.0f,
      isRow ? itemWidget.rect.height : itemWidget.rect.width
    );
    if (auto pOld = idx in vc.fItemMainSizes) {
      vc.fKnownMainSizesSum -= *pOld;
    }
    vc.fItemMainSizes[idx] = measuredMain;
    vc.fKnownMainSizesSum += measuredMain;
    vc.fItemCrossSizes[idx] = measuredCross;
    return MeasuredItemSize(measuredMain, measuredCross);
  }

  static AcquiredItem acquireItemWidget(
    ref VirtListPass pass,
    size_t idx
  ) {
    foreach (i, ref oldItem; pass.prevActive) {
      if (!pass.claimed[i] && oldItem.index == idx && oldItem.widget !is null) {
        pass.claimed[i] = true;
        return AcquiredItem(oldItem.widget, false, oldItem.needsRebind);
      }
    }
    auto reused = pass.vc.fFreePool.tryPopBack();
    if (!reused.isNull) {
      return AcquiredItem(reused.get(), true, true);
    }
    Widget stolen = stealUnclaimedActive(pass, idx);
    if (stolen !is null) {
      return AcquiredItem(stolen, true, true);
    }
    Widget created = pass.vc.provider.createWidget(pass.listWidget);
    if (created !is null && created.parent !is pass.listWidget) {
      pass.listWidget.addChild(created);
    }
    return AcquiredItem(created, true, true);
  }

  static Widget stealUnclaimedActive(
    ref VirtListPass pass,
    size_t currIdx
  ) {
    VirtListComponent vc = pass.vc;
    foreach (i, ref oldItem; pass.prevActive) {
      if (!pass.claimed[i] && oldItem.widget !is null &&
          (oldItem.index == size_t.max || oldItem.index < currIdx ||
          oldItem.index >= vc.itemsCount)) {
        pass.claimed[i] = true;
        vc.provider.onWidgetRecycled(oldItem.widget);
        return oldItem.widget;
      }
    }
    foreach_reverse (i, ref oldItem; pass.prevActive) {
      if (!pass.claimed[i] && oldItem.widget !is null) {
        pass.claimed[i] = true;
        vc.provider.onWidgetRecycled(oldItem.widget);
        return oldItem.widget;
      }
    }
    return null;
  }

  void handleBottomUnderflow(
    ref VirtListPass pass,
    ref ReusableArray!VirtListActiveItem active
  ) {
    if (active.length == 0) {
      return;
    }
    const size_t lastIdx = active[active.length - 1].index;
    const float lastBottom = active[active.length - 1].mainOffset +
      active[active.length - 1].mainSize;
    if (lastIdx + 1 != pass.vc.itemsCount ||
        lastBottom >= pass.viewportMain) {
      return;
    }
    if (active[0].index == 0 && active[0].mainOffset >= 0.0f) {
      return;
    }

    const float shortfall = pass.viewportMain - lastBottom;
    foreach (ref item; active[]) {
      item.mainOffset += shortfall;
    }

    SmallBuffer!(VirtListActiveItem, 16) backfill;
    float topEdge = active[0].mainOffset;
    size_t prevIdx = active[0].index;
    while (topEdge > 0.0f && prevIdx > 0) {
      prevIdx--;
      VirtListActiveItem entry = acquireAndMeasureItem(pass, prevIdx, 0.0f);
      if (entry.widget is null) {
        break;
      }
      entry.mainOffset = topEdge - pass.gap - entry.mainSize;
      topEdge = entry.mainOffset;
      backfill.push(entry);
    }

    foreach (ref item; backfill[]) {
      active.insertAt(0, item);
    }

    if (active[0].index == 0 && active[0].mainOffset > 0.0f) {
      const float clampShift = active[0].mainOffset;
      foreach (ref item; active[]) {
        item.mainOffset -= clampShift;
      }
    }
  }

  static void trimLeadingOffscreen(
    VirtListComponent vc,
    float gap,
    ref ReusableArray!VirtListActiveItem active
  ) {
    while (active.length > 1) {
      const float endPos = active[0].mainOffset + active[0].mainSize + gap;
      if (endPos > 0.0f) {
        break;
      }
      Widget w = active[0].widget;
      if (w !is null) {
        w.visible = false;
        vc.fFreePool.push(w);
        vc.provider.onWidgetRecycled(w);
      }
      active.removeAt(0);
    }
  }

  static void recycleUnclaimed(ref VirtListPass pass) {
    foreach (i, ref oldItem; pass.prevActive) {
      if (!pass.claimed[i] && oldItem.widget !is null) {
        oldItem.widget.visible = false;
        pass.vc.fFreePool.push(oldItem.widget);
        pass.vc.provider.onWidgetRecycled(oldItem.widget);
      }
    }
  }

  static void finalizeMetricsAndPositions(
    VirtListComponent vc,
    RectF contentArea,
    bool isRow,
    float gap,
    float viewportCross
  ) {
    import std.algorithm.comparison : max;
    const double avgMain = computeAvgMainSize(vc);
    vc.fTotalMainSize = estimateTotalMainSize(vc, avgMain, gap);

    if (vc.fActiveItems.length > 0) {
      vc.fAnchorIndex = vc.fActiveItems[0].index;
      vc.fAnchorOffset = vc.fActiveItems[0].mainOffset;
      vc.fVisibleItemsCount = vc.fActiveItems.length;
      vc.fMainOffset = computeCurrentMainOffset(vc, avgMain, gap);
    } else {
      vc.fVisibleItemsCount = 0;
      vc.fMainOffset = 0.0f;
    }

    float maxCross = 0.0f;
    foreach (cs; vc.fItemCrossSizes.byValue) {
      if (cs > maxCross) {
        maxCross = cs;
      }
    }
    vc.fMaxCrossSize = maxCross;

    const float maxCrossScroll = max(0.0f, maxCross - viewportCross);
    float crossOff = vc.fCrossOffsetTarget;
    if (!isFinite(crossOff) || crossOff < 0.0f) {
      crossOff = 0.0f;
    } else if (crossOff > maxCrossScroll) {
      crossOff = maxCrossScroll;
    }
    vc.fCrossOffset = crossOff;
    vc.fCrossOffsetTarget = crossOff;

    foreach (ref item; vc.fActiveItems[]) {
      if (isRow) {
        item.widget.rect.x = contentArea.x + item.mainOffset;
        item.widget.rect.y = contentArea.y - crossOff;
      } else {
        item.widget.rect.x = contentArea.x - crossOff;
        item.widget.rect.y = contentArea.y + item.mainOffset;
      }
    }
  }

  void measureItemSubtree(
    Widget itemWidget,
    Renderer r,
    float viewportCross,
    bool isRow,
    bool stretchCrossAxis
  ) {
    assert(itemWidget !is null);
    nodeBuf.clear();
    collectVisibleNodes(itemWidget, nodeBuf);
    if (nodeBuf.length == 0) {
      return;
    }

    foreach_reverse (node; nodeBuf[]) {
      LayoutSystem.handleSizeComp(node, r);
    }

    if (stretchCrossAxis) {
      applyCrossAxisStretch(itemWidget, viewportCross, isRow);
    }

    foreach (node; nodeBuf[]) {
      if (node !is itemWidget) {
        LayoutSystem.handleAnchorComp(node);
      }
      fLayoutSystem.handleFlexContainerComp(node, r);
    }

    recomputeAutoMainSizes(itemWidget, r, isRow, stretchCrossAxis);

    foreach (node; nodeBuf[]) {
      node.layoutDirty = false;
    }
  }

  static void collectVisibleNodes(
    Widget node,
    ref ReusableArray!Widget buf
  ) {
    if (node is null || !node.visible) {
      return;
    }
    buf.push(node);
    foreach (child; node.children) {
      collectVisibleNodes(child, buf);
    }
  }

  static void applyCrossAxisStretch(
    Widget itemWidget,
    float viewportCross,
    bool isRow
  ) {
    import std.algorithm.comparison : max;
    const Size sz = itemWidget.components.size;
    const bool isCrossFixed = sz !is null && (
      isRow
        ? sz.height.mode == SizingMode.fixed
        : sz.width.mode == SizingMode.fixed
    );
    if (isCrossFixed) {
      return;
    }
    float targetCross = max(0.0f, viewportCross);
    if (sz !is null) {
      const float minCross = isRow ? sz.minHeight : sz.minWidth;
      const float maxCross = isRow ? sz.maxHeight : sz.maxWidth;
      targetCross = clampDimension(targetCross, minCross, maxCross);
    }
    assignCrossSize(itemWidget, isRow, targetCross);
  }

  void recomputeAutoMainSizes(
    Widget itemWidget,
    Renderer r,
    bool isRow,
    bool stretchCrossAxis
  ) {
    foreach_reverse (node; nodeBuf[]) {
      const Size sz = node.components.size;
      if (sz is null) {
        continue;
      }
      const bool mainIsAuto = isRow
        ? sz.width.mode == SizingMode.auto_
        : sz.height.mode == SizingMode.auto_;
      if (!mainIsAuto) {
        continue;
      }
      const float savedCross = crossSize(node, isRow);
      LayoutSystem.handleSizeComp(node, r);
      if (stretchCrossAxis || node !is itemWidget) {
        assignCrossSize(node, isRow, savedCross);
      }
      if (node is itemWidget && !isRow && stretchCrossAxis && r !is null &&
          node.components.textLabel !is null && !hasVisibleFlowChild(node)) {
        updateFlexChildTextHeight(node, r);
      }
    }
  }

  static bool hasVisibleFlowChild(const Widget w) {
    foreach (child; w.children) {
      if (child.visible && child.components.anchor is null) {
        return true;
      }
    }
    return false;
  }

  static void handleVirtListPostLayout(Widget w, WidgetSystemHost activeHost) {
    import std.algorithm.comparison : min;
    VirtListComponent vc = w.components.virtList;
    assert(vc !is null);

    const uint firstIdx = cast(uint) min(vc.fAnchorIndex, size_t(uint.max));
    const uint visCount = cast(uint) min(
      vc.fVisibleItemsCount, size_t(uint.max)
    );
    const bool changed = (
      vc.fTotalMainSize != vc.fLastEmittedTotalMainSize ||
      vc.fViewportMainSize != vc.fLastEmittedViewportMainSize ||
      vc.fMainOffset != vc.fLastEmittedMainOffset ||
      vc.fMaxCrossSize != vc.fLastEmittedMaxCrossSize ||
      vc.fViewportCrossSize != vc.fLastEmittedViewportCrossSize ||
      vc.fCrossOffset != vc.fLastEmittedCrossOffset ||
      firstIdx != vc.fLastEmittedFirstVisible ||
      visCount != vc.fLastEmittedVisibleCount
    );

    vc.fLastEmittedTotalMainSize = vc.fTotalMainSize;
    vc.fLastEmittedViewportMainSize = vc.fViewportMainSize;
    vc.fLastEmittedMainOffset = vc.fMainOffset;
    vc.fLastEmittedMaxCrossSize = vc.fMaxCrossSize;
    vc.fLastEmittedViewportCrossSize = vc.fViewportCrossSize;
    vc.fLastEmittedCrossOffset = vc.fCrossOffset;
    vc.fLastEmittedFirstVisible = firstIdx;
    vc.fLastEmittedVisibleCount = visCount;

    if (changed && vc.metricsChangedEvent.length > 0 && activeHost !is null) {
      VirtListComponent.PackParams pp;
      pp.withTotalMainSize(vc.fTotalMainSize)
        .withViewportMainSize(vc.fViewportMainSize)
        .withMainOffset(vc.fMainOffset)
        .withMaxCrossSize(vc.fMaxCrossSize)
        .withViewportCrossSize(vc.fViewportCrossSize)
        .withCrossOffset(vc.fCrossOffset)
        .withFirstVisibleIndex(firstIdx)
        .withVisibleCount(visCount);
      auto val = VirtListComponent.AppEventViewValue.pack(pp);
      auto ev = ViewAppEventBuilder(vc.metricsChangedEvent)
        .widget(w)
        .valueArray(val)
        .build();
      passViewEvent(activeHost, w, ev);
    }
  }

  WidgetSystemHost fHost;
  LayoutSystem fLayoutSystem;
  ReusableArray!Widget nodeBuf;
  ReusableArray!VirtListActiveItem fNextActiveBuf;
}

version (unittest) {
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.uisystem : UiSystem;
  import yguilib.widget.builder : WidgetBuilder;
  import yguilib.widget.internal.collect_visible : VisibleWidgetsCollector;
  import yguilib.widget.layout_components : Dimension, FlexContainer, Insets;
  import yguilib.widget.test_fixture : MockWidgetSystemHost;
  import yguilib.widget.virtlist_components : VirtListProvider;

  private:
  final class TestItemProvider : VirtListProvider {
    UiSystem ui;
    size_t createCalls;
    size_t updateCalls;
    size_t recycleCalls;
    size_t[] boundIndices;
    Widget[] recycledWidgets;
    float[] itemMainSizes;
    float[] itemCrossSizes;
    bool horizontal;

    this(UiSystem ui) {
      assert(ui !is null);
      this.ui = ui;
    }

    override Widget createWidget(Widget parent) {
      createCalls++;
      return WidgetBuilder.make(ui)
        .parent(parent)
        .name("virtItem")
        .rect(RectF(0, 0, 100, 40))
        .fixedSize(100, 40)
        .build();
    }

    override void updateWidgetAt(Widget w, size_t index) {
      updateCalls++;
      boundIndices ~= index;
      const float mainSz = index < itemMainSizes.length
        ? itemMainSizes[index]
        : 40.0f;
      const float crossSz = index < itemCrossSizes.length
        ? itemCrossSizes[index]
        : 100.0f;
      if (w.components.size !is null) {
        if (horizontal) {
          w.components.size.width = Dimension(mainSz, SizingMode.fixed);
          w.components.size.height = Dimension(crossSz, SizingMode.fixed);
        } else {
          w.components.size.width = Dimension(crossSz, SizingMode.fixed);
          w.components.size.height = Dimension(mainSz, SizingMode.fixed);
        }
      }
      w.update(WidgetUpdateScope.layout);
    }

    override void onWidgetRecycled(Widget w) {
      recycleCalls++;
      recycledWidgets ~= w;
    }
  }

  final class HeterogeneousSubtreeProvider : VirtListProvider {
    UiSystem ui;
    size_t createCalls;
    size_t[] rowTypes;
    float[] variantHeights;

    this(UiSystem ui) {
      assert(ui !is null);
      this.ui = ui;
    }

    override Widget createWidget(Widget parent) {
      createCalls++;
      return WidgetBuilder.make(ui)
        .parent(parent)
        .name("heteroRow")
        .rect(RectF(0, 0, 0, 0))
        .autoSize()
        .flexColumn()
        .child((WidgetBuilder b) {
          b.name("variantA")
            .rect(RectF(0, 0, 120, 30))
            .fixedSize(120, 30);
        })
        .child((WidgetBuilder b) {
          b.name("variantB")
            .rect(RectF(0, 0, 320, 90))
            .fixedSize(320, 90);
        })
        .build();
    }

    override void updateWidgetAt(Widget w, size_t index) {
      const size_t t = index < rowTypes.length ? rowTypes[index] : 0;
      const float h = index < variantHeights.length
        ? variantHeights[index]
        : (t == 0 ? 30.0f : 90.0f);
      Widget va = w.findByName("variantA");
      Widget vb = w.findByName("variantB");
      va.visible = (t == 0);
      vb.visible = (t == 1);
      va.update(WidgetUpdateScope.layout);
      vb.update(WidgetUpdateScope.layout);
      if (t == 0) {
        va.components.size.height = Dimension(h, SizingMode.fixed);
        va.update(WidgetUpdateScope.layout);
      } else {
        vb.components.size.height = Dimension(h, SizingMode.fixed);
        vb.update(WidgetUpdateScope.layout);
      }
    }

    override void onWidgetRecycled(Widget w) {}
  }

  void runLayoutStep(
    VirtListSystem sys,
    MockWidgetSystemHost host,
    Widget viewport
  ) {
    WidgetSystemContext ctx;
    ctx.host = host;
    ctx.root = viewport;
    ctx.unclippedWidgets = [VisibleWidget(viewport, viewport.rect)];
    ctx.visibleWidgets = ctx.unclippedWidgets;
    sys.layout(ctx);
    sys.postLayout(ctx);
  }
}

// Single-template creation, bounded pool reuse, and onWidgetRecycled
unittest {
  auto ui = new UiSystemImpl(null);
  auto host = new MockWidgetSystemHost();
  auto sys = new VirtListSystem(host);
  assert(sys.priority == WidgetSystem.virtListSystemPriority);
  assert(
    sys.phases ==
      (SystemPhase.event | SystemPhase.layout | SystemPhase.postLayout)
  );

  auto provider = new TestItemProvider(ui);
  auto viewport = WidgetBuilder.make(ui)
    .name("vp")
    .rect(RectF(0, 0, 120, 100))
    .virtList(provider)
    .virtListCount(1000)
    .virtListGap(4.0f)
    .onVirtListMetricsChanged("vlMetrics")
    .build();

  runLayoutStep(sys, host, viewport);
  auto vc = viewport.components.virtList;
  assert(viewport.clipChildren);
  // 100px tall with 40px items + 4px gap: indices 0 (0..40), 1 (44..84),
  // 2 (88..128) -> 3 visible widgets created.
  assert(provider.createCalls == 3);
  assert(vc.activeWidgetsCount == 3);
  assert(vc.pooledWidgetsCount == 0);
  assert(vc.anchorIndex == 0);
  assert(vc.visibleItemsCount == 3);
  assert(host.sentEvents.length == 1);
  auto m0 = VirtListComponent.AppEventViewValue.fromRaw(
    host.sentEvents[0].view.value
  );
  assert(m0.firstVisibleIndex == 0);
  assert(m0.visibleCount == 3);

  // Scroll down past item 0 and 1 (100px -> offset 100)
  vc.scrollToMainOffset(100.0f);
  runLayoutStep(sys, host, viewport);
  // Items 0 and 1 recycled, items 2, 3, 4 visible -> reused from pool!
  assert(provider.recycleCalls == 2);
  assert(vc.anchorIndex == 2);
  assert(vc.activeWidgetsCount == 3);
  // Max visible items at once <= 4, no unbounded creation
  assert(provider.createCalls <= 4);

  // Release viewport cleans up pools and children bottom-up
  ui.releaseWidget(viewport);
  assert(viewport.released);
  assert(vc.activeWidgetsCount == 0);
  assert(vc.pooledWidgetsCount == 0);
}

// Heterogeneous row subtrees, variable & oversized items, smooth pixel scroll
unittest {
  auto ui = new UiSystemImpl(null);
  auto host = new MockWidgetSystemHost();
  auto sys = new VirtListSystem(host);
  auto provider = new HeterogeneousSubtreeProvider(ui);
  // Row 0: 30x120, Row 1: 220x320 (oversized on both main and cross axes!),
  // Row 2: 30x120
  provider.rowTypes = [0, 1, 0];
  provider.variantHeights = [30.0f, 220.0f, 30.0f];

  auto viewport = WidgetBuilder.make(ui)
    .name("heteroVp")
    .rect(RectF(0, 0, 150, 100))
    .virtList(provider)
    .virtListCount(3)
    .virtListGap(4.0f)
    .build();

  runLayoutStep(sys, host, viewport);
  auto vc = viewport.components.virtList;
  assert(provider.createCalls == 2);
  assert(vc.activeWidgetsCount == 2);
  assert(vc.maxCrossSize == 320.0f);

  // Scroll smoothly into oversized item 1 and pan cross axis
  vc.scrollByMain(60.0f);
  vc.requestCrossOffset(90.0f);
  runLayoutStep(sys, host, viewport);
  assert(vc.anchorIndex == 1);
  // Item 0 (30) + gap (4) = 34 -> remaining inside item 1 is 60 - 34 = 26
  assert(vc.anchorOffset == -26.0f);
  assert(vc.crossOffset == 90.0f);
  assert(vc.activeWidgetsCount == 1);
  // Active item 1 placed at x = -90, y = -26
  Widget active1 = viewport.children[0].visible
    ? viewport.children[0]
    : viewport.children[1];
  assert(active1.rect.x == -90.0f);
  assert(active1.rect.y == -26.0f);

  // Scroll further inside oversized item 1 until item 2 appears at bottom
  vc.scrollByMain(120.0f); // total 180 -> 34 + 220 + 4 = 258
  runLayoutStep(sys, host, viewport);
  assert(vc.anchorIndex == 1);
  assert(vc.anchorOffset == -146.0f);
  assert(vc.activeWidgetsCount == 2);
}

// Dynamic recordUpdate and isTreeLayoutDirty() reflow & trailing recycle
unittest {
  auto ui = new UiSystemImpl(null);
  auto host = new MockWidgetSystemHost();
  auto sys = new VirtListSystem(host);
  auto provider = new HeterogeneousSubtreeProvider(ui);
  provider.rowTypes = [0, 0, 0, 0];
  provider.variantHeights = [30.0f, 30.0f, 30.0f, 30.0f];

  auto viewport = WidgetBuilder.make(ui)
    .name("updateVp")
    .rect(RectF(0, 0, 200, 100))
    .virtList(provider)
    .virtListCount(4)
    .virtListGap(2.0f)
    .build();

  runLayoutStep(sys, host, viewport);
  auto vc = viewport.components.virtList;
  // 30 + 2 + 30 + 2 + 30 + 2 + 30 -> items 0 (0), 1 (32), 2 (64), 3 (96)
  assert(vc.activeWidgetsCount == 4);

  // Update row 1 to grow from 30px to 50px -> pushes row 3 past 100px
  // (30 + 2 + 50 + 2 + 30 -> rows 0, 1, 2 visible; row 3 pooled)
  provider.rowTypes[1] = 1;
  provider.variantHeights[1] = 50.0f;
  vc.recordUpdate(1, 1);
  runLayoutStep(sys, host, viewport);
  assert(vc.activeWidgetsCount == 3);
  assert(vc.pooledWidgetsCount == 1);

  // Now mutate active row 0 directly and mark its subtree layoutDirty
  // without calling recordUpdate -> isTreeLayoutDirty() triggers re-measure!
  Widget row0 = null;
  foreach (c; viewport.children) {
    if (c.visible && c.rect.y == 0.0f) {
      row0 = c;
      break;
    }
  }
  assert(row0 !is null);
  Widget va0 = row0.findByName("variantA");
  va0.components.size.height = Dimension(50.0f, SizingMode.fixed);
  va0.update(WidgetUpdateScope.layout);
  assert(row0.isTreeLayoutDirty());

  runLayoutStep(sys, host, viewport);
  // Row 0 (50) + gap (2) + Row 1 (80) = 132 > 100 -> row 2 recycled too!
  assert(vc.activeWidgetsCount == 2);
  assert(vc.pooledWidgetsCount == 2);
}

// Dynamic recordInsert & recordRemove preserving visible anchor item & offset
unittest {
  auto ui = new UiSystemImpl(null);
  auto host = new MockWidgetSystemHost();
  auto sys = new VirtListSystem(host);
  auto provider = new TestItemProvider(ui);

  auto viewport = WidgetBuilder.make(ui)
    .name("mutVp")
    .rect(RectF(0, 0, 120, 100))
    .virtList(provider)
    .virtListCount(20)
    .virtListGap(4.0f)
    .build();

  auto vc = viewport.components.virtList;
  // Scroll to item 5 with -12px anchor offset
  vc.scrollToIndex(5);
  vc.scrollByMain(12.0f);
  runLayoutStep(sys, host, viewport);
  assert(vc.anchorIndex == 5);
  assert(vc.anchorOffset == -12.0f);

  // Insert 3 items above anchor (at index 2): anchorIndex shifts 5 -> 8,
  // anchorOffset preserved at -12
  vc.itemsCount = 23;
  vc.recordInsert(2, 3);
  runLayoutStep(sys, host, viewport);
  assert(vc.anchorIndex == 8);
  assert(vc.anchorOffset == -12.0f);

  // Insert 2 items below anchor (at index 10): anchorIndex stays 8
  vc.itemsCount = 25;
  vc.recordInsert(10, 2);
  runLayoutStep(sys, host, viewport);
  assert(vc.anchorIndex == 8);
  assert(vc.anchorOffset == -12.0f);

  // Remove 2 items above anchor (at index 1): anchorIndex shifts 8 -> 6,
  // anchorOffset preserved at -12
  vc.itemsCount = 23;
  vc.recordRemove(1, 2);
  runLayoutStep(sys, host, viewport);
  assert(vc.anchorIndex == 6);
  assert(vc.anchorOffset == -12.0f);

  // Remove anchor itself (index 6, count 2): resets anchorOffset to 0 at 6
  vc.itemsCount = 21;
  vc.recordRemove(6, 2);
  runLayoutStep(sys, host, viewport);
  assert(vc.anchorIndex == 6);
  assert(vc.anchorOffset == 0.0f);
}

// Horizontal (FlexDirection.row) mode, stretchCrossAxis, and mouseWheel
unittest {
  auto ui = new UiSystemImpl(null);
  auto host = new MockWidgetSystemHost();
  auto sys = new VirtListSystem(host);
  auto provider = new TestItemProvider(ui);
  provider.horizontal = true;
  provider.itemMainSizes = [60.0f, 60.0f, 60.0f, 60.0f, 60.0f];

  auto viewport = WidgetBuilder.make(ui)
    .name("horizVp")
    .rect(RectF(10, 20, 130, 80))
    .virtList(provider)
    .virtListDirection(FlexDirection.row)
    .virtListCount(5)
    .virtListGap(5.0f)
    .virtListStretchCross(true)
    .build();

  // Replace size on provider to auto cross so stretchCrossAxis stretches it
  auto vc = viewport.components.virtList;
  runLayoutStep(sys, host, viewport);
  assert(vc.anchorIndex == 0);
  // 0..60, 65..125, 130 >= 130 -> 2 items visible
  assert(vc.activeWidgetsCount == 2);

  // Send mouseWheel event over viewport
  WidgetSystemContext ctx;
  ctx.host = host;
  ctx.root = viewport;
  ctx.visibleWidgets = [VisibleWidget(viewport, viewport.rect)];
  auto wheelEv = AppEvent.wheelEvent(
    AppEvent.WheelData(1, 0.0f, -1.0f, 50.0f, 50.0f, 1, 0, -1)
  );
  auto res = sys.handleEvent(wheelEv, ctx);
  assert(res.consumed);

  runLayoutStep(sys, host, viewport);
  assert(vc.mainOffset > 0.0f);

  // Test stretchCrossAxis and bottom underflow via scrollToIndex(last)
  final class AutoCrossProvider : VirtListProvider {
    UiSystem u;
    this(UiSystem u) {
      assert(u !is null);
      this.u = u;
    }

    override Widget createWidget(Widget parent) {
      return WidgetBuilder.make(u)
        .parent(parent)
        .name("autoRow")
        .rect(RectF(0, 0, 0, 0))
        .autoWidth()
        .fixedHeight(30.0f)
        .flexRow()
        .child((WidgetBuilder b) {
          b.name("cell")
            .rect(RectF(0, 0, 50, 20))
            .fixedSize(50, 20);
        })
        .build();
    }

    override void updateWidgetAt(Widget w, size_t index) {}
    override void onWidgetRecycled(Widget w) {}
  }

  auto stretchVp = WidgetBuilder.make(ui)
    .name("stretchVp")
    .rect(RectF(0, 0, 180, 100))
    .virtList(new AutoCrossProvider(ui))
    .virtListCount(10)
    .virtListGap(4.0f)
    .virtListStretchCross(true)
    .build();

  auto svc = stretchVp.components.virtList;
  svc.scrollToIndex(9);
  runLayoutStep(sys, host, stretchVp);
  assert(stretchVp.children[0].rect.width == 180.0f);
  // 30*3 + 4*2 = 98 < 100 -> 4 items backfilled (indices 6..9),
  // last item bottom aligns with 100.0f
  assert(svc.activeWidgetsCount == 4);
  assert(svc.anchorIndex == 6);
  Widget lastItem = null;
  foreach (c; stretchVp.children) {
    if (c.visible && (lastItem is null || c.rect.y > lastItem.rect.y)) {
      lastItem = c;
    }
  }
  assert(lastItem !is null);
  assert(lastItem.rect.y + lastItem.rect.height == 100.0f);
}

// Wheel gating: disabled list, occluding overlay, and clickable child item
unittest {
  auto ui = new UiSystemImpl(null);
  auto host = new MockWidgetSystemHost();
  auto sys = new VirtListSystem(host);
  auto provider = new TestItemProvider(ui);

  auto root = WidgetBuilder.make(ui)
    .name("root")
    .rect(RectF(0, 0, 300, 300))
    .build();

  auto viewport = WidgetBuilder.make(ui)
    .parent(root)
    .name("vp")
    .rect(RectF(0, 0, 120, 100))
    .virtList(provider)
    .virtListCount(20)
    .virtListGap(4.0f)
    .build();

  runLayoutStep(sys, host, viewport);
  auto vc = viewport.components.virtList;

  // Clickable child item inside list does NOT block wheel on list
  Widget item0 = viewport.children[0];
  item0.handleInput = true;
  WidgetSystemContext ctx;
  ctx.host = host;
  ctx.root = root;
  ctx.visibleWidgets = [
    VisibleWidget(root, root.rect),
    VisibleWidget(viewport, viewport.rect),
    VisibleWidget(item0, item0.rect),
  ];
  auto wheelEv = AppEvent.wheelEvent(
    AppEvent.WheelData(1, 0.0f, -1.0f, 20.0f, 20.0f, 1, 0, -1)
  );
  assert(sys.handleEvent(wheelEv, ctx).consumed);
  runLayoutStep(sys, host, viewport);
  assert(vc.mainOffset > 0.0f);
  const float prevOffset = vc.mainOffset;

  // Disabled list ignores wheel
  viewport.inputEnabled = false;
  assert(!sys.handleEvent(wheelEv, ctx).consumed);
  runLayoutStep(sys, host, viewport);
  assert(vc.mainOffset == prevOffset);
  viewport.inputEnabled = true;

  // Occluding overlay with handleInput blocks wheel
  auto overlay = WidgetBuilder.make(ui)
    .parent(root)
    .name("overlay")
    .rect(RectF(0, 0, 120, 100))
    .handleInput(true)
    .build();
  ctx.visibleWidgets ~= VisibleWidget(overlay, overlay.rect);
  assert(!sys.handleEvent(wheelEv, ctx).consumed);
  runLayoutStep(sys, host, viewport);
  assert(vc.mainOffset == prevOffset);

  // Transparent overlay (handleInput == false) does not block wheel
  overlay.handleInput = false;
  assert(sys.handleEvent(wheelEv, ctx).consumed);
}

// Empty-list cache reset, itemsCount shrink pruning, and multi-batch insert
unittest {
  auto ui = new UiSystemImpl(null);
  auto host = new MockWidgetSystemHost();
  auto sys = new VirtListSystem(host);
  auto provider = new TestItemProvider(ui);

  auto viewport = WidgetBuilder.make(ui)
    .name("cacheVp")
    .rect(RectF(0, 0, 120, 100))
    .virtList(provider)
    .virtListCount(10)
    .build();

  runLayoutStep(sys, host, viewport);
  auto vc = viewport.components.virtList;
  assert(vc.fItemMainSizes.length == 3);

  // Shrink itemsCount to 2 without recordRemove -> stale key 2 pruned
  vc.itemsCount = 2;
  runLayoutStep(sys, host, viewport);
  assert(vc.fItemMainSizes.length == 2);
  assert((2 in vc.fItemMainSizes) is null);

  // Reset itemsCount to 0 -> all size caches cleared
  vc.itemsCount = 0;
  runLayoutStep(sys, host, viewport);
  assert(vc.fItemMainSizes.length == 0);
  assert(vc.fItemCrossSizes.length == 0);
  assert(vc.fKnownMainSizesSum == 0.0);

  // Multi-batch insert into empty list preserves anchorIndex == 0
  vc.recordInsert(0, 3);
  vc.recordInsert(3, 3);
  vc.itemsCount = 6;
  runLayoutStep(sys, host, viewport);
  assert(vc.anchorIndex == 0);
  assert(vc.activeWidgetsCount == 3);
}

// Removal overflow guard, detachReleasedItem, and postLayout uint clamping
unittest {
  auto ui = new UiSystemImpl(null);
  auto host = new MockWidgetSystemHost();
  auto sys = new VirtListSystem(host);
  auto provider = new TestItemProvider(ui);

  auto viewport = WidgetBuilder.make(ui)
    .name("ovVp")
    .rect(RectF(0, 0, 120, 30))
    .virtList(provider)
    .virtListCount(10)
    .build();

  runLayoutStep(sys, host, viewport);
  auto vc = viewport.components.virtList;
  vc.scrollToIndex(2);
  runLayoutStep(sys, host, viewport);
  assert(vc.anchorIndex == 2);

  // Huge count near size_t.max must saturate instead of wrapping
  vc.itemsCount = 3;
  vc.recordRemove(3, size_t.max);
  runLayoutStep(sys, host, viewport);
  assert(vc.anchorIndex == 2);

  // Releasing an active item detaches it, updates visibleItemsCount, and
  // dirties parent layout
  const size_t beforeCount = vc.visibleItemsCount;
  assert(beforeCount > 0);
  Widget firstChild = viewport.children[0];
  viewport.layoutDirty = false;
  sys.onWidgetReleased(firstChild);
  assert(vc.visibleItemsCount == beforeCount - 1);
  assert(viewport.layoutDirty);

  // postLayout clamps size_t > uint.max to uint.max
  vc.fAnchorIndex = size_t(uint.max) + 42;
  vc.fVisibleItemsCount = size_t(uint.max) + 7;
  vc.metricsChangedEvent = "clampedMetrics";
  WidgetSystemContext ctx;
  ctx.host = host;
  ctx.root = viewport;
  ctx.unclippedWidgets = [VisibleWidget(viewport, viewport.rect)];
  ctx.visibleWidgets = ctx.unclippedWidgets;
  sys.postLayout(ctx);
  auto m = VirtListComponent.AppEventViewValue.fromRaw(
    host.sentEvents[$ - 1].view.value
  );
  assert(m.firstVisibleIndex == uint.max);
  assert(m.visibleCount == uint.max);
}

// LayoutSystem (priority 0) + VirtListSystem (priority 5) stretchCrossAxis
unittest {
  auto ui = new UiSystemImpl(null);
  auto host = new MockWidgetSystemHost();
  auto layoutSys = new LayoutSystem();
  auto virtSys = new VirtListSystem(host);

  final class AutoCrossProvider : VirtListProvider {
    UiSystem u;
    this(UiSystem u) {
      assert(u !is null);
      this.u = u;
    }

    override Widget createWidget(Widget parent) {
      return WidgetBuilder.make(u)
        .parent(parent)
        .name("autoRow")
        .rect(RectF(0, 0, 0, 0))
        .autoWidth()
        .fixedHeight(30.0f)
        .flexRow()
        .child((WidgetBuilder b) {
          b.name("cell")
            .rect(RectF(0, 0, 50, 20))
            .fixedSize(50, 20);
        })
        .build();
    }

    override void updateWidgetAt(Widget w, size_t index) {}
    override void onWidgetRecycled(Widget w) {}
  }

  auto viewport = WidgetBuilder.make(ui)
    .name("pipeVp")
    .rect(RectF(0, 0, 180, 100))
    .virtList(new AutoCrossProvider(ui))
    .virtListCount(5)
    .virtListStretchCross(true)
    .build();

  auto collector = new VisibleWidgetsCollector();
  WidgetSystemContext ctx;
  ctx.host = host;
  ctx.root = viewport;
  ctx.unclippedWidgets = collector.collectVisibleWithViewport(
    viewport, 400.0f, 400.0f, true
  );
  layoutSys.layout(ctx);
  virtSys.layout(ctx);
  virtSys.postLayout(ctx);
  assert(viewport.children[0].rect.width == 180.0f);

  // Second pass with all active children in unclippedWidgets must keep
  // stretched width 180.0f without LayoutSystem overwriting it
  ctx.unclippedWidgets = collector.collectVisibleWithViewport(
    viewport, 400.0f, 400.0f, true
  );
  layoutSys.layout(ctx);
  assert(viewport.children[0].rect.width == 180.0f);
  virtSys.layout(ctx);
  virtSys.postLayout(ctx);
  assert(viewport.children[0].rect.width == 180.0f);
}
