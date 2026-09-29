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
    // 1. Update animated alpha chip
    if (alphaChip !is null && alphaChip.components.background !is null) {
      if (alphaChip.components.background.color.a != m.alphaValue) {
        alphaChip.components.background.color.a = m.alphaValue;
        alphaChip.markDirty(false);
      }
    }

    // 2. Update auto-sized label text sample
    if (autoLabelWidget !is null &&
        autoLabelWidget.components.textLabel !is null) {
      const string targetText =
        textSamples[m.textSampleIndex % textSamples.length];
      if (autoLabelWidget.components.textLabel.caption != targetText) {
        autoLabelWidget.components.textLabel.caption = targetText;
        autoLabelWidget.markDirty();
      }
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
        playgroundContainer.markDirty();
      }
    }

    // 4. Update dynamic visibility child
    if (playgroundChild2 !is null) {
      if (playgroundChild2.visible != m.child2Visible) {
        playgroundChild2.visible = m.child2Visible;
        if (playgroundChild2.visible) {
          playgroundChild2.markTreeDirty();
        } else {
          playgroundChild2.markDirty();
        }
        playgroundContainer.markDirty();
      }
    }
  }

  Widget getRootWidget() {
    return root;
  }

  void setVisible(bool visible) {
    if (root.visible != visible) {
      root.visible = visible;
      if (visible) {
        root.markTreeDirty();
      } else {
        root.markDirty();
      }
      if (root.parent !is null) {
        root.parent.markLayoutDirty();
      }
    }
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

    // Style chips flex container
    auto chipsRow = new Widget(card, RectF(12, 36, 581, 60));
    auto flexChips = new FlexContainer;
    flexChips.direction = FlexDirection.row;
    flexChips.gap = 8.0f;
    flexChips.justify = JustifyContent.start;
    flexChips.alignItems = AlignItems.center;
    chipsRow.components.flexContainer = flexChips;

    // Chip 1: Rect background + Rect border
    auto c1 = new Widget(chipsRow, RectF(0, 0, 108, 48));
    auto szC1 = new Size;
    szC1.padding = Insets(6, 8, 6, 8);
    c1.components.size = szC1;
    c1.components.background = new Background(
      ColorF(0.18f, 0.35f, 0.60f, 1.0f),
      Background.Style.rect
    );
    c1.components.border = new Border(
      ColorF(0.40f, 0.70f, 1.0f, 1.0f),
      Border.Style.rect
    );
    c1.components.border.width = 2.0f;
    c1.components.textLabel = new TextLabel(
      "Rect Style",
      ColorF(1.0f, 1.0f, 1.0f, 1.0f)
    );

    // Chip 2: Round background + Round border
    auto c2 = new Widget(chipsRow, RectF(0, 0, 108, 48));
    auto szC2 = new Size;
    szC2.padding = Insets(6, 8, 6, 8);
    c2.components.size = szC2;
    c2.components.background = new Background(
      ColorF(0.18f, 0.50f, 0.30f, 1.0f),
      Background.Style.round
    );
    c2.components.background.cornerRadius = 10.0f;
    c2.components.border = new Border(
      ColorF(0.40f, 0.90f, 0.50f, 1.0f),
      Border.Style.round
    );
    c2.components.border.cornerRadius = 10.0f;
    c2.components.border.width = 2.0f;
    c2.components.textLabel = new TextLabel(
      "Round Style",
      ColorF(1.0f, 1.0f, 1.0f, 1.0f)
    );

    // Chip 3: None background + Dashed rect border
    auto c3 = new Widget(chipsRow, RectF(0, 0, 108, 48));
    auto szC3 = new Size;
    szC3.padding = Insets(6, 8, 6, 8);
    c3.components.size = szC3;
    c3.components.background = new Background(
      ColorF(0, 0, 0, 0),
      Background.Style.none
    );
    c3.components.border = new Border(
      ColorF(0.90f, 0.75f, 0.20f, 1.0f),
      Border.Style.dashed
    );
    c3.components.border.width = 2.0f;
    c3.components.border.dashLen = 6.0f;
    c3.components.border.gap = 3.0f;
    c3.components.textLabel = new TextLabel(
      "Dashed Rect",
      ColorF(0.95f, 0.85f, 0.30f, 1.0f)
    );

    // Chip 4: Round background + Round dashed border
    auto c4 = new Widget(chipsRow, RectF(0, 0, 114, 48));
    auto szC4 = new Size;
    szC4.padding = Insets(6, 8, 6, 8);
    c4.components.size = szC4;
    c4.components.background = new Background(
      ColorF(0.45f, 0.20f, 0.50f, 1.0f),
      Background.Style.round
    );
    c4.components.background.cornerRadius = 10.0f;
    c4.components.border = new Border(
      ColorF(0.85f, 0.50f, 0.95f, 1.0f),
      Border.Style.roundDashed
    );
    c4.components.border.cornerRadius = 10.0f;
    c4.components.border.width = 2.0f;
    c4.components.border.dashLen = 5.0f;
    c4.components.border.gap = 3.0f;
    c4.components.textLabel = new TextLabel(
      "Round Dashed",
      ColorF(1.0f, 1.0f, 1.0f, 1.0f)
    );

    // Chip 5: Pulsing alpha chip
    alphaChip = new Widget(chipsRow, RectF(0, 0, 114, 48));
    auto szC5 = new Size;
    szC5.padding = Insets(6, 8, 6, 8);
    alphaChip.components.size = szC5;
    alphaChip.components.background = new Background(
      ColorF(0.80f, 0.25f, 0.25f, 0.8f),
      Background.Style.round
    );
    alphaChip.components.background.cornerRadius = 8.0f;
    alphaChip.components.border = new Border(
      ColorF(1.0f, 0.50f, 0.50f, 1.0f),
      Border.Style.rect
    );
    alphaChip.components.border.width = 1.5f;
    alphaChip.components.textLabel = new TextLabel(
      "Alpha Pulse",
      ColorF(1.0f, 1.0f, 1.0f, 1.0f)
    );

    // Clipping demonstration area
    auto clipTitle = new Widget(card, RectF(12, 106, 581, 16));
    clipTitle.components.textLabel = new TextLabel(
      "Clipping (clipChildren = true & clipContents = true):",
      ColorF(0.70f, 0.75f, 0.85f, 1.0f)
    );

    // Parent container with clipChildren = true
    auto clipParent = new Widget(card, RectF(12, 128, 275, 136));
    clipParent.clipChildren = true;
    clipParent.components.background = new Background(
      ColorF(0.09f, 0.10f, 0.13f, 1.0f),
      Background.Style.round
    );
    clipParent.components.background.cornerRadius = 6.0f;
    clipParent.components.border = new Border(
      ColorF(0.35f, 0.40f, 0.50f, 1.0f),
      Border.Style.dashed
    );
    clipParent.components.border.width = 1.5f;

    auto clipParentLabel = new Widget(clipParent, RectF(8, 6, 250, 16));
    clipParentLabel.components.textLabel = new TextLabel(
      "Parent [clipChildren = true]",
      ColorF(0.60f, 0.70f, 0.90f, 1.0f)
    );

    // Child widget intentionally overflowing parent bounds
    auto overflowingChild = new Widget(clipParent, RectF(35, 30, 310, 80));
    auto szOvf = new Size;
    szOvf.padding = Insets(6, 8, 6, 8);
    overflowingChild.components.size = szOvf;
    overflowingChild.components.background = new Background(
      ColorF(0.70f, 0.25f, 0.15f, 0.85f),
      Background.Style.round
    );
    overflowingChild.components.background.cornerRadius = 8.0f;
    overflowingChild.components.border = new Border(
      ColorF(1.0f, 0.45f, 0.30f, 1.0f),
      Border.Style.rect
    );
    overflowingChild.components.border.width = 2.0f;
    overflowingChild.components.textLabel = new TextLabel(
      "Overflowing Child (Clipped at boundary)",
      ColorF(1.0f, 1.0f, 1.0f, 1.0f)
    );

    // Content clipping widget with clipContents = true
    auto contentClipBox = new Widget(card, RectF(302, 128, 291, 136));
    contentClipBox.clipContents = true;
    contentClipBox.components.background = new Background(
      ColorF(0.15f, 0.18f, 0.24f, 1.0f),
      Background.Style.round
    );
    contentClipBox.components.background.cornerRadius = 6.0f;
    contentClipBox.components.border = new Border(
      ColorF(0.40f, 0.50f, 0.65f, 1.0f),
      Border.Style.rect
    );
    contentClipBox.components.border.width = 1.5f;

    auto line1 = new Widget(contentClipBox, RectF(10, 12, 270, 18));
    line1.components.textLabel = new TextLabel(
      "Widget [clipContents = true]",
      ColorF(0.85f, 0.90f, 1.0f, 1.0f)
    );

    auto line2 = new Widget(contentClipBox, RectF(10, 36, 270, 18));
    line2.components.textLabel = new TextLabel(
      "Guarantees internal drawing calls",
      ColorF(0.70f, 0.75f, 0.85f, 1.0f)
    );

    auto line3 = new Widget(contentClipBox, RectF(10, 58, 270, 18));
    line3.components.textLabel = new TextLabel(
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

    // Row container for sizing modes
    auto sizingRow = new Widget(card, RectF(12, 34, 591, 62));
    auto flexSizing = new FlexContainer;
    flexSizing.direction = FlexDirection.row;
    flexSizing.gap = 8.0f;
    flexSizing.justify = JustifyContent.start;
    flexSizing.alignItems = AlignItems.center;
    sizingRow.components.flexContainer = flexSizing;

    // Fixed sizing mode
    auto fixedBox = new Widget(sizingRow, RectF(0, 0, 10, 10));
    auto fixedSz = new Size;
    fixedSz.width = Dimension(120, SizingMode.fixed);
    fixedSz.height = Dimension(48, SizingMode.fixed);
    fixedSz.padding = Insets(6, 10, 6, 10);
    fixedBox.components.size = fixedSz;
    fixedBox.components.background = new Background(
      ColorF(0.20f, 0.28f, 0.40f, 1.0f),
      Background.Style.round
    );
    fixedBox.components.border = new Border(
      ColorF(0.40f, 0.60f, 0.85f, 1.0f),
      Border.Style.rect
    );
    fixedBox.components.border.width = 1.5f;
    fixedBox.components.textLabel = new TextLabel(
      "Fixed (120x48)",
      ColorF(1.0f, 1.0f, 1.0f, 1.0f)
    );

    // Auto sizing mode (measured around text label + padding + border)
    autoLabelWidget = new Widget(sizingRow, RectF(0, 0, 10, 10));
    auto autoSz = new Size;
    autoSz.width = Dimension(0, SizingMode.auto_);
    autoSz.height = Dimension(0, SizingMode.auto_);
    autoSz.padding = Insets(6, 10, 6, 10);
    autoLabelWidget.components.size = autoSz;
    autoLabelWidget.components.background = new Background(
      ColorF(0.18f, 0.42f, 0.32f, 1.0f),
      Background.Style.round
    );
    autoLabelWidget.components.border = new Border(
      ColorF(0.35f, 0.85f, 0.55f, 1.0f),
      Border.Style.rect
    );
    autoLabelWidget.components.border.width = 1.5f;
    autoLabelWidget.components.textLabel = new TextLabel(
      textSamples[0],
      ColorF(1.0f, 1.0f, 1.0f, 1.0f)
    );

    // Fraction sizing container (1fr vs 2fr proportional width)
    auto fracTitle = new Widget(card, RectF(12, 106, 591, 16));
    fracTitle.components.textLabel = new TextLabel(
      "SizingMode.fraction (1fr vs 2fr space share) & Bounds [min: 100]:",
      ColorF(0.70f, 0.75f, 0.85f, 1.0f)
    );

    auto fracContainer = new Widget(card, RectF(12, 126, 591, 52));
    fracContainer.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    auto flexFrac = new FlexContainer;
    flexFrac.direction = FlexDirection.row;
    flexFrac.gap = 8.0f;
    flexFrac.justify = JustifyContent.start;
    flexFrac.alignItems = AlignItems.stretch;
    fracContainer.components.flexContainer = flexFrac;

    // 1fr child
    auto fracChild1 = new Widget(fracContainer, RectF(0, 0, 10, 10));
    auto szFrac1 = new Size;
    szFrac1.width = Dimension(1.0f, SizingMode.fraction);
    szFrac1.minWidth = 100.0f;
    szFrac1.padding = Insets(6, 10, 6, 10);
    fracChild1.components.size = szFrac1;
    fracChild1.components.background = new Background(
      ColorF(0.30f, 0.22f, 0.45f, 1.0f),
      Background.Style.round
    );
    fracChild1.components.border = new Border(
      ColorF(0.65f, 0.45f, 0.90f, 1.0f),
      Border.Style.rect
    );
    fracChild1.components.border.width = 1.5f;
    fracChild1.components.textLabel = new TextLabel(
      "Fraction 1fr (min: 100)",
      ColorF(1.0f, 1.0f, 1.0f, 1.0f)
    );

    // 2fr child
    auto fracChild2 = new Widget(fracContainer, RectF(0, 0, 10, 10));
    auto szFrac2 = new Size;
    szFrac2.width = Dimension(2.0f, SizingMode.fraction);
    szFrac2.maxWidth = 420.0f;
    szFrac2.padding = Insets(6, 10, 6, 10);
    fracChild2.components.size = szFrac2;
    fracChild2.components.background = new Background(
      ColorF(0.20f, 0.38f, 0.48f, 1.0f),
      Background.Style.round
    );
    fracChild2.components.border = new Border(
      ColorF(0.40f, 0.75f, 0.95f, 1.0f),
      Border.Style.rect
    );
    fracChild2.components.border.width = 1.5f;
    fracChild2.components.textLabel = new TextLabel(
      "Fraction 2fr (max: 420)",
      ColorF(1.0f, 1.0f, 1.0f, 1.0f)
    );

    // Insets demonstration container (padding on parent, margin on child)
    auto insetsContainer = new Widget(card, RectF(12, 190, 591, 74));
    insetsContainer.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    auto szInsetsParent = new Size;
    szInsetsParent.padding = Insets(6, 12, 6, 12);
    insetsContainer.components.size = szInsetsParent;
    insetsContainer.components.border = new Border(
      ColorF(0.30f, 0.35f, 0.45f, 1.0f),
      Border.Style.dashed
    );
    insetsContainer.components.border.width = 1.5f;

    auto flexInsets = new FlexContainer;
    flexInsets.direction = FlexDirection.row;
    flexInsets.gap = 10.0f;
    flexInsets.alignItems = AlignItems.center;
    insetsContainer.components.flexContainer = flexInsets;

    auto marginBox = new Widget(insetsContainer, RectF(0, 0, 10, 10));
    auto szMargin = new Size;
    szMargin.width = Dimension(0, SizingMode.auto_);
    szMargin.height = Dimension(0, SizingMode.auto_);
    szMargin.padding = Insets(6, 10, 6, 10);
    szMargin.margin = Insets(4, 14, 4, 14);
    marginBox.components.size = szMargin;
    marginBox.components.background = new Background(
      ColorF(0.45f, 0.32f, 0.15f, 1.0f),
      Background.Style.round
    );
    marginBox.components.border = new Border(
      ColorF(0.95f, 0.70f, 0.30f, 1.0f),
      Border.Style.rect
    );
    marginBox.components.border.width = 1.5f;
    marginBox.components.textLabel = new TextLabel(
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

    // 1. Box with corner-pinned anchors
    auto cornerBox = new Widget(card, RectF(12, 34, 280, 244));
    cornerBox.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    cornerBox.components.border = new Border(
      ColorF(0.28f, 0.32f, 0.40f, 1.0f),
      Border.Style.rect
    );
    cornerBox.components.border.width = 1.5f;

    auto l1 = new Widget(cornerBox, RectF(10, 95, 260, 18));
    l1.components.textLabel = new TextLabel(
      "Corner Anchors Demonstration:",
      ColorF(0.70f, 0.75f, 0.85f, 1.0f)
    );
    auto l2 = new Widget(cornerBox, RectF(10, 118, 260, 18));
    l2.components.textLabel = new TextLabel(
      "Top-Left, Top-Right,",
      ColorF(0.60f, 0.65f, 0.75f, 1.0f)
    );
    auto l3 = new Widget(cornerBox, RectF(10, 138, 260, 18));
    l3.components.textLabel = new TextLabel(
      "Bottom-Left, Bottom-Right",
      ColorF(0.60f, 0.65f, 0.75f, 1.0f)
    );

    // Helper for corner badge
    void addCornerBadge(
      string text,
      Nullable!float left,
      Nullable!float top,
      Nullable!float right,
      Nullable!float bottom,
      ColorF bgCol
    ) {
      auto b = new Widget(cornerBox, RectF(0, 0, 72, 28));
      auto sz = new Size;
      sz.padding = Insets(5, 8, 5, 8);
      b.components.size = sz;
      b.components.background = new Background(bgCol, Background.Style.round);
      b.components.anchor = new Anchor(left, top, right, bottom);
      b.components.textLabel = new TextLabel(text, ColorF(1, 1, 1, 1));
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

    // 2. Out-of-flow anchor inside a FlexContainer
    auto flexBoxWithAnchor = new Widget(card, RectF(302, 34, 291, 244));
    flexBoxWithAnchor.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    flexBoxWithAnchor.components.border = new Border(
      ColorF(0.28f, 0.32f, 0.40f, 1.0f),
      Border.Style.rect
    );
    flexBoxWithAnchor.components.border.width = 1.5f;

    auto flexAnchorComp = new FlexContainer;
    flexAnchorComp.direction = FlexDirection.column;
    flexAnchorComp.gap = 8.0f;
    flexAnchorComp.justify = JustifyContent.start;
    flexAnchorComp.alignItems = AlignItems.stretch;
    flexBoxWithAnchor.components.flexContainer = flexAnchorComp;

    auto flexHeader = new Widget(flexBoxWithAnchor, RectF(0, 0, 10, 10));
    auto szFh = new Size;
    szFh.height = Dimension(28, SizingMode.fixed);
    szFh.padding = Insets(4, 8, 4, 8);
    flexHeader.components.size = szFh;
    flexHeader.components.textLabel = new TextLabel(
      "Flex Flow + Pinned Badge",
      ColorF(0.75f, 0.80f, 0.90f, 1.0f)
    );

    auto flexItem1 = new Widget(flexBoxWithAnchor, RectF(0, 0, 10, 10));
    auto szFi1 = new Size;
    szFi1.height = Dimension(50, SizingMode.fixed);
    szFi1.padding = Insets(6, 8, 6, 8);
    szFi1.margin = Insets(0, 8, 0, 8);
    flexItem1.components.size = szFi1;
    flexItem1.components.background = new Background(
      ColorF(0.16f, 0.28f, 0.42f, 1.0f),
      Background.Style.round
    );
    flexItem1.components.textLabel = new TextLabel(
      "Flex Child 1 (Main Axis Flow)",
      ColorF(1, 1, 1, 1)
    );

    auto flexItem2 = new Widget(flexBoxWithAnchor, RectF(0, 0, 10, 10));
    auto szFi2 = new Size;
    szFi2.height = Dimension(50, SizingMode.fixed);
    szFi2.padding = Insets(6, 8, 6, 8);
    szFi2.margin = Insets(0, 8, 0, 8);
    flexItem2.components.size = szFi2;
    flexItem2.components.background = new Background(
      ColorF(0.22f, 0.35f, 0.28f, 1.0f),
      Background.Style.round
    );
    flexItem2.components.textLabel = new TextLabel(
      "Flex Child 2 (Main Axis Flow)",
      ColorF(1, 1, 1, 1)
    );

    // Anchored Badge inside FlexContainer (out-of-flow!)
    auto anchoredBadge = new Widget(flexBoxWithAnchor, RectF(0, 0, 108, 28));
    auto szAb = new Size;
    szAb.padding = Insets(4, 6, 4, 6);
    anchoredBadge.components.size = szAb;
    anchoredBadge.components.background = new Background(
      ColorF(0.85f, 0.30f, 0.10f, 1.0f),
      Background.Style.round
    );
    anchoredBadge.components.background.cornerRadius = 6.0f;
    anchoredBadge.components.border = new Border(
      ColorF(1.0f, 0.65f, 0.40f, 1.0f),
      Border.Style.rect
    );
    anchoredBadge.components.border.width = 1.5f;
    auto anchBadge = new Anchor;
    anchBadge.top = 8.0f;
    anchBadge.right = 8.0f;
    anchoredBadge.components.anchor = anchBadge;
    anchoredBadge.components.textLabel = new TextLabel(
      "OUT-OF-FLOW",
      ColorF(1.0f, 1.0f, 1.0f, 1.0f)
    );
  }

  void buildFlexPlayground() {
    auto card = makeSectionCard(
      root,
      RectF(645, 356, 615, 290),
      "4. Interactive Flexbox Playground (Keys: [D] [J] [A] [G] [V])"
    );

    // Interactive FlexContainer
    playgroundContainer = new Widget(card, RectF(12, 34, 591, 244));
    playgroundContainer.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    playgroundContainer.components.border = new Border(
      ColorF(0.30f, 0.35f, 0.45f, 1.0f),
      Border.Style.dashed
    );
    playgroundContainer.components.border.width = 1.5f;

    playgroundFlex = new FlexContainer;
    playgroundFlex.direction = FlexDirection.row;
    playgroundFlex.justify = JustifyContent.start;
    playgroundFlex.alignItems = AlignItems.stretch;
    playgroundFlex.gap = 8.0f;
    playgroundContainer.components.flexContainer = playgroundFlex;

    // Item A
    auto child1 = new Widget(playgroundContainer, RectF(0, 0, 10, 10));
    auto sz1 = new Size;
    sz1.width = Dimension(120, SizingMode.fixed);
    sz1.height = Dimension(48, SizingMode.fixed);
    sz1.padding = Insets(6, 8, 6, 8);
    child1.components.size = sz1;
    child1.components.background = new Background(
      ColorF(0.18f, 0.35f, 0.60f, 1.0f),
      Background.Style.round
    );
    child1.components.border = new Border(
      ColorF(0.40f, 0.70f, 1.0f, 1.0f),
      Border.Style.rect
    );
    child1.components.border.width = 2.0f;
    child1.components.textLabel = new TextLabel(
      "Box A (120x48)",
      ColorF(1, 1, 1, 1)
    );

    // Item B (toggleable visibility via [V])
    playgroundChild2 = new Widget(playgroundContainer, RectF(0, 0, 10, 10));
    auto sz2 = new Size;
    sz2.width = Dimension(140, SizingMode.fixed);
    sz2.height = Dimension(54, SizingMode.fixed);
    sz2.padding = Insets(6, 8, 6, 8);
    playgroundChild2.components.size = sz2;
    playgroundChild2.components.background = new Background(
      ColorF(0.60f, 0.25f, 0.35f, 1.0f),
      Background.Style.round
    );
    playgroundChild2.components.border = new Border(
      ColorF(0.95f, 0.50f, 0.65f, 1.0f),
      Border.Style.rect
    );
    playgroundChild2.components.border.width = 2.0f;
    playgroundChild2.components.textLabel = new TextLabel(
      "Box B [V to hide]",
      ColorF(1, 1, 1, 1)
    );

    // Item C
    auto child3 = new Widget(playgroundContainer, RectF(0, 0, 10, 10));
    auto sz3 = new Size;
    sz3.width = Dimension(110, SizingMode.fixed);
    sz3.height = Dimension(44, SizingMode.fixed);
    sz3.padding = Insets(6, 8, 6, 8);
    child3.components.size = sz3;
    child3.components.background = new Background(
      ColorF(0.20f, 0.50f, 0.30f, 1.0f),
      Background.Style.round
    );
    child3.components.border = new Border(
      ColorF(0.45f, 0.90f, 0.55f, 1.0f),
      Border.Style.rect
    );
    child3.components.border.width = 2.0f;
    child3.components.textLabel = new TextLabel(
      "Box C (110x44)",
      ColorF(1, 1, 1, 1)
    );
  }

  Widget root;
  Widget alphaChip;
  Widget autoLabelWidget;
  Widget playgroundContainer;
  FlexContainer playgroundFlex;
  Widget playgroundChild2;
}
