/**
 * simple_button_page.d - Page 9 showcase for the plain push `Button`
 * control (`yguilib.controls.button`): styles, disabled state and sizing.
 */
module guidemo.pages.simple_button_page;

import guidemo.common : makeSectionCard;
import guidemo.model : SimpleButtonPageModel;
import yguilib.controls.button : ButtonBuilder, ButtonStyle;
import yguilib.controls.common : WidgetColors;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.layout_components : AlignItems, JustifyContent;

/// View event names emitted by the Page 9 buttons.
enum simpleBtnPrimaryEvent = "simpleBtnPrimary";
enum simpleBtnSecondaryEvent = "simpleBtnSecondary";
enum simpleBtnDangerEvent = "simpleBtnDanger";
enum simpleBtnTargetEvent = "simpleBtnTarget";
enum simpleBtnToggleEvent = "simpleBtnToggle";
enum simpleBtnFixedEvent = "simpleBtnFixed";
enum simpleBtnAutoEvent = "simpleBtnAuto";

/// Page 9 widget container showcasing the plain push button control.
final class SimpleButtonPage {
  @disable this();

  /// Constructs SimpleButtonPage with an externally created `modelTracker`.
  this(
    UiSystem ui,
    Widget parent,
    ref ModelTracker!SimpleButtonPageModel modelTracker
  ) {
    assert(ui !is null, "UiSystem must not be null");
    assert(parent !is null, "parent must not be null");
    this.ui = ui;
    tracker = ModelTracker!SimpleButtonPageModel.from(modelTracker);
    root = new Widget(ui.nextWidgetId());
    root.name = "simpleButtonPage";
    root.rect = RectF(0, 0, 1280, 720);
    parent.addChild(root);

    buildStylesSection();
    buildDisabledSection();
    buildSizingSection();
  }

  invariant {
    assert(root !is null);
  }

  /// Syncs labels and the target button enabled state from the model.
  void update() {
    if (!tracker.update()) {
      return;
    }
    statsLabel.setCaption(formatStats());
    stateLabel.setCaption(formatTargetState());
    targetBtn.setInputEnabled(tracker.model.targetEnabled);
  }

  /// Returns the click counter text shown in the styles section.
  string formatStats() {
    import std.format : format;

    const auto m = tracker.model;
    return format("Clicks: %d | Last action: %s", m.clickCount, m.lastAction);
  }

  /// Returns the target button state text shown in the disabled section.
  string formatTargetState() {
    return tracker.model.targetEnabled
      ? "Target button: enabled"
      : "Target button: disabled";
  }

  /// Returns the status bar text for this page.
  string formatStatus() {
    import std.format : format;

    const auto m = tracker.model;
    return format(
      "Clicks: %d | Last: %s | Target: %s",
      m.clickCount,
      m.lastAction,
      m.targetEnabled ? "enabled" : "disabled"
    );
  }

  /// Returns the page root widget.
  Widget rootWidget() {
    return root;
  }

  /// Returns the "Primary" style button.
  Widget primaryButton() {
    return primaryBtn;
  }

  /// Returns the button whose enabled state is toggled.
  Widget targetButton() {
    return targetBtn;
  }

  /// Returns the "Toggle enabled" button.
  Widget toggleButton() {
    return toggleBtn;
  }

  /// Returns whether the page is visible.
  bool isVisible() const {
    return root.visible;
  }

private:
  void buildStylesSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(20, 68, 605, 280),
      "1. Styles",
      "simpleBtnStylesCard"
    );
    auto row = makeButtonRow(card, "simpleBtnStylesRow", 44.0f);

    ButtonBuilder primary;
    primaryBtn = primary.style(primaryStyle()).name("simpleBtnPrimary")
      .text("Primary").fixedSize(130.0f, 38.0f)
      .action(simpleBtnPrimaryEvent)
      .build(ui, row, RectF(0, 0, 130, 38));

    ButtonBuilder secondary;
    secondary.style(secondaryStyle()).name("simpleBtnSecondary")
      .text("Secondary").fixedSize(130.0f, 38.0f)
      .action(simpleBtnSecondaryEvent)
      .build(ui, row, RectF(0, 0, 130, 38));

    ButtonBuilder danger;
    danger.style(dangerStyle()).name("simpleBtnDanger")
      .text("Danger").fixedSize(130.0f, 38.0f)
      .action(simpleBtnDangerEvent)
      .build(ui, row, RectF(0, 0, 130, 38));

    statsLabel = makeInfoLabel(
      card,
      "simpleBtnStatsLabel",
      RectF(16, 112, 570, 20),
      formatStats()
    );
  }

  void buildDisabledSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(655, 68, 605, 280),
      "2. Disabled state",
      "simpleBtnDisabledCard"
    );
    auto row = makeButtonRow(card, "simpleBtnDisabledRow", 44.0f);

    ButtonBuilder target;
    targetBtn = target.style(primaryStyle()).name("simpleBtnTarget")
      .text("Target").fixedSize(130.0f, 38.0f)
      .action(simpleBtnTargetEvent)
      .enabled(tracker.model.targetEnabled)
      .build(ui, row, RectF(0, 0, 130, 38));

    ButtonBuilder toggle;
    toggleBtn = toggle.style(secondaryStyle()).name("simpleBtnToggle")
      .text("Toggle enabled").fixedSize(150.0f, 38.0f)
      .action(simpleBtnToggleEvent)
      .build(ui, row, RectF(0, 0, 150, 38));

    stateLabel = makeInfoLabel(
      card,
      "simpleBtnStateLabel",
      RectF(16, 112, 570, 20),
      formatTargetState()
    );
    makeInfoLabel(
      card,
      "simpleBtnDisabledHelp",
      RectF(16, 144, 570, 60),
      "- A disabled button shows muted colours and ignores input.\n" ~
        "- Disabling cancels a press in progress."
    );
  }

  void buildSizingSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(20, 362, 605, 280),
      "3. Sizing",
      "simpleBtnSizingCard"
    );
    auto row = makeButtonRow(card, "simpleBtnSizingRow", 44.0f);

    ButtonBuilder fixed;
    fixed.style(secondaryStyle()).name("simpleBtnFixed")
      .text("Fixed 160 x 44").fixedSize(160.0f, 44.0f)
      .action(simpleBtnFixedEvent)
      .build(ui, row, RectF(0, 0, 160, 44));

    ButtonBuilder auto_;
    auto_.style(primaryStyle()).name("simpleBtnAuto")
      .text("Auto-sized caption follows its text").autoSize()
      .captionTooltip().action(simpleBtnAutoEvent)
      .build(ui, row, RectF(0, 0, 0, 0));

    makeInfoLabel(
      card,
      "simpleBtnSizingHelp",
      RectF(16, 112, 570, 140),
      "- Press: colours fade to the pressed palette and the caption\n" ~
        "  sinks by a couple of pixels.\n" ~
        "- Drag off while held: the button un-sinks and the click is\n" ~
        "  cancelled; dragging back re-arms it.\n" ~
        "- The action fires only when released inside the same button.\n" ~
        "- No hover visuals; timers run only while animating."
    );
  }

  Widget makeButtonRow(Widget card, string rowName, float top) {
    return WidgetBuilder.make(ui)
      .parent(card)
      .name(rowName)
      .rect(RectF(16, top, 570, 56))
      .flexRow()
      .gap(14.0f)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.center)
      .build();
  }

  Widget makeInfoLabel(
    Widget card,
    string labelName,
    RectF rect,
    string caption
  ) {
    return WidgetBuilder.make(ui)
      .parent(card)
      .name(labelName)
      .rect(rect)
      .text(caption)
      .textColor(ColorF(0.74f, 0.80f, 0.88f, 1.0f))
      .fontSize(13.0f)
      .multiline(true)
      .build();
  }

  static ButtonStyle primaryStyle() {
    ButtonStyle s;
    s.normal = WidgetColors(
      ColorF(0.18f, 0.36f, 0.68f, 1.0f),
      ColorF(0.35f, 0.55f, 0.90f, 1.0f),
      ColorF(0.97f, 0.97f, 1.00f, 1.0f)
    );
    s.pressed = WidgetColors(
      ColorF(0.10f, 0.22f, 0.45f, 1.0f),
      ColorF(0.55f, 0.72f, 1.00f, 1.0f),
      ColorF(0.97f, 0.97f, 1.00f, 1.0f)
    );
    return s;
  }

  static ButtonStyle secondaryStyle() {
    ButtonStyle s;
    s.normal = WidgetColors(
      ColorF(0.22f, 0.24f, 0.28f, 1.0f),
      ColorF(0.40f, 0.43f, 0.50f, 1.0f),
      ColorF(0.90f, 0.92f, 0.95f, 1.0f)
    );
    s.pressed = WidgetColors(
      ColorF(0.14f, 0.15f, 0.18f, 1.0f),
      ColorF(0.60f, 0.64f, 0.72f, 1.0f),
      ColorF(0.90f, 0.92f, 0.95f, 1.0f)
    );
    return s;
  }

  static ButtonStyle dangerStyle() {
    ButtonStyle s;
    s.normal = WidgetColors(
      ColorF(0.62f, 0.16f, 0.20f, 1.0f),
      ColorF(0.88f, 0.35f, 0.40f, 1.0f),
      ColorF(1.00f, 0.95f, 0.95f, 1.0f)
    );
    s.pressed = WidgetColors(
      ColorF(0.40f, 0.08f, 0.12f, 1.0f),
      ColorF(1.00f, 0.50f, 0.55f, 1.0f),
      ColorF(1.00f, 0.95f, 0.95f, 1.0f)
    );
    return s;
  }

  UiSystem ui;
  ModelTracker!SimpleButtonPageModel tracker;
  Widget root;
  Widget primaryBtn;
  Widget targetBtn;
  Widget toggleBtn;
  Widget statsLabel;
  Widget stateLabel;
}
