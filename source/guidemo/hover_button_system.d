/**
 * hover_button_system.d - Hover button animation system and widget component.
 *
 * ARCHITECTURE OVERVIEW: WIDGET SYSTEM & COMPONENT (ECS-STYLE)
 * -------------------------------------------------------------
 * This module demonstrates an alternative to the View/Controller pattern:
 * an extensible WidgetSystem (AnimatedHoverButtonSystem) processing widgets
 * that have an attached AnimatedHoverButtonComponent.
 *
 * Contrast with HoverButtonController (in hover_button.d):
 * - Controller pattern:
 *     - Requires a 2-widget tree (parent with ViewComponent, child with
 *       MouseEvent).
 *     - Relies on ViewComponent event renaming and event bubbling through
 *       the controller stack.
 *     - Every button must be manually registered with the controller instance
 *       (e.g. controller.addButton(view)).
 * - WidgetSystem pattern:
 *     - Single widget tree node: background, border, text label, and
 *       AnimatedHoverButtonComponent attached directly.
 *     - No manual button registration: the system automatically processes
 *       any visible widget with the component during its pipeline phases.
 *     - Integrated into WidgetSystemPipeline across event, preLayout, and
 *       postLayout phases, driving 60 FPS animations when active and 0% CPU
 *       when idle.
 */
module guidemo.hover_button_system;

import core.time : MonoTime;
import std.algorithm.comparison : clamp, max, min;
import std.math : PI, abs, sin;
import yguilib.events : AppEvent;
import yguilib.events.builder : ViewAppEventBuilder;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.component : Component;
import yguilib.widget.drawing_components : Background, Border, TextLabel;
import yguilib.widget.layout_components : Anchor, Insets, Size;
import yguilib.widget.system : SystemEventResult, SystemPhase, WidgetSystem,
  WidgetSystemContext;
import yguilib.widget.visible : VisibleWidget, VisibleWidgets;

/// Widget construction styling options.
struct HoverButtonConfig {
  string text = "Button";
  ColorF normalBg = ColorF(0.20f, 0.22f, 0.28f, 1.0f);
  ColorF borderColor = ColorF(0.35f, 0.38f, 0.48f, 1.0f);
  ColorF textColor = ColorF(0.95f, 0.95f, 0.95f, 1.0f);
  float cornerRadius = 6.0f;
  float borderWidth = 1.0f;
  float fontSize = 13.0f;
  Insets padding = Insets(6.0f, 14.0f, 6.0f, 14.0f);
  string actionEvent = null;
}

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
final class AnimatedHoverButtonComponent : Component {
  HoverAnimConfig animConfig;
  ColorF normalBg = ColorF(0.20f, 0.22f, 0.28f, 1.0f);
  ColorF normalBorder = ColorF(0.35f, 0.38f, 0.48f, 1.0f);
  bool colorsInitialized = false;
  float hoverProgress = 0.0f;
  float pressProgress = 0.0f;
  float animPhase = 0.0f;
  bool isHovered = false;
  bool isPressed = false;
  float cursorNormX = 0.5f;
  float cursorNormY = 0.5f;

  this(in HoverAnimConfig animConfig = HoverAnimConfig()) {
    this.animConfig = animConfig;
  }
}

/// Fluent builder for constructing animated hover buttons using components.
struct AnimatedHoverButtonBuilder {
  HoverButtonConfig config;
  HoverAnimConfig animConfig;
  Size customSize = null;
  Anchor customAnchor = null;

  ref AnimatedHoverButtonBuilder text(string caption) return {
    config.text = caption;
    return this;
  }

  ref AnimatedHoverButtonBuilder bg(ColorF color) return {
    config.normalBg = color;
    return this;
  }

  ref AnimatedHoverButtonBuilder border(
    ColorF color,
    float width = 1.0f
  ) return {
    config.borderColor = color;
    config.borderWidth = width;
    return this;
  }

  ref AnimatedHoverButtonBuilder radius(float r) return {
    config.cornerRadius = r;
    return this;
  }

  ref AnimatedHoverButtonBuilder padding(
    float vertical,
    float horizontal
  ) return {
    config.padding = Insets(vertical, horizontal);
    return this;
  }

  ref AnimatedHoverButtonBuilder fontSize(float pt) return {
    config.fontSize = pt;
    return this;
  }

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

  ref AnimatedHoverButtonBuilder size(Size sz) return {
    customSize = sz;
    return this;
  }

  ref AnimatedHoverButtonBuilder fixedSize(float w, float h) return {
    customSize = Size.fixed(w, h);
    return this;
  }

  ref AnimatedHoverButtonBuilder autoSize() return {
    customSize = Size.autoSize();
    return this;
  }

  ref AnimatedHoverButtonBuilder anchor(Anchor a) return {
    customAnchor = a;
    return this;
  }

  Widget build(Widget parent, RectF rect) {
    const float initW = rect.width > 0.0f ? rect.width : 100.0f;
    const float initH = rect.height > 0.0f ? rect.height : 36.0f;

    auto b = WidgetBuilder(parent, rect);

    if (customSize !is null) {
      b.size(customSize);
    } else {
      b.fixedSize(initW, initH);
    }
    if (customAnchor !is null) {
      b.anchor(customAnchor);
    }

    b.padding(config.padding);

    if (config.cornerRadius > 0.0f) {
      b.roundBackground(config.normalBg, config.cornerRadius);
    } else {
      b.background(config.normalBg);
    }

    if (config.borderWidth > 0.0f) {
      b.border(
        config.borderColor,
        config.borderWidth,
        config.cornerRadius > 0.0f ? Border.Style.round : Border.Style.rect,
        config.cornerRadius
      );
    }

    b.text(
      config.text,
      config.textColor,
      config.fontSize,
      TextLabel.Alignment.center
    );

    auto comp = new AnimatedHoverButtonComponent(animConfig);
    comp.normalBg = config.normalBg;
    comp.normalBorder = config.borderColor;
    comp.colorsInitialized = true;
    b.component(comp);

    auto w = b.build();
    w.inputEnabled = true;
    return w;
  }
}

/// Convenience helper creating an animated hover button widget.
Widget createAnimatedHoverButton(
  Widget parent,
  RectF rect,
  in HoverButtonConfig config = HoverButtonConfig(),
  in HoverAnimConfig animConfig = HoverAnimConfig()
) {
  AnimatedHoverButtonBuilder b;
  b.config = config;
  b.animConfig = animConfig;
  return b.build(parent, rect);
}

/// Custom WidgetSystem processing widgets with AnimatedHoverButtonComponent.
final class AnimatedHoverButtonSystem : WidgetSystem {
  this(int priority = defaultPriority) nothrow @safe {
    super(priority);
  }

  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.event | SystemPhase.preLayout | SystemPhase.postLayout;
  }

  override @property int timeoutMs() const nothrow @safe {
    return isAnyAnimating() ? 16 : -1;
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
    if (event.kind == AppEvent.Kind.update) {
      return handleUpdateTick();
    }
    return SystemEventResult(false, false, timeoutMs);
  }

  override void preLayout(ref WidgetSystemContext ctx) {
    if (!needsAnimationStep && !isAnyAnimating()) {
      return;
    }
    needsAnimationStep = false;

    const float dt = computeDeltaTime();
    stepActiveButtons(dt);
  }

  override void postLayout(ref WidgetSystemContext ctx) {
    cleanInvisibleButtons();
  }

  bool isAnyAnimating() const nothrow @safe {
    return activeButtons.length > 0;
  }

private:
  SystemEventResult handleMouseMotion(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    const p = PointF(event.mouse.x, event.mouse.y);
    Widget hitWidget = findHitButton(ctx.visibleWidgets, p);

    if (hitWidget !is hoveredWidget) {
      if (hoveredWidget !is null) {
        auto prevComp =
          hoveredWidget.components.get!AnimatedHoverButtonComponent();
        if (prevComp !is null) {
          prevComp.isHovered = false;
          prevComp.isPressed = false;
          trackActiveButton(hoveredWidget);
        }
      }
      hoveredWidget = hitWidget;
      if (hoveredWidget !is null) {
        auto comp = hoveredWidget.components.get!AnimatedHoverButtonComponent();
        if (comp !is null) {
          initColorsIfNeeded(hoveredWidget, comp);
          comp.isHovered = true;
          updateCursorNorm(comp, hoveredWidget, ctx.visibleWidgets, p);
          trackActiveButton(hoveredWidget);
        }
      }
      needsAnimationStep = true;
    } else if (hoveredWidget !is null) {
      auto comp = hoveredWidget.components.get!AnimatedHoverButtonComponent();
      if (comp !is null) {
        updateCursorNorm(comp, hoveredWidget, ctx.visibleWidgets, p);
        if (comp.animConfig.style == HoverAnimConfig.AnimStyle.gradientPlay &&
            comp.hoverProgress > 0.01f) {
          applyVisualState(hoveredWidget, comp);
        }
      }
    }

    const bool anim = isAnyAnimating();
    return SystemEventResult(false, anim, anim ? 16 : -1);
  }

  SystemEventResult handleMouseButtonDown(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    if (event.mouse.button != 1) {
      return SystemEventResult(false, false, timeoutMs);
    }
    const p = PointF(event.mouse.x, event.mouse.y);
    Widget hitWidget = findHitButton(ctx.visibleWidgets, p);
    if (hitWidget !is null) {
      auto comp = hitWidget.components.get!AnimatedHoverButtonComponent();
      if (comp !is null) {
        comp.isPressed = true;
        pressedWidget = hitWidget;
        trackActiveButton(hitWidget);
        needsAnimationStep = true;
        return SystemEventResult(false, true, 16);
      }
    }
    return SystemEventResult(false, false, timeoutMs);
  }

  SystemEventResult handleMouseButtonUp(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    if (event.mouse.button != 1 || pressedWidget is null) {
      return SystemEventResult(false, false, timeoutMs);
    }

    Widget target = pressedWidget;
    pressedWidget = null;

    auto comp = target.components.get!AnimatedHoverButtonComponent();
    if (comp !is null) {
      comp.isPressed = false;
      trackActiveButton(target);
      needsAnimationStep = true;

      const p = PointF(event.mouse.x, event.mouse.y);
      Widget hitWidget = findHitButton(ctx.visibleWidgets, p);
      if (hitWidget is target && comp.animConfig.actionEvent.length > 0) {
        triggerAction(target, comp.animConfig.actionEvent, ctx);
      }
      return SystemEventResult(false, true, 16);
    }

    const bool anim = isAnyAnimating();
    return SystemEventResult(false, anim, anim ? 16 : -1);
  }

  SystemEventResult handleWindowMouseLeave(ref WidgetSystemContext ctx) {
    if (hoveredWidget !is null) {
      auto comp = hoveredWidget.components.get!AnimatedHoverButtonComponent();
      if (comp !is null) {
        comp.isHovered = false;
        comp.isPressed = false;
        trackActiveButton(hoveredWidget);
      }
      hoveredWidget = null;
      needsAnimationStep = true;
    }
    const bool anim = isAnyAnimating();
    return SystemEventResult(false, anim, anim ? 16 : -1);
  }

  SystemEventResult handleUpdateTick() {
    if (isAnyAnimating()) {
      needsAnimationStep = true;
      return SystemEventResult(false, true, 16);
    }
    hasLastTime = false;
    return SystemEventResult(false, false, -1);
  }

  void triggerAction(
    Widget target,
    string actionEvent,
    ref WidgetSystemContext ctx
  ) {
    if (ctx.host is null || actionEvent.length == 0) {
      return;
    }
    auto ev = ViewAppEventBuilder(actionEvent)
      .widget(target)
      .build();
    ctx.host.sendAppEvent(ev);
  }

  void trackActiveButton(Widget w) {
    if (w is null) {
      return;
    }
    foreach (existing; activeButtons) {
      if (existing is w) {
        return;
      }
    }
    activeButtons ~= w;
  }

  void cleanInvisibleButtons() {
    for (ptrdiff_t i = cast(ptrdiff_t) activeButtons.length - 1; i >= 0; --i) {
      Widget w = activeButtons[i];
      if (!isWidgetVisible(w)) {
        auto comp = w.components.get!AnimatedHoverButtonComponent();
        if (comp !is null) {
          comp.isHovered = false;
          comp.isPressed = false;
          comp.hoverProgress = 0.0f;
          comp.pressProgress = 0.0f;
          if (comp.colorsInitialized) {
            w.setBackgroundColor(comp.normalBg);
            w.setBorderColor(comp.normalBorder);
          }
        }
        removeActiveButtonAt(i);
      }
    }
    if (hoveredWidget !is null && !isWidgetVisible(hoveredWidget)) {
      hoveredWidget = null;
    }
    if (pressedWidget !is null && !isWidgetVisible(pressedWidget)) {
      pressedWidget = null;
    }
  }

  void removeActiveButtonAt(size_t index) {
    for (size_t i = index; i < activeButtons.length - 1; ++i) {
      activeButtons[i] = activeButtons[i + 1];
    }
    activeButtons = activeButtons[0 .. $ - 1];
  }

  static bool isWidgetVisible(Widget w) {
    for (Widget curr = w; curr !is null; curr = curr.parent) {
      if (!curr.visible) {
        return false;
      }
    }
    return true;
  }

  void stepActiveButtons(float dt) {
    for (ptrdiff_t i = cast(ptrdiff_t) activeButtons.length - 1; i >= 0; --i) {
      Widget w = activeButtons[i];
      auto comp = w.components.get!AnimatedHoverButtonComponent();
      if (comp is null) {
        removeActiveButtonAt(i);
        continue;
      }

      initColorsIfNeeded(w, comp);
      const bool stillActive = stepComponent(w, comp, dt);
      if (!stillActive) {
        removeActiveButtonAt(i);
      }
    }
  }

  bool stepComponent(
    Widget w,
    AnimatedHoverButtonComponent comp,
    float dt
  ) {
    const float targetHover = comp.isHovered ? 1.0f : 0.0f;
    const float targetPress = comp.isPressed ? 1.0f : 0.0f;
    const float speed = comp.animConfig.fadeSpeed;

    bool visualDirty = false;

    // Hover progress transition
    if (abs(comp.hoverProgress - targetHover) > 0.001f) {
      if (comp.hoverProgress < targetHover) {
        comp.hoverProgress = min(targetHover, comp.hoverProgress + dt * speed);
      } else {
        comp.hoverProgress = max(targetHover, comp.hoverProgress - dt * speed);
      }
      visualDirty = true;
    } else {
      comp.hoverProgress = targetHover;
    }

    // Press progress transition
    if (abs(comp.pressProgress - targetPress) > 0.001f) {
      if (comp.pressProgress < targetPress) {
        comp.pressProgress = min(
          targetPress,
          comp.pressProgress + dt * speed * 3.0f
        );
      } else {
        comp.pressProgress = max(
          targetPress,
          comp.pressProgress - dt * speed * 3.0f
        );
      }
      visualDirty = true;
    } else {
      comp.pressProgress = targetPress;
    }

    // Gradient play wave oscillation
    if (comp.animConfig.style == HoverAnimConfig.AnimStyle.gradientPlay &&
        (comp.isHovered || comp.hoverProgress > 0.001f)) {
      comp.animPhase += dt * 3.5f;
      if (comp.animPhase > 2.0f * PI) {
        comp.animPhase -= 2.0f * PI;
      }
      visualDirty = true;
    }

    if (visualDirty) {
      applyVisualState(w, comp);
    }

    // Check if this component needs further animation steps
    const bool isHoverBusy = abs(comp.hoverProgress - targetHover) > 0.001f;
    const bool isPressBusy = abs(comp.pressProgress - targetPress) > 0.001f;
    const bool isGradBusy =
      comp.animConfig.style == HoverAnimConfig.AnimStyle.gradientPlay &&
      (comp.isHovered || comp.hoverProgress > 0.001f);

    return isHoverBusy || isPressBusy || isGradBusy;
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

    w.setBackgroundColor(currentBg);
    w.setBorderColor(currentBorder);
  }

  static ColorF lerpColor(in ColorF a, in ColorF b, float t) {
    const float f = clamp(t, 0.0f, 1.0f);
    return ColorF(
      a.r + (b.r - a.r) * f,
      a.g + (b.g - a.g) * f,
      a.b + (b.b - a.b) * f,
      a.a + (b.a - a.a) * f
    );
  }

  static Widget findHitButton(VisibleWidgets widgets, PointF p) {
    foreach_reverse (ref VisibleWidget vw; widgets) {
      if (vw.widget.components.has!AnimatedHoverButtonComponent()) {
        if (vw.hasClip && !vw.clipRect.contains(p)) {
          continue;
        }
        if (vw.absRect.contains(p)) {
          return vw.widget;
        }
      }
    }
    return null;
  }

  static void updateCursorNorm(
    AnimatedHoverButtonComponent comp,
    Widget target,
    VisibleWidgets widgets,
    PointF p
  ) {
    foreach (ref VisibleWidget vw; widgets) {
      if (vw.widget is target) {
        if (vw.absRect.width > 0.0f && vw.absRect.height > 0.0f) {
          comp.cursorNormX = clamp(
            (p.x - vw.absRect.x) / vw.absRect.width, 0.0f, 1.0f
          );
          comp.cursorNormY = clamp(
            (p.y - vw.absRect.y) / vw.absRect.height, 0.0f, 1.0f
          );
        }
        return;
      }
    }
  }

  float computeDeltaTime() {
    const MonoTime now = MonoTime.currTime;
    if (!hasLastTime) {
      lastTime = now;
      hasLastTime = true;
      return 0.01667f;
    }
    const long usecs = (now - lastTime).total!"usecs";
    lastTime = now;
    const float dt = cast(float) usecs / 1_000_000.0f;
    return clamp(dt, 0.001f, 0.1f);
  }

  Widget hoveredWidget = null;
  Widget pressedWidget = null;
  Widget[] activeButtons;
  MonoTime lastTime;
  bool hasLastTime = false;
  bool needsAnimationStep = false;
}

// Unit tests for AnimatedHoverButtonComponent, Builder, and WidgetSystem
unittest {
  import yguilib.widget.system : WidgetSystemHost;

  class DummyHost : WidgetSystemHost {
    AppEvent[] sentEvents;
    override void sendAppEvent(AppEvent ev) {
      sentEvents ~= ev;
    }
  }

  auto host = new DummyHost();

  // Test 1: AnimatedHoverButtonBuilder single-widget tree structure
  AnimatedHoverButtonBuilder b;
  auto btn = b
    .text("Action Button")
    .bg(ColorF(0.2f, 0.2f, 0.2f, 1.0f))
    .border(ColorF(0.4f, 0.4f, 0.4f, 1.0f), 1.0f)
    .radius(4.0f)
    .fixedSize(120.0f, 32.0f)
    .action("customAction")
    .build(null, RectF(10, 10, 120, 32));

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
  assert((sys.phases & SystemPhase.event) != 0);
  assert((sys.phases & SystemPhase.preLayout) != 0);
  assert((sys.phases & SystemPhase.postLayout) != 0);
  assert(sys.timeoutMs == -1);

  WidgetSystemContext ctx;
  ctx.host = host;
  ctx.visibleWidgets = [
    VisibleWidget(btn, RectF(10, 10, 120, 32), false, RectF.init),
  ];

  // Mouse motion outside button
  AppEvent motionOut;
  motionOut.kind = AppEvent.Kind.mouseMotion;
  motionOut.mouse.x = 0.0f;
  motionOut.mouse.y = 0.0f;
  auto resOut = sys.handleEvent(motionOut, ctx);
  assert(!resOut.consumed);
  assert(!comp.isHovered);
  assert(!sys.isAnyAnimating());

  // Mouse motion inside button (btn is at x:10..130, y:10..42)
  AppEvent motionIn;
  motionIn.kind = AppEvent.Kind.mouseMotion;
  motionIn.mouse.x = 50.0f;
  motionIn.mouse.y = 20.0f;
  auto resIn = sys.handleEvent(motionIn, ctx);
  assert(resIn.requestUpdateView);
  assert(comp.isHovered);
  assert(sys.isAnyAnimating());
  assert(sys.timeoutMs == 16);

  // Run preLayout to step animation
  sys.preLayout(ctx);
  assert(comp.hoverProgress > 0.0f);

  // Mouse button down
  AppEvent mouseDown;
  mouseDown.kind = AppEvent.Kind.mouseButtonDown;
  mouseDown.mouse.x = 50.0f;
  mouseDown.mouse.y = 20.0f;
  mouseDown.mouse.button = 1;
  auto resDown = sys.handleEvent(mouseDown, ctx);
  assert(resDown.requestUpdateView);
  assert(comp.isPressed);

  // Mouse button up inside button (should trigger actionEvent)
  host.sentEvents = null;
  AppEvent mouseUp;
  mouseUp.kind = AppEvent.Kind.mouseButtonUp;
  mouseUp.mouse.x = 50.0f;
  mouseUp.mouse.y = 20.0f;
  mouseUp.mouse.button = 1;
  auto resUp = sys.handleEvent(mouseUp, ctx);
  assert(resUp.requestUpdateView);
  assert(!comp.isPressed);
  assert(host.sentEvents.length == 1);
  assert(host.sentEvents[0].view.eventName == "customAction");
  assert(host.sentEvents[0].view.widget is btn);

  // Mouse leave window
  AppEvent mouseLeave;
  mouseLeave.kind = AppEvent.Kind.windowMouseLeave;
  sys.handleEvent(mouseLeave, ctx);
  assert(!comp.isHovered);

  // Step until animation settles
  foreach (_; 0 .. 50) {
    sys.preLayout(ctx);
  }
  assert(comp.hoverProgress == 0.0f);
  assert(!sys.isAnyAnimating());
  assert(sys.timeoutMs == -1);

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
    .build(null, RectF(0, 0, 120, 32));

  auto gradComp = gradBtn.components.get!AnimatedHoverButtonComponent();
  assert(gradComp !is null);
  assert(gradComp.animConfig.style == HoverAnimConfig.AnimStyle.gradientPlay);

  ctx.visibleWidgets = [
    VisibleWidget(gradBtn, RectF(0, 0, 120, 32), false, RectF.init),
  ];

  AppEvent gradMotion;
  gradMotion.kind = AppEvent.Kind.mouseMotion;
  gradMotion.mouse.x = 60.0f;
  gradMotion.mouse.y = 16.0f;
  sys.handleEvent(gradMotion, ctx);
  assert(gradComp.isHovered);
  assert(sys.isAnyAnimating());
  assert(sys.timeoutMs == 16);

  sys.preLayout(ctx);
  assert(gradComp.hoverProgress > 0.0f);
  assert(gradComp.animPhase > 0.0f);
}

version (unittest) {
  void main() {
  }
}
