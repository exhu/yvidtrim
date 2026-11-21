/**
 * scrollbars.d - Reusable composite vertical and horizontal Scrollbar widget,
 * WidgetView, and WidgetViewController.
 */
module yguilib.controls.scrollbars;

import std.math.rounding : round;
import std.typecons : nullable;
import yguilib.controller : HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.builder : ViewAppEventBuilder;
import yguilib.model : ModelTracker, VersionedModel;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.uisystem : UiRegistry, UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : TextLabel;
import yguilib.widget.input_components : MouseEvent;
import yguilib.widget.layout_components : AlignItems, Anchor, Dimension,
  FlexDirection, Insets, JustifyContent, Size, SizingMode;
import yguilib.widget.scroll_components : ScrollableArea;
import yguilib.widget.widget_view : WidgetView, WidgetViewBase,
  WidgetViewControllerBase;

/// Internal view event emitted when clicking the decrement arrow button.
enum scrollbarDecEvent = "scrollbarDec";

/// Internal view event emitted when clicking the increment arrow button.
enum scrollbarIncEvent = "scrollbarInc";

/// Internal view event emitted when clicking on the free track area.
enum scrollbarTrackDownEvent = "scrollbarTrackDown";

/// Internal view event emitted by track ScrollableArea on resize.
enum scrollbarTrackChangedEvent = "scrollbarTrackChanged";

/// Internal view event emitted on thumb mouseDown.
enum scrollbarThumbDownEvent = "scrollbarThumbDown";

/// Internal view event emitted on thumb mouseDrag.
enum scrollbarThumbDragEvent = "scrollbarThumbDrag";

/// Internal view event emitted on thumb mouseUp.
enum scrollbarThumbUpEvent = "scrollbarThumbUp";

/// Default view event name emitted when scrollbar position changes.
enum defaultScrollbarEventName = "scrollbarChanged";

/// Registered name of ScrollbarWidgetView in UiRegistry.
enum scrollbarWidgetViewName = "ScrollbarWidgetView";

/// Registered name of ScrollbarWidgetViewController in UiRegistry.
enum scrollbarWidgetViewControllerName = "ScrollbarWidgetViewController";

/**
 * Versioned model tracking scrollbar bounds, position, visible window size,
 * step increment, and reporting mode.
 */
final class ScrollbarModel : VersionedModel {
  /// Minimum value (inclusive).
  long min = 0;
  /// Maximum value (inclusive).
  long max = 100;
  /// Current scroll value in `[min, max]`.
  long value = 0;
  /// Visible window size in units of `min`/`max`/`value` (also page step).
  long visibleSize = 20;
  /// Step increment for arrow button clicks.
  long stepSize = 5;
  /// When true, dragging updates visuals smoothly and emits the position
  /// change event only after the mouse button is released.
  bool reportOnReleaseOnly = false;

  /// Constructs a ScrollbarModel with default state.
  this() {
  }

  /// Sets [min, max] range and clamps `value`.
  ScrollbarModel withRange(long minVal, long maxVal) {
    import std.algorithm.comparison : clamp;
    this.min = minVal;
    this.max = (maxVal < minVal) ? minVal : maxVal;
    this.value = clamp(this.value, this.min, this.max);
    return this;
  }

  /// Sets and clamps `value` to [min, max].
  ScrollbarModel withValue(long val) {
    import std.algorithm.comparison : clamp;
    this.value = clamp(val, this.min, this.max);
    return this;
  }

  /// Sets visible window size (clamped >= 1).
  ScrollbarModel withVisibleSize(long vis) {
    this.visibleSize = (vis < 1) ? 1 : vis;
    return this;
  }

  /// Sets arrow step increment (clamped >= 1).
  ScrollbarModel withStepSize(long step) {
    this.stepSize = (step < 1) ? 1 : step;
    return this;
  }

  /// Sets whether drag events are emitted only on release.
  ScrollbarModel withReportOnReleaseOnly(bool releaseOnly) {
    this.reportOnReleaseOnly = releaseOnly;
    return this;
  }
}

/// Visual styling and sizing configuration for a Scrollbar.
struct ScrollbarStyle {
  float thickness = 22.0f;
  float arrowButtonSize = 22.0f;
  float gap = 2.0f;
  float trackPadding = 2.0f;
  float minThumbSize = 20.0f;
  float cornerRadius = 4.0f;
  float thumbCornerRadius = 3.0f;
  float fontSize = 11.0f;

  ColorF trackBg = ColorF(0.10f, 0.12f, 0.15f, 1.0f);
  ColorF trackBorder = ColorF(0.20f, 0.23f, 0.29f, 1.0f);

  ColorF arrowBg = ColorF(0.16f, 0.19f, 0.25f, 1.0f);
  ColorF arrowBorder = ColorF(0.28f, 0.33f, 0.42f, 1.0f);
  ColorF arrowText = ColorF(0.88f, 0.92f, 0.98f, 1.0f);

  ColorF thumbBg = ColorF(0.32f, 0.46f, 0.68f, 1.0f);
  ColorF thumbBorder = ColorF(0.45f, 0.62f, 0.88f, 1.0f);
  ColorF thumbDragBg = ColorF(0.42f, 0.62f, 0.92f, 1.0f);
  ColorF thumbDragBorder = ColorF(0.62f, 0.80f, 1.0f, 1.0f);

  ColorF disabledBg = ColorF(0.11f, 0.12f, 0.15f, 1.0f);
  ColorF disabledBorder = ColorF(0.18f, 0.20f, 0.24f, 1.0f);
  ColorF disabledText = ColorF(0.38f, 0.40f, 0.46f, 1.0f);
}

/// Internal bookkeeping entry tracking a registered Scrollbar composite.
final class ScrollbarEntry {
  ModelTracker!ScrollbarModel tracker;
  Widget decBtn;
  Widget track;
  Widget thumb;
  Widget incBtn;
  ScrollbarStyle style;
  FlexDirection direction;
  string eventName;

  PointF lastTrackViewportSize = PointF(0.0f, 0.0f);
  float currentThumbLen = 20.0f;
  float currentThumbOffset = 0.0f;

  bool isDragging = false;
  float dragStartWindowPos = 0.0f;
  float dragStartThumbOffset = 0.0f;
  long dragStartValue = 0;
  long pendingValue = 0;

  bool viewDirty = false;

  this(ref ModelTracker!ScrollbarModel tracker) {
    this.tracker = ModelTracker!ScrollbarModel.from(tracker);
  }
}

/**
 * WidgetView managing registered Scrollbar root widgets, computing
 * proportional thumb sizes and positions, handling arrow/track/drag
 * interactions, and synchronizing visuals with `ScrollbarModel`.
 */
final class ScrollbarWidgetView : WidgetViewBase {
  /// Registers a fully constructed Scrollbar composite with its parts.
  void registerScrollbar(
    Widget viewWidget,
    ref ModelTracker!ScrollbarModel tracker,
    Widget decBtn,
    Widget track,
    Widget thumb,
    Widget incBtn,
    in ScrollbarStyle style,
    FlexDirection direction,
    string eventName
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    if (!isWidgetRegistered(viewWidget)) {
      registerViewWidget(viewWidget);
    }
    auto entry = new ScrollbarEntry(tracker);
    entry.decBtn = decBtn;
    entry.track = track;
    entry.thumb = thumb;
    entry.incBtn = incBtn;
    entry.style = style;
    entry.direction = direction;
    entry.eventName = (eventName.length > 0)
      ? eventName
      : defaultScrollbarEventName;
    entries[viewWidget] = entry;
    syncEntryVisuals(entry);
  }

  /// Associates a `ScrollbarModel` with a registered or newly built root.
  void bindModel(Widget viewWidget, ref ModelTracker!ScrollbarModel tracker) {
    assert(viewWidget !is null, "viewWidget must not be null");
    if (!isWidgetRegistered(viewWidget)) {
      registerViewWidget(viewWidget);
    }
    if (auto pEntry = viewWidget in entries) {
      pEntry.tracker = ModelTracker!ScrollbarModel.from(tracker);
      syncEntryVisuals(*pEntry);
    } else {
      Widget decBtn, track, thumb, incBtn;
      findScrollbarParts(viewWidget, decBtn, track, thumb, incBtn);
      registerScrollbar(
        viewWidget, tracker, decBtn, track, thumb, incBtn,
        ScrollbarStyle(), FlexDirection.row, defaultScrollbarEventName
      );
    }
  }

  /// Associates a `ScrollbarModel` instance with `viewWidget`.
  void bindModelWithModel(Widget viewWidget, ScrollbarModel model) {
    assert(viewWidget !is null, "viewWidget must not be null");
    assert(model !is null, "model must not be null");
    auto tracker = ModelTracker!ScrollbarModel(model);
    bindModel(viewWidget, tracker);
  }

  override void unregisterViewWidget(Widget viewWidget) {
    super.unregisterViewWidget(viewWidget);
    entries.remove(viewWidget);
  }

  Widget getDecButton(Widget viewWidget) {
    if (auto p = viewWidget in entries) {
      return p.decBtn;
    }
    return null;
  }

  Widget getIncButton(Widget viewWidget) {
    if (auto p = viewWidget in entries) {
      return p.incBtn;
    }
    return null;
  }

  Widget getTrack(Widget viewWidget) {
    if (auto p = viewWidget in entries) {
      return p.track;
    }
    return null;
  }

  Widget getThumb(Widget viewWidget) {
    if (auto p = viewWidget in entries) {
      return p.thumb;
    }
    return null;
  }

  string getEventName(Widget viewWidget) {
    if (auto p = viewWidget in entries) {
      return p.eventName;
    }
    return null;
  }

  override void translateEventForViewWidget(
    ref AppEvent sourceEvent,
    Widget viewWidget
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    super.translateEventForViewWidget(sourceEvent, viewWidget);
  }

  /// Steps scrollbar value by `-stepSize` (arrow click).
  /// Returns true if the reported value changed.
  bool stepDecrement(Widget viewWidget, out long newValue) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto pEntry = viewWidget in entries;
    if (pEntry is null) {
      return false;
    }
    auto entry = *pEntry;
    const auto m = entry.tracker.model;
    import std.algorithm.comparison : max;
    const long step = max(1L, m.stepSize);
    return applyModelValue(entry, m.value - step, newValue);
  }

  /// Steps scrollbar value by `+stepSize` (arrow click).
  /// Returns true if the reported value changed.
  bool stepIncrement(Widget viewWidget, out long newValue) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto pEntry = viewWidget in entries;
    if (pEntry is null) {
      return false;
    }
    auto entry = *pEntry;
    const auto m = entry.tracker.model;
    import std.algorithm.comparison : max;
    const long step = max(1L, m.stepSize);
    return applyModelValue(entry, m.value + step, newValue);
  }

  /// Handles a click on the track free area, paging by `visibleSize`.
  /// Returns true if the reported value changed.
  bool handleTrackClick(
    Widget viewWidget,
    in MouseEvent.AppEventViewValue mouseVal,
    out long newValue
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto pEntry = viewWidget in entries;
    if (pEntry is null || pEntry.track is null) {
      return false;
    }
    auto entry = *pEntry;
    const auto m = entry.tracker.model;
    const long effMin = m.min;
    import std.algorithm.comparison : max;
    const long effMax = max(m.min, m.max);
    if (effMax <= effMin) {
      return false;
    }

    const bool isRow = (entry.direction == FlexDirection.row);
    const RectF ca = entry.track.getContentArea();
    const float clickLocal = isRow ? mouseVal.localX : mouseVal.localY;
    const float clickInContent = clickLocal - (isRow ? ca.x : ca.y);
    const float thumbStart = entry.currentThumbOffset;
    const float thumbEnd = thumbStart + entry.currentThumbLen;
    import std.algorithm.comparison : max;
    const long page = max(1L, m.visibleSize);

    if (clickInContent < thumbStart) {
      return applyModelValue(entry, m.value - page, newValue);
    } else if (clickInContent > thumbEnd) {
      return applyModelValue(entry, m.value + page, newValue);
    }
    return false;
  }

  /// Begins a thumb drag interaction on `mouseDown`.
  bool beginThumbDrag(
    Widget viewWidget,
    in MouseEvent.AppEventViewValue mouseVal
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto pEntry = viewWidget in entries;
    if (pEntry is null) {
      return false;
    }
    auto entry = *pEntry;
    const auto m = entry.tracker.model;
    const long effMin = m.min;
    import std.algorithm.comparison : max;
    const long effMax = max(m.min, m.max);
    if (effMax <= effMin) {
      return false;
    }

    const bool isRow = (entry.direction == FlexDirection.row);
    entry.isDragging = true;
    entry.dragStartWindowPos = isRow ? mouseVal.windowX : mouseVal.windowY;
    entry.dragStartThumbOffset = entry.currentThumbOffset;
    import std.algorithm.comparison : clamp;
    entry.dragStartValue = clamp(m.value, effMin, effMax);
    entry.pendingValue = entry.dragStartValue;
    updateThumbColors(entry, false);
    entry.viewDirty = true;
    return true;
  }

  /// Updates thumb position (and model value if live) during `mouseDrag`.
  /// Returns true if a position change event should be emitted now.
  bool updateThumbDrag(
    Widget viewWidget,
    in MouseEvent.AppEventViewValue mouseVal,
    out long newValue
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto pEntry = viewWidget in entries;
    if (pEntry is null || !pEntry.isDragging) {
      return false;
    }
    auto entry = *pEntry;
    const auto m = entry.tracker.model;
    const long effMin = m.min;
    import std.algorithm.comparison : max;
    const long effMax = max(m.min, m.max);
    const long range = max(0L, effMax - effMin);

    const float trackLen = getTrackMainLength(entry);
    const float thumbLen = computeThumbLength(
      trackLen,
      range,
      m.visibleSize,
      entry.style.minThumbSize
    );
    import std.algorithm.comparison : clamp, max;
    const float maxTravel = max(0.0f, trackLen - thumbLen);
    const float draggedOffset = computeDraggedOffset(
      entry, mouseVal, maxTravel
    );

    long computedVal = effMin;
    if (range > 0 && maxTravel > 0.0f) {
      const double norm = cast(double) draggedOffset / cast(double) maxTravel;
      const long offsetUnits = cast(long) round(norm * cast(double) range);
      computedVal = clamp(effMin + offsetUnits, effMin, effMax);
    }

    entry.pendingValue = computedVal;

    if (m.reportOnReleaseOnly) {
      applyThumbGeometry(entry, thumbLen, draggedOffset);
      entry.viewDirty = true;
      return false;
    }

    const bool changed = applyModelValue(entry, computedVal, newValue);
    return changed;
  }

  float computeDraggedOffset(
    const ref ScrollbarEntry entry,
    const ref MouseEvent.AppEventViewValue mouseVal,
    float maxTravel
  ) {
    import std.algorithm.comparison : clamp;

    const bool isRow = (entry.direction == FlexDirection.row);
    const float curPos = isRow ? mouseVal.windowX : mouseVal.windowY;
    const float deltaPx = curPos - entry.dragStartWindowPos;
    return clamp(entry.dragStartThumbOffset + deltaPx, 0.0f, maxTravel);
  }

  /// Ends a thumb drag interaction on `mouseUp`.
  /// Returns true if a deferred position change event should be emitted now.
  bool endThumbDrag(Widget viewWidget, out long newValue) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto pEntry = viewWidget in entries;
    if (pEntry is null || !pEntry.isDragging) {
      return false;
    }
    auto entry = *pEntry;
    entry.isDragging = false;
    const bool reportOnRelease = entry.tracker.model.reportOnReleaseOnly;
    const long targetVal = entry.pendingValue;

    bool changed = false;
    if (reportOnRelease) {
      changed = applyModelValue(entry, targetVal, newValue);
    }
    syncEntryVisuals(entry);
    entry.viewDirty = true;
    return changed;
  }

  /// Handles layout feedback from `track`'s `ScrollableArea` when resized.
  bool handleTrackChanged(
    Widget viewWidget,
    in ScrollableArea.AppEventViewValue val
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto pEntry = viewWidget in entries;
    if (pEntry is null) {
      return false;
    }
    auto entry = *pEntry;
    entry.lastTrackViewportSize = val.viewportSize;
    syncEntryVisuals(entry);
    return true;
  }

  override bool update() {
    bool anyUpdated = false;
    foreach (w, entry; entries) {
      if (entry.tracker.update()) {
        syncEntryVisuals(entry);
        anyUpdated = true;
      }
      if (entry.viewDirty) {
        entry.viewDirty = false;
        anyUpdated = true;
      }
    }
    return anyUpdated;
  }

private:
  ScrollbarEntry[Widget] entries;

  bool applyModelValue(
    ScrollbarEntry entry,
    long candidateVal,
    out long newValue
  ) {
    auto m = entry.tracker.model;
    const long effMin = m.min;
    import std.algorithm.comparison : max;
    const long effMax = max(m.min, m.max);
    import std.algorithm.comparison : clamp;
    const long clamped = clamp(candidateVal, effMin, effMax);
    newValue = clamped;
    if (clamped == m.value) {
      return false;
    }

    auto editable = entry.tracker.edit();
    editable.value = clamped;
    entry.tracker.commit(editable);
    syncEntryVisuals(entry);
    entry.viewDirty = true;
    return true;
  }

  static void syncEntryVisuals(ScrollbarEntry entry) {
    const auto m = entry.tracker.model;
    const long effMin = m.min;
    import std.algorithm.comparison : max;
    const long effMax = max(m.min, m.max);
    const long range = max(0L, effMax - effMin);
    import std.algorithm.comparison : clamp;
    const long val = clamp(m.value, effMin, effMax);

    const float trackLen = getTrackMainLength(entry);
    const float thumbLen = computeThumbLength(
      trackLen,
      range,
      m.visibleSize,
      entry.style.minThumbSize
    );
    import std.algorithm.comparison : max;
    const float maxTravel = max(0.0f, trackLen - thumbLen);

    float thumbOffset = 0.0f;
    if (range > 0 && maxTravel > 0.0f) {
      const double norm = cast(double) (val - effMin) / cast(double) range;
      import std.algorithm.comparison : clamp;
    thumbOffset = clamp(cast(float) (maxTravel * norm), 0.0f, maxTravel);
    }

    applyThumbGeometry(entry, thumbLen, thumbOffset);
    updateThumbColors(entry, range == 0);
    updateArrowStates(entry, val, effMin, effMax);
  }

  static float getTrackMainLength(ScrollbarEntry entry) {
    const bool isRow = (entry.direction == FlexDirection.row);
    const float cachedLen = isRow
      ? entry.lastTrackViewportSize.x
      : entry.lastTrackViewportSize.y;
    if (cachedLen > 0.0f) {
      return cachedLen;
    }
    if (entry.track !is null) {
      const RectF ca = entry.track.getContentArea();
      const float caLen = isRow ? ca.width : ca.height;
      if (caLen > 0.0f) {
        return caLen;
      }
      const float rawLen = isRow
        ? entry.track.rect.width
        : entry.track.rect.height;
      if (rawLen > 0.0f) {
        return rawLen;
      }
    }
    return 0.0f;
  }

  static float computeThumbLength(
    float trackLen,
    long range,
    long visibleSize,
    float minThumbSize
  ) {
    if (trackLen <= 0.0f) {
      return 0.0f;
    }
    if (range <= 0) {
      return trackLen;
    }
    import std.algorithm.comparison : max, min;
    const long vis = max(1L, visibleSize);
    const double ratio = cast(double) vis / cast(double) (range + vis);
    float thumbLen = cast(float) (trackLen * ratio);
    const float effMinLen = min(trackLen, max(1.0f, minThumbSize));
    if (thumbLen < effMinLen) {
      thumbLen = effMinLen;
    }
    if (thumbLen > trackLen) {
      thumbLen = trackLen;
    }
    return thumbLen;
  }

  static void applyThumbGeometry(
    ScrollbarEntry entry,
    float thumbLen,
    float thumbOffset
  ) {
    entry.currentThumbLen = thumbLen;
    entry.currentThumbOffset = thumbOffset;
    if (entry.thumb is null) {
      return;
    }
    const bool isRow = (entry.direction == FlexDirection.row);
    const bool changed = applyThumbSizeAndAnchor(
      entry, isRow, thumbLen, thumbOffset
    );

    const RectF trackCa = (entry.track !is null)
      ? entry.track.getContentArea()
      : RectF(0, 0, 0, 0);
    if (isRow) {
      entry.thumb.rect.x = trackCa.x + thumbOffset;
      entry.thumb.rect.y = trackCa.y;
      entry.thumb.rect.width = thumbLen;
      if (trackCa.height > 0.0f) {
        entry.thumb.rect.height = trackCa.height;
      }
    } else {
      entry.thumb.rect.x = trackCa.x;
      entry.thumb.rect.y = trackCa.y + thumbOffset;
      if (trackCa.width > 0.0f) {
        entry.thumb.rect.width = trackCa.width;
      }
      entry.thumb.rect.height = thumbLen;
    }

    if (changed) {
      entry.thumb.update(WidgetUpdateScope.layout);
    }
  }

  static bool applyThumbSizeAndAnchor(
    ScrollbarEntry entry,
    bool isRow,
    float thumbLen,
    float thumbOffset
  ) {
    bool changed = false;
    if (entry.thumb.components.size !is null) {
      auto sz = entry.thumb.components.size;
      if (isRow && sz.width.value != thumbLen) {
        sz.width = Dimension(thumbLen, SizingMode.fixed);
        changed = true;
      } else if (!isRow && sz.height.value != thumbLen) {
        sz.height = Dimension(thumbLen, SizingMode.fixed);
        changed = true;
      }
    }
    if (entry.thumb.components.anchor !is null) {
      auto anc = entry.thumb.components.anchor;
      if (isRow && (anc.left.isNull || anc.left.get != thumbOffset)) {
        anc.left = nullable(thumbOffset);
        changed = true;
      } else if (!isRow && (anc.top.isNull || anc.top.get != thumbOffset)) {
        anc.top = nullable(thumbOffset);
        changed = true;
      }
    }
    return changed;
  }

  static void updateThumbColors(ScrollbarEntry entry, bool disabled) {
    if (entry.thumb is null) {
      return;
    }
    entry.thumb.inputEnabled = !disabled;
    if (disabled) {
      entry.thumb.setBackgroundColor(entry.style.disabledBg);
      entry.thumb.setBorderColor(entry.style.disabledBorder);
    } else if (entry.isDragging) {
      entry.thumb.setBackgroundColor(entry.style.thumbDragBg);
      entry.thumb.setBorderColor(entry.style.thumbDragBorder);
    } else {
      entry.thumb.setBackgroundColor(entry.style.thumbBg);
      entry.thumb.setBorderColor(entry.style.thumbBorder);
    }
  }

  static void updateArrowStates(
    ScrollbarEntry entry,
    long val,
    long effMin,
    long effMax
  ) {
    const bool canDec = (effMax > effMin && val > effMin);
    const bool canInc = (effMax > effMin && val < effMax);

    if (entry.decBtn !is null) {
      entry.decBtn.inputEnabled = canDec;
      entry.decBtn.setBackgroundColor(
        canDec ? entry.style.arrowBg : entry.style.disabledBg
      );
      entry.decBtn.setBorderColor(
        canDec ? entry.style.arrowBorder : entry.style.disabledBorder
      );
      entry.decBtn.setTextColor(
        canDec ? entry.style.arrowText : entry.style.disabledText
      );
    }

    if (entry.incBtn !is null) {
      entry.incBtn.inputEnabled = canInc;
      entry.incBtn.setBackgroundColor(
        canInc ? entry.style.arrowBg : entry.style.disabledBg
      );
      entry.incBtn.setBorderColor(
        canInc ? entry.style.arrowBorder : entry.style.disabledBorder
      );
      entry.incBtn.setTextColor(
        canInc ? entry.style.arrowText : entry.style.disabledText
      );
    }
  }

  static bool findScrollbarParts(
    Widget viewWidget,
    out Widget decBtn,
    out Widget track,
    out Widget thumb,
    out Widget incBtn
  ) {
    if (viewWidget is null || viewWidget.children.length != 3) {
      return false;
    }
    decBtn = viewWidget.children[0];
    track = viewWidget.children[1];
    incBtn = viewWidget.children[2];
    if (track.children.length > 0) {
      thumb = track.children[0];
      return true;
    }
    return false;
  }
}

/**
 * WidgetViewController reacting to internal Scrollbar child events, updating
 * `ScrollbarModel`, and dispatching position-change `AppEvent` notifications.
 */
final class ScrollbarWidgetViewController : WidgetViewControllerBase {
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
      if (!v.isWidgetRegistered(ev.view.viewWidget)) {
        continue;
      }
      auto sbv = cast(ScrollbarWidgetView) v;
      if (sbv is null) {
        continue;
      }
      if (handleScrollbarViewEvent(sbv, ev)) {
        return HandleResult(HandleResult.Result.updateView, true);
      }
    }
    return super.handleEvent(ev);
  }

private:
  bool handleScrollbarViewEvent(ScrollbarWidgetView sbv, AppEvent ev) {
    Widget viewWidget = ev.view.viewWidget;
    const string eventName = ev.view.eventName;
    long newValue = 0;

    if (eventName == scrollbarDecEvent) {
      if (sbv.stepDecrement(viewWidget, newValue)) {
        emitPositionChanged(sbv, viewWidget, newValue);
      }
      return true;
    }
    if (eventName == scrollbarIncEvent) {
      if (sbv.stepIncrement(viewWidget, newValue)) {
        emitPositionChanged(sbv, viewWidget, newValue);
      }
      return true;
    }
    if (eventName == scrollbarTrackDownEvent) {
      auto mouseVal = MouseEvent.AppEventViewValue.fromRaw(ev.view.value);
      if (sbv.handleTrackClick(viewWidget, mouseVal, newValue)) {
        emitPositionChanged(sbv, viewWidget, newValue);
      }
      return true;
    }
    if (eventName == scrollbarThumbDownEvent) {
      auto mouseVal = MouseEvent.AppEventViewValue.fromRaw(ev.view.value);
      sbv.beginThumbDrag(viewWidget, mouseVal);
      return true;
    }
    if (eventName == scrollbarThumbDragEvent) {
      auto mouseVal = MouseEvent.AppEventViewValue.fromRaw(ev.view.value);
      if (sbv.updateThumbDrag(viewWidget, mouseVal, newValue)) {
        emitPositionChanged(sbv, viewWidget, newValue);
      }
      return true;
    }
    if (eventName == scrollbarThumbUpEvent) {
      if (sbv.endThumbDrag(viewWidget, newValue)) {
        emitPositionChanged(sbv, viewWidget, newValue);
      }
      return true;
    }
    if (eventName == scrollbarTrackChangedEvent) {
      auto scrollVal = ScrollableArea.AppEventViewValue.fromRaw(ev.view.value);
      sbv.handleTrackChanged(viewWidget, scrollVal);
      return true;
    }
    return false;
  }

  void emitPositionChanged(
    ScrollbarWidgetView sbv,
    Widget viewWidget,
    long value
  ) {
    const string targetEvent = sbv.getEventName(viewWidget);
    if (targetEvent.length == 0) {
      return;
    }
    auto outEv = ViewAppEventBuilder(targetEvent)
      .widget(viewWidget)
      .viewWidget(viewWidget)
      .value(cast(ulong) value)
      .build();
    uiSystem.sendAppEvent(outEv);
  }
}

/**
 * Fluent builder constructing a horizontal or vertical Scrollbar widget tree
 * and registering it with `ScrollbarWidgetView` via `UiRegistry`.
 */
struct ScrollbarBuilder {
  ref ScrollbarBuilder name(string controlName) return {
    widgetName = controlName;
    return this;
  }

  ref ScrollbarBuilder model(ScrollbarModel m) return {
    assert(m !is null, "m must not be null");
    sbTracker = ModelTracker!ScrollbarModel(m);
    hasModel = true;
    return this;
  }

  ref ScrollbarBuilder modelTracker(
    ref ModelTracker!ScrollbarModel tracker
  ) return {
    sbTracker = ModelTracker!ScrollbarModel.from(tracker);
    hasModel = true;
    return this;
  }

  ref ScrollbarBuilder event(string customEventName) return {
    eventName = customEventName;
    return this;
  }

  ref ScrollbarBuilder direction(FlexDirection dir) return {
    flexDir = dir;
    return this;
  }

  ref ScrollbarBuilder style(in ScrollbarStyle s) return {
    cfg = s;
    return this;
  }

  ref ScrollbarBuilder thickness(float t) return {
    customThickness = t;
    return this;
  }

  /**
   * Builds the Scrollbar composite Widget tree.
   *
   * Params:
   *   ui = Active UiSystem (must not be null).
   *   parent = Parent widget (allowed to be null in isolated tests).
   *   rect = Initial rectangle of the Scrollbar root container.
   *   registry = UiRegistry used to look up `ScrollbarWidgetView` (defaults
   *     to `ui` when null).
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
      sbTracker = ModelTracker!ScrollbarModel(new ScrollbarModel());
      hasModel = true;
    }

    const string rootName = (widgetName.length > 0)
      ? widgetName
      : "scrollbar";
    const bool isRow = (flexDir == FlexDirection.row);
    const float barThickness = (customThickness > 0.0f)
      ? customThickness
      : cfg.thickness;
    const float arrowW = isRow ? cfg.arrowButtonSize : barThickness;
    const float arrowH = isRow ? barThickness : cfg.arrowButtonSize;

    const string[string] renameMap = [
      scrollbarDecEvent: scrollbarDecEvent,
      scrollbarIncEvent: scrollbarIncEvent,
      scrollbarTrackDownEvent: scrollbarTrackDownEvent,
      scrollbarTrackChangedEvent: scrollbarTrackChangedEvent,
      scrollbarThumbDownEvent: scrollbarThumbDownEvent,
      scrollbarThumbDragEvent: scrollbarThumbDragEvent,
      scrollbarThumbUpEvent: scrollbarThumbUpEvent,
    ];

    Widget root = WidgetBuilder.make(ui)
      .parent(parent)
      .name(rootName)
      .rect(rect)
      .flexDirection(flexDir)
      .gap(cfg.gap)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.stretch)
      .viewEvents(renameMap.dup)
      .viewName(scrollbarWidgetViewName)
      .build();

    buildAndRegisterParts(
      ui, registry, root, rootName, rect, isRow, arrowW, arrowH, barThickness
    );
    return root;
  }

private:
  void buildAndRegisterParts(
    UiSystem ui,
    UiRegistry registry,
    Widget root,
    string rootName,
    RectF rect,
    bool isRow,
    float arrowW,
    float arrowH,
    float barThickness
  ) {
    auto decBtn = buildArrowBtn(
      ui, root, rootName ~ "DecBtn", arrowW, arrowH,
      isRow ? "<" : "^", scrollbarDecEvent
    );
    float estTrackW = 0.0f;
    float estTrackH = 0.0f;
    auto track = buildTrack(
      ui, root, rootName, rect, isRow, arrowW, arrowH,
      barThickness, estTrackW, estTrackH
    );
    auto thumb = buildThumb(ui, track, rootName, isRow, estTrackW, estTrackH);
    auto incBtn = buildArrowBtn(
      ui, root, rootName ~ "IncBtn", arrowW, arrowH,
      isRow ? ">" : "v", scrollbarIncEvent
    );

    root.update(WidgetUpdateScope.parentView);
    registerBuiltScrollbar(registry, root, decBtn, track, thumb, incBtn);
  }
  Widget buildArrowBtn(
    UiSystem ui,
    Widget root,
    string name,
    float w,
    float h,
    string label,
    string eventName
  ) {
    return WidgetBuilder.make(ui)
      .parent(root)
      .name(name)
      .rect(RectF(0, 0, w, h))
      .fixedSize(w, h)
      .roundBg(cfg.arrowBg)
      .bgRadius(cfg.cornerRadius)
      .border(cfg.arrowBorder)
      .borderWidth(1.0f)
      .text(label)
      .textColor(cfg.arrowText)
      .fontSize(cfg.fontSize)
      .textAlign(TextLabel.Alignment.center)
      .onMouseDown(eventName)
      .build();
  }

  Widget buildTrack(
    UiSystem ui,
    Widget root,
    string rootName,
    RectF rect,
    bool isRow,
    float arrowW,
    float arrowH,
    float barThickness,
    out float estTrackW,
    out float estTrackH
  ) {
    import std.algorithm.comparison : max;
    estTrackW = isRow
      ? max(1.0f, rect.width - 2.0f * (arrowW + cfg.gap))
      : barThickness;
    estTrackH = isRow
      ? barThickness
      : max(1.0f, rect.height - 2.0f * (arrowH + cfg.gap));

    return WidgetBuilder.make(ui)
      .parent(root)
      .name(rootName ~ "Track")
      .rect(RectF(0, 0, estTrackW, estTrackH))
      .sizeComponent(
        isRow ? Size.fraction(1.0f, 0.0f) : Size.fraction(0.0f, 1.0f)
      )
      .minWidth(1.0f)
      .minHeight(1.0f)
      .paddingAll(cfg.trackPadding)
      .roundBg(cfg.trackBg)
      .bgRadius(cfg.cornerRadius)
      .border(cfg.trackBorder)
      .borderWidth(1.0f)
      .scrollableArea()
      .scrollClamp(false)
      .onScrollChanged(scrollbarTrackChangedEvent)
      .onMouseDown(scrollbarTrackDownEvent)
      .build();
  }

  Widget buildThumb(
    UiSystem ui,
    Widget track,
    string rootName,
    bool isRow,
    float estTrackW,
    float estTrackH
  ) {
    import std.algorithm.comparison : max;
    auto thumbBuilder = WidgetBuilder.make(ui)
      .parent(track)
      .name(rootName ~ "Thumb")
      .rect(
        RectF(
          0,
          0,
          isRow ? cfg.minThumbSize : max(1.0f, estTrackW - 2.0f),
          isRow ? max(1.0f, estTrackH - 2.0f) : cfg.minThumbSize
        )
      )
      .roundBg(cfg.thumbBg)
      .bgRadius(cfg.thumbCornerRadius)
      .border(cfg.thumbBorder)
      .borderWidth(1.0f)
      .onMouseDown(scrollbarThumbDownEvent)
      .onMouseDrag(scrollbarThumbDragEvent, true)
      .onMouseUp(scrollbarThumbUpEvent);

    if (isRow) {
      thumbBuilder
        .fixedWidth(cfg.minThumbSize)
        .autoHeight()
        .anchorLeft(0.0f)
        .anchorTop(0.0f)
        .anchorBottom(0.0f);
    } else {
      thumbBuilder
        .autoWidth()
        .fixedHeight(cfg.minThumbSize)
        .anchorTop(0.0f)
        .anchorLeft(0.0f)
        .anchorRight(0.0f);
    }
    return thumbBuilder.build();
  }

  void registerBuiltScrollbar(
    UiRegistry registry,
    Widget root,
    Widget decBtn,
    Widget track,
    Widget thumb,
    Widget incBtn
  ) {
    if (registry is null) {
      return;
    }
    if (WidgetView wv = registry.widgetViews.getByName(
        scrollbarWidgetViewName
      )) {
      if (auto sbv = cast(ScrollbarWidgetView) wv) {
        sbv.registerScrollbar(
          root, sbTracker, decBtn, track, thumb, incBtn,
          cfg, flexDir, eventName
        );
      }
    }
  }

private:
  ModelTracker!ScrollbarModel sbTracker;
  bool hasModel = false;
  string eventName = defaultScrollbarEventName;
  FlexDirection flexDir = FlexDirection.row;
  ScrollbarStyle cfg;
  float customThickness = 0.0f;
  string widgetName = null;
}

/**
 * Registers a shared `ScrollbarWidgetView` and
 * `ScrollbarWidgetViewController` into `ui` and links them together.
 */
ScrollbarWidgetViewController registerScrollbars(UiSystem ui) {
  assert(ui !is null, "ui must not be null");
  auto view = new ScrollbarWidgetView();
  auto ctrl = new ScrollbarWidgetViewController(ui);
  ctrl.registerWidgetView(view);
  ui.widgetViews.register(view.getWidgetViewName(), view);
  ui.widgetViewControllers.register(ctrl.getControllerName(), ctrl);
  return ctrl;
}

unittest {
  import std.math.algebraic : abs;
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  final class RecordingUiSystem : UiSystemImpl {
    AppEvent[] sentEvents;

    this() {
      super(null);
    }

    override void sendAppEvent(AppEvent ev) {
      sentEvents ~= ev;
      super.sendAppEvent(ev);
    }
  }

  auto ui = new RecordingUiSystem();
  auto ctrl = registerScrollbars(ui);
  assert(ctrl !is null);

  auto sbView = cast(ScrollbarWidgetView)
    ui.widgetViews.getByName(scrollbarWidgetViewName);
  assert(sbView !is null);
  assert(
    ui.widgetViewControllers.getByName(scrollbarWidgetViewControllerName)
      is ctrl
  );

  // 1. Horizontal scrollbar with min=0, max=100, value=0, visible=25, step=10
  auto model = new ScrollbarModel()
    .withRange(0, 100)
    .withValue(0)
    .withVisibleSize(25)
    .withStepSize(10);
  auto tracker = ModelTracker!ScrollbarModel(model);

  ScrollbarBuilder b;
  Widget sb = b
    .name("hScroll")
    .modelTracker(tracker)
    .event("hScrollPos")
    .direction(FlexDirection.row)
    .build(ui, null, RectF(0, 0, 248, 22), null);

  assert(sb !is null);
  assert(sbView.isWidgetRegistered(sb));

  void verifyAllNamed(Widget w) {
    assert(w.name.length > 0, "Widget missing name");
    foreach (child; w.children) {
      verifyAllNamed(child);
    }
  }
  verifyAllNamed(sb);

  Widget decBtn = sbView.getDecButton(sb);
  Widget track = sbView.getTrack(sb);
  Widget thumb = sbView.getThumb(sb);
  Widget incBtn = sbView.getIncButton(sb);
  assert(
    decBtn !is null && track !is null && thumb !is null && incBtn !is null
  );
  assert(!decBtn.inputEnabled);
  assert(incBtn.inputEnabled);

  AppEvent translateChildEv(Widget root, AppEvent ev) {
    sbView.translateEventForViewWidget(ev, root);
    return ev;
  }

  // Simulate layout feedback: track viewport width = 200
  auto tcDispatched = translateChildEv(
    sb,
    ViewAppEventBuilder(scrollbarTrackChangedEvent)
      .widget(track)
      .valueArray(
        ScrollableArea.AppEventViewValue.pack(
          PointF(0, 0),
          PointF(200, 16),
          PointF(0, 0)
        )
      )
      .build()
  );
  assert(ctrl.handleEvent(tcDispatched).consume);

  // ratio = 25 / (100 + 25) = 0.2 -> thumb width = 200 * 0.2 = 40
  assert(abs(thumb.rect.width - 40.0f) < 0.1f);
  assert(abs(thumb.components.anchor.left.get - 0.0f) < 0.1f);

  // 2. Step increment via arrow button click -> value becomes 10
  ui.sentEvents = null;
  auto incEv = translateChildEv(
    sb,
    ViewAppEventBuilder(scrollbarIncEvent).widget(incBtn).build()
  );
  assert(ctrl.handleEvent(incEv).consume);
  assert(model.value == 10);
  assert(decBtn.inputEnabled);
  assert(ui.sentEvents.length == 1);
  assert(ui.sentEvents[0].view.eventName == "hScrollPos");
  assert(ui.sentEvents[0].view.viewWidget is sb);
  assert(cast(long) ui.sentEvents[0].view.value[0] == 10);

  // 3. Track click after thumb -> page increment (+25 -> 35)
  ui.sentEvents = null;
  auto trackClickRight = translateChildEv(
    sb,
    ViewAppEventBuilder(scrollbarTrackDownEvent)
      .widget(track)
      .valueArray(MouseEvent.AppEventViewValue.packLocal(150.0f, 8.0f, 1, true))
      .build()
  );
  ctrl.handleEvent(trackClickRight);
  assert(model.value == 35);
  assert(cast(long) ui.sentEvents[$ - 1].view.value[0] == 35);

  // Track click before thumb -> page decrement (-25 -> 10)
  ui.sentEvents = null;
  auto trackClickLeft = translateChildEv(
    sb,
    ViewAppEventBuilder(scrollbarTrackDownEvent)
      .widget(track)
      .valueArray(MouseEvent.AppEventViewValue.packLocal(5.0f, 8.0f, 1, true))
      .build()
  );
  ctrl.handleEvent(trackClickLeft);
  assert(model.value == 10);

  // 4. Live thumb drag: travel = 200 - 40 = 160 px.
  // Moving +80 px corresponds to +50 units -> value = 60.
  ui.sentEvents = null;
  ctrl.handleEvent(
    translateChildEv(
      sb,
      ViewAppEventBuilder(scrollbarThumbDownEvent)
        .widget(thumb)
        .valueArray(
          MouseEvent.AppEventViewValue.pack(10, 5, 1, true, 0, 0, 50.0f, 10.0f)
        )
        .build()
    )
  );

  ui.sentEvents = null;
  ctrl.handleEvent(
    translateChildEv(
      sb,
      ViewAppEventBuilder(scrollbarThumbDragEvent)
        .widget(thumb)
        .valueArray(
          MouseEvent.AppEventViewValue.pack(
            90, 5, 1, false, 80, 0, 130.0f, 10.0f
          )
        )
        .build()
    )
  );
  assert(model.value == 60);
  assert(ui.sentEvents.length == 1);
  assert(ui.sentEvents[0].view.eventName == "hScrollPos");
  assert(cast(long) ui.sentEvents[0].view.value[0] == 60);

  ctrl.handleEvent(
    translateChildEv(
      sb,
      ViewAppEventBuilder(scrollbarThumbUpEvent)
        .widget(thumb)
        .valueArray(
          MouseEvent.AppEventViewValue.pack(
            90, 5, 1, false, 0, 0, 130.0f, 10.0f
          )
        )
        .build()
    )
  );

  // 5. Report-on-release-only mode suppresses drag events until mouseUp
  auto relModel = new ScrollbarModel()
    .withRange(0, 100)
    .withValue(0)
    .withVisibleSize(25)
    .withStepSize(10)
    .withReportOnReleaseOnly(true);
  ScrollbarBuilder relBuilder;
  Widget relSb = relBuilder
    .name("relScroll")
    .model(relModel)
    .event("relScrollPos")
    .direction(FlexDirection.column)
    .build(ui, null, RectF(0, 0, 22, 248), null);
  Widget relTrack = sbView.getTrack(relSb);
  Widget relThumb = sbView.getThumb(relSb);

  ctrl.handleEvent(
    translateChildEv(
      relSb,
      ViewAppEventBuilder(scrollbarTrackChangedEvent)
        .widget(relTrack)
        .valueArray(
          ScrollableArea.AppEventViewValue.pack(
            PointF(0, 0),
            PointF(16, 200),
            PointF(0, 0)
          )
        )
        .build()
    )
  );

  // Drag down by 80px -> thumb moves visually, model stays 0 until release
  ctrl.handleEvent(
    translateChildEv(
      relSb,
      ViewAppEventBuilder(scrollbarThumbDownEvent)
        .widget(relThumb)
        .valueArray(
          MouseEvent.AppEventViewValue.pack(5, 10, 1, true, 0, 0, 10.0f, 30.0f)
        )
        .build()
    )
  );

  ui.sentEvents = null;
  ctrl.handleEvent(
    translateChildEv(
      relSb,
      ViewAppEventBuilder(scrollbarThumbDragEvent)
        .widget(relThumb)
        .valueArray(
          MouseEvent.AppEventViewValue.pack(
            5, 90, 1, true, 0, 80, 10.0f, 110.0f
          )
        )
        .build()
    )
  );
  assert(relModel.value == 0);
  assert(abs(relThumb.components.anchor.top.get - 80.0f) < 0.1f);
  assert(ui.sentEvents.length == 0);

  ui.sentEvents = null;
  ctrl.handleEvent(
    translateChildEv(
      relSb,
      ViewAppEventBuilder(scrollbarThumbUpEvent)
        .widget(relThumb)
        .valueArray(
          MouseEvent.AppEventViewValue.pack(5, 90, 1, true, 0, 0, 10.0f, 110.0f)
        )
        .build()
    )
  );
  assert(relModel.value == 50);
  assert(ui.sentEvents.length == 1);
  assert(ui.sentEvents[0].view.eventName == "relScrollPos");
  assert(cast(long) ui.sentEvents[0].view.value[0] == 50);

  // 6. Minimum thumb size clamping when range is huge
  auto hugeModel = new ScrollbarModel()
    .withRange(0, 100000)
    .withValue(0)
    .withVisibleSize(10)
    .withStepSize(10);
  ScrollbarBuilder hugeBuilder;
  Widget hugeSb = hugeBuilder
    .name("hugeScroll")
    .model(hugeModel)
    .build(ui, null, RectF(0, 0, 248, 22), null);
  Widget hugeTrack = sbView.getTrack(hugeSb);
  Widget hugeThumb = sbView.getThumb(hugeSb);
  ctrl.handleEvent(
    translateChildEv(
      hugeSb,
      ViewAppEventBuilder(scrollbarTrackChangedEvent)
        .widget(hugeTrack)
        .valueArray(
          ScrollableArea.AppEventViewValue.pack(
            PointF(0, 0),
            PointF(200, 16),
            PointF(0, 0)
          )
        )
        .build()
    )
  );
  assert(abs(hugeThumb.rect.width - 20.0f) < 0.1f);

  // 7. Release widget unregisters scrollbar cleanly
  ui.releaseWidget(sb);
  assert(!sbView.isWidgetRegistered(sb));
  assert(sb.released);
}
