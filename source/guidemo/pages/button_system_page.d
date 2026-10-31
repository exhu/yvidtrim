/**
 * button_system_page.d - Page 4 showcase for AnimatedHoverButtonSystem &
 * AnimatedHoverButtonComponent.
 */
module guidemo.pages.button_system_page;

import std.format : format;
import guidemo.common : makeSectionCard;
import guidemo.hover_button_system : AnimatedHoverButtonBuilder,
  HoverAnimConfig, HoverButtonConfig;
import guidemo.model : DemoModel;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.layout_components : AlignItems, FlexDirection, Insets,
  JustifyContent, Size;

/// Page 4 widget container showcasing AnimatedHoverButtonSystem and
/// AnimatedHoverButtonComponent.
final class ButtonSystemPage {
  this(Widget parent) {
    assert(parent !is null, "parent must not be null");
    root = new Widget(parent, RectF(0, 0, 1280, 720));

    buildFadingSection();
    buildGradientPlaySection();
    buildActionCounterSection();
    buildArchitectureSection();
  }

  void update(const DemoModel m) {
    if (counterLabel !is null) {
      counterLabel.setCaption(
        format("Button Action Invocations: %d clicks", m.buttonClickCount)
      );
    }
  }

  Widget getRootWidget() {
    return root;
  }

  void setVisible(bool visible) {
    root.setVisible(visible);
  }

  bool isVisible() const {
    return root.visible;
  }

private:
  void buildFadingSection() {
    auto card = makeSectionCard(
      root,
      RectF(20, 68, 605, 280),
      "1. System-Driven Smooth Color Fading (Hover & Press Transition)"
    );

    WidgetBuilder(card, RectF(16, 36, 570, 36))
      .text(
        "AnimatedHoverButtonSystem updates button colors in preLayout phase. " ~
          "No manual button registration or wrapper View required.",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f),
        13.0f
      )
      .build();

    // Row of fade buttons
    auto btnRow = WidgetBuilder(card, RectF(16, 80, 570, 50))
      .flex(
        FlexDirection.row,
        14.0f,
        JustifyContent.start,
        AlignItems.center
      )
      .build();

    // Button 1: Slate Neutral
    HoverAnimConfig cfg1;
    cfg1.style = HoverAnimConfig.AnimStyle.fade;
    cfg1.hoverBg = ColorF(0.28f, 0.38f, 0.55f, 1.0f);
    cfg1.pressBg = ColorF(0.12f, 0.18f, 0.30f, 1.0f);
    cfg1.hoverBorder = ColorF(0.50f, 0.70f, 1.0f, 1.0f);
    cfg1.actionEvent = "btnCountAction";

    AnimatedHoverButtonBuilder b1;
    b1.text("Slate Button")
      .bg(ColorF(0.18f, 0.20f, 0.25f, 1.0f))
      .border(ColorF(0.30f, 0.35f, 0.45f, 1.0f), 1.0f)
      .radius(6.0f)
      .fixedSize(140.0f, 38.0f)
      .anim(cfg1)
      .build(btnRow, RectF(0, 0, 140, 38));

    // Button 2: Emerald Success
    HoverAnimConfig cfg2;
    cfg2.style = HoverAnimConfig.AnimStyle.fade;
    cfg2.hoverBg = ColorF(0.18f, 0.55f, 0.35f, 1.0f);
    cfg2.pressBg = ColorF(0.08f, 0.35f, 0.20f, 1.0f);
    cfg2.hoverBorder = ColorF(0.35f, 0.85f, 0.55f, 1.0f);
    cfg2.actionEvent = "btnCountAction";

    AnimatedHoverButtonBuilder b2;
    b2.text("Emerald Confirm")
      .bg(ColorF(0.12f, 0.24f, 0.18f, 1.0f))
      .border(ColorF(0.20f, 0.45f, 0.30f, 1.0f), 1.0f)
      .radius(6.0f)
      .fixedSize(150.0f, 38.0f)
      .anim(cfg2)
      .build(btnRow, RectF(0, 0, 150, 38));

    // Button 3: Crimson Danger
    HoverAnimConfig cfg3;
    cfg3.style = HoverAnimConfig.AnimStyle.fade;
    cfg3.hoverBg = ColorF(0.65f, 0.20f, 0.25f, 1.0f);
    cfg3.pressBg = ColorF(0.40f, 0.10f, 0.15f, 1.0f);
    cfg3.hoverBorder = ColorF(0.95f, 0.40f, 0.45f, 1.0f);
    cfg3.actionEvent = "btnCountAction";

    AnimatedHoverButtonBuilder b3;
    b3.text("Crimson Delete")
      .bg(ColorF(0.26f, 0.12f, 0.14f, 1.0f))
      .border(ColorF(0.48f, 0.20f, 0.24f, 1.0f), 1.0f)
      .radius(6.0f)
      .fixedSize(140.0f, 38.0f)
      .anim(cfg3)
      .build(btnRow, RectF(0, 0, 140, 38));

    // Note card
    auto noteBox = WidgetBuilder(card, RectF(16, 148, 570, 110))
      .roundBackground(ColorF(0.09f, 0.11f, 0.14f, 1.0f), 6.0f)
      .border(ColorF(0.20f, 0.23f, 0.28f, 1.0f), 1.0f)
      .padding(10, 12)
      .build();

    WidgetBuilder(noteBox, RectF(12, 10, 546, 20))
      .text(
        "WidgetSystem Advantages:",
        ColorF(0.90f, 0.90f, 0.40f, 1.0f),
        13.0f
      )
      .build();

    WidgetBuilder(noteBox, RectF(12, 34, 546, 60))
      .text(
        "- Single Widget node with AnimatedHoverButtonComponent attached\n" ~
        "- Traversed via ctx.visibleWidgets in preLayout and postLayout\n" ~
        "- 60 FPS transitions while active, 0% CPU when animations settle",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f),
        12.0f
      )
      .build();
  }

  void buildGradientPlaySection() {
    auto card = makeSectionCard(
      root,
      RectF(645, 68, 615, 280),
      "2. System Dynamic Gradient Play & Shimmer Wave"
    );

    WidgetBuilder(card, RectF(16, 36, 580, 36))
      .text(
        "Continuous shimmer wave calculated during preLayout phase " ~
          "using cursor normalized coordinates.",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f),
        13.0f
      )
      .build();

    auto btnRow = WidgetBuilder(card, RectF(16, 80, 580, 50))
      .flex(
        FlexDirection.row,
        14.0f,
        JustifyContent.start,
        AlignItems.center
      )
      .build();

    // Button 1: Neon Cyan Wave
    HoverAnimConfig cfg1;
    cfg1.style = HoverAnimConfig.AnimStyle.gradientPlay;
    cfg1.hoverBg = ColorF(0.12f, 0.42f, 0.78f, 1.0f);
    cfg1.gradientAccentBg = ColorF(0.15f, 0.85f, 0.90f, 1.0f);
    cfg1.pressBg = ColorF(0.06f, 0.22f, 0.42f, 1.0f);
    cfg1.hoverBorder = ColorF(0.40f, 0.90f, 1.0f, 1.0f);
    cfg1.actionEvent = "btnCountAction";

    AnimatedHoverButtonBuilder b1;
    b1.text("Cyan Wave")
      .bg(ColorF(0.10f, 0.20f, 0.28f, 1.0f))
      .border(ColorF(0.20f, 0.45f, 0.65f, 1.0f), 1.0f)
      .radius(6.0f)
      .fixedSize(140.0f, 38.0f)
      .anim(cfg1)
      .build(btnRow, RectF(0, 0, 140, 38));

    // Button 2: Gold Sunset Pulse
    HoverAnimConfig cfg2;
    cfg2.style = HoverAnimConfig.AnimStyle.gradientPlay;
    cfg2.hoverBg = ColorF(0.78f, 0.35f, 0.12f, 1.0f);
    cfg2.gradientAccentBg = ColorF(1.0f, 0.82f, 0.20f, 1.0f);
    cfg2.pressBg = ColorF(0.45f, 0.18f, 0.06f, 1.0f);
    cfg2.hoverBorder = ColorF(1.0f, 0.88f, 0.35f, 1.0f);
    cfg2.actionEvent = "btnCountAction";

    AnimatedHoverButtonBuilder b2;
    b2.text("Sunset Glow")
      .bg(ColorF(0.26f, 0.20f, 0.10f, 1.0f))
      .border(ColorF(0.50f, 0.38f, 0.18f, 1.0f), 1.0f)
      .radius(6.0f)
      .fixedSize(145.0f, 38.0f)
      .anim(cfg2)
      .build(btnRow, RectF(0, 0, 145, 38));

    // Button 3: Purple Aurora
    HoverAnimConfig cfg3;
    cfg3.style = HoverAnimConfig.AnimStyle.gradientPlay;
    cfg3.hoverBg = ColorF(0.45f, 0.18f, 0.75f, 1.0f);
    cfg3.gradientAccentBg = ColorF(0.92f, 0.30f, 0.75f, 1.0f);
    cfg3.pressBg = ColorF(0.28f, 0.10f, 0.42f, 1.0f);
    cfg3.hoverBorder = ColorF(0.90f, 0.55f, 1.0f, 1.0f);
    cfg3.actionEvent = "btnCountAction";

    AnimatedHoverButtonBuilder b3;
    b3.text("Purple Aurora")
      .bg(ColorF(0.22f, 0.12f, 0.28f, 1.0f))
      .border(ColorF(0.42f, 0.22f, 0.55f, 1.0f), 1.0f)
      .radius(6.0f)
      .fixedSize(145.0f, 38.0f)
      .anim(cfg3)
      .build(btnRow, RectF(0, 0, 145, 38));

    // Note card
    auto noteBox = WidgetBuilder(card, RectF(16, 148, 580, 110))
      .roundBackground(ColorF(0.09f, 0.11f, 0.14f, 1.0f), 6.0f)
      .border(ColorF(0.20f, 0.23f, 0.28f, 1.0f), 1.0f)
      .padding(10, 12)
      .build();

    WidgetBuilder(noteBox, RectF(12, 10, 556, 20))
      .text(
        "Gradient Wave Features:",
        ColorF(0.90f, 0.90f, 0.40f, 1.0f),
        13.0f
      )
      .build();

    WidgetBuilder(noteBox, RectF(12, 34, 556, 60))
      .text(
        "- Continuous wave oscillation at 60 FPS while cursor is hovered\n" ~
        "- System queries cursorNormX/Y directly from hit test\n" ~
        "- Automatically suspends timeout when cursor departs",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f),
        12.0f
      )
      .build();
  }

  void buildActionCounterSection() {
    auto card = makeSectionCard(
      root,
      RectF(20, 360, 605, 280),
      "3. Interactive Action Button & Click Counter"
    );

    WidgetBuilder(card, RectF(16, 36, 570, 36))
      .text(
        "Clicking the action button dispatches an event via ctx.host. " ~
          "DemoController intercepts the event and updates DemoModel.",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f),
        13.0f
      )
      .build();

    auto actionRow = WidgetBuilder(card, RectF(16, 80, 570, 50))
      .flex(
        FlexDirection.row,
        14.0f,
        JustifyContent.start,
        AlignItems.center
      )
      .build();

    // Primary action trigger
    HoverAnimConfig cfg1;
    cfg1.style = HoverAnimConfig.AnimStyle.fade;
    cfg1.hoverBg = ColorF(0.25f, 0.45f, 0.80f, 1.0f);
    cfg1.pressBg = ColorF(0.10f, 0.22f, 0.45f, 1.0f);
    cfg1.hoverBorder = ColorF(0.60f, 0.85f, 1.0f, 1.0f);
    cfg1.actionEvent = "btnCountAction";

    AnimatedHoverButtonBuilder b1;
    b1.text("+ Click Increment")
      .bg(ColorF(0.15f, 0.30f, 0.55f, 1.0f))
      .border(ColorF(0.30f, 0.55f, 0.95f, 1.0f), 1.5f)
      .radius(8.0f)
      .fixedSize(180.0f, 42.0f)
      .anim(cfg1)
      .build(actionRow, RectF(0, 0, 180, 42));

    // Reset action trigger
    HoverAnimConfig cfg2;
    cfg2.style = HoverAnimConfig.AnimStyle.fade;
    cfg2.hoverBg = ColorF(0.30f, 0.34f, 0.40f, 1.0f);
    cfg2.pressBg = ColorF(0.14f, 0.16f, 0.18f, 1.0f);
    cfg2.hoverBorder = ColorF(0.55f, 0.60f, 0.70f, 1.0f);
    cfg2.actionEvent = "btnCountReset";

    AnimatedHoverButtonBuilder b2;
    b2.text("Reset Counter")
      .bg(ColorF(0.20f, 0.22f, 0.26f, 1.0f))
      .border(ColorF(0.35f, 0.38f, 0.45f, 1.0f), 1.0f)
      .radius(8.0f)
      .fixedSize(140.0f, 42.0f)
      .anim(cfg2)
      .build(actionRow, RectF(0, 0, 140, 42));

    // HUD Counter Display Box
    auto hudBox = WidgetBuilder(card, RectF(16, 148, 570, 110))
      .roundBackground(ColorF(0.09f, 0.12f, 0.16f, 1.0f), 6.0f)
      .border(ColorF(0.25f, 0.35f, 0.50f, 1.0f), 1.5f)
      .padding(12, 16)
      .build();

    counterLabel = WidgetBuilder(hudBox, RectF(16, 14, 538, 28))
      .text(
        "Button Action Invocations: 0 clicks",
        ColorF(0.40f, 0.95f, 0.60f, 1.0f),
        16.0f
      )
      .build();

    WidgetBuilder(hudBox, RectF(16, 50, 538, 44))
      .text(
        "AnimatedHoverButtonSystem dispatches action events on button\n" ~
        "release, seamlessly modifying model state via DemoController.",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f),
        12.0f
      )
      .build();
  }

  void buildArchitectureSection() {
    auto card = makeSectionCard(
      root,
      RectF(645, 360, 615, 280),
      "4. Architecture: WidgetSystem & Component (ECS-Style)"
    );

    WidgetBuilder(card, RectF(16, 36, 580, 50))
      .text(
        "A button instance is a single Widget with " ~
          "AnimatedHoverButtonComponent.\n" ~
        "AnimatedHoverButtonSystem handles event, preLayout, and postLayout\n" ~
        "phases without requiring manual registration or wrapper Views.",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f),
        12.0f
      )
      .build();

    // Pill shaped buttons demonstration
    auto pillRow = WidgetBuilder(card, RectF(16, 92, 580, 48))
      .flex(
        FlexDirection.row,
        14.0f,
        JustifyContent.start,
        AlignItems.center
      )
      .build();

    // Pill Button 1
    HoverAnimConfig pillCfg1;
    pillCfg1.style = HoverAnimConfig.AnimStyle.fade;
    pillCfg1.hoverBg = ColorF(0.40f, 0.28f, 0.60f, 1.0f);
    pillCfg1.pressBg = ColorF(0.18f, 0.12f, 0.26f, 1.0f);
    pillCfg1.hoverBorder = ColorF(0.75f, 0.55f, 1.0f, 1.0f);
    pillCfg1.actionEvent = "btnCountAction";

    AnimatedHoverButtonBuilder p1;
    p1.text("Pill Button (r=18)")
      .bg(ColorF(0.22f, 0.16f, 0.32f, 1.0f))
      .border(ColorF(0.45f, 0.32f, 0.65f, 1.5f), 1.5f)
      .radius(18.0f)
      .fixedSize(170.0f, 36.0f)
      .anim(pillCfg1)
      .build(pillRow, RectF(0, 0, 170, 36));

    // Pill Button 2 with gradient play
    HoverAnimConfig pillCfg2;
    pillCfg2.style = HoverAnimConfig.AnimStyle.gradientPlay;
    pillCfg2.hoverBg = ColorF(0.15f, 0.50f, 0.35f, 1.0f);
    pillCfg2.gradientAccentBg = ColorF(0.25f, 0.92f, 0.65f, 1.0f);
    pillCfg2.pressBg = ColorF(0.08f, 0.30f, 0.20f, 1.0f);
    pillCfg2.hoverBorder = ColorF(0.45f, 0.98f, 0.75f, 1.0f);
    pillCfg2.actionEvent = "btnCountAction";

    AnimatedHoverButtonBuilder p2;
    p2.text("Pill Wave (r=18)")
      .bg(ColorF(0.14f, 0.26f, 0.24f, 1.0f))
      .border(ColorF(0.28f, 0.55f, 0.50f, 1.5f), 1.5f)
      .radius(18.0f)
      .fixedSize(170.0f, 36.0f)
      .anim(pillCfg2)
      .build(pillRow, RectF(0, 0, 170, 36));

    // Explanatory code summary box
    auto archBox = WidgetBuilder(card, RectF(16, 148, 580, 110))
      .roundBackground(ColorF(0.09f, 0.11f, 0.14f, 1.0f), 6.0f)
      .border(ColorF(0.20f, 0.23f, 0.28f, 1.0f), 1.0f)
      .padding(10, 12)
      .build();

    WidgetBuilder(archBox, RectF(12, 8, 556, 18))
      .text(
        "WidgetSystem Pipeline Flow:",
        ColorF(0.95f, 0.80f, 0.30f, 1.0f),
        13.0f
      )
      .build();

    WidgetBuilder(archBox, RectF(12, 28, 556, 72))
      .text(
        "1. AppEvent -> AnimatedHoverButtonSystem.handleEvent\n" ~
        "2. preLayout: AnimatedHoverButtonSystem updates colors " ~
          "(dirty=visuals)\n" ~
        "3. layout: LayoutSystem recalculates geometry (if layoutDirty)\n" ~
        "4. render: WidgetPainterSystem draws widgets to window",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f),
        11.5f
      )
      .build();
  }

  Widget root;
  Widget counterLabel;
}
