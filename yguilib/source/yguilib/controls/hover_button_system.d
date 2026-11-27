/**
 * hover_button_system.d - Hover button animation system and widget component.
 *
 * ARCHITECTURE OVERVIEW: WIDGET SYSTEM & COMPONENT (ECS-STYLE)
 * -------------------------------------------------------------
 * An extensible WidgetSystem (AnimatedHoverButtonSystem) processing widgets
 * that carry an attached AnimatedHoverButtonComponent.
 *
 * - Single widget tree node: background, border, text label, and
 *   AnimatedHoverButtonComponent attached directly.
 * - No manual button registration: the system automatically processes any
 *   visible widget with the component during its pipeline phases.
 * - Integrated into WidgetSystemPipeline across event and postLayout phases,
 *   driving 60 FPS animations via TimerControl when active and 0% CPU when
 *   idle.
 */
module yguilib.controls.hover_button_system;

import std.math : PI, sin;
import yguilib.controls.common : ButtonBaseConfig, applyBgAndBorderColors;
import yguilib.controls.internal.button_support : ButtonAnimDriver,
  ButtonBuilderCommon, PressTracker, emitButtonAction;
import yguilib.events : AppEvent;
import yguilib.render.render_types : ColorF, PointF, RectF, lerpColor,
  normalizedIn;
import yguilib.timercontrol : TimerId, invalidTimerId;
import yguilib.timers : AnimationTimer, AnimationWrapMode;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget, isEffectivelyVisible;
import yguilib.widget.component : WidgetComponent;
import yguilib.widget.system : SystemEventResult, SystemPhase, WidgetSystem,
  WidgetSystemContext, WidgetSystemHost;

/// Widget construction styling options.
alias HoverButtonConfig = ButtonBaseConfig;

/// System-side animation and interactive options.
struct HoverAnimConfig {
  enum AnimStyle {
    fade,
    gradientPlay,
  }

  AnimStyle style = AnimStyle.fade;
  ColorF hoverBg = ColorF(0.28f, 0.48f, 0.85f, 1.0f);
  ColorF gradientAccentBg = ColorF(0.20f, 0.80f, 0.95f, 1.0f);
  ColorF pressBg = ColorF(0.16f, 0.32f, 0.65f, 1.0f);
  ColorF hoverBorder = ColorF(0.50f, 0.70f, 1.0f, 1.0f);
  float fadeSpeed = 3.5f;
  string actionEvent = null;
}

/// Component attached to a Widget to declare hover and press animation.
final class AnimatedHoverButtonComponent : WidgetComponent {
  HoverAnimConfig animConfig;
  ColorF normalBg = ColorF(0.20f, 0.22f, 0.28f, 1.0f);
  ColorF normalBorder = ColorF(0.35f, 0.38f, 0.48f, 1.0f);
  bool colorsInitialized = false;
  float hoverProgress = 0.0f;
  float pressProgress = 0.0f;
  float animPhase = 0.0f;
  AnimationTimer hoverTimer;
  AnimationTimer pressTimer;
  AnimationTimer gradTimer;
  bool isHovered = false;
  bool isPressed = false;
  bool hoverPulsePending = false;
  float cursorNormX = 0.5f;

  this(in HoverAnimConfig animConfig) {
    this.animConfig = animConfig;
    const float speed = animConfig.fadeSpeed > 0.0f
      ? animConfig.fadeSpeed
      : 3.5f;
    hoverTimer.start(1.0f / speed, AnimationWrapMode.once);
    pressTimer.start(1.0f / (speed * 3.0f), AnimationWrapMode.once);
    gradTimer.start((2.0f * PI) / 3.5f, AnimationWrapMode.loop);
    gradTimer.paused(false);
  }

  /// Clears active hover and press interaction flags without stopping timers.
  void releaseInteraction() {
    isHovered = false;
    isPressed = false;
  }

  /// Resets interaction state, stops timers, and restores normal colors.
  void resetToNormal(Widget w) {
    assert(w !is null, "w must not be null");
    releaseInteraction();
    hoverPulsePending = false;
    hoverTimer.stop();
    pressTimer.stop();
    hoverProgress = 0.0f;
    pressProgress = 0.0f;
    if (colorsInitialized) {
      applyBgAndBorderColors(w, normalBg, normalBorder);
    }
  }
}

/// Fluent builder for constructing animated hover buttons using components.
struct AnimatedHoverButtonBuilder {
  mixin ButtonBuilderCommon;
  HoverAnimConfig animConfig;

  ref AnimatedHoverButtonBuilder action(string eventName) return {
    config.actionEvent = eventName;
    animConfig.actionEvent = eventName;
    return this;
  }

  ref AnimatedHoverButtonBuilder anim(in HoverAnimConfig anim) return {
    animConfig = anim;
    if (config.actionEvent.length > 0 && animConfig.actionEvent.length == 0) {
      animConfig.actionEvent = config.actionEvent;
    }
    return this;
  }

  /// Builds the animated hover button widget; `parent` is allowed to be null.
  Widget build(UiSystem ui, Widget parent, RectF rect) {
    auto b = makeButtonBase(ui, parent, rect, "animatedHoverButton");
    auto comp = new AnimatedHoverButtonComponent(animConfig);
    comp.normalBg = config.normalBg;
    comp.normalBorder = config.borderColor;
    comp.colorsInitialized = true;
    b.component(comp);
    return b.build();
  }
}

/// Convenience helper creating an animated hover button widget.
/// `parent` is allowed to be null.
Widget createAnimatedHoverButton(
  UiSystem ui,
  Widget parent,
  RectF rect,
  in HoverButtonConfig config,
  in HoverAnimConfig animConfig
) {
  AnimatedHoverButtonBuilder b;
  b.config = config;
  b.animConfig = animConfig;
  return b.build(ui, parent, rect);
}

/// Custom WidgetSystem processing widgets with AnimatedHoverButtonComponent.
final class AnimatedHoverButtonSystem : WidgetSystem {
  enum float hoverPulsePeak = 0.75f;

  this() nothrow @safe {
  }

  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.event | SystemPhase.postLayout;
  }

  override void onRegister(WidgetSystemHost newHost) {
    if (host !is null && host !is newHost) {
      anim.stopTimer(host);
    }
    super.onRegister(newHost);
    if (newHost !is null) {
      anim.ensureTimer(this, newHost);
    }
  }

  override void onUnregister() {
    anim.stopTimer(host);
    super.onUnregister();
  }

  override SystemEventResult handleEvent(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    if (event.kind == AppEvent.Kind.mouseMotion) {
      return handleMouseMotion(event, ctx);
    }
    if (event.kind == AppEvent.Kind.mouseButtonDown) {
      return handleMouseButtonDown(event, ctx);
    }
    if (event.kind == AppEvent.Kind.mouseButtonUp) {
      return handleMouseButtonUp(event, ctx);
    }
    if (event.kind == AppEvent.Kind.windowMouseLeave) {
      return handleWindowMouseLeave(ctx);
    }
    return SystemEventResult(false, false);
  }

  override void onTimer(ref WidgetSystemContext ctx, TimerId id, float dt) {
    if (id == invalidTimerId || id != anim.animTimerId) {
      return;
    }
    if (!isAnyAnimating()) {
      anim.stopTimer(host);
      return;
    }
    stepActiveButtons(dt);
  }

  override void postLayout(ref WidgetSystemContext ctx) {
    cleanInactiveButtons();
  }

  override void onWidgetReleased(Widget w) {
    if (w is null) {
      return;
    }
    if (hoveredWidget is w) {
      hoveredWidget = null;
    }
    press.forget(w);
    anim.remove(w, host);
  }

  bool isAnyAnimating() const nothrow @safe {
    return !anim.empty;
  }

  @property TimerId animTimerId() const nothrow @safe {
    return anim.animTimerId;
  }

private:
  void ensureAnimTimer(WidgetSystemHost fallbackHost) {
    if (host is null && fallbackHost !is null) {
      host = fallbackHost;
    }
    anim.ensureTimer(this, host);
  }

  SystemEventResult handleMouseMotion(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    const p = PointF(event.mouse.x, event.mouse.y);
    auto hitVw = press.hitTest(ctx, p);
    Widget hitWidget = hitVw.isNull ? null : hitVw.get().widget;
    if (hitWidget !is null && !hitWidget.inputEnabled) {
      hitWidget = null;
    }

    if (hitWidget !is hoveredWidget) {
      if (hoveredWidget !is null) {
        auto prevComp =
          hoveredWidget.components.get!AnimatedHoverButtonComponent();
        if (prevComp !is null) {
          prevComp.releaseInteraction();
          anim.track(hoveredWidget);
        }
      }
      hoveredWidget = hitWidget;
      if (hoveredWidget !is null) {
        auto comp = hoveredWidget.components.get!AnimatedHoverButtonComponent();
        if (comp !is null) {
          initColorsIfNeeded(hoveredWidget, comp);
          comp.isHovered = true;
          comp.isPressed = (hoveredWidget is press.pressed);
          comp.hoverPulsePending = true;
          updateCursorNorm(comp, hitVw.get().absRect, p);
          anim.track(hoveredWidget);
        }
      }
    } else if (hoveredWidget !is null) {
      auto comp = hoveredWidget.components.get!AnimatedHoverButtonComponent();
      if (comp !is null) {
        updateCursorNorm(comp, hitVw.get().absRect, p);
        if (comp.animConfig.style == HoverAnimConfig.AnimStyle.gradientPlay &&
            comp.hoverProgress > 0.01f) {
          applyVisualState(hoveredWidget, comp);
        }
      }
    }

    ensureAnimTimer(ctx.host);
    return SystemEventResult(false, false);
  }

  SystemEventResult handleMouseButtonDown(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    if (event.mouse.button != 1) {
      return SystemEventResult(false, false);
    }
    const p = PointF(event.mouse.x, event.mouse.y);
    auto hitVw = press.hitTest(ctx, p);
    Widget hitWidget = hitVw.isNull ? null : hitVw.get().widget;
    if (hitWidget !is null && !hitWidget.inputEnabled) {
      hitWidget = null;
    }
    if (press.pressed !is null && press.pressed !is hitWidget) {
      Widget prev = press.end();
      if (auto prevComp = prev.components.get!AnimatedHoverButtonComponent()) {
        prevComp.isPressed = false;
        anim.track(prev);
      }
    }
    if (hitWidget !is null) {
      auto comp = hitWidget.components.get!AnimatedHoverButtonComponent();
      if (comp !is null) {
        comp.isPressed = true;
        press.begin(hitWidget);
        anim.track(hitWidget);
      }
    }
    ensureAnimTimer(ctx.host);
    return SystemEventResult(false, false);
  }

  SystemEventResult handleMouseButtonUp(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    if (event.mouse.button != 1 || press.pressed is null) {
      return SystemEventResult(false, false);
    }

    Widget target = press.end();
    auto comp = target.components.get!AnimatedHoverButtonComponent();
    if (comp !is null) {
      if (!target.inputEnabled) {
        comp.resetToNormal(target);
        anim.remove(target, host);
        return SystemEventResult(false, false);
      }
      comp.isPressed = false;
      anim.track(target);
      ensureAnimTimer(ctx.host);

      const p = PointF(event.mouse.x, event.mouse.y);
      auto hitVw = press.hitTest(ctx, p);
      if (!hitVw.isNull && hitVw.get().widget is target &&
          comp.animConfig.actionEvent.length > 0) {
        emitButtonAction(ctx, target, comp.animConfig.actionEvent);
      }
    }

    return SystemEventResult(false, false);
  }

  SystemEventResult handleWindowMouseLeave(ref WidgetSystemContext ctx) {
    bool changed = false;
    if (hoveredWidget !is null) {
      auto comp = hoveredWidget.components.get!AnimatedHoverButtonComponent();
      if (comp !is null) {
        comp.releaseInteraction();
        anim.track(hoveredWidget);
      }
      hoveredWidget = null;
      changed = true;
    }
    if (press.pressed !is null) {
      Widget prev = press.end();
      auto prevComp = prev.components.get!AnimatedHoverButtonComponent();
      if (prevComp !is null) {
        prevComp.releaseInteraction();
        anim.track(prev);
      }
      changed = true;
    }
    if (changed) {
      ensureAnimTimer(ctx.host);
    }
    return SystemEventResult(false, false);
  }

  void cleanInactiveButtons() {
    anim.activeButtons.removeInvisible((Widget w) {
      auto comp = w.components.get!AnimatedHoverButtonComponent();
      if (comp !is null) {
        comp.resetToNormal(w);
      }
    });
    if (hoveredWidget !is null &&
        (!isEffectivelyVisible(hoveredWidget) || !hoveredWidget.inputEnabled)) {
      auto comp = hoveredWidget.components.get!AnimatedHoverButtonComponent();
      if (comp !is null) {
        comp.resetToNormal(hoveredWidget);
      }
      anim.activeButtons.remove(hoveredWidget);
      hoveredWidget = null;
    }
    if (press.pressed !is null &&
        (!isEffectivelyVisible(press.pressed) || !press.pressed.inputEnabled)) {
      auto comp = press.pressed.components.get!AnimatedHoverButtonComponent();
      if (comp !is null) {
        comp.resetToNormal(press.pressed);
      }
      anim.activeButtons.remove(press.pressed);
      press.end();
    }
    anim.stopIfIdle(host);
  }

  void stepActiveButtons(float dt) {
    anim.step(host, (Widget w) {
      auto comp = w.components.get!AnimatedHoverButtonComponent();
      if (comp is null) {
        return false;
      }
      initColorsIfNeeded(w, comp);
      if (!w.inputEnabled) {
        comp.resetToNormal(w);
        if (hoveredWidget is w) {
          hoveredWidget = null;
        }
        press.forget(w);
        return false;
      }
      return stepComponent(w, comp, dt);
    });
  }

  bool stepComponent(
    Widget w,
    AnimatedHoverButtonComponent comp,
    float dt
  ) {
    bool visualDirty = stepHoverAndPress(comp, dt);

    const bool isGradBusy =
      comp.animConfig.style == HoverAnimConfig.AnimStyle.gradientPlay &&
      (comp.isHovered || comp.hoverPulsePending ||
        comp.hoverProgress > 0.001f);
    if (isGradBusy) {
      comp.gradTimer.update(dt);
      comp.animPhase = comp.gradTimer.map(0.0f, 2.0f * PI);
      visualDirty = true;
    }

    if (visualDirty) {
      applyVisualState(w, comp);
    }

    const bool nextHoverForward = comp.isHovered || comp.hoverPulsePending;
    const bool isHoverBusy =
      !comp.hoverTimer.isAtTarget(nextHoverForward) || comp.hoverPulsePending;
    const bool isPressBusy = !comp.pressTimer.isAtTarget(comp.isPressed);
    return isHoverBusy || isPressBusy || isGradBusy;
  }

  static bool stepHoverAndPress(
    AnimatedHoverButtonComponent comp,
    float dt
  ) {
    bool visualDirty = false;
    if (comp.hoverPulsePending && comp.hoverProgress >= hoverPulsePeak) {
      comp.hoverPulsePending = false;
    }
    const bool hoverForward = comp.isHovered || comp.hoverPulsePending;
    if (!comp.hoverTimer.isAtTarget(hoverForward)) {
      comp.hoverTimer.stepTowards(dt, hoverForward);
      comp.hoverProgress = comp.hoverTimer.progress();
      if (comp.hoverPulsePending && comp.hoverProgress >= hoverPulsePeak) {
        comp.hoverPulsePending = false;
      }
      visualDirty = true;
    }
    if (!comp.pressTimer.isAtTarget(comp.isPressed)) {
      comp.pressTimer.stepTowards(dt, comp.isPressed);
      comp.pressProgress = comp.pressTimer.progress();
      visualDirty = true;
    }
    return visualDirty;
  }

  static void initColorsIfNeeded(
    Widget w,
    AnimatedHoverButtonComponent comp
  ) {
    if (comp.colorsInitialized) {
      return;
    }
    if (w.components.background !is null) {
      comp.normalBg = w.components.background.color;
    }
    if (w.components.border !is null) {
      comp.normalBorder = w.components.border.color;
    }
    comp.colorsInitialized = true;
  }

  static void applyVisualState(
    Widget w,
    AnimatedHoverButtonComponent comp
  ) {
    ColorF targetHoverBg = comp.animConfig.hoverBg;

    if (comp.animConfig.style == HoverAnimConfig.AnimStyle.gradientPlay &&
        comp.hoverProgress > 0.01f) {
      const float wave = (
        sin(comp.animPhase + comp.cursorNormX * PI) + 1.0f
      ) * 0.5f;
      targetHoverBg = lerpColor(
        comp.animConfig.hoverBg,
        comp.animConfig.gradientAccentBg,
        wave
      );
    }

    ColorF currentBg = lerpColor(
      comp.normalBg,
      targetHoverBg,
      comp.hoverProgress
    );

    if (comp.pressProgress > 0.0f) {
      currentBg = lerpColor(
        currentBg,
        comp.animConfig.pressBg,
        comp.pressProgress
      );
    }

    ColorF currentBorder = lerpColor(
      comp.normalBorder,
      comp.animConfig.hoverBorder,
      comp.hoverProgress
    );

    applyBgAndBorderColors(w, currentBg, currentBorder);
  }

  static void updateCursorNorm(
    AnimatedHoverButtonComponent comp,
    in RectF absRect,
    PointF p
  ) {
    if (absRect.width > 0.0f && absRect.height > 0.0f) {
      const PointF norm = normalizedIn(absRect, p);
      comp.cursorNormX = norm.x;
    }
  }

  Widget hoveredWidget = null;
  PressTracker!AnimatedHoverButtonComponent press;
  ButtonAnimDriver anim;
}

// Unit tests for AnimatedHoverButtonComponent, Builder, and WidgetSystem
unittest {
  import yguilib.controls.testing : DummyWidgetSystemHost;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.visible : VisibleWidget;
  import yguilib.controls.tooltip : Tooltip;
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto host = new DummyWidgetSystemHost();
  auto testUi = new UiSystemImpl(null);

  // Test 1: AnimatedHoverButtonBuilder single-widget tree structure
  AnimatedHoverButtonBuilder b;
  auto btn = b
    .text("Action Button")
    .bg(ColorF(0.2f, 0.2f, 0.2f, 1.0f))
    .border(ColorF(0.4f, 0.4f, 0.4f, 1.0f), 1.0f)
    .radius(4.0f)
    .fixedSize(120.0f, 32.0f)
    .action("customAction")
    .build(testUi, null, RectF(10, 10, 120, 32));

  assert(btn !is null);
  assert(btn.inputEnabled);
  assert(btn.components.background !is null);
  assert(btn.components.border !is null);
  assert(btn.components.textLabel !is null);
  assert(btn.components.textLabel.caption == "Action Button");
  assert(btn.components.has!AnimatedHoverButtonComponent());

  auto comp = btn.components.get!AnimatedHoverButtonComponent();
  assert(comp !is null);
  assert(comp.animConfig.actionEvent == "customAction");
  assert(comp.normalBg == ColorF(0.2f, 0.2f, 0.2f, 1.0f));

  // Test 2: AnimatedHoverButtonSystem event handling and lifecycle
  auto sys = new AnimatedHoverButtonSystem();
  sys.onRegister(host);
  assert((sys.phases & SystemPhase.event) != 0);
  assert((sys.phases & SystemPhase.update) == 0);
  assert((sys.phases & SystemPhase.postLayout) != 0);
  assert(sys.animTimerId == invalidTimerId);

  WidgetSystemContext ctx;
  ctx.host = host;
  ctx.visibleWidgets = [
    VisibleWidget(btn, RectF(10, 10, 120, 32), false, RectF.init),
  ];

  // Mouse motion outside button
  auto motionOut = AppEvent(AppEvent.Kind.mouseMotion);
  motionOut.mouse.x = 0.0f;
  motionOut.mouse.y = 0.0f;
  auto resOut = sys.handleEvent(motionOut, ctx);
  assert(!resOut.consumed);
  assert(!resOut.requestUpdateView);
  assert(!comp.isHovered);
  assert(!sys.isAnyAnimating());

  // Mouse motion inside button (btn is at x:10..130, y:10..42)
  auto motionIn = AppEvent(AppEvent.Kind.mouseMotion);
  motionIn.mouse.x = 50.0f;
  motionIn.mouse.y = 20.0f;
  auto resIn = sys.handleEvent(motionIn, ctx);
  assert(!resIn.requestUpdateView);
  assert(comp.isHovered);
  assert(sys.isAnyAnimating());
  assert(host.isTimerActive(sys.animTimerId));

  // Run onTimer(ctx, id, dt) to step animation
  sys.onTimer(ctx, sys.animTimerId, 0.016f);
  assert(comp.hoverProgress > 0.0f);

  // Mouse button down
  auto mouseDown = AppEvent(AppEvent.Kind.mouseButtonDown);
  mouseDown.mouse.x = 50.0f;
  mouseDown.mouse.y = 20.0f;
  mouseDown.mouse.button = 1;
  auto resDown = sys.handleEvent(mouseDown, ctx);
  assert(!resDown.requestUpdateView);
  assert(comp.isPressed);

  // Mouse button up inside button (should trigger actionEvent)
  host.sentEvents = null;
  auto mouseUp = AppEvent(AppEvent.Kind.mouseButtonUp);
  mouseUp.mouse.x = 50.0f;
  mouseUp.mouse.y = 20.0f;
  mouseUp.mouse.button = 1;
  auto resUp = sys.handleEvent(mouseUp, ctx);
  assert(!resUp.requestUpdateView);
  assert(!comp.isPressed);
  assert(host.sentEvents.length == 1);
  assert(host.sentEvents[0].view.eventName == "customAction");
  assert(host.sentEvents[0].view.widget is btn);

  // Mouse leave window
  auto mouseLeave = AppEvent(AppEvent.Kind.windowMouseLeave);
  sys.handleEvent(mouseLeave, ctx);
  assert(!comp.isHovered);

  // Step until animation settles
  foreach (_; 0 .. 50) {
    sys.onTimer(ctx, sys.animTimerId, 0.016f);
  }
  assert(comp.hoverProgress == 0.0f);
  assert(!sys.isAnyAnimating());
  assert(sys.animTimerId == invalidTimerId);

  // Test 3: Gradient play animation and cursor motion tracking
  HoverAnimConfig gradAnim;
  gradAnim.style = HoverAnimConfig.AnimStyle.gradientPlay;
  gradAnim.hoverBg = ColorF(0.2f, 0.4f, 0.8f, 1.0f);
  gradAnim.gradientAccentBg = ColorF(0.1f, 0.9f, 0.8f, 1.0f);

  AnimatedHoverButtonBuilder gb;
  auto gradBtn = gb
    .text("Gradient Button")
    .anim(gradAnim)
    .fixedSize(120.0f, 32.0f)
    .build(testUi, null, RectF(0, 0, 120, 32));

  auto gradComp = gradBtn.components.get!AnimatedHoverButtonComponent();
  assert(gradComp !is null);
  assert(gradComp.animConfig.style == HoverAnimConfig.AnimStyle.gradientPlay);

  ctx.visibleWidgets = [
    VisibleWidget(gradBtn, RectF(0, 0, 120, 32), false, RectF.init),
  ];

  auto gradMotion = AppEvent(AppEvent.Kind.mouseMotion);
  gradMotion.mouse.x = 60.0f;
  gradMotion.mouse.y = 16.0f;
  sys.handleEvent(gradMotion, ctx);
  assert(gradComp.isHovered);
  assert(sys.isAnyAnimating());
  assert(host.isTimerActive(sys.animTimerId));

  sys.onTimer(ctx, sys.animTimerId, 0.016f);
  assert(gradComp.hoverProgress > 0.0f);
  assert(gradComp.animPhase > 0.0f);

  // Test onWidgetReleased
  sys.onWidgetReleased(gradBtn);
  assert(!sys.isAnyAnimating());
  assert(sys.animTimerId == invalidTimerId);

  // Test 4: Sub-frame curved sweep across 3 buttons latches hover pulses
  Widget[3] sweepBtns;
  AnimatedHoverButtonComponent[3] sweepComps;
  VisibleWidget[] sweepVis;
  foreach (i; 0 .. 3) {
    AnimatedHoverButtonBuilder sb;
    const RectF r = RectF(cast(float) (i * 100), 0, 80, 32);
    sweepBtns[i] = sb.fixedSize(80, 32).build(testUi, null, r);
    sweepComps[i] =
      sweepBtns[i].components.get!AnimatedHoverButtonComponent();
    sweepVis ~= VisibleWidget(sweepBtns[i], r, false, RectF.init);
  }
  ctx.visibleWidgets = sweepVis;

  // Sweep across all 3 buttons and exit before any update() tick runs
  float[4] sweepXs = [40.0f, 140.0f, 240.0f, 400.0f];
  foreach (sx; sweepXs) {
    auto ev = AppEvent(AppEvent.Kind.mouseMotion);
    ev.mouse.x = sx;
    ev.mouse.y = 16.0f;
    sys.handleEvent(ev, ctx);
  }
  assert(host.isTimerActive(sys.animTimerId));

  float[3] maxProg = [0.0f, 0.0f, 0.0f];
  foreach (_; 0 .. 60) {
    sys.onTimer(ctx, sys.animTimerId, 0.016f);
    foreach (i; 0 .. 3) {
      if (sweepComps[i].hoverProgress > maxProg[i]) {
        maxProg[i] = sweepComps[i].hoverProgress;
      }
    }
  }
  foreach (i; 0 .. 3) {
    assert(maxProg[i] >= AnimatedHoverButtonSystem.hoverPulsePeak);
    assert(sweepComps[i].hoverProgress == 0.0f);
  }
  assert(!sys.isAnyAnimating());
  assert(sys.animTimerId == invalidTimerId);

  // Test 5: .captionTooltip() attaches Tooltip component
  AnimatedHoverButtonBuilder tb1;
  auto tipBtn = tb1
    .name("tipBtn")
    .text("Fallback Caption")
    .captionTooltip()
    .build(testUi, null, RectF(0, 0, 100, 32));
  assert(tipBtn.components.has!Tooltip());
  assert(
    tipBtn.components.get!Tooltip().resolveText(tipBtn) == "Fallback Caption"
  );

  AnimatedHoverButtonBuilder tb2;
  auto tipBtnCustom = tb2
    .name("tipBtnCustom")
    .text("Short")
    .tooltipText("Explicit Tooltip Hint")
    .build(testUi, null, RectF(0, 0, 100, 32));
  assert(tipBtnCustom.components.has!Tooltip());
  assert(
    tipBtnCustom.components.get!Tooltip().resolveText(tipBtnCustom) ==
      "Explicit Tooltip Hint"
  );
}

// Test 6: inputEnabled, press tracking, cleanInactiveButtons, large-dt pulse
unittest {
  import yguilib.controls.testing : DummyWidgetSystemHost;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.visible : VisibleWidget;

  AppEvent mouseEv(AppEvent.Kind kind, float x, float y) {
    auto ev = AppEvent(kind);
    ev.mouse.x = x;
    ev.mouse.y = y;
    ev.mouse.button = 1;
    return ev;
  }

  auto host = new DummyWidgetSystemHost();
  auto testUi = new UiSystemImpl(null);
  AnimatedHoverButtonBuilder b1;
  auto btn1 = b1.name("h1").action("h1Click")
    .build(testUi, null, RectF(0, 0, 80, 30));
  AnimatedHoverButtonBuilder b2;
  auto btn2 = b2.name("h2").action("h2Click")
    .build(testUi, null, RectF(100, 0, 80, 30));
  auto comp1 = btn1.components.get!AnimatedHoverButtonComponent();
  auto comp2 = btn2.components.get!AnimatedHoverButtonComponent();

  auto sys = new AnimatedHoverButtonSystem();
  sys.onRegister(host);

  WidgetSystemContext ctx;
  ctx.host = host;
  ctx.visibleWidgets = [
    VisibleWidget(btn1, RectF(0, 0, 80, 30), false, RectF.init),
    VisibleWidget(btn2, RectF(100, 0, 80, 30), false, RectF.init),
  ];

  // Disabled button ignores motion/press/release
  btn1.inputEnabled = false;
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseMotion, 40, 15), ctx);
  assert(!comp1.isHovered);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 40, 15), ctx);
  assert(!comp1.isPressed);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonUp, 40, 15), ctx);
  assert(host.sentEvents.length == 0);
  btn1.inputEnabled = true;

  // Large-dt pulse tick reverses back to 0.0f instead of sticking at 1.0f
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseMotion, 40, 15), ctx);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseMotion, 300, 15), ctx);
  assert(!comp1.isHovered && comp1.hoverPulsePending);
  sys.onTimer(ctx, sys.animTimerId, 1.0f);
  assert(!comp1.hoverPulsePending);
  assert(comp1.hoverProgress == 1.0f);
  assert(sys.isAnyAnimating());
  sys.onTimer(ctx, sys.animTimerId, 1.0f);
  assert(comp1.hoverProgress == 0.0f);
  assert(!sys.isAnyAnimating());

  // Drag off and drag back restores isPressed
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseMotion, 40, 15), ctx);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 40, 15), ctx);
  assert(comp1.isPressed);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseMotion, 300, 15), ctx);
  assert(!comp1.isPressed);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseMotion, 40, 15), ctx);
  assert(comp1.isPressed);

  // Second mouseButtonDown on btn2 clears btn1 press
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 140, 15), ctx);
  assert(!comp1.isPressed && comp2.isPressed);
  assert(sys.press.pressed is btn2);

  // windowMouseLeave clears press and hover
  sys.handleEvent(AppEvent(AppEvent.Kind.windowMouseLeave), ctx);
  assert(sys.press.pressed is null);
  assert(!comp2.isPressed && !comp2.isHovered);

  // Settled hovered button reset on hide in postLayout
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseMotion, 40, 15), ctx);
  foreach (_; 0 .. 40) {
    if (sys.animTimerId != invalidTimerId) {
      sys.onTimer(ctx, sys.animTimerId, 0.016f);
    }
  }
  assert(!sys.isAnyAnimating());
  assert(comp1.hoverProgress == 1.0f);
  btn1.visible = false;
  sys.postLayout(ctx);
  assert(comp1.hoverProgress == 0.0f);
  assert(!comp1.isHovered);
}
