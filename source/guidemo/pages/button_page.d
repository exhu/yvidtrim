/**
 * button_page.d - Page 3 showcase for MouseEvent & View hover buttons.
 */
module guidemo.pages.button_page;

import std.format : format;
import guidemo.common : makeSectionCard;
import guidemo.hover_button : HoverAnimConfig, HoverButtonBuilder,
  HoverButtonConfig, HoverButtonController, createHoverButton;
import guidemo.model : DemoModel;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Background, Border, TextLabel;
import yguilib.widget.layout_components : AlignItems, FlexDirection, Insets,
  JustifyContent, Size;

/// Page 3 widget container showcasing HoverButton and HoverButtonController.
final class ButtonPage {
  this(Widget parent) {
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

  /**
   * Registers all buttons created on this page with the shared controller.
   */
  void registerWithController(HoverButtonController controller) {
    assert(controller !is null, "controller must not be null");
    foreach (i, btn; managedButtons) {
      controller.addButton(btn, managedAnimConfigs[i]);
    }
  }

private:
  void buildFadingSection() {
    auto card = makeSectionCard(
      root,
      RectF(20, 68, 605, 280),
      "1. Smooth Color Fading Buttons (Hover & Press Transition)"
    );

    WidgetBuilder(card, RectF(16, 36, 570, 36))
      .text(
        "Hovering transitions background color smoothly via lerp. " ~
          "Pressing darkens/highlights to pressed state.",
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
    HoverButtonBuilder b1;
    auto btn1 = b1
      .text("Slate Button")
      .bg(ColorF(0.18f, 0.20f, 0.25f, 1.0f))
      .border(ColorF(0.30f, 0.35f, 0.45f, 1.0f), 1.0f)
      .radius(6.0f)
      .fixedSize(140.0f, 38.0f)
      .action("fadeBtn1Click")
      .build(btnRow, RectF(0, 0, 140, 38));

    HoverAnimConfig cfg1;
    cfg1.style = HoverAnimConfig.AnimStyle.fade;
    cfg1.hoverBg = ColorF(0.28f, 0.38f, 0.55f, 1.0f);
    cfg1.pressBg = ColorF(0.12f, 0.18f, 0.30f, 1.0f);
    cfg1.hoverBorder = ColorF(0.50f, 0.70f, 1.0f, 1.0f);
    cfg1.actionEvent = "btnCountAction";

    managedButtons ~= btn1;
    managedAnimConfigs ~= cfg1;

    // Button 2: Emerald Success
    HoverButtonBuilder b2;
    auto btn2 = b2
      .text("Emerald Confirm")
      .bg(ColorF(0.12f, 0.24f, 0.18f, 1.0f))
      .border(ColorF(0.20f, 0.45f, 0.30f, 1.0f), 1.0f)
      .radius(6.0f)
      .fixedSize(150.0f, 38.0f)
      .action("btnCountAction")
      .build(btnRow, RectF(0, 0, 150, 38));

    HoverAnimConfig cfg2;
    cfg2.style = HoverAnimConfig.AnimStyle.fade;
    cfg2.hoverBg = ColorF(0.18f, 0.55f, 0.35f, 1.0f);
    cfg2.pressBg = ColorF(0.08f, 0.35f, 0.20f, 1.0f);
    cfg2.hoverBorder = ColorF(0.35f, 0.85f, 0.55f, 1.0f);
    cfg2.actionEvent = "btnCountAction";

    managedButtons ~= btn2;
    managedAnimConfigs ~= cfg2;

    // Button 3: Crimson Danger
    HoverButtonBuilder b3;
    auto btn3 = b3
      .text("Crimson Delete")
      .bg(ColorF(0.26f, 0.12f, 0.14f, 1.0f))
      .border(ColorF(0.48f, 0.20f, 0.24f, 1.0f), 1.0f)
      .radius(6.0f)
      .fixedSize(140.0f, 38.0f)
      .action("btnCountAction")
      .build(btnRow, RectF(0, 0, 140, 38));

    HoverAnimConfig cfg3;
    cfg3.style = HoverAnimConfig.AnimStyle.fade;
    cfg3.hoverBg = ColorF(0.65f, 0.20f, 0.25f, 1.0f);
    cfg3.pressBg = ColorF(0.40f, 0.10f, 0.15f, 1.0f);
    cfg3.hoverBorder = ColorF(0.95f, 0.40f, 0.45f, 1.0f);
    cfg3.actionEvent = "btnCountAction";

    managedButtons ~= btn3;
    managedAnimConfigs ~= cfg3;

    // Note card
    auto noteBox = WidgetBuilder(card, RectF(16, 148, 570, 110))
      .roundBackground(ColorF(0.09f, 0.11f, 0.14f, 1.0f), 6.0f)
      .border(ColorF(0.20f, 0.23f, 0.28f, 1.0f), 1.0f)
      .padding(10, 12)
      .build();

    WidgetBuilder(noteBox, RectF(12, 10, 546, 20))
      .text(
        "Fading Features:",
        ColorF(0.90f, 0.90f, 0.40f, 1.0f),
        13.0f
      )
      .build();

    WidgetBuilder(noteBox, RectF(12, 34, 546, 60))
      .text(
        "- Independent color lerping for background and border\n" ~
        "- Dynamic hoverProgress tracking on enter/leave\n" ~
        "- Immediate press feedback on mouseDown / mouseUp",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f),
        12.0f
      )
      .build();
  }

  void buildGradientPlaySection() {
    auto card = makeSectionCard(
      root,
      RectF(645, 68, 615, 280),
      "2. Dynamic Gradient Play & Shimmer Wave"
    );

    WidgetBuilder(card, RectF(16, 36, 580, 36))
      .text(
        "Hovering triggers dynamic gradient play with wave oscillation " ~
          "sin(phase + cursorX * PI) while cursor is over the button.",
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
    HoverButtonBuilder b1;
    auto btn1 = b1
      .text("Cyan Wave")
      .bg(ColorF(0.10f, 0.20f, 0.28f, 1.0f))
      .border(ColorF(0.20f, 0.45f, 0.65f, 1.0f), 1.0f)
      .radius(6.0f)
      .fixedSize(140.0f, 38.0f)
      .action("btnCountAction")
      .build(btnRow, RectF(0, 0, 140, 38));

    HoverAnimConfig cfg1;
    cfg1.style = HoverAnimConfig.AnimStyle.gradientPlay;
    cfg1.hoverBg = ColorF(0.15f, 0.45f, 0.75f, 1.0f);
    cfg1.pressBg = ColorF(0.08f, 0.25f, 0.45f, 1.0f);
    cfg1.hoverBorder = ColorF(0.40f, 0.85f, 1.0f, 1.0f);
    cfg1.actionEvent = "btnCountAction";

    managedButtons ~= btn1;
    managedAnimConfigs ~= cfg1;

    // Button 2: Gold Sunset Pulse
    HoverButtonBuilder b2;
    auto btn2 = b2
      .text("Sunset Glow")
      .bg(ColorF(0.26f, 0.20f, 0.10f, 1.0f))
      .border(ColorF(0.50f, 0.38f, 0.18f, 1.0f), 1.0f)
      .radius(6.0f)
      .fixedSize(145.0f, 38.0f)
      .action("btnCountAction")
      .build(btnRow, RectF(0, 0, 145, 38));

    HoverAnimConfig cfg2;
    cfg2.style = HoverAnimConfig.AnimStyle.gradientPlay;
    cfg2.hoverBg = ColorF(0.70f, 0.48f, 0.15f, 1.0f);
    cfg2.pressBg = ColorF(0.45f, 0.28f, 0.08f, 1.0f);
    cfg2.hoverBorder = ColorF(1.0f, 0.80f, 0.30f, 1.0f);
    cfg2.actionEvent = "btnCountAction";

    managedButtons ~= btn2;
    managedAnimConfigs ~= cfg2;

    // Button 3: Purple Aurora
    HoverButtonBuilder b3;
    auto btn3 = b3
      .text("Purple Aurora")
      .bg(ColorF(0.22f, 0.12f, 0.28f, 1.0f))
      .border(ColorF(0.42f, 0.22f, 0.55f, 1.0f), 1.0f)
      .radius(6.0f)
      .fixedSize(145.0f, 38.0f)
      .action("btnCountAction")
      .build(btnRow, RectF(0, 0, 145, 38));

    HoverAnimConfig cfg3;
    cfg3.style = HoverAnimConfig.AnimStyle.gradientPlay;
    cfg3.hoverBg = ColorF(0.55f, 0.25f, 0.75f, 1.0f);
    cfg3.pressBg = ColorF(0.35f, 0.12f, 0.50f, 1.0f);
    cfg3.hoverBorder = ColorF(0.85f, 0.50f, 1.0f, 1.0f);
    cfg3.actionEvent = "btnCountAction";

    managedButtons ~= btn3;
    managedAnimConfigs ~= cfg3;

    // Note card
    auto noteBox = WidgetBuilder(card, RectF(16, 148, 580, 110))
      .roundBackground(ColorF(0.09f, 0.11f, 0.14f, 1.0f), 6.0f)
      .border(ColorF(0.20f, 0.23f, 0.28f, 1.0f), 1.0f)
      .padding(10, 12)
      .build();

    WidgetBuilder(noteBox, RectF(12, 10, 556, 20))
      .text(
        "Gradient Play Features:",
        ColorF(0.90f, 0.90f, 0.40f, 1.0f),
        13.0f
      )
      .build();

    WidgetBuilder(noteBox, RectF(12, 34, 556, 60))
      .text(
        "- Continuous wave oscillation at 60 FPS while cursor is hovered\n" ~
        "- Responsive highlight position tracking mouse cursor X coordinate\n" ~
        "- Reverts cleanly to idle (0% CPU) when cursor leaves",
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
        "Clicking the action button dispatches an event via uiSystem. " ~
          "DemoController intercepts the event and updates the model.",
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
    HoverButtonBuilder b1;
    auto btn1 = b1
      .text("+ Click Increment")
      .bg(ColorF(0.15f, 0.30f, 0.55f, 1.0f))
      .border(ColorF(0.30f, 0.55f, 0.95f, 1.0f), 1.5f)
      .radius(8.0f)
      .fixedSize(180.0f, 42.0f)
      .action("btnCountAction")
      .build(actionRow, RectF(0, 0, 180, 42));

    HoverAnimConfig cfg1;
    cfg1.style = HoverAnimConfig.AnimStyle.fade;
    cfg1.hoverBg = ColorF(0.25f, 0.45f, 0.80f, 1.0f);
    cfg1.pressBg = ColorF(0.10f, 0.22f, 0.45f, 1.0f);
    cfg1.hoverBorder = ColorF(0.60f, 0.85f, 1.0f, 1.0f);
    cfg1.actionEvent = "btnCountAction";

    managedButtons ~= btn1;
    managedAnimConfigs ~= cfg1;

    // Reset action trigger
    HoverButtonBuilder b2;
    auto btn2 = b2
      .text("Reset Counter")
      .bg(ColorF(0.20f, 0.22f, 0.26f, 1.0f))
      .border(ColorF(0.35f, 0.38f, 0.45f, 1.0f), 1.0f)
      .radius(8.0f)
      .fixedSize(140.0f, 42.0f)
      .action("btnCountReset")
      .build(actionRow, RectF(0, 0, 140, 42));

    HoverAnimConfig cfg2;
    cfg2.style = HoverAnimConfig.AnimStyle.fade;
    cfg2.hoverBg = ColorF(0.30f, 0.34f, 0.40f, 1.0f);
    cfg2.pressBg = ColorF(0.14f, 0.16f, 0.18f, 1.0f);
    cfg2.hoverBorder = ColorF(0.55f, 0.60f, 0.70f, 1.0f);
    cfg2.actionEvent = "btnCountReset";

    managedButtons ~= btn2;
    managedAnimConfigs ~= cfg2;

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
        "Each button press-release sequence triggers an AppEvent.Kind.view\n" ~
        "action event handled by DemoController to modify DemoModel.",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f),
        12.0f
      )
      .build();
  }

  void buildArchitectureSection() {
    auto card = makeSectionCard(
      root,
      RectF(645, 360, 615, 280),
      "4. Architecture: View & MouseEvent Encapsulation"
    );

    WidgetBuilder(card, RectF(16, 36, 580, 50))
      .text(
        "A button instance consists of an empty root Widget with View\n" ~
        "component and a visual child with MouseEvent. A single controller\n" ~
        "services all buttons via dynamic array registration.",
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
    HoverButtonBuilder p1;
    auto pill1 = p1
      .text("Pill Button (r=18)")
      .bg(ColorF(0.22f, 0.16f, 0.32f, 1.0f))
      .border(ColorF(0.45f, 0.32f, 0.65f, 1.0f), 1.5f)
      .radius(18.0f)
      .fixedSize(170.0f, 36.0f)
      .action("btnCountAction")
      .build(pillRow, RectF(0, 0, 170, 36));

    HoverAnimConfig pillCfg1;
    pillCfg1.style = HoverAnimConfig.AnimStyle.fade;
    pillCfg1.hoverBg = ColorF(0.40f, 0.28f, 0.60f, 1.0f);
    pillCfg1.pressBg = ColorF(0.18f, 0.12f, 0.26f, 1.0f);
    pillCfg1.hoverBorder = ColorF(0.75f, 0.55f, 1.0f, 1.0f);
    pillCfg1.actionEvent = "btnCountAction";

    managedButtons ~= pill1;
    managedAnimConfigs ~= pillCfg1;

    // Pill Button 2 with gradient play
    HoverButtonBuilder p2;
    auto pill2 = p2
      .text("Pill Wave (r=18)")
      .bg(ColorF(0.14f, 0.26f, 0.24f, 1.0f))
      .border(ColorF(0.28f, 0.55f, 0.50f, 1.0f), 1.5f)
      .radius(18.0f)
      .fixedSize(170.0f, 36.0f)
      .action("btnCountAction")
      .build(pillRow, RectF(0, 0, 170, 36));

    HoverAnimConfig pillCfg2;
    pillCfg2.style = HoverAnimConfig.AnimStyle.gradientPlay;
    pillCfg2.hoverBg = ColorF(0.22f, 0.55f, 0.48f, 1.0f);
    pillCfg2.pressBg = ColorF(0.10f, 0.32f, 0.26f, 1.0f);
    pillCfg2.hoverBorder = ColorF(0.45f, 0.95f, 0.85f, 1.0f);
    pillCfg2.actionEvent = "btnCountAction";

    managedButtons ~= pill2;
    managedAnimConfigs ~= pillCfg2;

    // Explanatory code summary box
    auto archBox = WidgetBuilder(card, RectF(16, 148, 580, 110))
      .roundBackground(ColorF(0.09f, 0.11f, 0.14f, 1.0f), 6.0f)
      .border(ColorF(0.20f, 0.23f, 0.28f, 1.0f), 1.0f)
      .padding(10, 12)
      .build();

    WidgetBuilder(archBox, RectF(12, 8, 556, 18))
      .text(
        "Event Bubbling Chain:",
        ColorF(0.95f, 0.80f, 0.30f, 1.0f),
        13.0f
      )
      .build();

    WidgetBuilder(archBox, RectF(12, 28, 556, 72))
      .text(
        "1. Child widget MouseEvent captures: mouseEnter/leave/down/up\n" ~
        "2. InputSystem.passEvent bubbles event up to nearest parent View\n" ~
        "3. View.renameEvents sets eventName and event.view.viewWidget\n" ~
        "4. Non-modal HoverButtonController animates matching viewWidget",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f),
        11.5f
      )
      .build();
  }

  Widget root;
  Widget counterLabel;
  Widget[] managedButtons;
  HoverAnimConfig[] managedAnimConfigs;
}
