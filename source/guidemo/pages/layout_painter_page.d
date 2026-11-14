/**
 * layout_painter_page.d - Page 1 showcase for painter styles and layout system.
 */
module guidemo.pages.layout_painter_page;

import std.typecons : Nullable, nullable;

import guidemo.common : makeSectionCard;
import guidemo.model : DemoModel;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Background, Border, TextLabel;
import yguilib.widget.layout_components : AlignItems, Anchor, Dimension,
  FlexContainer, FlexDirection, Insets, JustifyContent, Size, SizingMode;

/// Page 1 widget container displaying Painter styles and layout features.
final class LayoutPainterPage {
  this(UiSystem ui, Widget parent) {
    assert(ui !is null, "UiSystem must not be null");
    this.ui = ui;
    root = new Widget(ui.nextWidgetId());
    root.name = "layoutPainterPage";
    root.rect = RectF(0, 0, 1280, 720);
    if (parent !is null) {
      parent.addChild(root);
    }

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
        playgroundContainer.update(WidgetUpdateScope.layout);
      }
    }

    // 4. Update dynamic visibility child
    if (playgroundChild2 !is null) {
      if (playgroundChild2.setVisible(m.child2Visible)) {
        playgroundContainer.update(WidgetUpdateScope.layout);
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
      ui,
      root,
      RectF(20, 68, 605, 280),
      "1. Painter Styles (Background, Border, Alpha & Clipping)",
      "painterCard"
    );

    buildChipsRow(card);
    buildClippingDemo(card);
  }

  void buildChipsRow(Widget card) {
    auto chipsRow = WidgetBuilder.make(ui)
      .parent(card)
      .name("chipsRow")
      .rect(RectF(12, 36, 581, 60))
      .flexRow()
      .gap(8.0f)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.center)
      .build();
    buildBasicChips(chipsRow);
    buildDashedAndPulseChips(chipsRow);
  }

  void buildBasicChips(Widget row) {
    WidgetBuilder.make(ui)
      .parent(row)
      .name("rectStyleChip")
      .rect(RectF(0, 0, 108, 48))
      .padding(Insets(6, 8, 6, 8))
      .bg(ColorF(0.18f, 0.35f, 0.60f, 1.0f))
      .bgStyle(Background.Style.rect)
      .border(ColorF(0.40f, 0.70f, 1.0f, 1.0f))
      .borderWidth(2.0f)
      .text("Rect Style")
      .build();

    WidgetBuilder.make(ui)
      .parent(row)
      .name("roundStyleChip")
      .rect(RectF(0, 0, 108, 48))
      .padding(Insets(6, 8, 6, 8))
      .roundBg(ColorF(0.18f, 0.50f, 0.30f, 1.0f))
      .bgRadius(10.0f)
      .roundBorder(ColorF(0.40f, 0.90f, 0.50f, 1.0f))
      .borderWidth(2.0f)
      .borderRadius(10.0f)
      .text("Round Style")
      .build();
  }

  void buildDashedAndPulseChips(Widget row) {
    WidgetBuilder.make(ui)
      .parent(row)
      .name("dashedRectChip")
      .rect(RectF(0, 0, 108, 48))
      .padding(Insets(6, 8, 6, 8))
      .bg(ColorF(0, 0, 0, 0))
      .bgStyle(Background.Style.none)
      .borderComponent(Border.dashed(
        ColorF(0.90f, 0.75f, 0.20f, 1.0f),
        2.0f,
        6.0f,
        3.0f
      ))
      .text("Dashed Rect")
      .textColor(ColorF(0.95f, 0.85f, 0.30f, 1.0f))
      .build();

    WidgetBuilder.make(ui)
      .parent(row)
      .name("roundDashedChip")
      .rect(RectF(0, 0, 114, 48))
      .padding(Insets(6, 8, 6, 8))
      .roundBg(ColorF(0.45f, 0.20f, 0.50f, 1.0f))
      .bgRadius(10.0f)
      .borderComponent(Border.roundDashed(
        ColorF(0.85f, 0.50f, 0.95f, 1.0f),
        10.0f,
        2.0f
      ).withDashes(5.0f, 3.0f))
      .text("Round Dashed")
      .build();

    alphaChip = WidgetBuilder.make(ui)
      .parent(row)
      .name("alphaPulseChip")
      .rect(RectF(0, 0, 114, 48))
      .padding(Insets(6, 8, 6, 8))
      .roundBg(ColorF(0.80f, 0.25f, 0.25f, 0.8f))
      .bgRadius(8.0f)
      .border(ColorF(1.0f, 0.50f, 0.50f, 1.0f))
      .borderWidth(1.5f)
      .text("Alpha Pulse")
      .build();
  }

  void buildClippingDemo(Widget card) {
    WidgetBuilder.make(ui)
      .parent(card)
      .name("clippingLabel")
      .rect(RectF(12, 106, 581, 16))
      .text("Clipping (clipChildren = true & clipContents = true):")
      .textColor(ColorF(0.70f, 0.75f, 0.85f, 1.0f))
      .build();

    auto clipParent = WidgetBuilder.make(ui)
      .parent(card)
      .name("clipParent")
      .rect(RectF(12, 128, 275, 136))
      .clipChildren(true)
      .roundBg(ColorF(0.09f, 0.10f, 0.13f, 1.0f))
      .bgRadius(6.0f)
      .borderComponent(Border.dashed(
        ColorF(0.35f, 0.40f, 0.50f, 1.0f),
        1.5f
      ))
      .build();

    WidgetBuilder.make(ui)
      .parent(clipParent)
      .name("clipParentTitle")
      .rect(RectF(8, 6, 250, 16))
      .text("Parent [clipChildren = true]")
      .textColor(ColorF(0.60f, 0.70f, 0.90f, 1.0f))
      .build();

    WidgetBuilder.make(ui)
      .parent(clipParent)
      .name("clipOverflowChild")
      .rect(RectF(35, 30, 310, 80))
      .padding(Insets(6, 8, 6, 8))
      .roundBg(ColorF(0.70f, 0.25f, 0.15f, 0.85f))
      .bgRadius(8.0f)
      .border(ColorF(1.0f, 0.45f, 0.30f, 1.0f))
      .borderWidth(2.0f)
      .text("Overflowing Child (Clipped at boundary)")
      .build();

    buildContentClipBox(card);
  }

  void buildContentClipBox(Widget card) {
    auto contentClipBox = WidgetBuilder.make(ui)
      .parent(card)
      .name("contentClipBox")
      .rect(RectF(302, 128, 291, 136))
      .clipContents(true)
      .roundBg(ColorF(0.15f, 0.18f, 0.24f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.40f, 0.50f, 0.65f, 1.0f))
      .borderWidth(1.5f)
      .build();

    WidgetBuilder.make(ui)
      .parent(contentClipBox)
      .name("contentClipTitle")
      .rect(RectF(10, 12, 270, 18))
      .text("Widget [clipContents = true]")
      .textColor(ColorF(0.85f, 0.90f, 1.0f, 1.0f))
      .build();
    WidgetBuilder.make(ui)
      .parent(contentClipBox)
      .name("contentClipLine1")
      .rect(RectF(10, 36, 270, 18))
      .text("Guarantees internal drawing calls")
      .textColor(ColorF(0.70f, 0.75f, 0.85f, 1.0f))
      .build();
    WidgetBuilder.make(ui)
      .parent(contentClipBox)
      .name("contentClipLine2")
      .rect(RectF(10, 58, 270, 18))
      .text("scissor precisely within rect bounds.")
      .textColor(ColorF(0.70f, 0.75f, 0.85f, 1.0f))
      .build();
  }

  void buildSizingSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(645, 68, 615, 280),
      "2. Layout Sizing Modes, Bounds & Insets",
      "sizingCard"
    );

    buildSizingRow(card);
    buildFractionDemo(card);
    buildInsetsDemo(card);
  }

  void buildSizingRow(Widget card) {
    auto sizingRow = WidgetBuilder.make(ui)
      .parent(card)
      .name("sizingRow")
      .rect(RectF(12, 34, 591, 62))
      .flexRow()
      .gap(8.0f)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.center)
      .build();

    WidgetBuilder.make(ui)
      .parent(sizingRow)
      .name("fixedSizeBox")
      .rect(RectF(0, 0, 10, 10))
      .fixedSize(120.0f, 48.0f)
      .padding(Insets(6, 10, 6, 10))
      .roundBg(ColorF(0.20f, 0.28f, 0.40f, 1.0f))
      .bgRadius(15.0f)
      .border(ColorF(0.40f, 0.60f, 0.85f, 1.0f))
      .borderWidth(1.5f)
      .text("Fixed (120x48)")
      .build();

    autoLabelWidget = WidgetBuilder.make(ui)
      .parent(sizingRow)
      .name("autoSizeLabel")
      .rect(RectF(0, 0, 10, 10))
      .autoSize()
      .padding(Insets(6, 10, 6, 10))
      .roundBg(ColorF(0.18f, 0.42f, 0.32f, 1.0f))
      .bgRadius(15.0f)
      .border(ColorF(0.35f, 0.85f, 0.55f, 1.0f))
      .borderWidth(1.5f)
      .text(textSamples[0])
      .build();
  }

  void buildFractionDemo(Widget card) {
    WidgetBuilder.make(ui)
      .parent(card)
      .name("fractionDemoLabel")
      .rect(RectF(12, 106, 591, 16))
      .text("SizingMode.fraction (1fr vs 2fr space share) & Bounds [min: 100]:")
      .textColor(ColorF(0.70f, 0.75f, 0.85f, 1.0f))
      .build();

    auto fracContainer = WidgetBuilder.make(ui)
      .parent(card)
      .name("fractionContainer")
      .rect(RectF(12, 126, 591, 52))
      .roundBg(ColorF(0.10f, 0.12f, 0.15f, 1.0f))
      .bgRadius(15.0f)
      .flexRow()
      .gap(8.0f)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.stretch)
      .build();

    WidgetBuilder.make(ui)
      .parent(fracContainer)
      .name("fraction1frBox")
      .rect(RectF(0, 0, 10, 10))
      .fractionWidth(1.0f)
      .minWidth(100.0f)
      .padding(Insets(6, 10, 6, 10))
      .roundBg(ColorF(0.30f, 0.22f, 0.45f, 1.0f))
      .bgRadius(15.0f)
      .border(ColorF(0.65f, 0.45f, 0.90f, 1.0f))
      .borderWidth(1.5f)
      .text("Fraction 1fr (min: 100)")
      .build();

    WidgetBuilder.make(ui)
      .parent(fracContainer)
      .name("fraction2frBox")
      .rect(RectF(0, 0, 10, 10))
      .fractionWidth(2.0f)
      .maxWidth(420.0f)
      .padding(Insets(6, 10, 6, 10))
      .roundBg(ColorF(0.20f, 0.38f, 0.48f, 1.0f))
      .bgRadius(15.0f)
      .border(ColorF(0.40f, 0.75f, 0.95f, 1.0f))
      .borderWidth(1.5f)
      .text("Fraction 2fr (max: 420)")
      .build();
  }

  void buildInsetsDemo(Widget card) {
    auto insetsContainer = WidgetBuilder.make(ui)
      .parent(card)
      .name("insetsContainer")
      .rect(RectF(12, 190, 591, 74))
      .roundBg(ColorF(0.10f, 0.12f, 0.15f, 1.0f))
      .bgRadius(15.0f)
      .padding(Insets(6, 12, 6, 12))
      .flexRow()
      .gap(10.0f)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.center)
      .borderComponent(Border.dashed(
        ColorF(0.30f, 0.35f, 0.45f, 1.0f),
        1.5f
      ))
      .build();

    WidgetBuilder.make(ui)
      .parent(insetsContainer)
      .name("insetsChildBox")
      .rect(RectF(0, 0, 10, 10))
      .autoSize()
      .padding(Insets(6, 10, 6, 10))
      .margin(Insets(4, 14, 4, 14))
      .roundBg(ColorF(0.45f, 0.32f, 0.15f, 1.0f))
      .bgRadius(15.0f)
      .border(ColorF(0.95f, 0.70f, 0.30f, 1.0f))
      .borderWidth(1.5f)
      .text("Parent Insets (6,12) + Child Margins (4,14)")
      .textColor(ColorF(1.0f, 0.95f, 0.85f, 1.0f))
      .build();
  }

  void buildAnchorSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(20, 356, 605, 290),
      "3. Anchors & Out-of-Flow Positioning",
      "anchorCard"
    );

    buildCornerAnchors(card);
    buildFlexBoxWithAnchor(card);
  }

  void buildCornerAnchors(Widget card) {
    auto cornerBox = WidgetBuilder.make(ui)
      .parent(card)
      .name("cornerAnchorBox")
      .rect(RectF(12, 34, 280, 244))
      .roundBg(ColorF(0.10f, 0.12f, 0.15f, 1.0f))
      .bgRadius(15.0f)
      .border(ColorF(0.28f, 0.32f, 0.40f, 1.0f))
      .borderWidth(1.5f)
      .build();

    WidgetBuilder.make(ui)
      .parent(cornerBox)
      .name("cornerAnchorTitle")
      .rect(RectF(10, 95, 260, 18))
      .text("Corner Anchors Demonstration:")
      .textColor(ColorF(0.70f, 0.75f, 0.85f, 1.0f))
      .build();
    WidgetBuilder.make(ui)
      .parent(cornerBox)
      .name("cornerAnchorLine1")
      .rect(RectF(10, 118, 260, 18))
      .text("Top-Left, Top-Right,")
      .textColor(ColorF(0.60f, 0.65f, 0.75f, 1.0f))
      .build();
    WidgetBuilder.make(ui)
      .parent(cornerBox)
      .name("cornerAnchorLine2")
      .rect(RectF(10, 138, 260, 18))
      .text("Bottom-Left, Bottom-Right")
      .textColor(ColorF(0.60f, 0.65f, 0.75f, 1.0f))
      .build();

    populateCornerBadges(cornerBox);
  }

  void populateCornerBadges(Widget cornerBox) {
    void addCornerBadge(
      string badgeName,
      string text,
      Nullable!float left,
      Nullable!float top,
      Nullable!float right,
      Nullable!float bottom,
      ColorF bgCol
    ) {
      auto b = WidgetBuilder.make(ui)
        .parent(cornerBox)
        .name(badgeName)
        .rect(RectF(0, 0, 72, 28))
        .padding(Insets(5, 8, 5, 8))
        .roundBg(bgCol)
        .bgRadius(15.0f)
        .text(text)
        .textColor(ColorF(1, 1, 1, 1));
      if (!left.isNull) {
        b.anchorLeft(left.get);
      }
      if (!top.isNull) {
        b.anchorTop(top.get);
      }
      if (!right.isNull) {
        b.anchorRight(right.get);
      }
      if (!bottom.isNull) {
        b.anchorBottom(bottom.get);
      }
      b.build();
    }

    addCornerBadge(
      "topLeftBadge",
      "Top-Left",
      nullable(6.0f),
      nullable(6.0f),
      Nullable!float.init,
      Nullable!float.init,
      ColorF(0.80f, 0.20f, 0.20f, 1.0f)
    );
    addCornerBadge(
      "topRightBadge",
      "Top-Right",
      Nullable!float.init,
      nullable(6.0f),
      nullable(6.0f),
      Nullable!float.init,
      ColorF(0.20f, 0.70f, 0.30f, 1.0f)
    );
    addCornerBadge(
      "bottomLeftBadge",
      "Bot-Left",
      nullable(6.0f),
      Nullable!float.init,
      Nullable!float.init,
      nullable(6.0f),
      ColorF(0.20f, 0.40f, 0.80f, 1.0f)
    );
    addCornerBadge(
      "bottomRightBadge",
      "Bot-Right",
      Nullable!float.init,
      Nullable!float.init,
      nullable(6.0f),
      nullable(6.0f),
      ColorF(0.70f, 0.50f, 0.20f, 1.0f)
    );
  }

  void buildFlexBoxWithAnchor(Widget card) {
    auto flexBoxWithAnchor = WidgetBuilder.make(ui)
      .parent(card)
      .name("flexBoxWithAnchor")
      .rect(RectF(302, 34, 291, 244))
      .roundBg(ColorF(0.10f, 0.12f, 0.15f, 1.0f))
      .bgRadius(15.0f)
      .border(ColorF(0.28f, 0.32f, 0.40f, 1.0f))
      .borderWidth(1.5f)
      .flexColumn()
      .gap(8.0f)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.stretch)
      .build();

    WidgetBuilder.make(ui)
      .parent(flexBoxWithAnchor)
      .name("flexAnchorTitle")
      .rect(RectF(0, 0, 10, 10))
      .fixedSize(10, 28)
      .padding(Insets(4, 8, 4, 8))
      .text("Flex Flow + Pinned Badge")
      .textColor(ColorF(0.75f, 0.80f, 0.90f, 1.0f))
      .build();

    WidgetBuilder.make(ui)
      .parent(flexBoxWithAnchor)
      .name("flexAnchorChild1")
      .rect(RectF(0, 0, 10, 10))
      .fixedSize(10, 50)
      .padding(Insets(6, 8, 6, 8))
      .margin(Insets(0, 8, 0, 8))
      .roundBg(ColorF(0.16f, 0.28f, 0.42f, 1.0f))
      .bgRadius(15.0f)
      .text("Flex Child 1 (Main Axis Flow)")
      .build();

    WidgetBuilder.make(ui)
      .parent(flexBoxWithAnchor)
      .name("flexAnchorChild2")
      .rect(RectF(0, 0, 10, 10))
      .fixedSize(10, 50)
      .padding(Insets(6, 8, 6, 8))
      .margin(Insets(0, 8, 0, 8))
      .roundBg(ColorF(0.22f, 0.35f, 0.28f, 1.0f))
      .bgRadius(15.0f)
      .text("Flex Child 2 (Main Axis Flow)")
      .build();

    WidgetBuilder.make(ui)
      .parent(flexBoxWithAnchor)
      .name("outOfFlowBadge")
      .rect(RectF(0, 0, 108, 28))
      .padding(Insets(4, 6, 4, 6))
      .roundBg(ColorF(0.85f, 0.30f, 0.10f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(1.0f, 0.65f, 0.40f, 1.0f))
      .borderWidth(1.5f)
      .anchorTop(8.0f)
      .anchorRight(8.0f)
      .text("OUT-OF-FLOW")
      .build();
  }

  void buildFlexPlayground() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(645, 356, 615, 290),
      "4. Interactive Flexbox Playground (Keys: [D] [J] [A] [G] [V])",
      "flexPlaygroundCard"
    );

    playgroundFlex = FlexContainer.row(8.0f)
      .withJustify(JustifyContent.start)
      .withAlign(AlignItems.stretch);

    playgroundContainer = WidgetBuilder.make(ui)
      .parent(card)
      .name("playgroundContainer")
      .rect(RectF(12, 34, 591, 244))
      .roundBg(ColorF(0.10f, 0.12f, 0.15f, 1.0f))
      .bgRadius(15.0f)
      .borderComponent(Border.dashed(
        ColorF(0.30f, 0.35f, 0.45f, 1.0f),
        1.5f
      ))
      .flexComponent(playgroundFlex)
      .build();

    WidgetBuilder.make(ui)
      .parent(playgroundContainer)
      .name("playgroundBoxA")
      .rect(RectF(0, 0, 10, 10))
      .fixedSize(120, 48)
      .padding(Insets(6, 8, 6, 8))
      .roundBg(ColorF(0.18f, 0.35f, 0.60f, 1.0f))
      .bgRadius(15.0f)
      .border(ColorF(0.40f, 0.70f, 1.0f, 1.0f))
      .borderWidth(2.0f)
      .text("Box A (120x48)")
      .build();

    playgroundChild2 = WidgetBuilder.make(ui)
      .parent(playgroundContainer)
      .name("playgroundBoxB")
      .rect(RectF(0, 0, 10, 10))
      .fixedSize(140, 54)
      .padding(Insets(6, 8, 6, 8))
      .roundBg(ColorF(0.60f, 0.25f, 0.35f, 1.0f))
      .bgRadius(15.0f)
      .border(ColorF(0.95f, 0.50f, 0.65f, 1.0f))
      .borderWidth(2.0f)
      .text("Box B [V to hide]")
      .build();

    WidgetBuilder.make(ui)
      .parent(playgroundContainer)
      .name("playgroundBoxC")
      .rect(RectF(0, 0, 10, 10))
      .fixedSize(110, 44)
      .padding(Insets(6, 8, 6, 8))
      .roundBg(ColorF(0.20f, 0.50f, 0.30f, 1.0f))
      .bgRadius(15.0f)
      .border(ColorF(0.45f, 0.90f, 0.55f, 1.0f))
      .borderWidth(2.0f)
      .text("Box C (110x44)")
      .build();
  }

  UiSystem ui;
  Widget root;
  Widget alphaChip;
  Widget autoLabelWidget;
  Widget playgroundContainer;
  FlexContainer playgroundFlex;
  Widget playgroundChild2;
}
