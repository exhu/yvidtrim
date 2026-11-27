/**
 * tooltip.d - Reusable tooltip component, topmost overlay layer builder, and
 * ECS-style TooltipSystem for delayed fade-in/out hints.
 */
module yguilib.controls.tooltip;

import yguilib.controls.common : WidgetColors, applyColors, orDefault;
import yguilib.events : AppEvent;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.timercontrol : TimerId, invalidTimerId;
import yguilib.timers : TimerIntervalMs, TimerMode;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope, isEffectivelyVisible;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.component : WidgetComponent;
import yguilib.widget.drawing_components : Border, TextLabel;
import yguilib.widget.layout_components : Insets;
import yguilib.widget.system : SystemEventResult, SystemPhase, WidgetSystem,
  WidgetSystemContext, WidgetSystemHost;
import yguilib.widget.visible : VisibleWidget, VisibleWidgets;

/// Component attached to a Widget to declare tooltip hint text.
final class Tooltip : WidgetComponent {
  /// Explicit tooltip text; when null or empty, falls back to owner's
  /// `TextLabel.caption`.
  string text;
  /// Enables or disables tooltip display for the owning widget.
  bool enabled = true;

  /// Constructs an enabled Tooltip with caption fallback.
  this() nothrow @safe {
  }

  /// Creates an enabled Tooltip with explicit `hintText`.
  /// `hintText` is allowed to be null or empty (falls back to caption).
  static Tooltip withText(string hintText) nothrow @safe {
    auto comp = new Tooltip();
    comp.text = hintText;
    return comp;
  }

  /// Resolves the display text for `owner`. `owner` is allowed to be null.
  string resolveText(const Widget owner) const nothrow @safe {
    if (!enabled) {
      return "";
    }
    if (text.length > 0) {
      return text;
    }
    if (owner !is null && owner.components.textLabel !is null) {
      return owner.components.textLabel.caption;
    }
    return "";
  }
}

/// Visual styling and positioning options for a tooltip popup layer.
struct TooltipStyle {
  WidgetColors colors = WidgetColors(
    ColorF(0.10f, 0.12f, 0.16f, 0.94f),
    ColorF(0.36f, 0.42f, 0.54f, 0.96f),
    ColorF(0.95f, 0.96f, 0.98f, 1.0f)
  );
  float cornerRadius = 5.0f;
  float borderWidth = 1.0f;
  float fontSize = 12.0f;
  Insets padding = Insets.vh(6.0f, 10.0f);
  float maxWidth = 360.0f;
  float maxHeight = float.infinity;
  float edgeMargin = 8.0f;
  float flipGap = 8.0f;
  PointF cursorOffset = PointF(12.0f, 18.0f);
}

/// Timing and pointer-dwell parameters for `TooltipSystem`.
struct TooltipTiming {
  uint showDelayMs = 450;
  float fadeInDuration = 0.12f;
  float fadeOutDuration = 0.22f;
  float moveResetThreshold = 3.0f;
}

/// Marker component attached to the topmost tooltip overlay layer widget.
final class TooltipLayerComponent : WidgetComponent {
  Widget popupWidget;
  TooltipStyle style;

  @disable this();

  /// Constructs a `TooltipLayerComponent` bound to `popupWidget`.
  this(Widget popupWidget) {
    assert(popupWidget !is null, "popupWidget must not be null");
    this.popupWidget = popupWidget;
  }

  invariant {
    assert(popupWidget !is null);
  }
}

/// Fluent builder for creating a topmost tooltip layer and its popup child.
struct TooltipLayerBuilder {
  /// Sets the layer widget name (popup child is named `<name>Popup`).
  ref TooltipLayerBuilder name(string layerName) return {
    widgetName = layerName;
    return this;
  }

  /// Sets the tooltip popup visual style.
  ref TooltipLayerBuilder style(in TooltipStyle tooltipStyle) return {
    config = tooltipStyle;
    return this;
  }

  /// Builds the transparent pass-through tooltip layer and hidden popup child.
  /// `parent` is allowed to be null in headless unit tests.
  Widget build(UiSystem ui, Widget parent) {
    assert(ui !is null, "ui must not be null");
    const string layerName = orDefault(widgetName, "tooltipLayer");

    auto layer = WidgetBuilder.make(ui)
      .parent(parent)
      .name(layerName)
      .rect(RectF(0, 0, 0, 0))
      .visible(true)
      .autoSize()
      .anchorLeft(0.0f)
      .anchorTop(0.0f)
      .anchorRight(0.0f)
      .anchorBottom(0.0f)
      .build();

    auto popup = buildPopupWidget(ui, layer, layerName ~ "Popup");
    auto layerComp = new TooltipLayerComponent(popup);
    layerComp.style = config;
    layer.components.set(layerComp);
    return layer;
  }

private:
  TooltipStyle config;
  string widgetName = null;

  Widget buildPopupWidget(UiSystem ui, Widget layer, string popupName) {
    auto b = WidgetBuilder.make(ui)
      .parent(layer)
      .name(popupName)
      .rect(RectF(0, 0, 0, 0))
      .visible(false)
      .autoSize()
      .padding(config.padding)
      .maxWidth(config.maxWidth)
      .maxHeight(config.maxHeight);

    if (config.cornerRadius > 0.0f) {
      b.roundBg(config.colors.bg).bgRadius(config.cornerRadius);
    } else {
      b.bg(config.colors.bg);
    }

    if (config.borderWidth > 0.0f) {
      b.border(config.colors.border)
        .borderWidth(config.borderWidth)
        .borderStyle(
          config.cornerRadius > 0.0f ? Border.Style.round : Border.Style.rect
        )
        .borderRadius(config.cornerRadius);
    }

    b.text("")
      .textColor(config.colors.text)
      .fontSize(config.fontSize)
      .textAlign(TextLabel.Alignment.left)
      .multiline(true)
      .ellipsis(true);

    return b.build();
  }
}

/// Convenience helper creating a tooltip layer widget.
/// `parent` and `name` are allowed to be null.
Widget createTooltipLayer(
  UiSystem ui,
  Widget parent,
  in TooltipStyle style,
  string name
) {
  assert(ui !is null, "ui must not be null");
  TooltipLayerBuilder b;
  b.style(style);
  if (name.length > 0) {
    b.name(name);
  }
  return b.build(ui, parent);
}

/// Returns true if `w` is `ancestor` or a descendant of `ancestor`.
/// `w` and `ancestor` are allowed to be null.
bool isDescendantOrSelf(
  const Widget w,
  const Widget ancestor
) nothrow @safe @nogc {
  if (w is null || ancestor is null) {
    return false;
  }
  if (w is ancestor) {
    return true;
  }
  return isDescendantOrSelf(w.parent, ancestor);
}

/// Front-to-back unobstructed hit-test for tooltips.
/// Checks only `visible`, `handleInput`, and `Tooltip` (never painting
/// components). `tooltipLayer` is allowed to be null.
Widget findUnobstructedTooltipTarget(
  VisibleWidgets widgets,
  PointF p,
  const Widget tooltipLayer
) {
  foreach_reverse (ref vw; widgets) {
    Widget w = vw.widget;
    if (w is null || !w.visible || w.released) {
      continue;
    }
    if (tooltipLayer !is null && isDescendantOrSelf(w, tooltipLayer)) {
      continue;
    }
    if (vw.hasClip && !vw.clipRect.contains(p)) {
      continue;
    }
    if (!vw.absRect.contains(p)) {
      continue;
    }

    auto tt = w.components.get!Tooltip();
    if (!w.handleInput && tt is null) {
      continue;
    }
    if (tt !is null && tt.enabled && tt.resolveText(w).length > 0) {
      return w;
    }
    return null;
  }
  return null;
}

/// ECS WidgetSystem managing hover dwell delay, fade animation, and layout
/// clamping for tooltips across the widget tree.
final class TooltipSystem : WidgetSystem {
  /// Execution priority (runs after LayoutSystem=0 and ScrollSystem=10).
  enum int tooltipSystemPriority = 20;

  /// State machine stages for tooltip lifecycle.
  enum State {
    idle,
    waitingDelay,
    showing,
    visible,
    hiding,
  }

  /// Constructs a `TooltipSystem` with default timing settings.
  this() nothrow @safe {
  }

  override @property int priority() const nothrow @safe {
    return tooltipSystemPriority;
  }

  /// Creates a `TooltipSystem` configured with custom `timing`.
  static TooltipSystem withTiming(in TooltipTiming timing) nothrow @safe {
    auto sys = new TooltipSystem();
    sys.fTiming = timing;
    return sys;
  }

  /// Updates timing configuration.
  void timing(in TooltipTiming timing) nothrow @safe {
    fTiming = timing;
  }

  /// Current state machine stage.
  @property State state() const nothrow @safe {
    return fState;
  }

  /// Current popup opacity in `[0.0f, 1.0f]`.
  @property float currentAlpha() const nothrow @safe {
    return fAlpha;
  }

  /// Active target widget, or null when idle.
  @property Widget activeTarget() nothrow @safe {
    return fActiveTarget;
  }

  /// Current one-shot dwell delay timer ID (or `invalidTimerId`).
  @property TimerId delayTimerId() const nothrow @safe {
    return fDelayTimerId;
  }

  /// Current 60 FPS fade animation timer ID (or `invalidTimerId`).
  @property TimerId animTimerId() const nothrow @safe {
    return fAnimTimerId;
  }

  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.event |
      SystemPhase.preLayout |
      SystemPhase.layout |
      SystemPhase.postLayout;
  }

  override void onRegister(WidgetSystemHost newHost) {
    if (host !is null && host !is newHost) {
      resetForHostChange();
    }
    super.onRegister(newHost);
  }

  override void onUnregister() {
    resetForHostChange();
    super.onUnregister();
  }

  override void onWidgetReleased(Widget w) {
    if (w is null) {
      return;
    }
    if (w is fPendingTarget) {
      fPendingTarget = null;
    }
    if (w is fCachedLayer || w is fCachedPopup) {
      fCachedLayer = null;
      fCachedPopup = null;
      fLayerMissing = false;
      resetToIdle();
      return;
    }
    if (w is fActiveTarget) {
      if (fCachedPopup !is null && !fCachedPopup.released &&
          fCachedPopup.visible) {
        fCachedPopup.visible = false;
        fCachedPopup.update(WidgetUpdateScope.layout);
      }
      resetToIdle();
    }
  }

  override SystemEventResult handleEvent(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    if (event.kind == AppEvent.Kind.mouseMotion) {
      return handleMouseMotion(event, ctx);
    }
    if (event.kind == AppEvent.Kind.mouseButtonDown ||
        event.kind == AppEvent.Kind.windowMouseLeave) {
      return handleDismissEvent(ctx);
    }
    return SystemEventResult(false, false);
  }

  override void onTimer(ref WidgetSystemContext ctx, TimerId id, float dt) {
    if (id != invalidTimerId && id == fDelayTimerId) {
      handleDelayTimer(ctx);
      return;
    }
    if (id != invalidTimerId && id == fAnimTimerId) {
      handleAnimTimer(ctx, dt);
    }
  }

  override void preLayout(ref WidgetSystemContext ctx) {
    import std.algorithm.comparison : max, min;

    fLayerMissing = false;
    if (!discoverLayer(ctx) || !fCachedPopup.visible) {
      return;
    }
    if (fCachedPopup.components.size is null) {
      return;
    }
    const PointF layerSize = resolveLayerSize(ctx);
    if (layerSize.x <= 0.0f || layerSize.y <= 0.0f) {
      return;
    }
    const float margin = fCachedStyle.edgeMargin;
    const float availW = max(0.0f, layerSize.x - 2.0f * margin);
    const float availH = max(0.0f, layerSize.y - 2.0f * margin);
    fCachedPopup.components.size.maxWidth = min(fCachedStyle.maxWidth, availW);
    fCachedPopup.components.size.maxHeight = min(
      fCachedStyle.maxHeight, availH
    );
  }

  override void layout(ref WidgetSystemContext ctx) {
    import std.algorithm.comparison : clamp, max;

    if (!discoverLayer(ctx) || !fCachedPopup.visible) {
      return;
    }
    const PointF layerOrigin = resolveLayerOrigin(ctx);
    const PointF layerSize = resolveLayerSize(ctx);
    const float margin = fCachedStyle.edgeMargin;
    const float lx = fAnchorCursorPos.x - layerOrigin.x;
    const float ly = fAnchorCursorPos.y - layerOrigin.y;

    float x = lx + fCachedStyle.cursorOffset.x;
    float y = ly + fCachedStyle.cursorOffset.y;

    if (layerSize.y > 0.0f &&
        y + fCachedPopup.rect.height > layerSize.y - margin) {
      y = ly - fCachedPopup.rect.height - fCachedStyle.flipGap;
    }
    if (layerSize.x > 0.0f) {
      const float maxX = max(
        margin, layerSize.x - margin - fCachedPopup.rect.width
      );
      x = clamp(x, margin, maxX);
    }
    if (layerSize.y > 0.0f) {
      const float maxY = max(
        margin, layerSize.y - margin - fCachedPopup.rect.height
      );
      y = clamp(y, margin, maxY);
    }

    fCachedPopup.rect.x = x;
    fCachedPopup.rect.y = y;
  }

  override void postLayout(ref WidgetSystemContext ctx) {
    if (fActiveTarget is null) {
      return;
    }
    if (fActiveTarget.released || !isEffectivelyVisible(fActiveTarget)) {
      cancelOrHideActive();
      return;
    }
    const bool checkObstruction =
      fState == State.waitingDelay ||
      fState == State.showing ||
      fState == State.visible;
    if (checkObstruction && fHasCursorPos && ctx.visibleWidgets.length > 0) {
      discoverLayer(ctx);
      Widget hit = findUnobstructedTooltipTarget(
        ctx.visibleWidgets, fLastCursorPos, fCachedLayer
      );
      if (hit !is fActiveTarget) {
        cancelOrHideActive();
      }
    }
  }

private:
  SystemEventResult handleMouseMotion(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    const p = PointF(event.mouse.x, event.mouse.y);
    fLastCursorPos = p;
    fHasCursorPos = true;
    discoverLayer(ctx);

    Widget hit = findUnobstructedTooltipTarget(
      ctx.visibleWidgets, p, fCachedLayer
    );

    final switch (fState) {
    case State.idle:
      if (hit !is null) {
        startWaitingDelay(hit, p);
      }
      break;
    case State.waitingDelay:
      handleMotionWhileWaiting(hit, p);
      break;
    case State.showing:
    case State.visible:
      if (hit !is fActiveTarget) {
        fPendingTarget = hit;
        fPendingCursorPos = p;
        beginHiding();
      }
      break;
    case State.hiding:
      if (hit is fActiveTarget && fActiveTarget !is null) {
        fPendingTarget = null;
        fState = State.showing;
        ensureAnimTimer();
      } else {
        fPendingTarget = hit;
        fPendingCursorPos = p;
      }
      break;
    }
    return SystemEventResult(false, false);
  }

  void handleMotionWhileWaiting(Widget hit, PointF p) {
    if (hit !is fActiveTarget) {
      stopDelayTimer();
      if (hit !is null) {
        startWaitingDelay(hit, p);
      } else {
        fActiveTarget = null;
        fState = State.idle;
      }
      return;
    }
    if (movedBeyondThreshold(p, fDwellOrigin)) {
      fDwellOrigin = p;
      restartDelayTimer();
    }
  }

  SystemEventResult handleDismissEvent(ref WidgetSystemContext ctx) {
    if (fState == State.waitingDelay) {
      resetToIdle();
    } else if (fState == State.showing || fState == State.visible) {
      fPendingTarget = null;
      beginHiding();
    } else if (fState == State.hiding) {
      fPendingTarget = null;
    }
    return SystemEventResult(false, false);
  }

  void handleDelayTimer(ref WidgetSystemContext ctx) {
    fDelayTimerId = invalidTimerId;
    if (fState != State.waitingDelay || !isTargetStillValid(ctx)) {
      resetToIdle();
      return;
    }
    if (!discoverLayer(ctx)) {
      resetToIdle();
      return;
    }
    auto tt = fActiveTarget.components.get!Tooltip();
    const string resolved = tt !is null ? tt.resolveText(fActiveTarget) : "";
    if (resolved.length == 0) {
      resetToIdle();
      return;
    }

    fAnchorCursorPos = fLastCursorPos;
    if (fCachedPopup.components.textLabel !is null) {
      fCachedPopup.components.textLabel.caption = resolved;
    }
    if (fTiming.fadeInDuration <= 0.0f) {
      fAlpha = 1.0f;
      applyPopupAlpha(fCachedPopup, fCachedStyle, fAlpha);
      fCachedPopup.visible = true;
      fCachedPopup.update(WidgetUpdateScope.layout);
      fState = State.visible;
      stopAnimTimer();
      return;
    }
    fAlpha = 0.0f;
    applyPopupAlpha(fCachedPopup, fCachedStyle, fAlpha);
    fCachedPopup.visible = true;
    fCachedPopup.update(WidgetUpdateScope.layout);

    fState = State.showing;
    ensureAnimTimer();
  }

  void handleAnimTimer(ref WidgetSystemContext ctx, float dt) {
    if (fCachedPopup is null || fCachedPopup.released) {
      resetToIdle();
      return;
    }
    if (fState == State.showing) {
      stepShowing(dt);
    } else if (fState == State.hiding) {
      stepHiding(dt);
    } else {
      stopAnimTimer();
    }
  }

  void stepShowing(float dt) {
    if (fTiming.fadeInDuration <= 0.0f) {
      fAlpha = 1.0f;
    } else {
      fAlpha += dt / fTiming.fadeInDuration;
    }
    if (fAlpha >= 1.0f) {
      fAlpha = 1.0f;
      applyPopupAlpha(fCachedPopup, fCachedStyle, fAlpha);
      fState = State.visible;
      stopAnimTimer();
    } else {
      applyPopupAlpha(fCachedPopup, fCachedStyle, fAlpha);
    }
  }

  void stepHiding(float dt) {
    if (fTiming.fadeOutDuration <= 0.0f) {
      fAlpha = 0.0f;
    } else {
      fAlpha -= dt / fTiming.fadeOutDuration;
    }
    if (fAlpha <= 0.0f) {
      finishHiding();
    } else {
      applyPopupAlpha(fCachedPopup, fCachedStyle, fAlpha);
    }
  }

  void finishHiding() {
    fAlpha = 0.0f;
    if (fCachedPopup !is null && !fCachedPopup.released) {
      applyPopupAlpha(fCachedPopup, fCachedStyle, fAlpha);
      fCachedPopup.visible = false;
      fCachedPopup.update(WidgetUpdateScope.layout);
    }
    stopAnimTimer();
    fActiveTarget = null;

    if (fPendingTarget !is null && !fPendingTarget.released) {
      Widget nextTarget = fPendingTarget;
      const PointF nextPos = fPendingCursorPos;
      fPendingTarget = null;
      startWaitingDelay(nextTarget, nextPos);
    } else {
      fPendingTarget = null;
      fState = State.idle;
    }
  }

  void startWaitingDelay(Widget target, PointF origin) {
    fActiveTarget = target;
    fDwellOrigin = origin;
    fState = State.waitingDelay;
    restartDelayTimer();
  }

  void restartDelayTimer() {
    stopDelayTimer();
    if (host !is null) {
      fDelayTimerId = startTimer(fTiming.showDelayMs, TimerMode.oneShot);
    }
  }

  void beginHiding() {
    stopDelayTimer();
    if (fTiming.fadeOutDuration <= 0.0f) {
      finishHiding();
      return;
    }
    fState = State.hiding;
    ensureAnimTimer();
  }

  void cancelOrHideActive() {
    if (fState == State.waitingDelay) {
      resetToIdle();
    } else if (fState == State.showing || fState == State.visible) {
      fPendingTarget = null;
      beginHiding();
    }
  }

  void resetForHostChange() {
    if (fCachedPopup !is null && !fCachedPopup.released &&
        fCachedPopup.visible) {
      fCachedPopup.visible = false;
      fCachedPopup.update(WidgetUpdateScope.layout);
    }
    resetToIdle();
    fCachedLayer = null;
    fCachedPopup = null;
    fLayerMissing = false;
  }

  void resetToIdle() {
    stopAllTimers();
    fActiveTarget = null;
    fPendingTarget = null;
    fAlpha = 0.0f;
    fState = State.idle;
  }

  void ensureAnimTimer() {
    if (fAnimTimerId == invalidTimerId && host !is null) {
      fAnimTimerId = startTimer(TimerIntervalMs.fps60, TimerMode.repeat);
    }
  }

  void stopDelayTimer() {
    stopTimer(fDelayTimerId);
  }

  void stopAnimTimer() {
    stopTimer(fAnimTimerId);
  }

  void stopAllTimers() {
    stopDelayTimer();
    stopAnimTimer();
  }

  bool isTargetStillValid(ref WidgetSystemContext ctx) {
    if (fActiveTarget is null || fActiveTarget.released) {
      return false;
    }
    if (ctx.visibleWidgets.length > 0 && fHasCursorPos) {
      return findUnobstructedTooltipTarget(
        ctx.visibleWidgets, fLastCursorPos, fCachedLayer
      ) is fActiveTarget;
    }
    return isEffectivelyVisible(fActiveTarget);
  }

  bool movedBeyondThreshold(PointF a, PointF b) const nothrow @safe @nogc {
    const float dx = a.x - b.x;
    const float dy = a.y - b.y;
    const float thresh = fTiming.moveResetThreshold;
    return (dx * dx + dy * dy) > (thresh * thresh);
  }

  bool discoverLayer(ref WidgetSystemContext ctx) {
    if (fCachedLayer !is null && !fCachedLayer.released &&
        fCachedPopup !is null && !fCachedPopup.released) {
      if (auto comp = fCachedLayer.components.get!TooltipLayerComponent()) {
        fCachedStyle = comp.style;
      }
      return true;
    }
    if (fLayerMissing) {
      return false;
    }
    fCachedLayer = null;
    fCachedPopup = null;

    Widget found = findLayerInList(ctx.visibleWidgets);
    if (found is null) {
      found = findLayerInList(ctx.unclippedWidgets);
    }
    if (found is null && ctx.root !is null) {
      found = findLayerInTree(ctx.root);
    }
    if (found is null) {
      fLayerMissing = true;
      return false;
    }
    auto comp = found.components.get!TooltipLayerComponent();
    if (comp is null || comp.popupWidget is null || comp.popupWidget.released) {
      fLayerMissing = true;
      return false;
    }
    fCachedLayer = found;
    fCachedPopup = comp.popupWidget;
    fCachedStyle = comp.style;
    return true;
  }

  static Widget findLayerInList(VisibleWidgets widgets) {
    foreach_reverse (ref vw; widgets) {
      if (vw.widget !is null && !vw.widget.released &&
          vw.widget.components.has!TooltipLayerComponent()) {
        return vw.widget;
      }
    }
    return null;
  }

  static Widget findLayerInTree(Widget root) {
    if (root is null || root.released) {
      return null;
    }
    foreach_reverse (child; root.children) {
      if (auto found = findLayerInTree(child)) {
        return found;
      }
    }
    if (root.components.has!TooltipLayerComponent()) {
      return root;
    }
    return null;
  }

  PointF resolveLayerSize(ref WidgetSystemContext ctx) const nothrow @safe {
    if (fCachedLayer !is null &&
        fCachedLayer.rect.width > 0.0f &&
        fCachedLayer.rect.height > 0.0f) {
      return PointF(fCachedLayer.rect.width, fCachedLayer.rect.height);
    }
    if (ctx.root !is null) {
      return PointF(ctx.root.rect.width, ctx.root.rect.height);
    }
    return PointF(0.0f, 0.0f);
  }

  PointF resolveLayerOrigin(ref WidgetSystemContext ctx) const nothrow @safe {
    foreach (ref vw; ctx.unclippedWidgets) {
      if (vw.widget is fCachedLayer) {
        return PointF(vw.absRect.x, vw.absRect.y);
      }
    }
    foreach (ref vw; ctx.visibleWidgets) {
      if (vw.widget is fCachedLayer) {
        return PointF(vw.absRect.x, vw.absRect.y);
      }
    }
    if (fCachedLayer !is null) {
      return PointF(fCachedLayer.rect.x, fCachedLayer.rect.y);
    }
    return PointF(0.0f, 0.0f);
  }

  static void applyPopupAlpha(
    Widget popup,
    in TooltipStyle style,
    float alpha
  ) {
    import std.algorithm.comparison : clamp;

    const float a = clamp(alpha, 0.0f, 1.0f);
    applyColors(
      popup,
      WidgetColors(
        scaleAlpha(style.colors.bg, a),
        scaleAlpha(style.colors.border, a),
        scaleAlpha(style.colors.text, a)
      )
    );
  }

  static ColorF scaleAlpha(ColorF c, float factor) nothrow @safe @nogc {
    return ColorF(c.r, c.g, c.b, c.a * factor);
  }

  TooltipTiming fTiming;
  State fState = State.idle;
  float fAlpha = 0.0f;
  Widget fActiveTarget = null;
  Widget fPendingTarget = null;
  PointF fLastCursorPos;
  PointF fDwellOrigin;
  PointF fAnchorCursorPos;
  PointF fPendingCursorPos;
  bool fHasCursorPos = false;
  Widget fCachedLayer = null;
  Widget fCachedPopup = null;
  TooltipStyle fCachedStyle;
  bool fLayerMissing = false;
  TimerId fDelayTimerId = invalidTimerId;
  TimerId fAnimTimerId = invalidTimerId;
}

// Test 1: TooltipLayerBuilder structure and component configuration.
unittest {
  import yguilib.controls.testing : verifyAllNamed;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.drawing_components : Background;

  auto ui = new UiSystemImpl(null);
  auto root = WidgetBuilder.make(ui)
    .name("root")
    .rect(RectF(0, 0, 800, 600))
    .build();

  TooltipLayerBuilder builder;
  auto layer = builder.name("appTooltipLayer").build(ui, root);

  assert(layer !is null);
  assert(layer.parent is root);
  assert(layer.name == "appTooltipLayer");
  assert(layer.visible);
  assert(!layer.handleInput);
  assert(layer.components.background is null);
  assert(layer.components.border is null);
  assert(layer.components.anchor !is null);
  assert(layer.components.size !is null);
  assert(layer.components.has!TooltipLayerComponent());

  auto layerComp = layer.components.get!TooltipLayerComponent();
  assert(layerComp !is null);
  auto popup = layerComp.popupWidget;
  assert(popup !is null);
  assert(popup.parent is layer);
  assert(popup.name == "appTooltipLayerPopup");
  assert(!popup.visible);
  assert(!popup.handleInput);
  assert(popup.components.background !is null);
  assert(popup.components.background.style == Background.Style.round);
  assert(popup.components.border !is null);
  assert(popup.components.border.style == Border.Style.round);
  assert(popup.components.textLabel !is null);
  assert(popup.components.textLabel.multiline);
  assert(popup.components.textLabel.overflowEllipsis);
  assert(popup.components.textLabel.alignment == TextLabel.Alignment.left);
  verifyAllNamed(layer);

  // Also test createTooltipLayer with null parent and default fallback name.
  auto standalone = createTooltipLayer(ui, null, TooltipStyle.init, null);
  assert(standalone.name == "tooltipLayer");
  verifyAllNamed(standalone);
}

// Test 2: Tooltip.resolveText explicit text, caption fallback, disabled.
unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto ui = new UiSystemImpl(null);
  auto w = WidgetBuilder.make(ui)
    .name("btn")
    .text("Caption Fallback")
    .build();

  auto explicit = Tooltip.withText("Explicit Hint");
  assert(explicit.resolveText(w) == "Explicit Hint");

  auto fallback = new Tooltip();
  assert(fallback.resolveText(w) == "Caption Fallback");
  assert(fallback.resolveText(null) == "");

  explicit.enabled = false;
  assert(explicit.resolveText(w) == "");
}

// Test 3: Unobstructed hit-testing rules.
unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto ui = new UiSystemImpl(null);
  auto root = WidgetBuilder.make(ui)
    .name("root")
    .rect(RectF(0, 0, 400, 300))
    .build();

  auto btn = WidgetBuilder.make(ui)
    .parent(root)
    .name("btn")
    .rect(RectF(20, 20, 100, 40))
    .handleInput(true)
    .text("Save")
    .component(Tooltip.withText("Save document"))
    .build();

  auto passThrough = WidgetBuilder.make(ui)
    .parent(root)
    .name("passThrough")
    .rect(RectF(0, 0, 400, 300))
    .build();

  auto modalBackdrop = WidgetBuilder.make(ui)
    .parent(root)
    .name("modalBackdrop")
    .rect(RectF(0, 0, 400, 300))
    .visible(true)
    .handleInput(true)
    .build();
  assert(modalBackdrop.components.background is null);

  auto layer = createTooltipLayer(ui, root, TooltipStyle.init, "ttLayer");
  auto popup = layer.components.get!TooltipLayerComponent().popupWidget;

  // Pass-through container on top does NOT obstruct.
  VisibleWidgets listPass = [
    VisibleWidget(root, RectF(0, 0, 400, 300), false, RectF.init),
    VisibleWidget(btn, RectF(20, 20, 100, 40), false, RectF.init),
    VisibleWidget(passThrough, RectF(0, 0, 400, 300), false, RectF.init),
    VisibleWidget(layer, RectF(0, 0, 400, 300), false, RectF.init),
    VisibleWidget(popup, RectF(20, 20, 100, 40), false, RectF.init),
  ];
  assert(
    findUnobstructedTooltipTarget(listPass, PointF(50, 35), layer) is btn
  );

  // Transparent modal backdrop (visible=true, handleInput=true, no Background)
  // on top DOES obstruct.
  VisibleWidgets listBlocked = [
    VisibleWidget(root, RectF(0, 0, 400, 300), false, RectF.init),
    VisibleWidget(btn, RectF(20, 20, 100, 40), false, RectF.init),
    VisibleWidget(modalBackdrop, RectF(0, 0, 400, 300), false, RectF.init),
  ];
  assert(
    findUnobstructedTooltipTarget(listBlocked, PointF(50, 35), layer) is null
  );

  // Clipped widget outside clipRect is not hit.
  VisibleWidgets listClipped = [
    VisibleWidget(
      btn, RectF(20, 20, 100, 40), true, RectF(20, 20, 20, 40)
    ),
  ];
  assert(
    findUnobstructedTooltipTarget(listClipped, PointF(25, 35), layer) is btn
  );
  assert(
    findUnobstructedTooltipTarget(listClipped, PointF(80, 35), layer) is null
  );
}

// Test 4: Full state machine lifecycle with DummyWidgetSystemHost.
unittest {
  import yguilib.controls.testing : DummyWidgetSystemHost;
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto host = new DummyWidgetSystemHost();
  auto ui = new UiSystemImpl(null);
  auto root = WidgetBuilder.make(ui)
    .name("root")
    .rect(RectF(0, 0, 400, 300))
    .build();
  auto btn = WidgetBuilder.make(ui)
    .parent(root)
    .name("btn")
    .rect(RectF(20, 20, 100, 40))
    .handleInput(true)
    .text("Play")
    .component(Tooltip.withText("Start playback"))
    .build();
  auto layer = createTooltipLayer(ui, root, TooltipStyle.init, "ttLayer");
  auto popup = layer.components.get!TooltipLayerComponent().popupWidget;

  TooltipTiming timing;
  timing.showDelayMs = 400;
  timing.fadeInDuration = 0.10f;
  timing.fadeOutDuration = 0.20f;
  timing.moveResetThreshold = 3.0f;

  auto sys = TooltipSystem.withTiming(timing);
  sys.onRegister(host);
  assert(sys.priority == TooltipSystem.tooltipSystemPriority);
  assert(sys.state == TooltipSystem.State.idle);

  WidgetSystemContext ctx;
  ctx.host = host;
  ctx.root = root;
  ctx.visibleWidgets = [
    VisibleWidget(root, RectF(0, 0, 400, 300), false, RectF.init),
    VisibleWidget(btn, RectF(20, 20, 100, 40), false, RectF.init),
    VisibleWidget(layer, RectF(0, 0, 400, 300), false, RectF.init),
  ];

  // Hover -> waitingDelay
  auto ev = AppEvent(AppEvent.Kind.mouseMotion);
  ev.mouse.x = 50.0f;
  ev.mouse.y = 35.0f;
  auto res = sys.handleEvent(ev, ctx);
  assert(!res.consumed);
  assert(sys.state == TooltipSystem.State.waitingDelay);
  assert(host.isTimerActive(sys.delayTimerId));
  assert(!popup.visible);

  // Jitter > threshold resets delay timer
  const TimerId firstDelayId = sys.delayTimerId;
  ev.mouse.x = 60.0f;
  ev.mouse.y = 35.0f;
  sys.handleEvent(ev, ctx);
  assert(sys.delayTimerId != firstDelayId);
  assert(!host.isTimerActive(firstDelayId));
  assert(host.isTimerActive(sys.delayTimerId));

  // Delay fires -> showing, popup visible, 60 FPS timer active
  sys.onTimer(ctx, sys.delayTimerId, 0.4f);
  assert(sys.state == TooltipSystem.State.showing);
  assert(popup.visible);
  assert(popup.components.textLabel.caption == "Start playback");
  assert(host.isTimerActive(sys.animTimerId));

  // Step fade-in to 1.0 -> visible, 60 FPS timer stopped (0% CPU)
  sys.onTimer(ctx, sys.animTimerId, 0.05f);
  assert(sys.currentAlpha > 0.4f && sys.currentAlpha < 0.6f);
  sys.onTimer(ctx, sys.animTimerId, 0.06f);
  assert(sys.state == TooltipSystem.State.visible);
  assert(sys.currentAlpha == 1.0f);
  assert(sys.animTimerId == invalidTimerId);

  // Mouse leaves -> hiding, 60 FPS timer active
  ev.mouse.x = 200.0f;
  ev.mouse.y = 200.0f;
  sys.handleEvent(ev, ctx);
  assert(sys.state == TooltipSystem.State.hiding);
  assert(host.isTimerActive(sys.animTimerId));

  // Step partway through fade-out, then re-enter -> reverses to showing
  sys.onTimer(ctx, sys.animTimerId, 0.10f);
  assert(sys.currentAlpha > 0.4f && sys.currentAlpha < 0.6f);
  ev.mouse.x = 50.0f;
  ev.mouse.y = 35.0f;
  sys.handleEvent(ev, ctx);
  assert(sys.state == TooltipSystem.State.showing);
  assert(host.isTimerActive(sys.animTimerId));

  // Reach visible again, then click dismisses to hiding
  sys.onTimer(ctx, sys.animTimerId, 0.10f);
  assert(sys.state == TooltipSystem.State.visible);
  auto downEv = AppEvent(AppEvent.Kind.mouseButtonDown);
  downEv.mouse.x = 50.0f;
  downEv.mouse.y = 35.0f;
  sys.handleEvent(downEv, ctx);
  assert(sys.state == TooltipSystem.State.hiding);

  // Finish fade-out -> popup hidden, timer stopped, idle
  sys.onTimer(ctx, sys.animTimerId, 0.25f);
  assert(sys.state == TooltipSystem.State.idle);
  assert(!popup.visible);
  assert(sys.animTimerId == invalidTimerId);
  assert(sys.delayTimerId == invalidTimerId);

  // Hover then windowMouseLeave cancels waitingDelay
  sys.handleEvent(ev, ctx);
  assert(sys.state == TooltipSystem.State.waitingDelay);
  auto leaveEv = AppEvent(AppEvent.Kind.windowMouseLeave);
  sys.handleEvent(leaveEv, ctx);
  assert(sys.state == TooltipSystem.State.idle);
  assert(sys.delayTimerId == invalidTimerId);
}

// Test 5: Layout stretching, maxWidth/maxHeight clamping, and corner flip.
unittest {
  import yguilib.controls.testing : DummyWidgetSystemHost;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.internal.collect_visible : VisibleWidgetsCollector;
  import yguilib.widget.internal.layout_system : LayoutSystem;

  auto host = new DummyWidgetSystemHost();
  auto ui = new UiSystemImpl(null);
  auto root = WidgetBuilder.make(ui)
    .name("root")
    .rect(RectF(0, 0, 300, 200))
    .build();
  auto btn = WidgetBuilder.make(ui)
    .parent(root)
    .name("cornerBtn")
    .rect(RectF(250, 160, 40, 30))
    .handleInput(true)
    .component(Tooltip.withText("Tooltip near bottom-right corner"))
    .build();

  TooltipStyle style;
  style.maxWidth = 360.0f;
  style.maxHeight = 500.0f;
  style.edgeMargin = 8.0f;
  auto layer = createTooltipLayer(ui, root, style, "ttLayer");
  auto popup = layer.components.get!TooltipLayerComponent().popupWidget;

  auto layoutSys = new LayoutSystem();
  auto tooltipSys = new TooltipSystem();
  tooltipSys.onRegister(host);

  auto collector = new VisibleWidgetsCollector();
  WidgetSystemContext ctx;
  ctx.host = host;
  ctx.root = root;
  ctx.visibleWidgets = collector.collectVisibleWithViewport(
    root, 300.0f, 200.0f, false
  );
  ctx.unclippedWidgets = collector.collectVisibleWithViewport(
    root, 300.0f, 200.0f, true
  );

  // Trigger tooltip near bottom-right corner
  auto ev = AppEvent(AppEvent.Kind.mouseMotion);
  ev.mouse.x = 270.0f;
  ev.mouse.y = 175.0f;
  tooltipSys.handleEvent(ev, ctx);
  tooltipSys.onTimer(ctx, tooltipSys.delayTimerId, 0.5f);
  assert(popup.visible);

  // Run preLayout -> LayoutSystem -> TooltipSystem.layout
  tooltipSys.preLayout(ctx);
  assert(popup.components.size.maxWidth == 284.0f);
  assert(popup.components.size.maxHeight == 184.0f);

  ctx.unclippedWidgets = collector.collectVisibleWithViewport(
    root, 300.0f, 200.0f, true
  );
  layoutSys.layout(ctx);
  // Layer stretched to cover root via Anchor(0, 0, 0, 0)
  assert(layer.rect.width == 300.0f);
  assert(layer.rect.height == 200.0f);

  // Simulate measured popup size (120x40) and run TooltipSystem.layout
  popup.rect.width = 120.0f;
  popup.rect.height = 40.0f;
  tooltipSys.layout(ctx);

  // Clamped within [8, 300 - 8 - 120] horizontally and flipped above cursor
  assert(popup.rect.x >= 8.0f);
  assert(popup.rect.x + popup.rect.width <= 300.0f - 8.0f);
  assert(popup.rect.y < 175.0f);
  assert(popup.rect.y >= 8.0f);
}

// Test 6: onWidgetReleased safely clears active target and cached layer.
unittest {
  import yguilib.controls.testing : DummyWidgetSystemHost;
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto host = new DummyWidgetSystemHost();
  auto ui = new UiSystemImpl(null);
  auto root = WidgetBuilder.make(ui)
    .name("root")
    .rect(RectF(0, 0, 400, 300))
    .build();
  auto btn = WidgetBuilder.make(ui)
    .parent(root)
    .name("btn")
    .rect(RectF(10, 10, 80, 30))
    .handleInput(true)
    .component(Tooltip.withText("Release me"))
    .build();
  auto layer = createTooltipLayer(ui, root, TooltipStyle.init, "ttLayer");
  auto popup = layer.components.get!TooltipLayerComponent().popupWidget;

  auto sys = new TooltipSystem();
  sys.onRegister(host);

  WidgetSystemContext ctx;
  ctx.host = host;
  ctx.root = root;
  ctx.visibleWidgets = [
    VisibleWidget(root, RectF(0, 0, 400, 300), false, RectF.init),
    VisibleWidget(btn, RectF(10, 10, 80, 30), false, RectF.init),
    VisibleWidget(layer, RectF(0, 0, 400, 300), false, RectF.init),
  ];

  auto ev = AppEvent(AppEvent.Kind.mouseMotion);
  ev.mouse.x = 30.0f;
  ev.mouse.y = 20.0f;
  sys.handleEvent(ev, ctx);
  sys.onTimer(ctx, sys.delayTimerId, 0.5f);
  assert(popup.visible);
  assert(sys.activeTarget is btn);

  // Release active target -> popup hidden, timers stopped, state idle
  btn.release();
  sys.onWidgetReleased(btn);
  assert(sys.activeTarget is null);
  assert(sys.state == TooltipSystem.State.idle);
  assert(!popup.visible);
  assert(sys.animTimerId == invalidTimerId);
  assert(sys.delayTimerId == invalidTimerId);

  // Release layer -> cached layer cleared cleanly
  layer.release();
  sys.onWidgetReleased(layer);
  assert(sys.state == TooltipSystem.State.idle);
}

// Test 7: postLayout obstruction, target handoff, host switch, 0-dur fade
unittest {
  import yguilib.controls.testing : DummyWidgetSystemHost;
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto host1 = new DummyWidgetSystemHost();
  auto host2 = new DummyWidgetSystemHost();
  auto ui = new UiSystemImpl(null);
  auto root = WidgetBuilder.make(ui)
    .name("root")
    .rect(RectF(0, 0, 400, 300))
    .build();
  auto btnA = WidgetBuilder.make(ui)
    .parent(root)
    .name("btnA")
    .rect(RectF(10, 10, 80, 30))
    .handleInput(true)
    .component(Tooltip.withText("Hint A"))
    .build();
  auto btnB = WidgetBuilder.make(ui)
    .parent(root)
    .name("btnB")
    .rect(RectF(120, 10, 80, 30))
    .handleInput(true)
    .component(Tooltip.withText("Hint B"))
    .build();
  auto blocker = WidgetBuilder.make(ui)
    .parent(root)
    .name("blocker")
    .rect(RectF(10, 10, 80, 30))
    .visible(false)
    .handleInput(true)
    .build();
  auto layer = createTooltipLayer(ui, root, TooltipStyle.init, "ttLayer");
  auto popup = layer.components.get!TooltipLayerComponent().popupWidget;

  // 0-duration fade fast-path
  TooltipTiming zeroFade;
  zeroFade.showDelayMs = 100;
  zeroFade.fadeInDuration = 0.0f;
  zeroFade.fadeOutDuration = 0.0f;
  auto sys = TooltipSystem.withTiming(zeroFade);
  sys.onRegister(host1);

  WidgetSystemContext ctx;
  ctx.host = host1;
  ctx.root = root;
  ctx.visibleWidgets = [
    VisibleWidget(root, RectF(0, 0, 400, 300), false, RectF.init),
    VisibleWidget(btnA, RectF(10, 10, 80, 30), false, RectF.init),
    VisibleWidget(btnB, RectF(120, 10, 80, 30), false, RectF.init),
    VisibleWidget(layer, RectF(0, 0, 400, 300), false, RectF.init),
  ];

  AppEvent motion(float x, float y) {
    auto ev = AppEvent(AppEvent.Kind.mouseMotion);
    ev.mouse.x = x;
    ev.mouse.y = y;
    return ev;
  }

  sys.handleEvent(motion(30, 20), ctx);
  sys.onTimer(ctx, sys.delayTimerId, 0.1f);
  assert(sys.state == TooltipSystem.State.visible);
  assert(sys.animTimerId == invalidTimerId);
  assert(popup.visible);

  // Target-A -> Target-B handoff with 0-duration fadeOut
  sys.handleEvent(motion(140, 20), ctx);
  assert(sys.state == TooltipSystem.State.waitingDelay);
  assert(sys.activeTarget is btnB);
  assert(!popup.visible);

  // Obstruction in postLayout cancels waitingDelay
  blocker.visible = true;
  ctx.visibleWidgets = [
    VisibleWidget(root, RectF(0, 0, 400, 300), false, RectF.init),
    VisibleWidget(btnA, RectF(10, 10, 80, 30), false, RectF.init),
    VisibleWidget(btnB, RectF(120, 10, 80, 30), false, RectF.init),
    VisibleWidget(blocker, RectF(120, 10, 80, 30), false, RectF.init),
    VisibleWidget(layer, RectF(0, 0, 400, 300), false, RectF.init),
  ];
  sys.postLayout(ctx);
  assert(sys.state == TooltipSystem.State.idle);
  assert(sys.activeTarget is null);

  // Host switch and onUnregister hide popup and reset state
  blocker.visible = false;
  ctx.visibleWidgets = [
    VisibleWidget(root, RectF(0, 0, 400, 300), false, RectF.init),
    VisibleWidget(btnA, RectF(10, 10, 80, 30), false, RectF.init),
    VisibleWidget(layer, RectF(0, 0, 400, 300), false, RectF.init),
  ];
  sys.handleEvent(motion(30, 20), ctx);
  sys.onTimer(ctx, sys.delayTimerId, 0.1f);
  assert(popup.visible);
  sys.onRegister(host2);
  assert(!popup.visible);
  assert(sys.state == TooltipSystem.State.idle);
  assert(sys.activeTarget is null);

  ctx.host = host2;
  sys.handleEvent(motion(30, 20), ctx);
  sys.onTimer(ctx, sys.delayTimerId, 0.1f);
  assert(popup.visible);
  sys.onUnregister();
  assert(!popup.visible);
  assert(sys.state == TooltipSystem.State.idle);
}
