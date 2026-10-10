/**
 * layout_painter_page.d - Page 1 showcase for painter styles and layout system.
 */
module guidemo.pages.layout_painter_page;

import std.typecons : Nullable, nullable;

import guidemo.common : makeSectionCard;
import guidemo.model : DemoModel;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.widget : Widget;
import yguilib.widget.drawing_components : Background, Border, TextLabel;
import yguilib.widget.layout_components : AlignItems, Anchor, Dimension,
  FlexContainer, FlexDirection, Insets, JustifyContent, Size, SizingMode;

/// Page 1 widget container displaying Painter styles and layout features.
final class LayoutPainterPage {
  this(Widget parent) {
    root = new Widget(parent, RectF(0, 0, 1280, 720));

    buildPainterSection();
    buildSizingSection();
    buildAnchorSection();
    buildFlexPlayground();
  }

  void update(const DemoModel m) {
    // 1. Update animated alpha chip (only visual dirty, no flex re-layout!)
    if (alphaChip !is null && alphaChip.components.background !is null) {
      ColorF c = alphaChip.components.background.color;
      c.a = m.alphaValue;
      alphaChip.setBackgroundColor(c);
    }

    // 2. Update auto-sized label text sample
    if (autoLabelWidget !is null) {
      const string targetText =
        textSamples[m.textSampleIndex % textSamples.length];
      autoLabelWidget.setCaption(targetText);
    }

    // 3. Update interactive flex playground container
    if (playgroundFlex !is null) {
      if (playgroundFlex.direction != m.direction ||
          playgroundFlex.justify != m.justify ||
          playgroundFlex.alignItems != m.alignItems ||
          playgroundFlex.gap != m.gap) {
        playgroundFlex.direction = m.direction;
        playgroundFlex.justify = m.justify;
        playgroundFlex.alignItems = m.alignItems;
        playgroundFlex.gap = m.gap;
        playgroundContainer.update();
      }
    }

    // 4. Update dynamic visibility child
    if (playgroundChild2 !is null) {
      if (playgroundChild2.setVisible(m.child2Visible)) {
        playgroundContainer.update();
      }
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
  static immutable string[] textSamples = [
    "Compact Auto Text",
    "Medium Length Text Demonstrating Auto Size",
    "Long Text Expanding Container Bounds Horizontally And Vertically",
  ];

  void buildPainterSection() {
    auto card = makeSectionCard(
      root,
      RectF(20, 68, 605, 280),
      "1. Painter Styles (Background, Border, Alpha & Clipping)"
    );

    buildChipsRow(card);
    buildClippingDemo(card);
  }

  void buildChipsRow(Widget card) {
    auto chipsRow = new Widget(card, RectF(12, 36, 581, 60))
      .withFlex(
        FlexDirection.row,
        8.0f,
        JustifyContent.start,
        AlignItems.center
      );
    buildBasicChips(chipsRow);
    buildDashedAndPulseChips(chipsRow);
  }

  void buildBasicChips(Widget row) {
    new Widget(row, RectF(0, 0, 108, 48))
      .withPadding(Insets(6, 8, 6, 8))
      .withBackground(ColorF(0.18f, 0.35f, 0.60f, 1.0f), Background.Style.rect)
      .withBorder(ColorF(0.40f, 0.70f, 1.0f, 1.0f), 2.0f)
      .withText("Rect Style");

    new Widget(row, RectF(0, 0, 108, 48))
      .withPadding(Insets(6, 8, 6, 8))
      .withRoundBackground(ColorF(0.18f, 0.50f, 0.30f, 1.0f), 10.0f)
      .withBorder(
        ColorF(0.40f, 0.90f, 0.50f, 1.0f),
        2.0f,
        Border.Style.round,
        10.0f
      )
      .withText("Round Style");
  }

  void buildDashedAndPulseChips(Widget row) {
    auto c3 = new Widget(row, RectF(0, 0, 108, 48))
      .withPadding(Insets(6, 8, 6, 8))
      .withBackground(ColorF(0, 0, 0, 0), Background.Style.none)
      .withText("Dashed Rect", ColorF(0.95f, 0.85f, 0.30f, 1.0f));
    c3.components.border = Border.dashed(
      ColorF(0.90f, 0.75f, 0.20f, 1.0f),
      2.0f,
      6.0f,
      3.0f
    );

    auto c4 = new Widget(row, RectF(0, 0, 114, 48))
      .withPadding(Insets(6, 8, 6, 8))
      .withRoundBackground(ColorF(0.45f, 0.20f, 0.50f, 1.0f), 10.0f)
      .withText("Round Dashed");
    c4.components.border = Border.roundDashed(
      ColorF(0.85f, 0.50f, 0.95f, 1.0f),
      10.0f,
      2.0f
    ).withDashes(5.0f, 3.0f);

    alphaChip = new Widget(row, RectF(0, 0, 114, 48))
      .withPadding(Insets(6, 8, 6, 8))
      .withRoundBackground(ColorF(0.80f, 0.25f, 0.25f, 0.8f), 8.0f)
      .withBorder(ColorF(1.0f, 0.50f, 0.50f, 1.0f), 1.5f)
      .withText("Alpha Pulse");
  }

  void buildClippingDemo(Widget card) {
    new Widget(card, RectF(12, 106, 581, 16))
      .withText(
        "Clipping (clipChildren = true & clipContents = true):",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f)
      );

    auto clipParent = new Widget(card, RectF(12, 128, 275, 136))
      .withClipChildren(true)
      .withRoundBackground(ColorF(0.09f, 0.10f, 0.13f, 1.0f), 6.0f);
    clipParent.components.border = Border.dashed(
      ColorF(0.35f, 0.40f, 0.50f, 1.0f),
      1.5f
    );

    new Widget(clipParent, RectF(8, 6, 250, 16))
      .withText(
        "Parent [clipChildren = true]",
        ColorF(0.60f, 0.70f, 0.90f, 1.0f)
      );

    new Widget(clipParent, RectF(35, 30, 310, 80))
      .withPadding(Insets(6, 8, 6, 8))
      .withRoundBackground(ColorF(0.70f, 0.25f, 0.15f, 0.85f), 8.0f)
      .withBorder(ColorF(1.0f, 0.45f, 0.30f, 1.0f), 2.0f)
      .withText("Overflowing Child (Clipped at boundary)");

    auto contentClipBox = new Widget(card, RectF(302, 128, 291, 136))
      .withClipContents(true)
      .withRoundBackground(ColorF(0.15f, 0.18f, 0.24f, 1.0f), 6.0f)
      .withBorder(ColorF(0.40f, 0.50f, 0.65f, 1.0f), 1.5f);

    new Widget(contentClipBox, RectF(10, 12, 270, 18))
      .withText(
        "Widget [clipContents = true]",
        ColorF(0.85f, 0.90f, 1.0f, 1.0f)
      );
    new Widget(contentClipBox, RectF(10, 36, 270, 18))
      .withText(
        "Guarantees internal drawing calls",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f)
      );
    new Widget(contentClipBox, RectF(10, 58, 270, 18))
      .withText(
        "scissor precisely within rect bounds.",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f)
      );
  }

  void buildSizingSection() {
    auto card = makeSectionCard(
      root,
      RectF(645, 68, 615, 280),
      "2. Layout Sizing Modes, Bounds & Insets"
    );

    buildSizingRow(card);
    buildFractionDemo(card);
    buildInsetsDemo(card);
  }

  void buildSizingRow(Widget card) {
    auto sizingRow = new Widget(card, RectF(12, 34, 591, 62))
      .withFlex(
        FlexDirection.row,
        8.0f,
        JustifyContent.start,
        AlignItems.center
      );

    new Widget(sizingRow, RectF(0, 0, 10, 10))
      .withFixedSize(120.0f, 48.0f)
      .withPadding(Insets(6, 10, 6, 10))
      .withRoundBackground(ColorF(0.20f, 0.28f, 0.40f, 1.0f), 15.0f)
      .withBorder(ColorF(0.40f, 0.60f, 0.85f, 1.0f), 1.5f)
      .withText("Fixed (120x48)");

    autoLabelWidget = new Widget(sizingRow, RectF(0, 0, 10, 10))
      .withAutoSize()
      .withPadding(Insets(6, 10, 6, 10))
      .withRoundBackground(ColorF(0.18f, 0.42f, 0.32f, 1.0f), 15.0f)
      .withBorder(ColorF(0.35f, 0.85f, 0.55f, 1.0f), 1.5f)
      .withText(textSamples[0]);
  }

  void buildFractionDemo(Widget card) {
    new Widget(card, RectF(12, 106, 591, 16))
      .withText(
        "SizingMode.fraction (1fr vs 2fr space share) & Bounds [min: 100]:",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f)
      );

    auto fracContainer = new Widget(card, RectF(12, 126, 591, 52))
      .withRoundBackground(ColorF(0.10f, 0.12f, 0.15f, 1.0f), 15.0f)
      .withFlex(
        FlexDirection.row,
        8.0f,
        JustifyContent.start,
        AlignItems.stretch
      );

    auto fracChild1 = new Widget(fracContainer, RectF(0, 0, 10, 10))
      .withFractionSize(1.0f)
      .withPadding(Insets(6, 10, 6, 10))
      .withRoundBackground(ColorF(0.30f, 0.22f, 0.45f, 1.0f), 15.0f)
      .withBorder(ColorF(0.65f, 0.45f, 0.90f, 1.0f), 1.5f)
      .withText("Fraction 1fr (min: 100)");
    fracChild1.components.size.minWidth = 100.0f;

    auto fracChild2 = new Widget(fracContainer, RectF(0, 0, 10, 10))
      .withFractionSize(2.0f)
      .withPadding(Insets(6, 10, 6, 10))
      .withRoundBackground(ColorF(0.20f, 0.38f, 0.48f, 1.0f), 15.0f)
      .withBorder(ColorF(0.40f, 0.75f, 0.95f, 1.0f), 1.5f)
      .withText("Fraction 2fr (max: 420)");
    fracChild2.components.size.maxWidth = 420.0f;
  }

  void buildInsetsDemo(Widget card) {
    auto insetsContainer = new Widget(card, RectF(12, 190, 591, 74))
      .withRoundBackground(ColorF(0.10f, 0.12f, 0.15f, 1.0f), 15.0f)
      .withPadding(Insets(6, 12, 6, 12))
      .withFlex(
        FlexDirection.row,
        10.0f,
        JustifyContent.start,
        AlignItems.center
      );
    insetsContainer.components.border = Border.dashed(
      ColorF(0.30f, 0.35f, 0.45f, 1.0f),
      1.5f
    );

    new Widget(insetsContainer, RectF(0, 0, 10, 10))
      .withAutoSize()
      .withPadding(Insets(6, 10, 6, 10))
      .withMargin(Insets(4, 14, 4, 14))
      .withRoundBackground(ColorF(0.45f, 0.32f, 0.15f, 1.0f), 15.0f)
      .withBorder(ColorF(0.95f, 0.70f, 0.30f, 1.0f), 1.5f)
      .withText(
        "Parent Insets (6,12) + Child Margins (4,14)",
        ColorF(1.0f, 0.95f, 0.85f, 1.0f)
      );
  }

  void buildAnchorSection() {
    auto card = makeSectionCard(
      root,
      RectF(20, 356, 605, 290),
      "3. Anchors & Out-of-Flow Positioning"
    );

    buildCornerAnchors(card);
    buildFlexBoxWithAnchor(card);
  }

  void buildCornerAnchors(Widget card) {
    auto cornerBox = new Widget(card, RectF(12, 34, 280, 244))
      .withRoundBackground(ColorF(0.10f, 0.12f, 0.15f, 1.0f), 15.0f)
      .withBorder(ColorF(0.28f, 0.32f, 0.40f, 1.0f), 1.5f);

    new Widget(cornerBox, RectF(10, 95, 260, 18))
      .withText(
        "Corner Anchors Demonstration:",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f)
      );
    new Widget(cornerBox, RectF(10, 118, 260, 18))
      .withText("Top-Left, Top-Right,", ColorF(0.60f, 0.65f, 0.75f, 1.0f));
    new Widget(cornerBox, RectF(10, 138, 260, 18))
      .withText(
        "Bottom-Left, Bottom-Right",
        ColorF(0.60f, 0.65f, 0.75f, 1.0f)
      );

    populateCornerBadges(cornerBox);
  }

  void populateCornerBadges(Widget cornerBox) {
    void addCornerBadge(
      string text,
      Nullable!float left,
      Nullable!float top,
      Nullable!float right,
      Nullable!float bottom,
      ColorF bgCol
    ) {
      new Widget(cornerBox, RectF(0, 0, 72, 28))
        .withPadding(Insets(5, 8, 5, 8))
        .withRoundBackground(bgCol, 15.0f)
        .withAnchor(left, top, right, bottom)
        .withText(text, ColorF(1, 1, 1, 1));
    }

    addCornerBadge(
      "Top-Left",
      nullable(6.0f),
      nullable(6.0f),
      Nullable!float.init,
      Nullable!float.init,
      ColorF(0.80f, 0.20f, 0.20f, 1.0f)
    );
    addCornerBadge(
      "Top-Right",
      Nullable!float.init,
      nullable(6.0f),
      nullable(6.0f),
      Nullable!float.init,
      ColorF(0.20f, 0.70f, 0.30f, 1.0f)
    );
    addCornerBadge(
      "Bot-Left",
      nullable(6.0f),
      Nullable!float.init,
      Nullable!float.init,
      nullable(6.0f),
      ColorF(0.20f, 0.40f, 0.80f, 1.0f)
    );
    addCornerBadge(
      "Bot-Right",
      Nullable!float.init,
      Nullable!float.init,
      nullable(6.0f),
      nullable(6.0f),
      ColorF(0.70f, 0.50f, 0.20f, 1.0f)
    );
  }

  void buildFlexBoxWithAnchor(Widget card) {
    auto flexBoxWithAnchor = new Widget(card, RectF(302, 34, 291, 244))
      .withRoundBackground(ColorF(0.10f, 0.12f, 0.15f, 1.0f), 15.0f)
      .withBorder(ColorF(0.28f, 0.32f, 0.40f, 1.0f), 1.5f)
      .withFlex(
        FlexDirection.column,
        8.0f,
        JustifyContent.start,
        AlignItems.stretch
      );

    new Widget(flexBoxWithAnchor, RectF(0, 0, 10, 10))
      .withFixedSize(10, 28)
      .withPadding(Insets(4, 8, 4, 8))
      .withText("Flex Flow + Pinned Badge", ColorF(0.75f, 0.80f, 0.90f, 1.0f));

    auto item1 = new Widget(flexBoxWithAnchor, RectF(0, 0, 10, 10))
      .withFixedSize(10, 50)
      .withPadding(Insets(6, 8, 6, 8))
      .withMargin(Insets(0, 8, 0, 8))
      .withRoundBackground(ColorF(0.16f, 0.28f, 0.42f, 1.0f), 15.0f)
      .withText("Flex Child 1 (Main Axis Flow)");

    auto item2 = new Widget(flexBoxWithAnchor, RectF(0, 0, 10, 10))
      .withFixedSize(10, 50)
      .withPadding(Insets(6, 8, 6, 8))
      .withMargin(Insets(0, 8, 0, 8))
      .withRoundBackground(ColorF(0.22f, 0.35f, 0.28f, 1.0f), 15.0f)
      .withText("Flex Child 2 (Main Axis Flow)");

    new Widget(flexBoxWithAnchor, RectF(0, 0, 108, 28))
      .withPadding(Insets(4, 6, 4, 6))
      .withRoundBackground(ColorF(0.85f, 0.30f, 0.10f, 1.0f), 6.0f)
      .withBorder(ColorF(1.0f, 0.65f, 0.40f, 1.0f), 1.5f)
      .withAnchor(
        Nullable!float.init,
        nullable(8.0f),
        nullable(8.0f),
        Nullable!float.init
      )
      .withText("OUT-OF-FLOW");
  }

  void buildFlexPlayground() {
    auto card = makeSectionCard(
      root,
      RectF(645, 356, 615, 290),
      "4. Interactive Flexbox Playground (Keys: [D] [J] [A] [G] [V])"
    );

    playgroundFlex = FlexContainer.row(8.0f)
      .withJustify(JustifyContent.start)
      .withAlign(AlignItems.stretch);

    playgroundContainer = new Widget(card, RectF(12, 34, 591, 244))
      .withRoundBackground(ColorF(0.10f, 0.12f, 0.15f, 1.0f), 15.0f);
    playgroundContainer.components.border = Border.dashed(
      ColorF(0.30f, 0.35f, 0.45f, 1.0f),
      1.5f
    );
    playgroundContainer.components.flexContainer = playgroundFlex;

    new Widget(playgroundContainer, RectF(0, 0, 10, 10))
      .withFixedSize(120, 48)
      .withPadding(Insets(6, 8, 6, 8))
      .withRoundBackground(ColorF(0.18f, 0.35f, 0.60f, 1.0f), 15.0f)
      .withBorder(ColorF(0.40f, 0.70f, 1.0f, 1.0f), 2.0f)
      .withText("Box A (120x48)");

    playgroundChild2 = new Widget(playgroundContainer, RectF(0, 0, 10, 10))
      .withFixedSize(140, 54)
      .withPadding(Insets(6, 8, 6, 8))
      .withRoundBackground(ColorF(0.60f, 0.25f, 0.35f, 1.0f), 15.0f)
      .withBorder(ColorF(0.95f, 0.50f, 0.65f, 1.0f), 2.0f)
      .withText("Box B [V to hide]");

    new Widget(playgroundContainer, RectF(0, 0, 10, 10))
      .withFixedSize(110, 44)
      .withPadding(Insets(6, 8, 6, 8))
      .withRoundBackground(ColorF(0.20f, 0.50f, 0.30f, 1.0f), 15.0f)
      .withBorder(ColorF(0.45f, 0.90f, 0.55f, 1.0f), 2.0f)
      .withText("Box C (110x44)");
  }

  Widget root;
  Widget alphaChip;
  Widget autoLabelWidget;
  Widget playgroundContainer;
  FlexContainer playgroundFlex;
  Widget playgroundChild2;
}
