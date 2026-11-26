/**
 * scrollbars.d - Reusable composite vertical and horizontal Scrollbar widget,
 * WidgetView, and WidgetViewController.
 */
module yguilib.controls.scrollbars;

import std.math.rounding : round;
import std.typecons : Nullable, nullable;
import yguilib.controller : HandleResult;
import yguilib.controls.button : ButtonBuilder, ButtonRepeat, ButtonStyle,
  ButtonTrigger;
import yguilib.controls.common : WidgetColors, applyBgAndBorderColors,
  defaultDisabledColors, emitViewValueEvent, findArrowComposite,
  findWidgetView, firstPositive, orDefault, registerWidgetViewPair;
import yguilib.controls.composite_view : bindCompositeModel,
  ensureDefaultModelTracker, ensureViewWidgetRegistered, findEntry,
  findOwningView, entryField, resolveBuilderRegistry, assignBuilderModel,
  assignBuilderTracker, unregisterCompositeWidget, updateCompositeEntries;
import yguilib.controls.internal.axis : Axis;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker, VersionedModel;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.uisystem : UiRegistry, UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.input_components : CursorCapture, MouseEvent;
import yguilib.widget.layout_components : AlignItems, Dimension,
  FlexDirection, JustifyContent, Size, SizingMode;
import yguilib.widget.scroll_components : ScrollableArea;
import yguilib.widget.widget_view : WidgetViewBase,
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

  /// Returns effective upper bound (`max` clamped to `>= min`).
  long effMax() const nothrow @safe @nogc {
    return (max < min) ? min : max;
  }

  /// Returns non-negative value span `effMax() - min`.
  long range() const nothrow @safe @nogc {
    const long top = effMax();
    return (top > min) ? (top - min) : 0;
  }

  /// Clamps `v` into `[min, effMax()]`.
  long clampValue(long v) const nothrow @safe @nogc {
    const long top = effMax();
    if (v < min) {
      return min;
    }
    if (v > top) {
      return top;
    }
    return v;
  }

  /// Updates bounds, window, step, and clamped value; returns true if changed.
  bool updateMetrics(
    long minVal,
    long maxVal,
    long vis,
    long step,
    long val
  ) {
    const long normMax = (maxVal < minVal) ? minVal : maxVal;
    const long normVis = (vis < 1) ? 1 : vis;
    const long normStep = (step < 1) ? 1 : step;
    const long normVal = (val < minVal)
      ? minVal
      : ((val > normMax) ? normMax : val);

    if (
      min == minVal &&
      max == normMax &&
      visibleSize == normVis &&
      stepSize == normStep &&
      value == normVal
    ) {
      return false;
    }

    min = minVal;
    max = normMax;
    visibleSize = normVis;
    stepSize = normStep;
    value = normVal;
    return true;
  }

  /// Sets [min, max] range and clamps `value`.
  ScrollbarModel withRange(long minVal, long maxVal) {
    this.min = minVal;
    this.max = (maxVal < minVal) ? minVal : maxVal;
    this.value = clampValue(this.value);
    return this;
  }

  /// Sets and clamps `value` to [min, max].
  ScrollbarModel withValue(long val) {
    this.value = clampValue(val);
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

  WidgetColors arrow = WidgetColors(
    ColorF(0.16f, 0.19f, 0.25f, 1.0f),
    ColorF(0.28f, 0.33f, 0.42f, 1.0f),
    ColorF(0.88f, 0.92f, 0.98f, 1.0f)
  );
  WidgetColors thumb = WidgetColors(
    ColorF(0.32f, 0.46f, 0.68f, 1.0f),
    ColorF(0.45f, 0.62f, 0.88f, 1.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f)
  );
  WidgetColors thumbDrag = WidgetColors(
    ColorF(0.42f, 0.62f, 0.92f, 1.0f),
    ColorF(0.62f, 0.80f, 1.0f, 1.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f)
  );
  WidgetColors disabled = defaultDisabledColors;
  /// Auto-repeat of the dec/inc arrow buttons while held.
  ButtonRepeat arrowRepeat = ButtonRepeat(true, 400, 50);
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
    ensureViewWidgetRegistered(this, viewWidget);
    auto entry = new ScrollbarEntry(tracker);
    entry.decBtn = decBtn;
    entry.track = track;
    entry.thumb = thumb;
    entry.incBtn = incBtn;
    entry.style = style;
    entry.direction = direction;
    entry.eventName = orDefault(eventName, defaultScrollbarEventName);
    entries[viewWidget] = entry;
    syncEntryVisuals(entry);
  }

  /// Associates a `ScrollbarModel` with a registered or newly built root.
  void bindModel(Widget viewWidget, ref ModelTracker!ScrollbarModel tracker) {
    assert(viewWidget !is null, "viewWidget must not be null");
    ensureViewWidgetRegistered(this, viewWidget);
    if (auto entry = findEntry(entries, viewWidget)) {
      entry.tracker = ModelTracker!ScrollbarModel.from(tracker);
      syncEntryVisuals(entry);
    } else {
      auto found = findArrowComposite(viewWidget);
      Widget decBtn = null;
      Widget track = null;
      Widget thumb = null;
      Widget incBtn = null;
      if (!found.isNull) {
        auto parts = found.get();
        decBtn = parts.dec;
        track = parts.middle;
        thumb = parts.inner;
        incBtn = parts.inc;
      }
      registerScrollbar(
        viewWidget, tracker, decBtn, track, thumb, incBtn,
        ScrollbarStyle(), FlexDirection.row, defaultScrollbarEventName
      );
    }
  }

  /// Associates a `ScrollbarModel` instance with `viewWidget`.
  void bindModelWithModel(Widget viewWidget, ScrollbarModel model) {
    bindCompositeModel(this, viewWidget, model);
  }

  override void unregisterViewWidget(Widget viewWidget) {
    unregisterCompositeWidget(this, entries, viewWidget);
  }

  Widget decButton(Widget viewWidget) {
    return entryField!"decBtn"(entries, viewWidget);
  }

  Widget incButton(Widget viewWidget) {
    return entryField!"incBtn"(entries, viewWidget);
  }

  Widget track(Widget viewWidget) {
    return entryField!"track"(entries, viewWidget);
  }

  Widget thumb(Widget viewWidget) {
    return entryField!"thumb"(entries, viewWidget);
  }

  string eventName(Widget viewWidget) {
    return entryField!"eventName"(entries, viewWidget);
  }

  /// Steps scrollbar value by `dir * stepSize` (arrow click).
  /// Returns the new value when changed, or null `Nullable` when unchanged.
  Nullable!long stepBy(Widget viewWidget, int dir) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto entry = findEntry(entries, viewWidget);
    if (entry is null) {
      return Nullable!long.init;
    }
    const auto m = entry.tracker.model;
    import std.algorithm.comparison : max;
    const long step = max(1L, m.stepSize);
    return applyModelValue(entry, m.value + cast(long) dir * step);
  }

  /// Steps scrollbar value by `-stepSize` (arrow click).
  /// Returns the new value when changed, or null `Nullable` when unchanged.
  Nullable!long stepDecrement(Widget viewWidget) {
    return stepBy(viewWidget, -1);
  }

  /// Steps scrollbar value by `+stepSize` (arrow click).
  /// Returns the new value when changed, or null `Nullable` when unchanged.
  Nullable!long stepIncrement(Widget viewWidget) {
    return stepBy(viewWidget, 1);
  }

  /// Handles a click on the track free area, paging by `visibleSize`.
  /// Returns the new value when changed, or null `Nullable` when unchanged.
  Nullable!long handleTrackClick(
    Widget viewWidget,
    in MouseEvent.AppEventViewValue mouseVal
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto entry = findEntry(entries, viewWidget);
    if (entry is null || entry.track is null) {
      return Nullable!long.init;
    }
    const auto m = entry.tracker.model;
    if (m.range() <= 0) {
      return Nullable!long.init;
    }

    const Axis ax = Axis.of(entry.direction);
    const RectF ca = entry.track.contentArea();
    const float clickLocal = ax.mainCoord(
      PointF(mouseVal.localX, mouseVal.localY)
    );
    const float clickInContent = clickLocal - ax.mainPos(ca);
    const float thumbStart = entry.currentThumbOffset;
    const float thumbEnd = thumbStart + entry.currentThumbLen;
    import std.algorithm.comparison : max;
    const long page = max(1L, m.visibleSize);

    if (clickInContent < thumbStart) {
      return applyModelValue(entry, m.value - page);
    } else if (clickInContent > thumbEnd) {
      return applyModelValue(entry, m.value + page);
    }
    return Nullable!long.init;
  }

  /// Begins a thumb drag interaction on `mouseDown`.
  bool beginThumbDrag(
    Widget viewWidget,
    in MouseEvent.AppEventViewValue mouseVal
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto entry = findEntry(entries, viewWidget);
    if (entry is null) {
      return false;
    }
    const auto m = entry.tracker.model;
    if (m.range() <= 0) {
      return false;
    }

    const Axis ax = Axis.of(entry.direction);
    entry.isDragging = true;
    entry.dragStartWindowPos = ax.mainCoord(
      PointF(mouseVal.windowX, mouseVal.windowY)
    );
    entry.dragStartThumbOffset = entry.currentThumbOffset;
    entry.dragStartValue = m.clampValue(m.value);
    entry.pendingValue = entry.dragStartValue;
    updateThumbColors(entry, false);
    entry.viewDirty = true;
    return true;
  }

  /// Updates thumb position (and model value if live) during `mouseDrag`.
  /// Returns the new value if an event should be emitted now, or null
  /// `Nullable` otherwise.
  Nullable!long updateThumbDrag(
    Widget viewWidget,
    in MouseEvent.AppEventViewValue mouseVal
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto entry = findEntry(entries, viewWidget);
    if (entry is null || !entry.isDragging) {
      return Nullable!long.init;
    }
    const auto m = entry.tracker.model;
    const ThumbMetrics tm = computeThumbMetrics(entry);
    const float draggedOffset = computeDraggedOffset(
      entry, mouseVal, tm.maxTravel
    );

    long computedVal = tm.effMin;
    if (tm.range > 0 && tm.maxTravel > 0.0f) {
      const double norm =
        cast(double) draggedOffset / cast(double) tm.maxTravel;
      const long offsetUnits = cast(long) round(norm * cast(double) tm.range);
      computedVal = m.clampValue(tm.effMin + offsetUnits);
    }

    entry.pendingValue = computedVal;

    if (m.reportOnReleaseOnly) {
      applyThumbGeometry(entry, tm.thumbLen, draggedOffset);
      entry.viewDirty = true;
      return Nullable!long.init;
    }

    return applyModelValue(entry, computedVal);
  }

  /// Ends a thumb drag interaction on `mouseUp`.
  /// Returns the new value if a deferred event should be emitted now, or null
  /// `Nullable` otherwise.
  Nullable!long endThumbDrag(Widget viewWidget) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto entry = findEntry(entries, viewWidget);
    if (entry is null || !entry.isDragging) {
      return Nullable!long.init;
    }
    entry.isDragging = false;
    const bool reportOnRelease = entry.tracker.model.reportOnReleaseOnly;
    const long targetVal = entry.pendingValue;

    Nullable!long newValue = Nullable!long.init;
    if (reportOnRelease) {
      newValue = applyModelValue(entry, targetVal);
    }
    syncEntryVisuals(entry);
    entry.viewDirty = true;
    return newValue;
  }

  /// Handles layout feedback from `track`'s `ScrollableArea` when resized.
  bool handleTrackChanged(
    Widget viewWidget,
    in ScrollableArea.AppEventViewValue val
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto entry = findEntry(entries, viewWidget);
    if (entry is null) {
      return false;
    }
    entry.lastTrackViewportSize = val.viewportSize;
    syncEntryVisuals(entry);
    return true;
  }

  override bool update() {
    return updateCompositeEntries(entries, (ScrollbarEntry entry) {
      syncEntryVisuals(entry);
      return true;
    });
  }

private:
  struct ThumbMetrics {
    long effMin;
    long effMax;
    long range;
    float trackLen;
    float thumbLen;
    float maxTravel;
  }

  ScrollbarEntry[Widget] entries;

  static ThumbMetrics computeThumbMetrics(ScrollbarEntry entry) {
    assert(entry !is null, "entry must not be null");
    import std.algorithm.comparison : max;
    const auto m = entry.tracker.model;
    const long effMin = m.min;
    const long effMax = m.effMax();
    const long range = m.range();
    const float trackLen = trackMainLength(entry);
    const float thumbLen = computeThumbLength(
      trackLen,
      range,
      m.visibleSize,
      entry.style.minThumbSize
    );
    const float maxTravel = max(0.0f, trackLen - thumbLen);
    return ThumbMetrics(
      effMin, effMax, range, trackLen, thumbLen, maxTravel
    );
  }

  static float computeDraggedOffset(
    const ref ScrollbarEntry entry,
    const ref MouseEvent.AppEventViewValue mouseVal,
    float maxTravel
  ) {
    import std.algorithm.comparison : clamp;
    const Axis ax = Axis.of(entry.direction);
    const float curPos = ax.mainCoord(
      PointF(mouseVal.windowX, mouseVal.windowY)
    );
    const float deltaPx = curPos - entry.dragStartWindowPos;
    return clamp(entry.dragStartThumbOffset + deltaPx, 0.0f, maxTravel);
  }

  Nullable!long applyModelValue(ScrollbarEntry entry, long candidateVal) {
    auto m = entry.tracker.model;
    const long clamped = m.clampValue(candidateVal);
    if (clamped == m.value) {
      return Nullable!long.init;
    }

    auto editable = entry.tracker.edit();
    editable.value = clamped;
    entry.tracker.commit(editable);
    syncEntryVisuals(entry);
    entry.viewDirty = true;
    return Nullable!long(clamped);
  }

  static void syncEntryVisuals(ScrollbarEntry entry) {
    assert(entry !is null, "entry must not be null");
    const auto m = entry.tracker.model;
    const ThumbMetrics tm = computeThumbMetrics(entry);
    const long val = m.clampValue(m.value);

    float thumbOffset = 0.0f;
    if (tm.range > 0 && tm.maxTravel > 0.0f) {
      import std.algorithm.comparison : clamp;
      const double norm =
        cast(double) (val - tm.effMin) / cast(double) tm.range;
      thumbOffset = clamp(
        cast(float) (tm.maxTravel * norm), 0.0f, tm.maxTravel
      );
    }

    applyThumbGeometry(entry, tm.thumbLen, thumbOffset);
    updateThumbColors(entry, tm.range == 0);
    updateArrowStates(entry, val, tm.effMin, tm.effMax);
  }

  static float trackMainLength(ScrollbarEntry entry) {
    const Axis ax = Axis.of(entry.direction);
    const float cachedLen = ax.mainCoord(entry.lastTrackViewportSize);
    if (cachedLen > 0.0f) {
      return cachedLen;
    }
    if (entry.track !is null) {
      const float caLen = ax.mainSize(entry.track.contentArea());
      const float rawLen = ax.mainSize(entry.track.rect);
      return firstPositive(caLen, rawLen, 0.0f);
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
    const Axis ax = Axis.of(entry.direction);
    const bool changed = applyThumbSizeAndAnchor(
      entry, ax, thumbLen, thumbOffset
    );

    const RectF trackCa = (entry.track !is null)
      ? entry.track.contentArea()
      : RectF(0, 0, 0, 0);
    if (ax.isRow) {
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
    Axis ax,
    float thumbLen,
    float thumbOffset
  ) {
    bool changed = false;
    if (entry.thumb.components.size !is null) {
      auto sz = entry.thumb.components.size;
      if (ax.isRow && sz.width.value != thumbLen) {
        sz.width = Dimension(thumbLen, SizingMode.fixed);
        changed = true;
      } else if (!ax.isRow && sz.height.value != thumbLen) {
        sz.height = Dimension(thumbLen, SizingMode.fixed);
        changed = true;
      }
    }
    if (entry.thumb.components.anchor !is null) {
      auto anc = entry.thumb.components.anchor;
      if (ax.isRow && (anc.left.isNull || anc.left.get != thumbOffset)) {
        anc.left = nullable(thumbOffset);
        changed = true;
      } else if (!ax.isRow &&
          (anc.top.isNull || anc.top.get != thumbOffset)) {
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
    const bool enabledChanged = (entry.thumb.inputEnabled != !disabled);
    entry.thumb.inputEnabled = !disabled;
    if (disabled) {
      applyBgAndBorderColors(
        entry.thumb, entry.style.disabled.bg, entry.style.disabled.border
      );
    } else if (entry.isDragging) {
      applyBgAndBorderColors(
        entry.thumb, entry.style.thumbDrag.bg, entry.style.thumbDrag.border
      );
    } else {
      applyBgAndBorderColors(
        entry.thumb, entry.style.thumb.bg, entry.style.thumb.border
      );
    }
    if (enabledChanged && !entry.thumb.dirty) {
      entry.thumb.update(WidgetUpdateScope.visuals);
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
    // ButtonSystem applies normal/disabled colours in postLayout.
    if (entry.decBtn !is null && entry.decBtn.inputEnabled != canDec) {
      entry.decBtn.inputEnabled = canDec;
      entry.decBtn.update(WidgetUpdateScope.visuals);
    }
    if (entry.incBtn !is null && entry.incBtn.inputEnabled != canInc) {
      entry.incBtn.inputEnabled = canInc;
      entry.incBtn.update(WidgetUpdateScope.visuals);
    }
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

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind != AppEvent.Kind.view || ev.view.viewWidget is null) {
      return super.handleEvent(ev);
    }

    auto sbv = findOwningView!ScrollbarWidgetView(views, ev.view.viewWidget);
    if (sbv !is null && handleScrollbarViewEvent(sbv, ev)) {
      return HandleResult(HandleResult.Result.updateView, true);
    }
    return super.handleEvent(ev);
  }

private:
  bool handleScrollbarViewEvent(ScrollbarWidgetView sbv, AppEvent ev) {
    Widget viewWidget = ev.view.viewWidget;
    const string eventName = ev.view.eventName;
    Nullable!long newValue = Nullable!long.init;

    if (eventName == scrollbarDecEvent) {
      newValue = sbv.stepDecrement(viewWidget);
    } else if (eventName == scrollbarIncEvent) {
      newValue = sbv.stepIncrement(viewWidget);
    } else if (eventName == scrollbarTrackDownEvent) {
      auto mouseVal = MouseEvent.AppEventViewValue.fromRaw(ev.view.value);
      newValue = sbv.handleTrackClick(viewWidget, mouseVal);
    } else if (eventName == scrollbarThumbDownEvent) {
      auto mouseVal = MouseEvent.AppEventViewValue.fromRaw(ev.view.value);
      sbv.beginThumbDrag(viewWidget, mouseVal);
    } else if (eventName == scrollbarThumbDragEvent) {
      auto mouseVal = MouseEvent.AppEventViewValue.fromRaw(ev.view.value);
      newValue = sbv.updateThumbDrag(viewWidget, mouseVal);
    } else if (eventName == scrollbarThumbUpEvent) {
      newValue = sbv.endThumbDrag(viewWidget);
    } else if (eventName == scrollbarTrackChangedEvent) {
      auto scrollVal = ScrollableArea.AppEventViewValue.fromRaw(ev.view.value);
      sbv.handleTrackChanged(viewWidget, scrollVal);
    } else {
      return false;
    }

    if (!newValue.isNull) {
      emitViewValueEvent(
        uiSystem, sbv.eventName(viewWidget), viewWidget,
        cast(ulong) newValue.get()
      );
    }
    return true;
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
    assignBuilderModel(sbTracker, m);
    return this;
  }

  ref ScrollbarBuilder modelTracker(
    ref ModelTracker!ScrollbarModel tracker
  ) return {
    assignBuilderTracker(sbTracker, tracker);
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
    registry = resolveBuilderRegistry(ui, registry);
    ensureDefaultModelTracker(sbTracker, () => new ScrollbarModel());

    const string rootName = orDefault(widgetName, "scrollbar");
    const Axis ax = Axis.of(flexDir);
    const float barThickness = firstPositive(
      customThickness, cfg.thickness, 0.0f
    );
    const float arrowW = ax.isRow ? cfg.arrowButtonSize : barThickness;
    const float arrowH = ax.isRow ? barThickness : cfg.arrowButtonSize;

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
      ui, registry, root, rootName, rect, ax, arrowW, arrowH, barThickness
    );
    return root;
  }

private:
  struct TrackBuildResult {
    Widget track;
    float estWidth;
    float estHeight;
  }

  void buildAndRegisterParts(
    UiSystem ui,
    UiRegistry registry,
    Widget root,
    string rootName,
    RectF rect,
    Axis ax,
    float arrowW,
    float arrowH,
    float barThickness
  ) {
    auto decBtn = buildArrowBtn(
      ui, root, rootName ~ "DecBtn", arrowW, arrowH,
      ax.decArrow(), scrollbarDecEvent
    );
    auto trackRes = buildTrack(
      ui, root, rootName, rect, ax, arrowW, arrowH, barThickness
    );
    auto thumb = buildThumb(
      ui, trackRes.track, rootName, ax, trackRes.estWidth, trackRes.estHeight
    );
    auto incBtn = buildArrowBtn(
      ui, root, rootName ~ "IncBtn", arrowW, arrowH,
      ax.incArrow(), scrollbarIncEvent
    );

    root.update(WidgetUpdateScope.parentView);
    registerBuiltScrollbar(
      registry, root, decBtn, trackRes.track, thumb, incBtn
    );
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
    ButtonStyle bs;
    bs.normal = cfg.arrow;
    ButtonBuilder b;
    return b.name(name)
      .text(label)
      .fixedSize(w, h)
      .radius(cfg.cornerRadius)
      .fontSize(cfg.fontSize)
      .padding(0.0f, 0.0f)
      .style(bs)
      .border(cfg.arrow.border, 1.0f)
      .disabledColors(cfg.disabled)
      .sink(1.0f)
      .trigger(ButtonTrigger.press)
      .repeat(cfg.arrowRepeat)
      .action(eventName)
      .build(ui, root, RectF(0, 0, w, h));
  }

  TrackBuildResult buildTrack(
    UiSystem ui,
    Widget root,
    string rootName,
    RectF rect,
    Axis ax,
    float arrowW,
    float arrowH,
    float barThickness
  ) {
    import std.algorithm.comparison : max;
    const float estTrackW = ax.isRow
      ? max(1.0f, rect.width - 2.0f * (arrowW + cfg.gap))
      : barThickness;
    const float estTrackH = ax.isRow
      ? barThickness
      : max(1.0f, rect.height - 2.0f * (arrowH + cfg.gap));

    Widget track = WidgetBuilder.make(ui)
      .parent(root)
      .name(rootName ~ "Track")
      .rect(RectF(0, 0, estTrackW, estTrackH))
      .sizeComponent(
        ax.isRow ? Size.fraction(1.0f, 0.0f) : Size.fraction(0.0f, 1.0f)
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
    return TrackBuildResult(track, estTrackW, estTrackH);
  }

  Widget buildThumb(
    UiSystem ui,
    Widget track,
    string rootName,
    Axis ax,
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
          ax.isRow ? cfg.minThumbSize : max(1.0f, estTrackW - 2.0f),
          ax.isRow ? max(1.0f, estTrackH - 2.0f) : cfg.minThumbSize
        )
      )
      .roundBg(cfg.thumb.bg)
      .bgRadius(cfg.thumbCornerRadius)
      .border(cfg.thumb.border)
      .borderWidth(1.0f)
      .onMouseDown(scrollbarThumbDownEvent)
      .onMouseDrag(scrollbarThumbDragEvent, CursorCapture.capture)
      .onMouseUp(scrollbarThumbUpEvent);

    if (ax.isRow) {
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
    if (auto sbv = findWidgetView!ScrollbarWidgetView(
        registry, scrollbarWidgetViewName
      )) {
      sbv.registerScrollbar(
        root, sbTracker, decBtn, track, thumb, incBtn,
        cfg, flexDir, eventName
      );
    }
  }

  ModelTracker!ScrollbarModel sbTracker;
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
  return registerWidgetViewPair!(
    ScrollbarWidgetView,
    ScrollbarWidgetViewController
  )(ui);
}

unittest {
  import std.math.algebraic : abs;
  import yguilib.controls.testing : RecordingUiSystem, verifyAllNamed;
  import yguilib.events.builder : ViewAppEventBuilder;

  auto ui = new RecordingUiSystem();
  auto ctrl = registerScrollbars(ui);
  assert(ctrl !is null);

  auto sbView = cast(ScrollbarWidgetView)
    ui.widgetViews.findByName(scrollbarWidgetViewName);
  assert(sbView !is null);
  assert(
    ui.widgetViewControllers.findByName(scrollbarWidgetViewControllerName)
      is ctrl
  );

  // 0. ScrollbarModel helpers (effMax, range, clampValue, updateMetrics)
  auto metricsModel = new ScrollbarModel();
  assert(metricsModel.effMax() == 100);
  assert(metricsModel.range() == 100);
  assert(metricsModel.clampValue(-5) == 0);
  assert(metricsModel.clampValue(250) == 100);
  assert(metricsModel.updateMetrics(10, 5, 0, 0, 99));
  assert(metricsModel.min == 10);
  assert(metricsModel.max == 10);
  assert(metricsModel.effMax() == 10);
  assert(metricsModel.range() == 0);
  assert(metricsModel.visibleSize == 1);
  assert(metricsModel.stepSize == 1);
  assert(metricsModel.value == 10);
  assert(!metricsModel.updateMetrics(10, 5, 0, 0, 99));

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
  verifyAllNamed(sb);

  Widget decBtn = sbView.decButton(sb);
  Widget track = sbView.track(sb);
  Widget thumb = sbView.thumb(sb);
  Widget incBtn = sbView.incButton(sb);
  assert(
    decBtn !is null && track !is null && thumb !is null && incBtn !is null
  );
  assert(!decBtn.inputEnabled);
  assert(incBtn.inputEnabled);
  foreach (arrow; [decBtn, incBtn]) {
    import yguilib.controls.button : ButtonComponent;

    auto comp = arrow.components.get!ButtonComponent();
    assert(comp !is null);
    assert(comp.repeat.enabled);
    assert(comp.repeat == ButtonRepeat(true, 400, 50));
  }

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
  Widget relTrack = sbView.track(relSb);
  Widget relThumb = sbView.thumb(relSb);

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
  Widget hugeTrack = sbView.track(hugeSb);
  Widget hugeThumb = sbView.thumb(hugeSb);
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
