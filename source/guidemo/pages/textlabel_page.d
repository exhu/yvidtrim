/**
 * textlabel_page.d - Page 2 showcase for TextLabel component features.
 */
module guidemo.pages.textlabel_page;

import guidemo.common : makeSectionCard;
import guidemo.model : DemoModel;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Background, Border, TextLabel;
import yguilib.widget.layout_components : Dimension, Insets, Size, SizingMode;

/// Page 2 container displaying TextLabel multiline, ellipsis, alignment demos.
final class TextLabelPage {
  this(Widget parent) {
    root = new Widget(parent, RectF(0, 0, 1280, 720));

    buildAlignmentSection();
    buildEllipsisSection();
    buildMultilineSection();
    buildPlaygroundSection();
  }

  void update(const DemoModel m) {
    if (interactiveLabelWidget !is null &&
        interactiveLabelWidget.components.textLabel !is null) {
      auto tl = interactiveLabelWidget.components.textLabel;
      const string targetText = labelInteractiveSamples[
        m.labelSampleIndex % labelInteractiveSamples.length
      ];
      if (tl.multiline != m.labelMultiline ||
          tl.overflowEllipsis != m.labelEllipsis ||
          tl.alignment != m.labelAlignment ||
          tl.caption != targetText) {
        tl.multiline = m.labelMultiline;
        tl.overflowEllipsis = m.labelEllipsis;
        tl.alignment = m.labelAlignment;
        tl.caption = targetText;
        interactiveLabelWidget.update();
      }
    }

    if (interactiveStatusWidget !is null) {
      interactiveStatusWidget.setCaption(formatInteractiveStatus(m));
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

  static immutable string[] labelInteractiveSamples = [
    "Interactive TextLabel showcasing multiline wrapping, overflow " ~
      "ellipsis, and dynamic alignment.\nLines wrap cleanly to content area.",
    "Short text snippet demonstrating horizontal alignment within bounds.",
    "Multiline paragraph with explicit line breaks:\n" ~
      "• Line 1: Demonstrates line spacing & font metrics\n" ~
      "• Line 2: Testing text scissoring & ellipsis\n" ~
      "• Line 3: Supercalifragilisticexpialidocious extra line\n" ~
      "• Line 4: Additional content exceeding height boundary",
  ];

  static string formatInteractiveStatus(const DemoModel m) {
    import std.format : format;

    string alignStr;
    final switch (m.labelAlignment) {
    case TextLabel.Alignment.left:
      alignStr = "left";
      break;
    case TextLabel.Alignment.center:
      alignStr = "center";
      break;
    case TextLabel.Alignment.right:
      alignStr = "right";
      break;
    }

    return format(
      "[M] Multiline: %s | [E] Ellipsis: %s | [L] Align: %s | [T] Sample: %d/3",
      m.labelMultiline ? "ON" : "OFF",
      m.labelEllipsis ? "ON" : "OFF",
      alignStr,
      m.labelSampleIndex + 1
    );
  }

private:
  void buildAlignmentSection() {
    auto card = makeSectionCard(
      root,
      RectF(20, 68, 605, 280),
      "1. Horizontal Alignment (Left, Center, Right)"
    );

    buildSingleLineAlignment(card);
    buildMultilineAlignment(card);
  }

  void buildSingleLineAlignment(Widget card) {
    WidgetBuilder(card, RectF(12, 34, 581, 16))
      .text(
        "Single-line alignment within fixed-width boxes:",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f)
      )
      .build();

    Widget makeAlignBox(
      RectF rect,
      string text,
      ColorF textCol,
      TextLabel.Alignment alignment,
      ColorF borderCol
    ) {
      return WidgetBuilder(card, rect)
        .fixedSize(rect.width, rect.height)
        .padding(Insets(6, 10, 6, 10))
        .roundBackground(ColorF(0.10f, 0.12f, 0.15f, 1.0f), 15.0f)
        .border(Border.dashed(borderCol, 1.5f))
        .text(text, textCol, 14.0f, alignment)
        .build();
    }

    makeAlignBox(
      RectF(12, 54, 185, 48),
      "Left Aligned",
      ColorF(0.40f, 0.80f, 1.0f, 1.0f),
      TextLabel.Alignment.left,
      ColorF(0.30f, 0.50f, 0.75f, 1.0f)
    );
    makeAlignBox(
      RectF(205, 54, 185, 48),
      "Center Aligned",
      ColorF(0.45f, 0.90f, 0.60f, 1.0f),
      TextLabel.Alignment.center,
      ColorF(0.35f, 0.70f, 0.50f, 1.0f)
    );
    makeAlignBox(
      RectF(398, 54, 195, 48),
      "Right Aligned",
      ColorF(1.0f, 0.70f, 0.40f, 1.0f),
      TextLabel.Alignment.right,
      ColorF(0.85f, 0.55f, 0.30f, 1.0f)
    );
  }

  void buildMultilineAlignment(Widget card) {
    WidgetBuilder(card, RectF(12, 110, 581, 16))
      .text(
        "Multiline alignment (each line aligned individually):",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f)
      )
      .build();

    auto multiCenterBox = WidgetBuilder(card, RectF(12, 130, 285, 138))
      .fixedSize(285, 138)
      .padding(Insets(8, 12, 8, 12))
      .roundBackground(ColorF(0.10f, 0.12f, 0.15f, 1.0f), 15.0f)
      .border(ColorF(0.30f, 0.55f, 0.45f, 1.0f), 1.5f)
      .text(new TextLabel(
        "Centered Paragraph:\nEach wrapped line\nis positioned at the\n" ~
          "exact horizontal center\nof the content bounds.",
        ColorF(0.80f, 1.0f, 0.85f, 1.0f)
      ).withMultiline(true).withAlignment(TextLabel.Alignment.center))
      .build();

    auto multiRightBox = WidgetBuilder(card, RectF(307, 130, 286, 138))
      .fixedSize(286, 138)
      .padding(Insets(8, 12, 8, 12))
      .roundBackground(ColorF(0.10f, 0.12f, 0.15f, 1.0f), 15.0f)
      .border(ColorF(0.60f, 0.45f, 0.30f, 1.0f), 1.5f)
      .text(new TextLabel(
        "Right-Aligned Paragraph:\nEach wrapped line\nis pushed against\n" ~
          "the right boundary\nof the container area.",
        ColorF(1.0f, 0.85f, 0.70f, 1.0f)
      ).withMultiline(true).withAlignment(TextLabel.Alignment.right))
      .build();
  }

  void buildEllipsisSection() {
    auto card = makeSectionCard(
      root,
      RectF(645, 68, 615, 280),
      "2. Overflow Ellipsis (Single-Line & Vertical Truncation)"
    );

    buildSingleLineEllipsis(card);
    buildMultilineEllipsis(card);
  }

  void buildSingleLineEllipsis(Widget card) {
    WidgetBuilder(card, RectF(12, 34, 591, 16))
      .text(
        "Single-line overflow (overflowEllipsis = true vs false):",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f)
      )
      .build();

    auto boxEllipsis = WidgetBuilder(card, RectF(12, 54, 288, 48))
      .fixedSize(288, 48)
      .padding(Insets(6, 10, 6, 10))
      .roundBackground(ColorF(0.10f, 0.12f, 0.15f, 1.0f), 15.0f)
      .border(ColorF(0.30f, 0.55f, 0.75f, 1.0f), 1.5f)
      .text(new TextLabel(
        "overflowEllipsis=true: Very long sentence truncated with ellipsis.",
        ColorF(0.60f, 0.85f, 1.0f, 1.0f)
      ).withMultiline(false).withEllipsis(true))
      .build();

    auto boxNoEllipsis = WidgetBuilder(card, RectF(308, 54, 295, 48))
      .fixedSize(295, 48)
      .padding(Insets(6, 10, 6, 10))
      .clipContents(true)
      .roundBackground(ColorF(0.10f, 0.12f, 0.15f, 1.0f), 15.0f)
      .border(ColorF(0.65f, 0.35f, 0.40f, 1.0f), 1.5f)
      .text(new TextLabel(
        "overflowEllipsis=false: Long sentence scissored without " ~
          "ellipsis dots.",
        ColorF(1.0f, 0.65f, 0.70f, 1.0f)
      ).withMultiline(false).withEllipsis(false))
      .build();
  }

  void buildMultilineEllipsis(Widget card) {
    WidgetBuilder(card, RectF(12, 110, 591, 16))
      .text(
        "Multiline vertical overflow (last visible line truncated with '...'):",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f)
      )
      .build();

    auto multiVertEllipsis = WidgetBuilder(card, RectF(12, 130, 288, 138))
      .fixedSize(288, 138)
      .padding(Insets(8, 12, 8, 12))
      .clipContents(true)
      .roundBackground(ColorF(0.10f, 0.12f, 0.15f, 1.0f), 15.0f)
      .border(ColorF(0.35f, 0.65f, 0.50f, 1.0f), 1.5f)
      .text(new TextLabel(
        "Line 1: Primary line\nLine 2: Secondary line\n" ~
          "Line 3: Content line\nLine 4: Approaching boundary\n" ~
          "Line 5: Near container limit\n" ~
          "Line 6: Last visible truncated line\n" ~
          "Line 7: Overflow line\nLine 8: Clipped line\n" ~
          "Line 9: Invisible extra line",
        ColorF(0.70f, 1.0f, 0.80f, 1.0f)
      ).withMultiline(true).withEllipsis(true))
      .build();

    auto multiVertNoEllipsis = WidgetBuilder(card, RectF(308, 130, 295, 138))
      .fixedSize(295, 138)
      .padding(Insets(8, 12, 8, 12))
      .clipContents(true)
      .roundBackground(ColorF(0.10f, 0.12f, 0.15f, 1.0f), 15.0f)
      .border(ColorF(0.65f, 0.50f, 0.30f, 1.0f), 1.5f)
      .text(new TextLabel(
        "Line 1: Primary line\nLine 2: Secondary line\n" ~
          "Line 3: Content line\nLine 4: Approaching boundary\n" ~
          "Line 5: Near container limit\n" ~
          "Line 6: Last visible line (no ellipsis)\n" ~
          "Line 7: Overflow line\nLine 8: Clipped line\n" ~
          "Line 9: Invisible extra line",
        ColorF(1.0f, 0.85f, 0.60f, 1.0f)
      ).withMultiline(true).withEllipsis(false))
      .build();
  }

  void buildMultilineSection() {
    auto card = makeSectionCard(
      root,
      RectF(20, 356, 605, 290),
      "3. Multiline & Word Wrapping (wrapLine vs Single-Line)"
    );

    buildWrappingBoxes(card);
    buildSanitizedComparison(card);
  }

  void buildWrappingBoxes(Widget card) {
    WidgetBuilder(card, RectF(12, 34, 581, 16))
      .text(
        "Automatic word wrapping & explicit newlines [multiline = true]:",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f)
      )
      .build();

    auto wrapBox = WidgetBuilder(card, RectF(12, 54, 285, 120))
      .fixedSize(285, 120)
      .padding(Insets(8, 12, 8, 12))
      .roundBackground(ColorF(0.10f, 0.12f, 0.15f, 1.0f), 15.0f)
      .border(ColorF(0.35f, 0.45f, 0.65f, 1.0f), 1.5f)
      .text(new TextLabel(
        "Word wrapping algorithm wraps lines cleanly at space delimiters " ~
          "when width is limited.",
        ColorF(0.85f, 0.90f, 1.0f, 1.0f)
      ).withMultiline(true))
      .build();

    auto newlinesBox = WidgetBuilder(card, RectF(307, 54, 286, 120))
      .fixedSize(286, 120)
      .padding(Insets(8, 12, 8, 12))
      .roundBackground(ColorF(0.10f, 0.12f, 0.15f, 1.0f), 15.0f)
      .border(ColorF(0.40f, 0.35f, 0.55f, 1.0f), 1.5f)
      .text(new TextLabel(
        "Explicit newlines:\n" ~
          "• First item in list\n" ~
          "• Second item with line break\n" ~
          "• Third item preserved",
        ColorF(0.90f, 0.80f, 1.0f, 1.0f)
      ).withMultiline(true))
      .build();
  }

  void buildSanitizedComparison(Widget card) {
    WidgetBuilder(card, RectF(12, 180, 581, 16))
      .text(
        "Multiline disabled comparison [multiline = false]:",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f)
      )
      .build();

    auto sanitizedBox = WidgetBuilder(card, RectF(12, 200, 581, 74))
      .fixedSize(581, 74)
      .padding(Insets(8, 12, 8, 12))
      .roundBackground(ColorF(0.10f, 0.12f, 0.15f, 1.0f), 15.0f)
      .border(Border.dashed(
        ColorF(0.65f, 0.50f, 0.25f, 1.0f),
        1.5f
      ))
      .text(new TextLabel(
        "Line 1\\nLine 2\\r\\nLine 3 (newlines sanitized into single spaces " ~
          "automatically when multiline=false, followed by overflow ellipsis)",
        ColorF(1.0f, 0.90f, 0.60f, 1.0f)
      ).withMultiline(false).withEllipsis(true))
      .build();
  }

  void buildPlaygroundSection() {
    auto card = makeSectionCard(
      root,
      RectF(645, 356, 615, 290),
      "4. Interactive TextLabel Playground (Keys: [M] [E] [L] [T])"
    );

    interactiveStatusWidget = WidgetBuilder(card, RectF(12, 34, 591, 30))
      .fixedSize(591, 30)
      .padding(Insets(4, 10, 4, 10))
      .roundBackground(ColorF(0.14f, 0.17f, 0.23f, 1.0f), 4.0f)
      .border(ColorF(0.35f, 0.45f, 0.65f, 1.0f), 1.0f)
      .text(
        "[M] Multiline: ON | [E] Ellipsis: ON | [L] Align: left | Sample: 1/3",
        ColorF(0.95f, 0.95f, 0.40f, 1.0f)
      )
      .build();

    interactiveLabelWidget = WidgetBuilder(card, RectF(12, 70, 591, 148))
      .fixedSize(591, 148)
      .padding(Insets(10, 14, 10, 14))
      .clipContents(true)
      .roundBackground(ColorF(0.09f, 0.11f, 0.15f, 1.0f), 6.0f)
      .border(Border.dashed(
        ColorF(0.30f, 0.75f, 0.90f, 1.0f),
        2.0f,
        6.0f,
        3.0f
      ))
      .text(new TextLabel(
        labelInteractiveSamples[0],
        ColorF(1.0f, 1.0f, 1.0f, 1.0f)
      ).withMultiline(true)
        .withEllipsis(true)
        .withAlignment(TextLabel.Alignment.left)
        .withFontSize(15.0f))
      .build();

    buildPlaygroundHint(card);
  }

  void buildPlaygroundHint(Widget card) {
    WidgetBuilder(card, RectF(12, 226, 591, 52))
      .fixedSize(591, 52)
      .padding(Insets(6, 10, 6, 10))
      .roundBackground(ColorF(0.11f, 0.13f, 0.17f, 1.0f), 4.0f)
      .border(ColorF(0.25f, 0.28f, 0.35f, 1.0f), 1.0f)
      .text(new TextLabel(
        "[M] Toggle multiline | [E] Toggle ellipsis | [L] Cycle alignment\n" ~
          "[T] Cycle sample text | [Tab] or [1]/[2] Switch demo pages",
        ColorF(0.65f, 0.72f, 0.85f, 1.0f)
      ).withMultiline(true)
        .withFontSize(12.0f))
      .build();
  }

  Widget root;
  Widget interactiveLabelWidget;
  Widget interactiveStatusWidget;
}
