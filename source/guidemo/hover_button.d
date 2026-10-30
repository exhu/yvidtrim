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
 * NON-MODAL CONTROLLER TIMEOUT LIFECYCLE
 * --------------------------------------
 * HoverButtonController is a non-modal controller that can service one or
 * multiple buttons concurrently. During active transitions (e.g. fading or
 * gradient play), it returns timeoutMs = 16 to keep the event loop stepping
 * at ~60 FPS. Once all buttons reach their resting state (idle or fully
 * hovered/pressed), it returns timeoutMs = -1, allowing the application to
 * sleep and consume 0% idle CPU.
 */
module guidemo.hover_button;

import core.time : MonoTime;
import std.algorithm.comparison : clamp, max, min;
import std.math : PI, abs, sin;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.builder : ViewAppEventBuilder;
import yguilib.render.render_types : ColorF, RectF;
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

  ref HoverButtonBuilder text(string caption) return {
    config.text = caption;
    return this;
  }

  ref HoverButtonBuilder bg(ColorF color) return {
    config.normalBg = color;
    return this;
  }

  ref HoverButtonBuilder border(ColorF color, float width = 1.0f) return {
    config.borderColor = color;
    config.borderWidth = width;
    return this;
  }

  ref HoverButtonBuilder radius(float r) return {
    config.cornerRadius = r;
    return this;
  }

  ref HoverButtonBuilder padding(float vertical, float horizontal) return {
    config.padding = Insets(vertical, horizontal);
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
  Widget build(Widget parent, RectF rect) {
    const float initW = rect.width > 0.0f ? rect.width : 100.0f;
    const float initH = rect.height > 0.0f ? rect.height : 36.0f;

    auto rootBuilder = WidgetBuilder(parent, rect)
      .view([
        "mouseEnter": "hoverBtn.enter",
        "mouseLeave": "hoverBtn.leave",
        "mouseDown": "hoverBtn.down",
        "mouseUp": "hoverBtn.up",
        "mouseMove": "hoverBtn.move",
      ]);

    if (customSize !is null) {
      rootBuilder.size(customSize);
    }
    if (customAnchor !is null) {
      rootBuilder.anchor(customAnchor);
    }

    rootBuilder.child(RectF(0, 0, initW, initH), (ref WidgetBuilder cb) {
      cb.fixedSize(initW, initH)
        .padding(config.padding);

      if (config.cornerRadius > 0.0f) {
        cb.roundBackground(config.normalBg, config.cornerRadius);
      } else {
        cb.background(config.normalBg);
      }

      if (config.borderWidth > 0.0f) {
        cb.border(
          config.borderColor,
          config.borderWidth,
          config.cornerRadius > 0.0f ? Border.Style.round : Border.Style.rect,
          config.cornerRadius
        );
      }

      cb.text(
        config.text,
        config.textColor,
        config.fontSize,
        TextLabel.Alignment.center
      )
      .onMouseEnter("mouseEnter")
      .onMouseLeave("mouseLeave")
      .onMouseDown("mouseDown")
      .onMouseUp("mouseUp")
      .onMouseMove("mouseMove");
    });

    return rootBuilder.build();
  }
}

/// Convenience helper to create a hover button using default configuration.
Widget createHoverButton(
  Widget parent,
  RectF rect,
  in HoverButtonConfig config = HoverButtonConfig()
) {
  HoverButtonBuilder b;
  b.config = config;
  return b.build(parent, rect);
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
    bool isHovered = false;
    bool isPressed = false;
    float cursorNormX = 0.5f;
    float cursorNormY = 0.5f;
  }

  this(
    UiSystem ui,
    Widget[] buttonViews = null,
    in HoverAnimConfig[] animConfigs = null
  ) {
    super(ui);
    if (buttonViews.length > 0) {
      addButtons(buttonViews, animConfigs);
    }
  }

  void addButton(
    Widget buttonView,
    in HoverAnimConfig animConfig = HoverAnimConfig()
  ) {
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

    entries ~= entry;
  }

  void addButtons(
    Widget[] buttonViews,
    in HoverAnimConfig[] animConfigs = null
  ) {
    foreach (i, view; buttonViews) {
      HoverAnimConfig cfg = (animConfigs !is null && i < animConfigs.length)
        ? animConfigs[i]
        : HoverAnimConfig();
      addButton(view, cfg);
    }
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.view) {
      ptrdiff_t idx = findEntryIndex(ev.view.viewWidget);
      if (idx >= 0) {
        return handleButtonEvent(entries[idx], ev);
      }
    }

    if (ev.kind == AppEvent.Kind.update) {
      if (isAnyAnimating()) {
        return HandleResult(HandleResult.Result.updateView, false, 16);
      } else {
        hasLastTime = false;
        return HandleResult(HandleResult.Result.nothing, false, -1);
      }
    }

    // Keep timeout alive on other events (e.g. updateUiLayer or input)
    // while animating, without requesting updateView recursion!
    HandleResult res = super.handleEvent(ev);
    if (isAnyAnimating()) {
      res.timeoutMs = 16;
    }
    return res;
  }

  override bool updateView() {
    const float dt = computeDeltaTime();
    return stepAnimation(dt);
  }

private:
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

  float computeDeltaTime() {
    const MonoTime now = MonoTime.currTime;
    if (!hasLastTime) {
      lastTime = now;
      hasLastTime = true;
      return 0.01667f;
    }
    const long usecs = (now - lastTime).total!"usecs";
    lastTime = now;
    const float dt = cast(float)usecs / 1_000_000.0f;
    return clamp(dt, 0.001f, 0.1f);
  }

  void updateCursorNorm(ref ButtonEntry entry, in AppEvent ev) {
    auto val = MouseEvent.AppEventViewValue(ev.view.value);
    if (entry.visualWidget !is null &&
        entry.visualWidget.rect.width > 0.0f &&
        entry.visualWidget.rect.height > 0.0f) {
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
        applyVisualState(entry);
      }
      consumed = true;
      break;
    default:
      break;
    }

    if (consumed) {
      HandleResult res;
      res.result = isAnyAnimating()
        ? HandleResult.Result.updateView
        : HandleResult.Result.nothing;
      res.consume = true;
      res.timeoutMs = isAnyAnimating() ? 16 : -1;
      return res;
    }

    HandleResult res = super.handleEvent(ev);
    if (isAnyAnimating()) {
      res.timeoutMs = 16;
    }
    return res;
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
      const float targetHover = entry.isHovered ? 1.0f : 0.0f;
      const float targetPress = entry.isPressed ? 1.0f : 0.0f;
      const float speed = entry.animConfig.fadeSpeed;

      bool buttonVisualDirty = false;

      // Hover progress transition
      if (abs(entry.hoverProgress - targetHover) > 0.001f) {
        if (entry.hoverProgress < targetHover) {
          entry.hoverProgress = min(
            targetHover,
            entry.hoverProgress + dt * speed
          );
        } else {
          entry.hoverProgress = max(
            targetHover,
            entry.hoverProgress - dt * speed
          );
        }
        buttonVisualDirty = true;
      } else {
        entry.hoverProgress = targetHover;
      }

      // Press progress transition
      if (abs(entry.pressProgress - targetPress) > 0.001f) {
        if (entry.pressProgress < targetPress) {
          entry.pressProgress = min(
            targetPress,
            entry.pressProgress + dt * speed * 3.0f
          );
        } else {
          entry.pressProgress = max(
            targetPress,
            entry.pressProgress - dt * speed * 3.0f
          );
        }
        buttonVisualDirty = true;
      } else {
        entry.pressProgress = targetPress;
      }

      // Gradient play oscillation while hovered or fading out
      if (entry.animConfig.style == HoverAnimConfig.AnimStyle.gradientPlay &&
          (entry.isHovered || entry.hoverProgress > 0.001f)) {
        entry.animPhase += dt * 3.5f;
        if (entry.animPhase > 2.0f * PI) {
          entry.animPhase -= 2.0f * PI;
        }
        buttonVisualDirty = true;
      }

      if (buttonVisualDirty) {
        applyVisualState(entry);
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
    const float f = clamp(t, 0.0f, 1.0f);
    return ColorF(
      a.r + (b.r - a.r) * f,
      a.g + (b.g - a.g) * f,
      a.b + (b.b - a.b) * f,
      a.a + (b.a - a.a) * f
    );
  }

  ButtonEntry[] entries;
  MonoTime lastTime;
  bool hasLastTime = false;
}

// Unit tests verifying HoverButtonBuilder, View event renaming, and controller.
unittest {
  import yguilib.controller : Controller;
  import yguilib.widget : WidgetViewController;
  import yguilib.widget.system : WidgetSystem;
  import yguilib.window : Window;

  class TestUiSystem : UiSystem {
    AppEvent[] sentEvents;
    override void sendAppEvent(AppEvent ev) {
      sentEvents ~= ev;
    }
    override void registerWidgetViewController(WidgetViewController c) {}
    override void unregisterWidgetViewController(WidgetViewController c) {}
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
    .build(null, RectF(10, 10, 120, 32));

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

  auto controller = new HoverButtonController(testUi, [btnRoot], [animCfg]);
  assert(controller.entries.length == 1);

  // Dispatch enter event to controller
  auto enterEv = ViewAppEventBuilder("hoverBtn.enter")
    .widget(child)
    .viewWidget(btnRoot)
    .build();
  auto res = controller.handleEvent(enterEv);
  assert(res.result == HandleResult.Result.updateView);
  assert(res.timeoutMs == 16);
  assert(controller.entries[0].isHovered);

  // Advance animation step
  bool updated = controller.updateView();
  assert(updated);
  assert(controller.entries[0].hoverProgress > 0.0f);

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

  auto gradController = new HoverButtonController(testUi, [btnRoot], [gradCfg]);
  assert(gradController.entries.length == 1);

  gradController.handleEvent(enterEv);
  assert(gradController.isAnyAnimating());
  bool gradUpdated = gradController.updateView();
  assert(gradUpdated);
  assert(gradController.entries[0].animPhase > 0.0f);

  // Test mouseMove with cursor coordinate calculation
  auto moveVal = MouseEvent.AppEventViewValue(50.0f, 15.0f);
  auto moveEv = ViewAppEventBuilder("hoverBtn.move")
    .widget(child)
    .viewWidget(btnRoot)
    .value(moveVal.raw)
    .build();
  auto moveRes = gradController.handleEvent(moveEv);
  assert(moveRes.result == HandleResult.Result.updateView);
  assert(moveRes.timeoutMs == 16);
}

version (unittest) {
  void main() {
  }
}
