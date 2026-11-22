/**
 * button.d - Plain push button control (component + WidgetSystem).
 *
 * DESIGN
 * ------
 * A button is a single widget (background, border, text label) with an
 * attached `ButtonComponent`. `ButtonSystem` processes every visible widget
 * carrying the component; no per-button registration is needed.
 *
 * - No hover visuals: plain pointer motion without a held press is ignored
 *   and never starts a timer.
 * - Press animation: while pressed, background and border fade from
 *   `ButtonStyle.normal` to `ButtonStyle.pressed` and the caption sinks by
 *   up to `ButtonStyle.sinkPx` whole pixels (top padding grows, bottom
 *   padding shrinks). The fade-in lasts `pressInSec`, the fade-out
 *   `pressOutSec`: the press `AnimationTimer` runs over a normalized
 *   duration of 1.0 and is stepped with `dt / pressInSec` or
 *   `dt / pressOutSec` depending on direction.
 * - Action: with `ButtonTrigger.release` (default), releasing the primary
 *   button over the same button that was pressed sends a view event named
 *   `actionEvent` with `view.widget` set to the button. Dragging off
 *   un-sinks the button and cancels the action unless the pointer is
 *   dragged back before release. With `ButtonTrigger.press` the event is
 *   sent once on the primary button press; release only un-sinks. The
 *   event bubbles through parent ViewComponents (`passViewEvent`), so
 *   composite views can rename it.
 * - Rest colours: `setButtonRestColors` replaces `ButtonStyle.normal` at
 *   runtime (e.g. active/inactive tab), applying it at once when idle.
 * - Disabled state: `Widget.inputEnabled` is the enabled flag; change it
 *   with `Widget.setInputEnabled` (marks the widget dirty). Hittability is
 *   the separate `Widget.handleInput` flag (set by the button builder), so
 *   a disabled button still blocks clicks to widgets behind it. The system
 *   ignores buttons with `inputEnabled == false`, and in `postLayout` syncs
 *   visible buttons whose flag changed: muted `ButtonStyle.disabled`
 *   colours are applied (or normal ones restored) and any press cancelled.
 * - Repeat: a `ButtonTrigger.press` button with `ButtonComponent.repeat`
 *   enabled sends `actionEvent` on press, again after `repeat.delayMs`
 *   (oneShot timer) and then every `repeat.intervalMs` (repeat timer)
 *   until release. While dragged off, the timer keeps running but events
 *   are skipped; dragging back resumes them. Repeat stops on release,
 *   disable, hide, widget release, a press on another button and system
 *   unregister.
 * - Timers: the system runs a 60 FPS repeat timer only while some button
 *   animates and stops it once all settle (0% CPU when idle). The auto-
 *   repeat timer runs only while a repeat button is held.
 */
module yguilib.controls.button;

import std.math : round;
import yguilib.controls.common : WidgetColors, applyBgAndBorderColors,
  applyColors, defaultDisabledColors;
import yguilib.controls.internal.button_support : ActiveWidgets,
  ButtonBaseConfig, ButtonBuilderCommon, PressTracker, emitButtonAction;
import yguilib.events : AppEvent;
import yguilib.render.render_types : ColorF, PointF, RectF, lerpColor;
import yguilib.timercontrol : TimerId, invalidTimerId;
import yguilib.timers : AnimationTimer, AnimationWrapMode, TimerIntervalMs,
  TimerMode;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.component : WidgetComponent;
import yguilib.widget.layout_components : Insets;
import yguilib.widget.system : SystemEventResult, SystemPhase, WidgetSystem,
  WidgetSystemContext, WidgetSystemHost;

/// Widget construction styling options (caption, colours, padding, action).
alias ButtonConfig = ButtonBaseConfig;

/// Press animation and state colours of a `Button`.
struct ButtonStyle {
  /// Resting colours; the builder's bg/border/text settings override them.
  WidgetColors normal = WidgetColors(
    ColorF(0.20f, 0.22f, 0.28f, 1.0f),
    ColorF(0.35f, 0.38f, 0.48f, 1.0f),
    ColorF(0.95f, 0.95f, 0.95f, 1.0f)
  );
  /// Fully pressed colours (text colour is not animated).
  WidgetColors pressed = WidgetColors(
    ColorF(0.12f, 0.13f, 0.17f, 1.0f),
    ColorF(0.55f, 0.60f, 0.75f, 1.0f),
    ColorF(0.95f, 0.95f, 0.95f, 1.0f)
  );
  /// Muted colours shown while the button is disabled.
  WidgetColors disabled = defaultDisabledColors;
  /// Caption sink distance in pixels when fully pressed.
  float sinkPx = 2.0f;
  /// Seconds to animate from normal to fully pressed.
  float pressInSec = 0.06f;
  /// Seconds to animate from fully pressed back to normal.
  float pressOutSec = 0.15f;
}

/// When a button sends its `actionEvent`.
enum ButtonTrigger { release, press }

/// Auto-repeat of the press-trigger action while a button is held.
struct ButtonRepeat {
  bool enabled = false;
  /// Delay before the first repeated event.
  uint delayMs = 400;
  /// Interval between subsequent repeated events.
  uint intervalMs = 80;
}

/// Component marking a widget as a push button handled by `ButtonSystem`.
final class ButtonComponent : WidgetComponent {
  ButtonStyle style;
  /// View event name sent on click; empty disables the event.
  string actionEvent = null;
  /// Whether `actionEvent` is sent on release (default) or on press.
  ButtonTrigger trigger = ButtonTrigger.release;
  /// Auto-repeat of `actionEvent` while held (press trigger only).
  ButtonRepeat repeat;
  /// `inputEnabled` state the current colours were applied for.
  bool appliedEnabled = true;
  /// True while the primary button is held and the pointer is over it.
  bool isPressed = false;
  /// Press animation progress in [0..1].
  float pressProgress = 0.0f;
  /// Normalized (duration 1.0) press timer; see module comment.
  AnimationTimer pressTimer;
  /// Padding of the unpressed button.
  Insets basePadding;
  /// Last applied whole-pixel caption sink.
  int appliedSink = 0;

  this() {
    pressTimer.start(1.0f, AnimationWrapMode.once);
    pressTimer.setPause(true);
  }

  /// Returns the resting colours for enabled state `enabled`.
  WidgetColors restColors(bool enabled) const {
    return enabled ? style.normal : style.disabled;
  }

  /// Cancels the press, restores base padding and resting colours of `w`
  /// for its current `inputEnabled` state.
  void resetPress(Widget w) {
    assert(w !is null, "w must not be null");
    isPressed = false;
    pressTimer.stop();
    pressProgress = 0.0f;
    applySink(w, 0);
    appliedEnabled = w.inputEnabled;
    applyColors(w, restColors(appliedEnabled));
  }

  /// Applies normal/disabled colours and cancels any press when
  /// `w.inputEnabled` differs from `appliedEnabled`. Returns true if synced.
  bool syncEnabled(Widget w) {
    assert(w !is null, "w must not be null");
    if (w.inputEnabled == appliedEnabled) {
      return false;
    }
    resetPress(w);
    return true;
  }

  /// Applies a caption sink of `sink` whole pixels to `w` when it changed.
  void applySink(Widget w, int sink) {
    assert(w !is null, "w must not be null");
    if (sink == appliedSink) {
      return;
    }
    appliedSink = sink;
    if (w.components.size is null) {
      return;
    }
    Insets p = basePadding;
    p.top += sink;
    p.bottom = p.bottom - sink > 0.0f ? p.bottom - sink : 0.0f;
    w.components.size.padding = p;
    w.update(WidgetUpdateScope.layout);
  }
}

/// Fluent builder for push buttons.
struct ButtonBuilder {
  mixin ButtonBuilderCommon;
  ButtonStyle buttonStyle;
  bool isEnabled = true;
  bool isVisible = true;
  ButtonTrigger buttonTrigger = ButtonTrigger.release;
  ButtonRepeat buttonRepeat;

  /// Sets the view event name sent on click.
  ref ButtonBuilder action(string eventName) return {
    config.actionEvent = eventName;
    return this;
  }

  /// Sets the press style. Its `normal` colours become the builder's
  /// bg/border/text; later `bg()`/`border()` calls override them.
  ref ButtonBuilder style(in ButtonStyle s) return {
    buttonStyle = s;
    config.normalBg = s.normal.bg;
    config.borderColor = s.normal.border;
    config.textColor = s.normal.text;
    return this;
  }

  /// Sets the fully pressed background and border colours.
  ref ButtonBuilder pressedColors(ColorF bg, ColorF border) return {
    buttonStyle.pressed.bg = bg;
    buttonStyle.pressed.border = border;
    return this;
  }

  /// Sets the colours shown while the button is disabled.
  ref ButtonBuilder disabledColors(in WidgetColors c) return {
    buttonStyle.disabled = c;
    return this;
  }

  /// Sets the caption sink distance in pixels when fully pressed.
  ref ButtonBuilder sink(float px) return {
    buttonStyle.sinkPx = px;
    return this;
  }

  /// Sets when the action event is sent (release by default).
  ref ButtonBuilder trigger(ButtonTrigger t) return {
    buttonTrigger = t;
    return this;
  }

  /// Enables auto-repeat with `delayMs` before the first repeated event
  /// and `intervalMs` between later ones (needs `ButtonTrigger.press`).
  ref ButtonBuilder repeatWithTiming(uint delayMs, uint intervalMs) return {
    buttonRepeat = ButtonRepeat(true, delayMs, intervalMs);
    return this;
  }

  /// Sets the auto-repeat settings; enabled needs `ButtonTrigger.press`.
  ref ButtonBuilder repeat(in ButtonRepeat r) return {
    buttonRepeat = r;
    return this;
  }

  /// Sets the initial enabled state (`Widget.inputEnabled`).
  ref ButtonBuilder enabled(bool on) return {
    isEnabled = on;
    return this;
  }

  /// Sets the initial visibility (`Widget.visible`).
  ref ButtonBuilder visible(bool on) return {
    isVisible = on;
    return this;
  }

  /// Builds the button widget; `parent` may be null.
  Widget build(UiSystem ui, Widget parent, RectF rect) {
    assert(
      !buttonRepeat.enabled || buttonTrigger == ButtonTrigger.press,
      "repeat requires ButtonTrigger.press"
    );
    auto b = makeButtonBase(ui, parent, rect, "button");
    auto comp = new ButtonComponent();
    comp.style = buttonStyle;
    comp.style.normal = WidgetColors(
      config.normalBg,
      config.borderColor,
      config.textColor
    );
    comp.actionEvent = config.actionEvent;
    comp.trigger = buttonTrigger;
    comp.repeat = buttonRepeat;
    comp.basePadding = config.padding;
    comp.appliedEnabled = isEnabled;
    b.component(comp);
    if (!isEnabled) {
      b.inputEnabled(false);
    }
    if (!isVisible) {
      b.visible(false);
    }
    Widget w = b.build();
    if (!isEnabled) {
      applyColors(w, comp.style.disabled);
    }
    return w;
  }
}

/// Creates a push button; `config` colours override `style.normal`.
/// `parent` may be null.
Widget createButton(
  UiSystem ui,
  Widget parent,
  RectF rect,
  in ButtonConfig config,
  in ButtonStyle style
) {
  ButtonBuilder b;
  b.buttonStyle = style;
  b.config = config;
  return b.build(ui, parent, rect);
}

/// Sets the resting (normal) colours of button `w` (must carry a
/// ButtonComponent). Applies them at once when enabled and idle;
/// a running press animation lerps from the new colours.
void setButtonRestColors(Widget w, in WidgetColors c) {
  assert(w !is null, "w must not be null");
  auto comp = w.components.get!ButtonComponent();
  assert(comp !is null, "w must carry a ButtonComponent");
  comp.style.normal = c;
  if (!w.inputEnabled) {
    // Disabled colours stay; `syncEnabled` restores the new normal ones.
    return;
  }
  if (comp.pressProgress == 0.0f) {
    applyColors(w, c);
  } else {
    // Text is not animated; bg/border follow on the next press step.
    w.setTextColor(c.text);
  }
}

/// WidgetSystem driving press animation and click events of buttons.
final class ButtonSystem : WidgetSystem {
  this() nothrow @safe {
  }

  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.event | SystemPhase.postLayout;
  }

  override void onRegister(WidgetSystemHost newHost) {
    if (host !is null && host !is newHost) {
      stopAnimTimer();
      stopRepeat();
    }
    super.onRegister(newHost);
    if (newHost !is null) {
      ensureAnimTimer(newHost);
    }
  }

  override void onUnregister() {
    stopAnimTimer();
    stopRepeat();
    super.onUnregister();
  }

  override SystemEventResult handleEvent(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    switch (event.kind) {
    case AppEvent.Kind.mouseButtonDown:
      handleMouseButtonDown(event, ctx);
      break;
    case AppEvent.Kind.mouseMotion:
      handleMouseMotion(event, ctx);
      break;
    case AppEvent.Kind.mouseButtonUp:
      handleMouseButtonUp(event, ctx);
      break;
    case AppEvent.Kind.windowMouseLeave:
      handleWindowMouseLeave(ctx);
      break;
    default:
      break;
    }
    return SystemEventResult(false, false);
  }

  override void onTimer(ref WidgetSystemContext ctx, TimerId id, float dt) {
    if (id != invalidTimerId && id == repeatTimerId) {
      onRepeatTimer(ctx);
      return;
    }
    stepActiveButtons(dt);
    if (!isAnyAnimating()) {
      stopAnimTimer();
    }
  }

  override void postLayout(ref WidgetSystemContext ctx) {
    syncEnabledStates(ctx);
    activeButtons.removeInvisible((Widget w) {
      auto comp = w.components.get!ButtonComponent();
      if (comp !is null) {
        comp.resetPress(w);
      }
    });
    const bool hadPress = press.pressed !is null;
    press.forgetInvisible();
    if (hadPress && press.pressed is null) {
      stopRepeat();
    }
    if (!isAnyAnimating()) {
      stopAnimTimer();
    }
  }

  override void onWidgetReleased(Widget w) {
    if (w is null) {
      return;
    }
    activeButtons.remove(w);
    if (press.pressed is w) {
      stopRepeat();
    }
    press.forget(w);
    if (!isAnyAnimating()) {
      stopAnimTimer();
    }
  }

  /// Returns true while some button press animation is running.
  bool isAnyAnimating() const nothrow @safe {
    return !activeButtons.empty;
  }

private:
  void ensureAnimTimer(WidgetSystemHost fallbackHost) {
    if (host is null && fallbackHost !is null) {
      host = fallbackHost;
    }
    if (animTimerId == invalidTimerId && isAnyAnimating() && host !is null) {
      animTimerId = startTimer(TimerIntervalMs.fps60, TimerMode.repeat);
    }
  }

  void stopAnimTimer() {
    stopTimer(animTimerId);
  }

  /// Starts the oneShot delay timer of `comp`'s auto-repeat (restarting).
  void startRepeat(ButtonComponent comp) {
    stopRepeat();
    if (host is null) {
      return;
    }
    repeatTimerId = startTimer(comp.repeat.delayMs, TimerMode.oneShot);
    repeatInDelay = true;
  }

  void stopRepeat() {
    stopTimer(repeatTimerId);
    repeatInDelay = false;
  }

  /// Handles the auto-repeat timer: after the delay switches to the
  /// interval timer; emits the action while the pointer is over the button.
  void onRepeatTimer(ref WidgetSystemContext ctx) {
    auto comp = pressedComponent();
    if (comp is null) {
      stopRepeat();
      return;
    }
    if (repeatInDelay) {
      // The oneShot delay timer has expired: no stop needed.
      repeatTimerId = startTimer(comp.repeat.intervalMs, TimerMode.repeat);
      repeatInDelay = false;
    }
    if (comp.isPressed) {
      emitButtonAction(ctx, press.pressed, comp.actionEvent);
    }
  }

  /// Applies disabled/normal colours to visible buttons whose
  /// `inputEnabled` changed since their colours were last applied.
  static void syncEnabledStates(ref WidgetSystemContext ctx) {
    foreach (ref vw; ctx.visibleWidgets) {
      if (vw.widget is null) {
        continue;
      }
      if (auto comp = vw.widget.components.get!ButtonComponent()) {
        comp.syncEnabled(vw.widget);
      }
    }
  }

  /// Returns the pressed widget's enabled component, or null (forgetting
  /// a press whose button got disabled or lost its component).
  ButtonComponent pressedComponent() {
    if (press.pressed is null) {
      return null;
    }
    auto comp = press.pressed.components.get!ButtonComponent();
    if (comp is null || !press.pressed.inputEnabled) {
      press.end();
      stopRepeat();
      return null;
    }
    return comp;
  }

  void handleMouseButtonDown(in AppEvent event, ref WidgetSystemContext ctx) {
    if (event.mouse.button != 1) {
      return;
    }
    const p = PointF(event.mouse.x, event.mouse.y);
    Widget hit = press.hitTest(ctx, p);
    if (hit is null) {
      return;
    }
    auto comp = hit.components.get!ButtonComponent();
    if (comp is null || !hit.inputEnabled) {
      return;
    }
    comp.isPressed = true;
    press.begin(hit);
    setActive(hit, ctx.host);
    if (comp.trigger == ButtonTrigger.press) {
      emitButtonAction(ctx, hit, comp.actionEvent);
    }
    if (comp.trigger == ButtonTrigger.press && comp.repeat.enabled) {
      startRepeat(comp);
    } else {
      stopRepeat();
    }
  }

  void handleMouseMotion(in AppEvent event, ref WidgetSystemContext ctx) {
    auto comp = pressedComponent();
    if (comp is null) {
      return;
    }
    const p = PointF(event.mouse.x, event.mouse.y);
    const bool over = press.hitTest(ctx, p) is press.pressed;
    if (over != comp.isPressed) {
      comp.isPressed = over;
      setActive(press.pressed, ctx.host);
    }
  }

  void handleMouseButtonUp(in AppEvent event, ref WidgetSystemContext ctx) {
    if (event.mouse.button != 1) {
      return;
    }
    auto comp = pressedComponent();
    if (comp is null) {
      return;
    }
    Widget target = press.end();
    stopRepeat();
    comp.isPressed = false;
    setActive(target, ctx.host);

    if (comp.trigger != ButtonTrigger.release) {
      return;
    }
    const p = PointF(event.mouse.x, event.mouse.y);
    if (press.hitTest(ctx, p) is target) {
      emitButtonAction(ctx, target, comp.actionEvent);
    }
  }

  void handleWindowMouseLeave(ref WidgetSystemContext ctx) {
    auto comp = pressedComponent();
    if (comp is null || !comp.isPressed) {
      return;
    }
    comp.isPressed = false;
    setActive(press.pressed, ctx.host);
  }

  void setActive(Widget w, WidgetSystemHost fallbackHost) {
    activeButtons.track(w);
    ensureAnimTimer(fallbackHost);
  }

  void stepActiveButtons(float dt) {
    for (ptrdiff_t i = cast(ptrdiff_t) activeButtons.length - 1; i >= 0; --i) {
      Widget w = activeButtons[i];
      auto comp = w.components.get!ButtonComponent();
      if (comp is null || !w.inputEnabled || !stepComponent(w, comp, dt)) {
        activeButtons.removeAt(cast(size_t) i);
      }
    }
  }

  /// Steps the press animation of `w`; returns true while still animating.
  static bool stepComponent(Widget w, ButtonComponent comp, float dt) {
    const bool forward = comp.isPressed;
    if (comp.pressTimer.isAtTarget(forward)) {
      return false;
    }
    const float sec = forward
      ? comp.style.pressInSec
      : comp.style.pressOutSec;
    // Normalized duration 1.0: non-positive durations settle at once.
    const float step = sec > 0.0f ? dt / sec : 1.0f;
    comp.pressTimer.stepTowards(step, forward);
    comp.pressProgress = comp.pressTimer.getProgress();
    applyPressVisuals(w, comp);
    return !comp.pressTimer.isAtTarget(forward);
  }

  static void applyPressVisuals(Widget w, ButtonComponent comp) {
    const float t = comp.pressProgress;
    applyBgAndBorderColors(
      w,
      lerpColor(comp.style.normal.bg, comp.style.pressed.bg, t),
      lerpColor(comp.style.normal.border, comp.style.pressed.border, t)
    );
    comp.applySink(w, cast(int) round(t * comp.style.sinkPx));
  }

  PressTracker!ButtonComponent press;
  ActiveWidgets activeButtons;
  TimerId animTimerId = invalidTimerId;
  TimerId repeatTimerId = invalidTimerId;
  bool repeatInDelay = false;
}

// Unit tests for ButtonBuilder, enabled state, and ButtonSystem
unittest {
  import yguilib.controls.testing : DummyWidgetSystemHost;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import std.math : isClose;
  import yguilib.widget.visible : VisibleWidget;

  bool colorClose(ColorF a, ColorF b) {
    return isClose(a.r, b.r) && isClose(a.g, b.g) && isClose(a.b, b.b) &&
      isClose(a.a, b.a);
  }

  auto host = new DummyWidgetSystemHost();
  auto testUi = new UiSystemImpl(null);

  AppEvent mouseEv(AppEvent.Kind kind, float x, float y) {
    AppEvent ev;
    ev.kind = kind;
    ev.mouse.x = x;
    ev.mouse.y = y;
    ev.mouse.button = 1;
    return ev;
  }

  // Builder tree and defaults
  ButtonBuilder b;
  auto btn = b
    .text("OK")
    .bg(ColorF(0.3f, 0.3f, 0.3f, 1.0f))
    .fixedSize(100.0f, 30.0f)
    .action("okClicked")
    .build(testUi, null, RectF(10, 10, 100, 30));
  assert(btn !is null);
  assert(btn.name == "button");
  assert(btn.inputEnabled);
  assert(btn.components.textLabel.caption == "OK");
  auto comp = btn.components.get!ButtonComponent();
  assert(comp !is null);
  assert(comp.appliedEnabled);
  assert(comp.actionEvent == "okClicked");
  assert(comp.style.normal.bg == ColorF(0.3f, 0.3f, 0.3f, 1.0f));
  assert(comp.style.normal.border == ButtonConfig.init.borderColor);
  assert(comp.basePadding == ButtonConfig.init.padding);
  assert(comp.style.sinkPx == 2.0f);
  assert(btn.components.background.color == comp.style.normal.bg);

  auto sys = new ButtonSystem();
  sys.onRegister(host);
  assert((sys.phases & SystemPhase.event) != 0);
  assert((sys.phases & SystemPhase.postLayout) != 0);
  assert((sys.phases & SystemPhase.update) == 0);
  assert(sys.animTimerId == invalidTimerId);

  WidgetSystemContext ctx;
  ctx.host = host;
  ctx.visibleWidgets = [
    VisibleWidget(btn, RectF(10, 10, 100, 30), false, RectF.init),
  ];
  const Insets base = comp.basePadding;

  // Hover (motion without press) starts no timer
  auto res = sys.handleEvent(
    mouseEv(AppEvent.Kind.mouseMotion, 50, 20), ctx
  );
  assert(!res.consumed && !res.requestUpdateView);
  assert(!sys.isAnyAnimating());
  assert(sys.animTimerId == invalidTimerId);

  // Press -> timer active, progress and sink grow, padding shifts
  res = sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 50, 20), ctx);
  assert(!res.consumed);
  assert(comp.isPressed);
  assert(host.isTimerActive(sys.animTimerId));
  foreach (_; 0 .. 10) {
    sys.onTimer(ctx, 1, 0.016f);
  }
  assert(comp.pressProgress == 1.0f);
  assert(comp.appliedSink == 2);
  assert(btn.components.size.padding.top == base.top + 2.0f);
  assert(btn.components.size.padding.bottom == base.bottom - 2.0f);
  assert(colorClose(btn.components.background.color, comp.style.pressed.bg));
  // Fully pressed and held: settled, timer stopped
  assert(!sys.isAnyAnimating());
  assert(sys.animTimerId == invalidTimerId);

  // Release inside -> exactly one event
  host.sentEvents = null;
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonUp, 50, 20), ctx);
  assert(!comp.isPressed);
  assert(host.sentEvents.length == 1);
  assert(host.sentEvents[0].kind == AppEvent.Kind.view);
  assert(host.sentEvents[0].view.eventName == "okClicked");
  assert(host.sentEvents[0].view.widget is btn);
  assert(host.isTimerActive(sys.animTimerId));
  foreach (_; 0 .. 20) {
    sys.onTimer(ctx, 1, 0.016f);
  }
  assert(comp.pressProgress == 0.0f && comp.appliedSink == 0);
  assert(btn.components.size.padding == base);
  assert(btn.components.background.color == comp.style.normal.bg);
  assert(!sys.isAnyAnimating());
  assert(sys.animTimerId == invalidTimerId);

  // Press, drag off (un-sinks), drag back (re-sinks), drag off, release
  host.sentEvents = null;
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 50, 20), ctx);
  sys.onTimer(ctx, 1, 0.016f);
  assert(comp.pressProgress > 0.0f);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseMotion, 300, 20), ctx);
  assert(!comp.isPressed);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseMotion, 60, 20), ctx);
  assert(comp.isPressed);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseMotion, 300, 20), ctx);
  assert(!comp.isPressed);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonUp, 300, 20), ctx);
  assert(host.sentEvents.length == 0);
  foreach (_; 0 .. 20) {
    sys.onTimer(ctx, 1, 0.016f);
  }
  assert(comp.pressProgress == 0.0f);
  assert(btn.components.size.padding == base);
  assert(btn.components.background.color == comp.style.normal.bg);
  assert(sys.animTimerId == invalidTimerId);

  // Window mouse leave un-presses visually, release still cancels
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 50, 20), ctx);
  AppEvent leave;
  leave.kind = AppEvent.Kind.windowMouseLeave;
  sys.handleEvent(leave, ctx);
  assert(!comp.isPressed);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonUp, 300, 20), ctx);
  assert(host.sentEvents.length == 0);
  foreach (_; 0 .. 20) {
    sys.onTimer(ctx, 1, 0.016f);
  }
  assert(sys.animTimerId == invalidTimerId);

  // setInputEnabled(false) mid-press: pressed button is ignored at once,
  // postLayout applies muted colours and cancels the press
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 50, 20), ctx);
  sys.onTimer(ctx, 1, 0.016f);
  assert(comp.appliedSink > 0);
  assert(btn.setInputEnabled(false));
  assert(!btn.setInputEnabled(false));
  sys.onTimer(ctx, 1, 0.016f);
  assert(!sys.isAnyAnimating());
  sys.postLayout(ctx);
  assert(!comp.appliedEnabled);
  assert(comp.pressProgress == 0.0f && !comp.isPressed);
  assert(btn.components.size.padding == base);
  assert(btn.components.background.color == comp.style.disabled.bg);
  assert(btn.components.textLabel.color == comp.style.disabled.text);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonUp, 50, 20), ctx);
  assert(host.sentEvents.length == 0);
  sys.onTimer(ctx, 1, 0.016f);
  assert(!sys.isAnyAnimating());
  assert(sys.animTimerId == invalidTimerId);

  // Press on disabled button is ignored
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 50, 20), ctx);
  assert(!comp.isPressed && !sys.isAnyAnimating());
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonUp, 50, 20), ctx);
  assert(host.sentEvents.length == 0);

  // Re-enable restores normal colours on the next postLayout
  assert(btn.setInputEnabled(true));
  sys.postLayout(ctx);
  assert(comp.appliedEnabled);
  assert(btn.components.background.color == comp.style.normal.bg);
  assert(btn.components.border.color == comp.style.normal.border);
  assert(btn.components.textLabel.color == comp.style.normal.text);

  // Builder-disabled button and null-safety
  ButtonBuilder db;
  auto dis = db.enabled(false).action("never")
    .build(testUi, null, RectF(200, 10, 100, 30));
  auto disComp = dis.components.get!ButtonComponent();
  assert(!dis.inputEnabled && !disComp.appliedEnabled);
  assert(dis.components.background.color == disComp.style.disabled.bg);
  assert(dis.components.textLabel.color == disComp.style.disabled.text);
  ctx.visibleWidgets = [
    VisibleWidget(dis, RectF(200, 10, 100, 30), false, RectF.init),
  ];
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 250, 20), ctx);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonUp, 250, 20), ctx);
  assert(host.sentEvents.length == 0);
  // postLayout keeps the builder-disabled colours (already in sync)
  sys.postLayout(ctx);
  assert(dis.components.background.color == disComp.style.disabled.bg);

  // Style/pressedColors and createButton convenience
  ButtonStyle st;
  st.normal.bg = ColorF(0.5f, 0.1f, 0.1f, 1.0f);
  ButtonBuilder sb;
  auto styled = sb.style(st)
    .pressedColors(ColorF(0.1f, 0.1f, 0.1f, 1.0f), ColorF(1, 1, 1, 1))
    .build(testUi, null, RectF(0, 0, 80, 30));
  auto stComp = styled.components.get!ButtonComponent();
  assert(stComp.style.normal.bg == ColorF(0.5f, 0.1f, 0.1f, 1.0f));
  assert(stComp.style.pressed.bg == ColorF(0.1f, 0.1f, 0.1f, 1.0f));
  ButtonConfig cfg;
  cfg.text = "Created";
  cfg.actionEvent = "created";
  auto created = createButton(testUi, null, RectF(0, 0, 80, 30), cfg, st);
  auto crComp = created.components.get!ButtonComponent();
  assert(created.components.textLabel.caption == "Created");
  assert(crComp.actionEvent == "created");
  assert(crComp.style.normal.bg == cfg.normalBg);

  // onWidgetReleased cleanup stops timer
  ctx.visibleWidgets = [
    VisibleWidget(btn, RectF(10, 10, 100, 30), false, RectF.init),
  ];
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 50, 20), ctx);
  assert(host.isTimerActive(sys.animTimerId));
  sys.onWidgetReleased(btn);
  assert(!sys.isAnyAnimating());
  assert(sys.animTimerId == invalidTimerId);
  assert(sys.press.pressed is null);

  // postLayout resets and forgets invisible buttons
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 50, 20), ctx);
  sys.onTimer(ctx, 1, 0.016f);
  btn.visible = false;
  sys.postLayout(ctx);
  assert(!sys.isAnyAnimating());
  assert(sys.press.pressed is null);
  assert(comp.pressProgress == 0.0f);
  assert(btn.components.size.padding == base);
  assert(sys.animTimerId == invalidTimerId);
  sys.onUnregister();
}

// Unit tests for ButtonTrigger.press, setButtonRestColors, builder setters
// and view-event routing through parent ViewComponents
unittest {
  import yguilib.controls.testing : DummyWidgetSystemHost;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : ViewComponent;
  import yguilib.widget.visible : VisibleWidget;

  auto host = new DummyWidgetSystemHost();
  auto testUi = new UiSystemImpl(null);

  AppEvent mouseEv(AppEvent.Kind kind, float x, float y) {
    AppEvent ev;
    ev.kind = kind;
    ev.mouse.x = x;
    ev.mouse.y = y;
    ev.mouse.button = 1;
    return ev;
  }

  void settle(ButtonSystem sys, ref WidgetSystemContext ctx) {
    foreach (_; 0 .. 30) {
      sys.onTimer(ctx, 1, 0.016f);
    }
  }

  // Builder setters: trigger, sink, disabledColors, visible
  const WidgetColors dimmed = WidgetColors(
    ColorF(0.1f, 0.1f, 0.1f, 1.0f),
    ColorF(0.2f, 0.2f, 0.2f, 1.0f),
    ColorF(0.3f, 0.3f, 0.3f, 1.0f)
  );
  ButtonBuilder b;
  auto btn = b
    .text("Tab")
    .action("tabPressed")
    .trigger(ButtonTrigger.press)
    .sink(1.0f)
    .disabledColors(dimmed)
    .build(testUi, null, RectF(0, 0, 80, 30));
  auto comp = btn.components.get!ButtonComponent();
  assert(comp.trigger == ButtonTrigger.press);
  assert(comp.style.sinkPx == 1.0f);
  assert(comp.style.disabled == dimmed);
  assert(btn.visible);
  ButtonBuilder hb;
  auto hidden = hb.visible(false).build(testUi, null, RectF(0, 0, 80, 30));
  assert(!hidden.visible);
  ButtonBuilder rb;
  auto relBtn = rb.build(testUi, null, RectF(0, 0, 80, 30));
  assert(relBtn.components.get!ButtonComponent().trigger ==
    ButtonTrigger.release);

  auto sys = new ButtonSystem();
  sys.onRegister(host);
  WidgetSystemContext ctx;
  ctx.host = host;
  ctx.visibleWidgets = [
    VisibleWidget(btn, RectF(0, 0, 80, 30), false, RectF.init),
  ];

  // Press trigger: one event on mouseDown, none on mouseUp
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 40, 15), ctx);
  assert(host.sentEvents.length == 1);
  assert(host.sentEvents[0].kind == AppEvent.Kind.view);
  assert(host.sentEvents[0].view.eventName == "tabPressed");
  assert(host.sentEvents[0].view.widget is btn);
  assert(comp.isPressed);
  assert(host.isTimerActive(sys.animTimerId));
  settle(sys, ctx);
  assert(comp.pressProgress == 1.0f && comp.appliedSink == 1);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonUp, 40, 15), ctx);
  assert(host.sentEvents.length == 1);
  assert(!comp.isPressed);
  assert(host.isTimerActive(sys.animTimerId));
  settle(sys, ctx);
  assert(comp.pressProgress == 0.0f && comp.appliedSink == 0);
  assert(btn.components.background.color == comp.style.normal.bg);
  assert(!sys.isAnyAnimating());
  assert(sys.animTimerId == invalidTimerId);

  // setButtonRestColors while idle applies at once
  const WidgetColors active = WidgetColors(
    ColorF(0.4f, 0.5f, 0.6f, 1.0f),
    ColorF(0.7f, 0.7f, 0.7f, 1.0f),
    ColorF(1.0f, 1.0f, 0.0f, 1.0f)
  );
  setButtonRestColors(btn, active);
  assert(comp.style.normal == active);
  assert(btn.components.background.color == active.bg);
  assert(btn.components.border.color == active.border);
  assert(btn.components.textLabel.color == active.text);

  // Mid-press: normal updated, background lerps to new normal on settle
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 40, 15), ctx);
  sys.onTimer(ctx, 1, 0.016f);
  assert(comp.pressProgress > 0.0f);
  const WidgetColors inactive = WidgetColors(
    ColorF(0.25f, 0.25f, 0.25f, 1.0f),
    ColorF(0.3f, 0.3f, 0.3f, 1.0f),
    ColorF(0.8f, 0.8f, 0.8f, 1.0f)
  );
  setButtonRestColors(btn, inactive);
  assert(comp.style.normal == inactive);
  assert(btn.components.background.color != inactive.bg);
  assert(btn.components.textLabel.color == inactive.text);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonUp, 40, 15), ctx);
  settle(sys, ctx);
  assert(comp.pressProgress == 0.0f);
  assert(btn.components.background.color == inactive.bg);
  assert(btn.components.border.color == inactive.border);
  assert(sys.animTimerId == invalidTimerId);

  // Disabled: rest colours are stored, disabled colours stay visible
  assert(btn.setInputEnabled(false));
  sys.postLayout(ctx);
  assert(btn.components.background.color == dimmed.bg);
  setButtonRestColors(btn, active);
  assert(comp.style.normal == active);
  assert(btn.components.background.color == dimmed.bg);
  assert(btn.components.textLabel.color == dimmed.text);
  assert(btn.setInputEnabled(true));
  sys.postLayout(ctx);
  assert(btn.components.background.color == active.bg);

  // Routing: parent ViewComponent renames the action event
  auto viewRoot = testUi.makeWidget();
  viewRoot.name = "viewRoot";
  viewRoot.components.view = new ViewComponent;
  viewRoot.components.view.renameEvents["clicked"] = "renamed";
  ButtonBuilder cb;
  auto child = cb.action("clicked")
    .build(testUi, viewRoot, RectF(0, 0, 80, 30));
  viewRoot.update(WidgetUpdateScope.parentView);
  assert(child.parentView is viewRoot);
  ctx.visibleWidgets = [
    VisibleWidget(child, RectF(0, 0, 80, 30), false, RectF.init),
  ];
  host.sentEvents = null;
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 40, 15), ctx);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonUp, 40, 15), ctx);
  assert(host.sentEvents.length == 1);
  assert(host.sentEvents[0].view.eventName == "renamed");
  assert(host.sentEvents[0].view.widget is child);
  assert(host.sentEvents[0].view.viewWidget is viewRoot);
  settle(sys, ctx);
  sys.onUnregister();
}

// Unit tests for ButtonRepeat: builder, delay/interval timeline, drag-off
// skip and stop conditions (release, disable, widget release, hide)
unittest {
  import yguilib.controls.testing : DummyWidgetSystemHost;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.visible : VisibleWidget;

  auto host = new DummyWidgetSystemHost();
  auto testUi = new UiSystemImpl(null);

  AppEvent mouseEv(AppEvent.Kind kind, float x, float y) {
    AppEvent ev;
    ev.kind = kind;
    ev.mouse.x = x;
    ev.mouse.y = y;
    ev.mouse.button = 1;
    return ev;
  }

  // Builder: repeatWithTiming / repeat set comp.repeat; default is off
  ButtonBuilder db;
  auto plain = db.trigger(ButtonTrigger.press).action("plain")
    .build(testUi, null, RectF(200, 0, 80, 30));
  auto plainComp = plain.components.get!ButtonComponent();
  assert(!plainComp.repeat.enabled);
  ButtonBuilder sb;
  auto viaStruct = sb.trigger(ButtonTrigger.press)
    .repeat(ButtonRepeat(true))
    .build(testUi, null, RectF(0, 0, 80, 30));
  auto vsComp = viaStruct.components.get!ButtonComponent();
  assert(vsComp.repeat == ButtonRepeat(true, 400, 80));
  ButtonBuilder b;
  auto btn = b
    .action("step")
    .trigger(ButtonTrigger.press)
    .repeatWithTiming(300, 50)
    .build(testUi, null, RectF(0, 0, 80, 30));
  auto comp = btn.components.get!ButtonComponent();
  assert(comp.repeat == ButtonRepeat(true, 300, 50));

  auto sys = new ButtonSystem();
  sys.onRegister(host);
  WidgetSystemContext ctx;
  ctx.host = host;

  // Non-repeat press-trigger button starts no repeat timer
  ctx.visibleWidgets = [
    VisibleWidget(plain, RectF(200, 0, 80, 30), false, RectF.init),
  ];
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 240, 15), ctx);
  assert(host.sentEvents.length == 1);
  assert(sys.repeatTimerId == invalidTimerId);
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonUp, 240, 15), ctx);

  ctx.visibleWidgets = [
    VisibleWidget(btn, RectF(0, 0, 80, 30), false, RectF.init),
  ];

  // Press -> 1 event, delay timer; delay fire -> 2 events, interval timer
  host.sentEvents = null;
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 40, 15), ctx);
  assert(host.sentEvents.length == 1);
  assert(host.sentEvents[0].view.eventName == "step");
  assert(host.isTimerActive(sys.repeatTimerId));
  const TimerId delayId = sys.repeatTimerId;
  sys.onTimer(ctx, delayId, 0.3f);
  assert(host.sentEvents.length == 2);
  assert(host.sentEvents[1].view.widget is btn);
  assert(sys.repeatTimerId != delayId);
  assert(host.isTimerActive(sys.repeatTimerId));
  sys.onTimer(ctx, sys.repeatTimerId, 0.05f);
  sys.onTimer(ctx, sys.repeatTimerId, 0.05f);
  assert(host.sentEvents.length == 4);

  // Animation timer ticks emit nothing
  assert(host.isTimerActive(sys.animTimerId));
  sys.onTimer(ctx, sys.animTimerId, 0.016f);
  assert(host.sentEvents.length == 4);

  // Dragged off: fire skipped, timer kept; dragged back: fire emits
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseMotion, 300, 15), ctx);
  sys.onTimer(ctx, sys.repeatTimerId, 0.05f);
  assert(host.sentEvents.length == 4);
  assert(host.isTimerActive(sys.repeatTimerId));
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseMotion, 40, 15), ctx);
  sys.onTimer(ctx, sys.repeatTimerId, 0.05f);
  assert(host.sentEvents.length == 5);

  // Release stops the repeat timer
  const TimerId intervalId = sys.repeatTimerId;
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonUp, 40, 15), ctx);
  assert(sys.repeatTimerId == invalidTimerId);
  assert(!host.isTimerActive(intervalId));
  assert(host.sentEvents.length == 5);

  // Disabled mid-hold: next fire emits nothing and stops the timer
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 40, 15), ctx);
  assert(host.sentEvents.length == 6);
  TimerId heldId = sys.repeatTimerId;
  assert(host.isTimerActive(heldId));
  assert(btn.setInputEnabled(false));
  sys.onTimer(ctx, heldId, 0.3f);
  assert(host.sentEvents.length == 6);
  assert(sys.repeatTimerId == invalidTimerId);
  assert(!host.isTimerActive(heldId));
  assert(btn.setInputEnabled(true));
  sys.postLayout(ctx);

  // Widget release stops the repeat timer
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 40, 15), ctx);
  heldId = sys.repeatTimerId;
  assert(host.isTimerActive(heldId));
  sys.onWidgetReleased(btn);
  assert(sys.repeatTimerId == invalidTimerId);
  assert(!host.isTimerActive(heldId));

  // Hidden button: postLayout forgets the press and stops the timer
  sys.handleEvent(mouseEv(AppEvent.Kind.mouseButtonDown, 40, 15), ctx);
  heldId = sys.repeatTimerId;
  assert(host.isTimerActive(heldId));
  btn.visible = false;
  sys.postLayout(ctx);
  assert(sys.press.pressed is null);
  assert(sys.repeatTimerId == invalidTimerId);
  assert(!host.isTimerActive(heldId));
  sys.onUnregister();
  assert(sys.repeatTimerId == invalidTimerId);
}
