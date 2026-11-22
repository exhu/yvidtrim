/**
 * hover_button.d - Reusable hover button widget tree & animation controller.
 *
 * TUTORIAL: WIDGET TREE & EVENT BUBBLING ARCHITECTURE
 * ---------------------------------------------------
 * This module demonstrates yguilib's View component and MouseEvent component
 * working together to create an encapsulated, reusable interactive button:
 *
 * +-------------------------------------------------------------------+
 * |                           Window View                             |
 * |                                                                   |
 * |   +-----------------------------------------------------------+   |
 * |   | Button Root Widget (empty container, Size, Anchor)        |   |
 * |   | components.view = View (renameEvents: mouseEnter -> ...)  |   |
 * |   |                                                           |   |
 * |   |   +---------------------------------------------------+   |   |
 * |   |   | Button Visual Child Widget                        |   |   |
 * |   |   | - components.background (round/rect color)        |   |   |
 * |   |   | - components.border     (width/color/radius)      |   |   |
 * |   |   | - components.textLabel  (caption/color/align)     |   |   |
 * |   |   | - components.mouseEvent (raw mouse triggers)      |   |   |
 * |   |   +---------------------------------------------------+   |   |
 * |   +-----------------------------------------------------------+   |
 * +-------------------------------------------------------------------+
 *
 * Event Flow:
 * 1. SDL emits raw mouse motion or button clicks.
 * 2. UiSystemController passes input events to InputSystem.
 * 3. InputSystem generates MouseEvent view events (e.g. "mouseEnter",
 *    "mouseLeave", "mouseDown", "mouseUp", "mouseMove") on the visual child.
 * 4. InputSystem.passEvent bubbles events upward through ancestor Views.
 * 5. Button Root Widget's View component matches renameEvents:
 *    - Renames eventName (e.g. "mouseEnter" -> "hoverBtn.enter").
 *    - Updates event.view.viewWidget to point to the Button Root Widget.
 * 6. UiSystem.sendAppEvent dispatches the renamed event to controllers.
 * 7. HoverButtonController matches event.view.viewWidget against its managed
 *    button list and drives smooth visual animations.
 *
 * NON-MODAL CONTROLLER TIMER LIFECYCLE
 * ------------------------------------
 * HoverButtonController is a non-modal controller that can service one or
 * multiple buttons concurrently. During active transitions (e.g. fading or
 * gradient play), it runs a 16 ms controller timer via `startTimer` to
 * step animations in `onTimer(id, dt)`. Once all buttons reach their resting
 * (idle or fully hovered/pressed), it stops the timer, allowing the
 * application to sleep at 0% idle CPU.
 */
module guidemo.hover_button;

import std.math : PI, abs, sin;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.builder : ViewAppEventBuilder;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.timercontrol : TimerId, invalidTimerId;
import yguilib.timers : AnimationTimer, AnimationWrapMode, TimerIntervalMs,
  TimerMode;
import yguilib.uisystem : UiSystem;
import yguilib.widget : ViewComponent, Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Background, Border, TextLabel;
import yguilib.widget.input_components : MouseEvent;
import yguilib.widget.layout_components : Anchor, Dimension, Insets, Size,
  SizingMode;

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

/// Fluent builder for constructing hover button widget trees.
struct HoverButtonBuilder {
  HoverButtonConfig config;
  Size customSize = null;
  Anchor customAnchor = null;
  string widgetName = null;

  ref HoverButtonBuilder name(string buttonName) return {
    widgetName = buttonName;
    return this;
  }

  ref HoverButtonBuilder text(string caption) return {
    config.text = caption;
    return this;
  }

  ref HoverButtonBuilder bg(ColorF color) return {
    config.normalBg = color;
    return this;
  }

  ref HoverButtonBuilder border(ColorF color, float width) return {
    config.borderColor = color;
    config.borderWidth = width;
    return this;
  }

  ref HoverButtonBuilder radius(float r) return {
    config.cornerRadius = r;
    return this;
  }

  ref HoverButtonBuilder padding(float vertical, float horizontal) return {
    config.padding = Insets.vh(vertical, horizontal);
    return this;
  }

  ref HoverButtonBuilder fontSize(float pt) return {
    config.fontSize = pt;
    return this;
  }

  ref HoverButtonBuilder action(string eventName) return {
    config.actionEvent = eventName;
    return this;
  }

  ref HoverButtonBuilder size(Size sz) return {
    customSize = sz;
    return this;
  }

  ref HoverButtonBuilder fixedSize(float w, float h) return {
    customSize = Size.fixed(w, h);
    return this;
  }

  ref HoverButtonBuilder autoSize() return {
    customSize = Size.autoSize();
    return this;
  }

  ref HoverButtonBuilder anchor(Anchor a) return {
    customAnchor = a;
    return this;
  }

  /**
   * Constructs the button widget tree.
   *
   * Returns: The root Widget with attached View component.
   */
  Widget build(UiSystem ui, Widget parent, RectF rect) {
    const float initW = rect.width > 0.0f ? rect.width : 100.0f;
    const float initH = rect.height > 0.0f ? rect.height : 36.0f;
    const string rootName = (widgetName.length > 0)
      ? widgetName
      : "hoverButton";

    auto rootBuilder = WidgetBuilder.make(ui)
      .parent(parent)
      .name(rootName)
      .rect(rect)
      .viewEvents([
        "mouseEnter": "hoverBtn.enter",
        "mouseLeave": "hoverBtn.leave",
        "mouseDown": "hoverBtn.down",
        "mouseUp": "hoverBtn.up",
        "mouseMove": "hoverBtn.move",
      ]);

    if (customSize !is null) {
      rootBuilder.sizeComponent(customSize);
    }
    if (customAnchor !is null) {
      rootBuilder.anchorComponent(customAnchor);
    }

    rootBuilder.child((WidgetBuilder cb) {
      buildVisualChild(cb, initW, initH, rootName);
    });

    return rootBuilder.build();
  }

private:
  void buildVisualChild(
    WidgetBuilder cb,
    float initW,
    float initH,
    string rootName
  ) {
    cb.name(rootName ~ "Label")
      .rect(RectF(0, 0, initW, initH))
      .fixedSize(initW, initH)
      .padding(config.padding);

    if (config.cornerRadius > 0.0f) {
      cb.roundBg(config.normalBg).bgRadius(config.cornerRadius);
    } else {
      cb.bg(config.normalBg);
    }

    if (config.borderWidth > 0.0f) {
      cb.border(config.borderColor)
        .borderWidth(config.borderWidth)
        .borderStyle(
          config.cornerRadius > 0.0f
            ? Border.Style.round
            : Border.Style.rect
        )
        .borderRadius(config.cornerRadius);
    }

    cb.text(config.text)
      .textColor(config.textColor)
      .fontSize(config.fontSize)
      .textAlign(TextLabel.Alignment.center)
      .onMouseEnter("mouseEnter")
      .onMouseLeave("mouseLeave")
      .onMouseDown("mouseDown")
      .onMouseUp("mouseUp")
      .onMouseMove("mouseMove");
  }
}

/// Convenience helper to create a hover button using explicit configuration.
Widget createHoverButton(
  UiSystem ui,
  Widget parent,
  RectF rect,
  in HoverButtonConfig config
) {
  HoverButtonBuilder b;
  b.config = config;
  return b.build(ui, parent, rect);
}

/// Controller-side animation and interactive options.
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

/// Controller servicing hover and press visual animations for button views.
final class HoverButtonController : DefaultController {
  struct ButtonEntry {
    Widget viewWidget;
    Widget visualWidget;
    HoverAnimConfig animConfig;
    ColorF normalBg;
    ColorF normalBorder;
    float hoverProgress = 0.0f;
    float pressProgress = 0.0f;
    float animPhase = 0.0f;
    AnimationTimer hoverTimer;
    AnimationTimer pressTimer;
    AnimationTimer gradTimer;
    bool isHovered = false;
    bool isPressed = false;
    bool hoverPulsePending = false;
    bool visualDirty = false;
    float cursorNormX = 0.5f;
    float cursorNormY = 0.5f;
  }

  enum float hoverPulsePeak = 0.75f;

  this(UiSystem ui) {
    assert(ui !is null, "ui must not be null");
    super(ui);
  }

  void addButton(Widget buttonView, in HoverAnimConfig animConfig) {
    assert(buttonView !is null, "buttonView must not be null");
    assert(
      buttonView.children.length > 0,
      "buttonView must contain a visual child widget"
    );

    auto visual = buttonView.children[0];
    ColorF normalBg = ColorF(0.2f, 0.2f, 0.2f, 1.0f);
    if (visual.components.background !is null) {
      normalBg = visual.components.background.color;
    }

    ColorF normalBorder = ColorF(0.4f, 0.4f, 0.4f, 1.0f);
    if (visual.components.border !is null) {
      normalBorder = visual.components.border.color;
    }

    ButtonEntry entry;
    entry.viewWidget = buttonView;
    entry.visualWidget = visual;
    entry.animConfig = animConfig;
    entry.normalBg = normalBg;
    entry.normalBorder = normalBorder;
    const float speed = animConfig.fadeSpeed > 0.0f
      ? animConfig.fadeSpeed
      : 3.5f;
    entry.hoverTimer.start(1.0f / speed, AnimationWrapMode.once);
    entry.pressTimer.start(1.0f / (speed * 3.0f), AnimationWrapMode.once);
    entry.gradTimer.start((2.0f * PI) / 3.5f, AnimationWrapMode.loop);
    entry.gradTimer.setPause(false);

    entries ~= entry;
  }

  void addButtons(
    Widget[] buttonViews,
    in HoverAnimConfig[] animConfigs
  ) {
    foreach (i, view; buttonViews) {
      HoverAnimConfig cfg = (animConfigs !is null && i < animConfigs.length)
        ? animConfigs[i]
        : HoverAnimConfig();
      addButton(view, cfg);
    }
  }

  void removeButton(Widget button) {
    if (button is null) {
      return;
    }
    import std.algorithm.mutation : remove;
    entries = entries.remove!(
      e => e.viewWidget is button || e.visualWidget is button
    );
    if (!isAnyAnimating()) {
      stopTimer(animTimerId);
    }
  }

  override void onPop() {
    stopTimer(animTimerId);
  }

  override void onWidgetReleased(Widget w) {
    removeButton(w);
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.view) {
      ptrdiff_t idx = findEntryIndex(ev.view.viewWidget);
      if (idx >= 0) {
        return handleButtonEvent(entries[idx], ev);
      }
    }
    return super.handleEvent(ev);
  }

  override bool onTimer(TimerId id, float dt) {
    if (id == invalidTimerId || id != animTimerId) {
      return false;
    }
    const bool anyChanged = stepAnimation(dt);
    if (!isAnyAnimating()) {
      stopTimer(animTimerId);
    }
    return anyChanged;
  }

  override bool updateView() {
    bool anyUpdated = false;
    foreach (ref entry; entries) {
      if (entry.visualDirty) {
        entry.visualDirty = false;
        applyVisualState(entry);
        anyUpdated = true;
      }
    }
    return anyUpdated;
  }

private:
  void ensureAnimTimer() {
    if (animTimerId == invalidTimerId && isAnyAnimating()) {
      animTimerId = startTimer(TimerIntervalMs.fps60, TimerMode.repeat);
    }
  }
  ptrdiff_t findEntryIndex(Widget viewWidget) const {
    if (viewWidget is null) {
      return -1;
    }
    foreach (i, const ref e; entries) {
      if (e.viewWidget is viewWidget) {
        return i;
      }
    }
    return -1;
  }

  bool isAnyAnimating() const {
    foreach (const ref e; entries) {
      if (e.hoverPulsePending) {
        return true;
      }
      const float targetHover = e.isHovered ? 1.0f : 0.0f;
      const float targetPress = e.isPressed ? 1.0f : 0.0f;
      if (abs(e.hoverProgress - targetHover) > 0.001f ||
          abs(e.pressProgress - targetPress) > 0.001f) {
        return true;
      }
      if (e.animConfig.style == HoverAnimConfig.AnimStyle.gradientPlay &&
          (e.isHovered || e.hoverProgress > 0.001f)) {
        return true;
      }
    }
    return false;
  }

  void updateCursorNorm(ref ButtonEntry entry, in AppEvent ev) {
    auto val = MouseEvent.AppEventViewValue.fromRaw(ev.view.value);
    if (entry.visualWidget !is null &&
        entry.visualWidget.rect.width > 0.0f &&
        entry.visualWidget.rect.height > 0.0f) {
      import std.algorithm.comparison : clamp;
      entry.cursorNormX = clamp(
        val.localX / entry.visualWidget.rect.width, 0.0f, 1.0f
      );
      entry.cursorNormY = clamp(
        val.localY / entry.visualWidget.rect.height, 0.0f, 1.0f
      );
    }
  }

  HandleResult handleButtonEvent(ref ButtonEntry entry, in AppEvent ev) {
    bool consumed = false;

    switch (ev.view.eventName) {
    case "hoverBtn.enter":
      entry.isHovered = true;
      entry.hoverPulsePending = true;
      updateCursorNorm(entry, ev);
      consumed = true;
      break;
    case "hoverBtn.leave":
      entry.isHovered = false;
      entry.isPressed = false;
      consumed = true;
      break;
    case "hoverBtn.down":
      entry.isPressed = true;
      consumed = true;
      break;
    case "hoverBtn.up":
      if (entry.isPressed) {
        entry.isPressed = false;
        triggerAction(entry);
      }
      consumed = true;
      break;
    case "hoverBtn.move":
      updateCursorNorm(entry, ev);
      if (entry.animConfig.style == HoverAnimConfig.AnimStyle.gradientPlay &&
          entry.hoverProgress > 0.01f) {
        entry.visualDirty = true;
      }
      consumed = true;
      break;
    default:
      break;
    }

    if (consumed) {
      ensureAnimTimer();
      HandleResult res;
      res.result = entry.visualDirty
        ? HandleResult.Result.updateView
        : HandleResult.Result.nothing;
      res.consume = true;
      return res;
    }

    return super.handleEvent(ev);
  }

  void triggerAction(ref ButtonEntry entry) {
    if (entry.animConfig.actionEvent.length > 0) {
      auto actionEv = ViewAppEventBuilder(entry.animConfig.actionEvent)
        .widget(entry.viewWidget)
        .build();
      uiSystem.sendAppEvent(actionEv);
    }
  }

  bool stepAnimation(float dt) {
    bool anyChanged = false;

    foreach (ref entry; entries) {
      bool buttonVisualDirty = false;

      if (entry.hoverPulsePending && entry.hoverProgress >= hoverPulsePeak) {
        entry.hoverPulsePending = false;
      }
      const bool hoverForward = entry.isHovered || entry.hoverPulsePending;

      // Hover progress transition
      if (!entry.hoverTimer.isAtTarget(hoverForward)) {
        entry.hoverTimer.stepTowards(dt, hoverForward);
        entry.hoverProgress = entry.hoverTimer.getProgress();
        if (entry.hoverPulsePending &&
            entry.hoverProgress >= hoverPulsePeak) {
          entry.hoverPulsePending = false;
        }
        buttonVisualDirty = true;
      }

      // Press progress transition
      if (!entry.pressTimer.isAtTarget(entry.isPressed)) {
        entry.pressTimer.stepTowards(dt, entry.isPressed);
        entry.pressProgress = entry.pressTimer.getProgress();
        buttonVisualDirty = true;
      }

      // Gradient play oscillation while hovered or fading out
      if (entry.animConfig.style == HoverAnimConfig.AnimStyle.gradientPlay &&
          (entry.isHovered || entry.hoverPulsePending ||
            entry.hoverProgress > 0.001f)) {
        entry.gradTimer.update(dt);
        entry.animPhase = entry.gradTimer.map(0.0f, 2.0f * PI);
        buttonVisualDirty = true;
      }

      if (buttonVisualDirty) {
        entry.visualDirty = true;
        anyChanged = true;
      }
    }

    return anyChanged;
  }

  void applyVisualState(ref ButtonEntry entry) {
    ColorF targetHoverBg = entry.animConfig.hoverBg;

    if (entry.animConfig.style == HoverAnimConfig.AnimStyle.gradientPlay &&
        entry.hoverProgress > 0.01f) {
      const float wave = (
        sin(entry.animPhase + entry.cursorNormX * PI) + 1.0f
      ) * 0.5f;
      targetHoverBg = lerpColor(
        entry.animConfig.hoverBg,
        entry.animConfig.gradientAccentBg,
        wave
      );
    }

    ColorF currentBg = lerpColor(
      entry.normalBg,
      targetHoverBg,
      entry.hoverProgress
    );

    if (entry.pressProgress > 0.0f) {
      currentBg = lerpColor(
        currentBg,
        entry.animConfig.pressBg,
        entry.pressProgress
      );
    }

    ColorF currentBorder = lerpColor(
      entry.normalBorder,
      entry.animConfig.hoverBorder,
      entry.hoverProgress
    );

    entry.visualWidget.setBackgroundColor(currentBg);
    entry.visualWidget.setBorderColor(currentBorder);
  }

  static ColorF lerpColor(in ColorF a, in ColorF b, float t) {
    import std.algorithm.comparison : clamp;
    const float f = clamp(t, 0.0f, 1.0f);
    return ColorF(
      a.r + (b.r - a.r) * f,
      a.g + (b.g - a.g) * f,
      a.b + (b.b - a.b) * f,
      a.a + (b.a - a.a) * f
    );
  }

  ButtonEntry[] entries;
  TimerId animTimerId = invalidTimerId;
}

// Unit tests verifying HoverButtonBuilder, View event renaming, and controller.
unittest {
  import yguilib.controller : Controller;
  import yguilib.object_registry : ObjectRegistry;
  import yguilib.widget.widget_view : WidgetViewController, WidgetView;
  import yguilib.widget.system : WidgetSystem;
  import yguilib.window : Window;

  class TestUiSystem : UiSystem {
    AppEvent[] sentEvents;
    bool[TimerId] activeTimers;
    TimerId nextTimerId = 1;

    override void sendAppEvent(AppEvent ev) {
      sentEvents ~= ev;
    }
    override TimerId startTimer(
      Object owner,
      uint intervalMs,
      TimerMode mode
    ) {
      const TimerId id = nextTimerId++;
      activeTimers[id] = true;
      return id;
    }
    override void stopTimer(TimerId id) {
      activeTimers.remove(id);
    }
    override bool isTimerActive(TimerId id) const {
      return (id in activeTimers) !is null;
    }
    override @property
    ObjectRegistry!WidgetViewController widgetViewControllers() {
      return null;
    }
    override @property ObjectRegistry!WidgetView widgetViews() {
      return null;
    }
    override void popController() {}
    override void pushController(Controller c) {}
    override void pushModalController(Controller c) {}
    override void popFocusRoot() {}
    override void pushFocusRoot(Widget w) {}
    override void registerWidgetSystem(WidgetSystem system) {}
    override void unregisterWidgetSystem(WidgetSystem system) {}
    override protected WidgetSystem findWidgetSystemByType(
      TypeInfo_Class type
    ) {
      return null;
    }
    override @property Window mainWindow() { return null; }
    override void mainEventLoop() {}
    override uint nextWidgetId() {
      return fNextWidgetId++;
    }
    override Widget makeWidget() {
      return new Widget(nextWidgetId());
    }
    override void releaseWidget(Widget w) {
      if (w !is null) {
        w.release();
      }
    }
    override void setEventStatsEnabled(bool enabled) {}
    override @property bool eventStatsEnabled() {
      return false;
    }
    override string dumpInfo() {
      return "{}";
    }

  private:
    uint fNextWidgetId = 1;
  }

  auto testUi = new TestUiSystem();

  // Test 1: HoverButtonBuilder tree structure
  HoverButtonBuilder builder;
  auto btnRoot = builder
    .text("Click Me")
    .bg(ColorF(0.2f, 0.2f, 0.2f, 1.0f))
    .border(ColorF(0.4f, 0.4f, 0.4f, 1.0f), 1.0f)
    .radius(4.0f)
    .fixedSize(120.0f, 32.0f)
    .action("customAction")
    .build(testUi, null, RectF(10, 10, 120, 32));

  assert(btnRoot !is null);
  assert(btnRoot.components.view !is null);
  assert(btnRoot.components.size !is null);
  assert(btnRoot.children.length == 1);

  auto child = btnRoot.children[0];
  assert(child.parentView is btnRoot);
  assert(child.inputEnabled);
  assert(child.components.background !is null);
  assert(child.components.border !is null);
  assert(child.components.textLabel !is null);
  assert(child.components.textLabel.caption == "Click Me");
  assert(child.components.mouseEvent !is null);

  // Test 2: View component renameEvents configuration
  const auto renames = btnRoot.components.view.renameEvents;
  assert(renames["mouseEnter"] == "hoverBtn.enter");
  assert(renames["mouseLeave"] == "hoverBtn.leave");
  assert(renames["mouseDown"] == "hoverBtn.down");
  assert(renames["mouseUp"] == "hoverBtn.up");
  assert(renames["mouseMove"] == "hoverBtn.move");

  // Test 3: HoverButtonController event handling and animation step
  HoverAnimConfig animCfg;
  animCfg.hoverBg = ColorF(0.4f, 0.6f, 0.9f, 1.0f);
  animCfg.actionEvent = "customAction";

  auto controller = new HoverButtonController(testUi);
  controller.addButtons([btnRoot], [animCfg]);
  assert(controller.entries.length == 1);

  // Dispatch enter event to controller
  auto enterEv = ViewAppEventBuilder("hoverBtn.enter")
    .widget(child)
    .viewWidget(btnRoot)
    .build();
  auto res = controller.handleEvent(enterEv);
  assert(res.result == HandleResult.Result.nothing);
  assert(res.consume);
  assert(controller.entries[0].isHovered);
  assert(testUi.isTimerActive(controller.animTimerId));

  // Advance animation step and sync view
  assert(controller.onTimer(controller.animTimerId, 0.016f));
  assert(controller.entries[0].hoverProgress > 0.0f);
  assert(controller.updateView());

  // Dispatch leave event
  auto leaveEv = ViewAppEventBuilder("hoverBtn.leave")
    .widget(child)
    .viewWidget(btnRoot)
    .build();
  controller.handleEvent(leaveEv);
  assert(!controller.entries[0].isHovered);

  // Test click sequence (down then up)
  testUi.sentEvents = null;
  auto downEv = ViewAppEventBuilder("hoverBtn.down")
    .widget(child)
    .viewWidget(btnRoot)
    .build();
  controller.handleEvent(downEv);
  assert(controller.entries[0].isPressed);

  auto upEv = ViewAppEventBuilder("hoverBtn.up")
    .widget(child)
    .viewWidget(btnRoot)
    .build();
  controller.handleEvent(upEv);
  assert(!controller.entries[0].isPressed);

  // Verify actionEvent was dispatched via uiSystem
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "customAction");
  assert(testUi.sentEvents[0].view.widget is btnRoot);

  // Test 4: Gradient play animation and cursor tracking
  HoverAnimConfig gradCfg;
  gradCfg.style = HoverAnimConfig.AnimStyle.gradientPlay;
  gradCfg.hoverBg = ColorF(0.2f, 0.4f, 0.8f, 1.0f);
  gradCfg.gradientAccentBg = ColorF(0.1f, 0.9f, 0.8f, 1.0f);

  auto gradController = new HoverButtonController(testUi);
  gradController.addButtons([btnRoot], [gradCfg]);
  assert(gradController.entries.length == 1);

  gradController.handleEvent(enterEv);
  assert(gradController.isAnyAnimating());
  assert(gradController.onTimer(gradController.animTimerId, 0.016f));
  assert(gradController.updateView());
  assert(gradController.entries[0].animPhase > 0.0f);

  // Test mouseMove with cursor coordinate calculation
  auto moveVal = MouseEvent.AppEventViewValue.packLocal(50.0f, 15.0f, 0, true);
  auto moveEv = ViewAppEventBuilder("hoverBtn.move")
    .widget(child)
    .viewWidget(btnRoot)
    .valueArray(moveVal.raw)
    .build();
  auto moveRes = gradController.handleEvent(moveEv);
  assert(moveRes.result == HandleResult.Result.updateView);
  assert(moveRes.consume);

  // Test 5: Sub-frame curved sweep (enter + leave before tick) latches hover
  // pulse on all 3 touched buttons so every button visibly lights up and fades.
  Widget[3] sweepBtns;
  foreach (i; 0 .. 3) {
    HoverButtonBuilder sb;
    sweepBtns[i] = sb.fixedSize(80, 32).build(
      testUi,
      null,
      RectF(cast(float) (i * 90), 0, 80, 32)
    );
  }
  auto sweepCtrl = new HoverButtonController(testUi);
  sweepCtrl.addButtons(sweepBtns[], null);
  foreach (btn; sweepBtns) {
    sweepCtrl.handleEvent(ViewAppEventBuilder("hoverBtn.enter")
      .widget(btn.children[0])
      .viewWidget(btn)
      .build());
    sweepCtrl.handleEvent(ViewAppEventBuilder("hoverBtn.leave")
      .widget(btn.children[0])
      .viewWidget(btn)
      .build());
  }
  assert(testUi.isTimerActive(sweepCtrl.animTimerId));
  float[3] maxProgress = [0.0f, 0.0f, 0.0f];
  foreach (_; 0 .. 60) {
    sweepCtrl.onTimer(sweepCtrl.animTimerId, 0.016f);
    sweepCtrl.updateView();
    foreach (i; 0 .. 3) {
      if (sweepCtrl.entries[i].hoverProgress > maxProgress[i]) {
        maxProgress[i] = sweepCtrl.entries[i].hoverProgress;
      }
    }
  }
  foreach (i; 0 .. 3) {
    assert(maxProgress[i] >= HoverButtonController.hoverPulsePeak);
    assert(sweepCtrl.entries[i].hoverProgress == 0.0f);
  }
  assert(!testUi.isTimerActive(sweepCtrl.animTimerId));

  // Test onWidgetReleased removes button from controller
  gradController.onWidgetReleased(btnRoot);
  assert(gradController.entries.length == 0);
  assert(!testUi.isTimerActive(gradController.animTimerId));
}
