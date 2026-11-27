/**
 * button_page.d - Page 3 showcase for MouseEvent & View hover buttons.
 */
module guidemo.pages.button_page;

import guidemo.common : makeSectionCard;
import guidemo.hover_button : HoverAnimConfig, HoverButtonBuilder,
  HoverButtonConfig, HoverButtonController, createHoverButton;
import guidemo.model : ButtonPageModel;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Background, Border, TextLabel;
import yguilib.widget.layout_components : AlignItems, FlexDirection, Insets,
  JustifyContent, Size;

/// View event names emitted by Page 3 buttons.
enum btnCountActionEvent = "btnCountAction";
enum btnCountResetEvent = "btnCountReset";

/// Page 3 widget container showcasing HoverButton and HoverButtonController.
final class ButtonPage {
  @disable this();

  /// Constructs ButtonPage with an externally created `modelTracker`.
  this(
    UiSystem ui,
    Widget parent,
    ref ModelTracker!ButtonPageModel modelTracker
  ) {
    assert(ui !is null, "UiSystem must not be null");
    assert(parent !is null, "parent must not be null");
    this.ui = ui;
    tracker = ModelTracker!ButtonPageModel.from(modelTracker);
    root = new Widget(ui.nextWidgetId());
    root.name = "buttonPage";
    root.rect = RectF(0, 0, 1280, 720);
    parent.addChild(root);

    buildFadingSection();
    buildGradientPlaySection();
    buildActionCounterSection();
    buildArchitectureSection();
  }

  invariant {
    assert(root !is null);
  }

  /// Syncs widgets from the page model when it changed.
  void update() {
    import std.format : format;

    if (!tracker.update()) {
      return;
    }

    if (counterLabel !is null && counterLabel.components.textLabel !is null) {
      const string text = format(
        "Button Action Invocations: %d clicks",
        tracker.model.buttonClickCount
      );
      if (counterLabel.components.textLabel.caption != text) {
        counterLabel.components.textLabel.caption = text;
        counterLabel.update(WidgetUpdateScope.content);
      }
    }
  }

  /// Returns the status bar text for this page.
  string formatStatus() {
    import std.format : format;

    return format("Clicks: %d", tracker.model.buttonClickCount);
  }

  /// Returns the page root widget.
  Widget rootWidget() {
    return root;
  }

  /// Shows or hides the page.
  void visible(bool visible) {
    if (root.visible != visible) {
      root.visible = visible;
      root.update(WidgetUpdateScope.layout);
    }
  }

  /// Returns whether the page is visible.
  bool visible() const {
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
  void registerManagedButton(
    Widget row,
    ref HoverButtonBuilder builder,
    float width,
    float height,
    HoverAnimConfig cfg
  ) {
    auto btn = builder.build(ui, row, RectF(0, 0, width, height));
    managedButtons ~= btn;
    managedAnimConfigs ~= cfg;
  }

  void buildFadingSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(20, 68, 605, 280),
      "1. Smooth Color Fading Buttons (Hover & Press Transition)",
      "buttonFadingCard"
    );

    WidgetBuilder.make(ui)
      .parent(card)
      .name("fadingDescLabel")
      .rect(RectF(16, 36, 570, 36))
      .text(
        "Hovering transitions background color smoothly via lerp. " ~
          "Pressing darkens/highlights to pressed state."
      )
      .textColor(ColorF(0.70f, 0.75f, 0.85f, 1.0f))
      .fontSize(13.0f)
      .build();

    auto btnRow = WidgetBuilder.make(ui)
      .parent(card)
      .name("fadeBtnRow")
      .rect(RectF(16, 80, 570, 50))
      .flexRow()
      .gap(14.0f)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.center)
      .build();

    buildFadingButtons(btnRow);
    buildFadingNoteBox(card);
  }

  void buildFadingButtons(Widget btnRow) {
    HoverButtonBuilder b1;
    b1.name("fadeSlateBtn")
      .text("Slate Button")
      .bg(ColorF(0.18f, 0.20f, 0.25f, 1.0f))
      .border(ColorF(0.30f, 0.35f, 0.45f, 1.0f), 1.0f)
      .radius(6.0f)
      .fixedSize(140.0f, 38.0f)
      .action("fadeBtn1Click").captionTooltip();
    HoverAnimConfig cfg1;
    cfg1.style = HoverAnimConfig.AnimStyle.fade;
    cfg1.hoverBg = ColorF(0.28f, 0.38f, 0.55f, 1.0f);
    cfg1.pressBg = ColorF(0.12f, 0.18f, 0.30f, 1.0f);
    cfg1.hoverBorder = ColorF(0.50f, 0.70f, 1.0f, 1.0f);
    cfg1.actionEvent = "btnCountAction";
    registerManagedButton(btnRow, b1, 140.0f, 38.0f, cfg1);

    HoverButtonBuilder b2;
    b2.name("fadeEmeraldBtn")
      .text("Emerald Confirm Action With Long Truncated Caption For Tooltip")
      .bg(ColorF(0.12f, 0.24f, 0.18f, 1.0f))
      .border(ColorF(0.20f, 0.45f, 0.30f, 1.0f), 1.0f)
      .radius(6.0f)
      .fixedSize(150.0f, 38.0f)
      .action("btnCountAction").captionTooltip();
    HoverAnimConfig cfg2;
    cfg2.style = HoverAnimConfig.AnimStyle.fade;
    cfg2.hoverBg = ColorF(0.18f, 0.55f, 0.35f, 1.0f);
    cfg2.pressBg = ColorF(0.08f, 0.35f, 0.20f, 1.0f);
    cfg2.hoverBorder = ColorF(0.35f, 0.85f, 0.55f, 1.0f);
    cfg2.actionEvent = "btnCountAction";
    registerManagedButton(btnRow, b2, 150.0f, 38.0f, cfg2);

    HoverButtonBuilder b3;
    b3.name("fadeCrimsonBtn")
      .text("Crimson Delete")
      .bg(ColorF(0.26f, 0.12f, 0.14f, 1.0f))
      .border(ColorF(0.48f, 0.20f, 0.24f, 1.0f), 1.0f)
      .radius(6.0f)
      .fixedSize(140.0f, 38.0f)
      .action("btnCountAction").captionTooltip();
    HoverAnimConfig cfg3;
    cfg3.style = HoverAnimConfig.AnimStyle.fade;
    cfg3.hoverBg = ColorF(0.65f, 0.20f, 0.25f, 1.0f);
    cfg3.pressBg = ColorF(0.40f, 0.10f, 0.15f, 1.0f);
    cfg3.hoverBorder = ColorF(0.95f, 0.40f, 0.45f, 1.0f);
    cfg3.actionEvent = "btnCountAction";
    registerManagedButton(btnRow, b3, 140.0f, 38.0f, cfg3);
  }

  void buildFadingNoteBox(Widget card) {
    auto noteBox = WidgetBuilder.make(ui)
      .parent(card)
      .name("fadingNoteBox")
      .rect(RectF(16, 148, 570, 110))
      .roundBg(ColorF(0.09f, 0.11f, 0.14f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.20f, 0.23f, 0.28f, 1.0f))
      .borderWidth(1.0f)
      .paddingVh(10, 12)
      .build();

    WidgetBuilder.make(ui)
      .parent(noteBox)
      .name("fadingNoteTitle")
      .rect(RectF(12, 10, 546, 20))
      .text("Fading Features:")
      .textColor(ColorF(0.90f, 0.90f, 0.40f, 1.0f))
      .fontSize(13.0f)
      .build();

    WidgetBuilder.make(ui)
      .parent(noteBox)
      .name("fadingNoteBody")
      .rect(RectF(12, 34, 546, 60))
      .text(
        "- Independent color lerping for background and border\n" ~
        "- Dynamic hoverProgress tracking on enter/leave\n" ~
        "- Immediate press feedback on mouseDown / mouseUp"
      )
      .textColor(ColorF(0.70f, 0.75f, 0.85f, 1.0f))
      .fontSize(12.0f)
      .build();
  }

  void buildGradientPlaySection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(645, 68, 615, 280),
      "2. Dynamic Gradient Play & Shimmer Wave",
      "buttonGradientCard"
    );

    WidgetBuilder.make(ui)
      .parent(card)
      .name("gradientDescLabel")
      .rect(RectF(16, 36, 580, 36))
      .text(
        "Hovering triggers dynamic gradient play with wave oscillation " ~
          "sin(phase + cursorX * PI) while cursor is over the button."
      )
      .textColor(ColorF(0.70f, 0.75f, 0.85f, 1.0f))
      .fontSize(13.0f)
      .build();

    auto btnRow = WidgetBuilder.make(ui)
      .parent(card)
      .name("gradientBtnRow")
      .rect(RectF(16, 80, 580, 50))
      .flexRow()
      .gap(14.0f)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.center)
      .build();

    buildGradientButtons(btnRow);
    buildGradientNoteBox(card);
  }

  void addGradientButton(
    Widget btnRow,
    string btnName,
    string caption,
    float width,
    ColorF bgCol,
    ColorF borderCol,
    ColorF hoverBg,
    ColorF accentBg,
    ColorF pressBg,
    ColorF hoverBorder
  ) {
    HoverButtonBuilder b;
    b.name(btnName)
      .text(caption)
      .bg(bgCol)
      .border(borderCol, 1.0f)
      .radius(6.0f)
      .fixedSize(width, 38.0f)
      .action("btnCountAction")
      .captionTooltip();
    HoverAnimConfig cfg;
    cfg.style = HoverAnimConfig.AnimStyle.gradientPlay;
    cfg.hoverBg = hoverBg;
    cfg.gradientAccentBg = accentBg;
    cfg.pressBg = pressBg;
    cfg.hoverBorder = hoverBorder;
    cfg.actionEvent = "btnCountAction";
    registerManagedButton(btnRow, b, width, 38.0f, cfg);
  }

  void buildGradientButtons(Widget btnRow) {
    addGradientButton(
      btnRow, "gradCyanBtn", "Cyan Wave", 140.0f,
      ColorF(0.10f, 0.20f, 0.28f, 1.0f), ColorF(0.20f, 0.45f, 0.65f, 1.0f),
      ColorF(0.12f, 0.42f, 0.78f, 1.0f), ColorF(0.15f, 0.85f, 0.90f, 1.0f),
      ColorF(0.06f, 0.22f, 0.42f, 1.0f), ColorF(0.40f, 0.90f, 1.0f, 1.0f)
    );
    addGradientButton(
      btnRow, "gradSunsetBtn", "Sunset Glow", 145.0f,
      ColorF(0.26f, 0.20f, 0.10f, 1.0f), ColorF(0.50f, 0.38f, 0.18f, 1.0f),
      ColorF(0.78f, 0.35f, 0.12f, 1.0f), ColorF(1.0f, 0.82f, 0.20f, 1.0f),
      ColorF(0.45f, 0.18f, 0.06f, 1.0f), ColorF(1.0f, 0.88f, 0.35f, 1.0f)
    );
    addGradientButton(
      btnRow, "gradAuroraBtn", "Purple Aurora", 145.0f,
      ColorF(0.22f, 0.12f, 0.28f, 1.0f), ColorF(0.42f, 0.22f, 0.55f, 1.0f),
      ColorF(0.45f, 0.18f, 0.75f, 1.0f), ColorF(0.92f, 0.30f, 0.75f, 1.0f),
      ColorF(0.28f, 0.10f, 0.42f, 1.0f), ColorF(0.90f, 0.55f, 1.0f, 1.0f)
    );
  }

  void buildGradientNoteBox(Widget card) {
    auto noteBox = WidgetBuilder.make(ui)
      .parent(card)
      .name("gradientNoteBox")
      .rect(RectF(16, 148, 580, 110))
      .roundBg(ColorF(0.09f, 0.11f, 0.14f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.20f, 0.23f, 0.28f, 1.0f))
      .borderWidth(1.0f)
      .paddingVh(10, 12)
      .build();

    WidgetBuilder.make(ui)
      .parent(noteBox)
      .name("gradientNoteTitle")
      .rect(RectF(12, 10, 556, 20))
      .text("Gradient Play Features:")
      .textColor(ColorF(0.90f, 0.90f, 0.40f, 1.0f))
      .fontSize(13.0f)
      .build();

    WidgetBuilder.make(ui)
      .parent(noteBox)
      .name("gradientNoteBody")
      .rect(RectF(12, 34, 556, 60))
      .text(
        "- Continuous wave oscillation at 60 FPS while cursor is hovered\n" ~
        "- Responsive highlight position tracking mouse cursor X coordinate\n" ~
        "- Reverts cleanly to idle (0% CPU) when cursor leaves"
      )
      .textColor(ColorF(0.70f, 0.75f, 0.85f, 1.0f))
      .fontSize(12.0f)
      .build();
  }

  void buildActionCounterSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(20, 360, 605, 280),
      "3. Interactive Action Button & Click Counter",
      "buttonCounterCard"
    );

    WidgetBuilder.make(ui)
      .parent(card)
      .name("counterDescLabel")
      .rect(RectF(16, 36, 570, 36))
      .text(
        "Clicking the action button dispatches an event via uiSystem. " ~
          "DemoController intercepts the event and updates the model."
      )
      .textColor(ColorF(0.70f, 0.75f, 0.85f, 1.0f))
      .fontSize(13.0f)
      .build();

    auto actionRow = WidgetBuilder.make(ui)
      .parent(card)
      .name("actionBtnRow")
      .rect(RectF(16, 80, 570, 50))
      .flexRow()
      .gap(14.0f)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.center)
      .build();

    buildActionButtons(actionRow);
    buildCounterHudBox(card);
  }

  void buildActionButtons(Widget actionRow) {
    HoverButtonBuilder b1;
    b1.name("incrementBtn")
      .text("+ Click Increment")
      .bg(ColorF(0.15f, 0.30f, 0.55f, 1.0f))
      .border(ColorF(0.30f, 0.55f, 0.95f, 1.0f), 1.5f)
      .radius(8.0f)
      .fixedSize(180.0f, 42.0f)
      .action("btnCountAction")
      .captionTooltip();
    HoverAnimConfig cfg1;
    cfg1.style = HoverAnimConfig.AnimStyle.fade;
    cfg1.hoverBg = ColorF(0.25f, 0.45f, 0.80f, 1.0f);
    cfg1.pressBg = ColorF(0.10f, 0.22f, 0.45f, 1.0f);
    cfg1.hoverBorder = ColorF(0.60f, 0.85f, 1.0f, 1.0f);
    cfg1.actionEvent = "btnCountAction";
    registerManagedButton(actionRow, b1, 180.0f, 42.0f, cfg1);

    HoverButtonBuilder b2;
    b2.name("resetCounterBtn")
      .text("Reset Counter")
      .bg(ColorF(0.20f, 0.22f, 0.26f, 1.0f))
      .border(ColorF(0.35f, 0.38f, 0.45f, 1.0f), 1.0f)
      .radius(8.0f)
      .fixedSize(140.0f, 42.0f)
      .action("btnCountReset")
      .captionTooltip();
    HoverAnimConfig cfg2;
    cfg2.style = HoverAnimConfig.AnimStyle.fade;
    cfg2.hoverBg = ColorF(0.30f, 0.34f, 0.40f, 1.0f);
    cfg2.pressBg = ColorF(0.14f, 0.16f, 0.18f, 1.0f);
    cfg2.hoverBorder = ColorF(0.55f, 0.60f, 0.70f, 1.0f);
    cfg2.actionEvent = "btnCountReset";
    registerManagedButton(actionRow, b2, 140.0f, 42.0f, cfg2);
  }

  void buildCounterHudBox(Widget card) {
    auto hudBox = WidgetBuilder.make(ui)
      .parent(card)
      .name("counterHudBox")
      .rect(RectF(16, 148, 570, 110))
      .roundBg(ColorF(0.09f, 0.12f, 0.16f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.25f, 0.35f, 0.50f, 1.0f))
      .borderWidth(1.5f)
      .paddingVh(12, 16)
      .build();

    counterLabel = WidgetBuilder.make(ui)
      .parent(hudBox)
      .name("counterLabel")
      .rect(RectF(16, 14, 538, 28))
      .text("Button Action Invocations: 0 clicks")
      .textColor(ColorF(0.40f, 0.95f, 0.60f, 1.0f))
      .fontSize(16.0f)
      .build();

    WidgetBuilder.make(ui)
      .parent(hudBox)
      .name("counterHintLabel")
      .rect(RectF(16, 50, 538, 44))
      .text(
        "Each button press-release sequence triggers an AppEvent.Kind.view\n" ~
        "action event handled by DemoController to modify DemoModel."
      )
      .textColor(ColorF(0.70f, 0.75f, 0.85f, 1.0f))
      .fontSize(12.0f)
      .build();
  }

  void buildArchitectureSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(645, 360, 615, 280),
      "4. Architecture: View & MouseEvent Encapsulation",
      "buttonArchCard"
    );

    WidgetBuilder.make(ui)
      .parent(card)
      .name("buttonArchDescLabel")
      .rect(RectF(16, 36, 580, 50))
      .text(
        "A button instance consists of an empty root Widget with View\n" ~
        "component and a visual child with MouseEvent. A single controller\n" ~
        "services all buttons via dynamic array registration."
      )
      .textColor(ColorF(0.70f, 0.75f, 0.85f, 1.0f))
      .fontSize(12.0f)
      .build();

    // Pill shaped buttons demonstration
    auto pillRow = WidgetBuilder.make(ui)
      .parent(card)
      .name("pillBtnRow")
      .rect(RectF(16, 92, 580, 48))
      .flexRow()
      .gap(14.0f)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.center)
      .build();

    buildPillButtons(pillRow);
    buildArchBox(card);
  }

  void buildPillButtons(Widget pillRow) {
    HoverButtonBuilder p1;
    p1.name("pillFadeBtn")
      .text("Pill Button (r=18)")
      .bg(ColorF(0.22f, 0.16f, 0.32f, 1.0f))
      .border(ColorF(0.45f, 0.32f, 0.65f, 1.0f), 1.5f)
      .radius(18.0f)
      .fixedSize(170.0f, 36.0f)
      .action("btnCountAction")
      .captionTooltip();
    HoverAnimConfig pillCfg1;
    pillCfg1.style = HoverAnimConfig.AnimStyle.fade;
    pillCfg1.hoverBg = ColorF(0.40f, 0.28f, 0.60f, 1.0f);
    pillCfg1.pressBg = ColorF(0.18f, 0.12f, 0.26f, 1.0f);
    pillCfg1.hoverBorder = ColorF(0.75f, 0.55f, 1.0f, 1.0f);
    pillCfg1.actionEvent = "btnCountAction";
    registerManagedButton(pillRow, p1, 170.0f, 36.0f, pillCfg1);

    HoverButtonBuilder p2;
    p2.name("pillWaveBtn")
      .text("Pill Wave (r=18)")
      .bg(ColorF(0.14f, 0.26f, 0.24f, 1.0f))
      .border(ColorF(0.28f, 0.55f, 0.50f, 1.0f), 1.5f)
      .radius(18.0f)
      .fixedSize(170.0f, 36.0f)
      .action("btnCountAction")
      .captionTooltip();
    HoverAnimConfig pillCfg2;
    pillCfg2.style = HoverAnimConfig.AnimStyle.gradientPlay;
    pillCfg2.hoverBg = ColorF(0.15f, 0.50f, 0.35f, 1.0f);
    pillCfg2.gradientAccentBg = ColorF(0.25f, 0.92f, 0.65f, 1.0f);
    pillCfg2.pressBg = ColorF(0.08f, 0.30f, 0.20f, 1.0f);
    pillCfg2.hoverBorder = ColorF(0.45f, 0.98f, 0.75f, 1.0f);
    pillCfg2.actionEvent = "btnCountAction";
    registerManagedButton(pillRow, p2, 170.0f, 36.0f, pillCfg2);
  }

  void buildArchBox(Widget card) {
    auto archBox = WidgetBuilder.make(ui)
      .parent(card)
      .name("buttonArchBox")
      .rect(RectF(16, 148, 580, 110))
      .roundBg(ColorF(0.09f, 0.11f, 0.14f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.20f, 0.23f, 0.28f, 1.0f))
      .borderWidth(1.0f)
      .paddingVh(10, 12)
      .build();

    WidgetBuilder.make(ui)
      .parent(archBox)
      .name("buttonArchTitle")
      .rect(RectF(12, 8, 556, 18))
      .text("Event Bubbling Chain:")
      .textColor(ColorF(0.95f, 0.80f, 0.30f, 1.0f))
      .fontSize(13.0f)
      .build();

    WidgetBuilder.make(ui)
      .parent(archBox)
      .name("buttonArchBody")
      .rect(RectF(12, 28, 556, 72))
      .text(
        "1. Child widget MouseEvent captures: mouseEnter/leave/down/up\n" ~
        "2. InputSystem.passEvent bubbles event up to nearest parent View\n" ~
        "3. View.renameEvents sets eventName and event.view.viewWidget\n" ~
        "4. Non-modal HoverButtonController animates matching viewWidget"
      )
      .textColor(ColorF(0.70f, 0.75f, 0.85f, 1.0f))
      .fontSize(11.5f)
      .build();
  }

  UiSystem ui;
  ModelTracker!ButtonPageModel tracker;
  Widget root;
  Widget counterLabel;
  Widget[] managedButtons;
  HoverAnimConfig[] managedAnimConfigs;
}

unittest {
  import yguilib.controls.tooltip : Tooltip;
  import yguilib.uisystem : makeHeadlessUiSystem;

  auto ui = makeHeadlessUiSystem();
  auto parent = new Widget(ui.nextWidgetId());
  auto pageTracker = ModelTracker!ButtonPageModel(new ButtonPageModel());
  auto page = new ButtonPage(ui, parent, pageTracker);

  assert(page.managedButtons.length > 0);
  bool foundLongCaption = false;
  foreach (btn; page.managedButtons) {
    assert(btn.children.length > 0);
    auto visual = btn.children[0];
    assert(visual.components.has!Tooltip());
    assert(visual.components.textLabel !is null);
    const string resolved = visual.components.get!Tooltip().resolveText(visual);
    assert(resolved == visual.components.textLabel.caption);
    if (btn.name == "fadeEmeraldBtn") {
      assert(resolved.length > 30);
      foundLongCaption = true;
    }
  }
  assert(foundLongCaption);
}
