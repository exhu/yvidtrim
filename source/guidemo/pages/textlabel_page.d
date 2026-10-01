/**
 * textlabel_page.d - Page 2 showcase for TextLabel component features.
 */
module guidemo.pages.textlabel_page;

import std.format : format;

import guidemo.common : makeSectionCard;
import guidemo.model : DemoModel;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.widget : Widget;
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
    auto tl = interactiveLabelWidget.components.textLabel;
    const string targetText = labelInteractiveSamples[
      m.labelSampleIndex % labelInteractiveSamples.length
    ];
    if (tl.multiline != m.labelMultiline ||
        tl.overflowEllipsis != m.labelEllipsis ||
        tl.alignment != m.labelAlignment ||
        tl.caption != targetText) {
      interactiveLabelWidget.modify!TextLabel((comp) {
        comp.multiline = m.labelMultiline;
        comp.overflowEllipsis = m.labelEllipsis;
        comp.alignment = m.labelAlignment;
        comp.caption = targetText;
      });
    }

    const string targetStatus = formatInteractiveStatus(m);
    if (interactiveStatusWidget.components.textLabel.caption !=
        targetStatus) {
      interactiveStatusWidget.modify!TextLabel((comp) {
        comp.caption = targetStatus;
      });
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

    auto sub1 = new Widget(card, RectF(12, 34, 581, 16));
    sub1.components.textLabel = new TextLabel(
      "Single-line alignment within fixed-width boxes:",
      ColorF(0.70f, 0.75f, 0.85f, 1.0f)
    );

    // Left aligned box
    auto boxLeft = new Widget(card, RectF(12, 54, 185, 48));
    auto szBl = new Size;
    szBl.width = Dimension(185, SizingMode.fixed);
    szBl.height = Dimension(48, SizingMode.fixed);
    szBl.padding = Insets(6, 10, 6, 10);
    boxLeft.components.size = szBl;
    boxLeft.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    boxLeft.components.border = new Border(
      ColorF(0.30f, 0.50f, 0.75f, 1.0f),
      Border.Style.dashed
    );
    boxLeft.components.border.width = 1.5f;
    boxLeft.components.textLabel = new TextLabel(
      "Left Aligned",
      ColorF(0.40f, 0.80f, 1.0f, 1.0f)
    );
    boxLeft.components.textLabel.alignment = TextLabel.Alignment.left;

    // Center aligned box
    auto boxCenter = new Widget(card, RectF(205, 54, 185, 48));
    auto szBc = new Size;
    szBc.width = Dimension(185, SizingMode.fixed);
    szBc.height = Dimension(48, SizingMode.fixed);
    szBc.padding = Insets(6, 10, 6, 10);
    boxCenter.components.size = szBc;
    boxCenter.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    boxCenter.components.border = new Border(
      ColorF(0.35f, 0.70f, 0.50f, 1.0f),
      Border.Style.dashed
    );
    boxCenter.components.border.width = 1.5f;
    boxCenter.components.textLabel = new TextLabel(
      "Center Aligned",
      ColorF(0.45f, 0.90f, 0.60f, 1.0f)
    );
    boxCenter.components.textLabel.alignment = TextLabel.Alignment.center;

    // Right aligned box
    auto boxRight = new Widget(card, RectF(398, 54, 195, 48));
    auto szBr = new Size;
    szBr.width = Dimension(195, SizingMode.fixed);
    szBr.height = Dimension(48, SizingMode.fixed);
    szBr.padding = Insets(6, 10, 6, 10);
    boxRight.components.size = szBr;
    boxRight.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    boxRight.components.border = new Border(
      ColorF(0.85f, 0.55f, 0.30f, 1.0f),
      Border.Style.dashed
    );
    boxRight.components.border.width = 1.5f;
    boxRight.components.textLabel = new TextLabel(
      "Right Aligned",
      ColorF(1.0f, 0.70f, 0.40f, 1.0f)
    );
    boxRight.components.textLabel.alignment = TextLabel.Alignment.right;

    auto sub2 = new Widget(card, RectF(12, 110, 581, 16));
    sub2.components.textLabel = new TextLabel(
      "Multiline alignment (each line aligned individually):",
      ColorF(0.70f, 0.75f, 0.85f, 1.0f)
    );

    // Multiline Center box
    auto multiCenterBox = new Widget(card, RectF(12, 130, 285, 138));
    auto szMc = new Size;
    szMc.width = Dimension(285, SizingMode.fixed);
    szMc.height = Dimension(138, SizingMode.fixed);
    szMc.padding = Insets(8, 12, 8, 12);
    multiCenterBox.components.size = szMc;
    multiCenterBox.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    multiCenterBox.components.border = new Border(
      ColorF(0.30f, 0.55f, 0.45f, 1.0f),
      Border.Style.rect
    );
    multiCenterBox.components.border.width = 1.5f;
    multiCenterBox.components.textLabel = new TextLabel(
      "Centered Paragraph:\nEach wrapped line\nis positioned at the\n" ~
        "exact horizontal center\nof the content bounds.",
      ColorF(0.80f, 1.0f, 0.85f, 1.0f)
    );
    multiCenterBox.components.textLabel.multiline = true;
    multiCenterBox.components.textLabel.alignment = TextLabel.Alignment.center;

    // Multiline Right box
    auto multiRightBox = new Widget(card, RectF(307, 130, 286, 138));
    auto szMr = new Size;
    szMr.width = Dimension(286, SizingMode.fixed);
    szMr.height = Dimension(138, SizingMode.fixed);
    szMr.padding = Insets(8, 12, 8, 12);
    multiRightBox.components.size = szMr;
    multiRightBox.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    multiRightBox.components.border = new Border(
      ColorF(0.60f, 0.45f, 0.30f, 1.0f),
      Border.Style.rect
    );
    multiRightBox.components.border.width = 1.5f;
    multiRightBox.components.textLabel = new TextLabel(
      "Right-Aligned Paragraph:\nEach wrapped line\nis pushed against\n" ~
        "the right boundary\nof the container area.",
      ColorF(1.0f, 0.85f, 0.70f, 1.0f)
    );
    multiRightBox.components.textLabel.multiline = true;
    multiRightBox.components.textLabel.alignment = TextLabel.Alignment.right;
  }

  void buildEllipsisSection() {
    auto card = makeSectionCard(
      root,
      RectF(645, 68, 615, 280),
      "2. Overflow Ellipsis (Single-Line & Vertical Truncation)"
    );

    auto sub1 = new Widget(card, RectF(12, 34, 591, 16));
    sub1.components.textLabel = new TextLabel(
      "Single-line overflow (overflowEllipsis = true vs false):",
      ColorF(0.70f, 0.75f, 0.85f, 1.0f)
    );

    // Single line with ellipsis = true
    auto boxEllipsis = new Widget(card, RectF(12, 54, 288, 48));
    auto szBe = new Size;
    szBe.width = Dimension(288, SizingMode.fixed);
    szBe.height = Dimension(48, SizingMode.fixed);
    szBe.padding = Insets(6, 10, 6, 10);
    boxEllipsis.components.size = szBe;
    boxEllipsis.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    boxEllipsis.components.border = new Border(
      ColorF(0.30f, 0.55f, 0.75f, 1.0f),
      Border.Style.rect
    );
    boxEllipsis.components.border.width = 1.5f;
    boxEllipsis.components.textLabel = new TextLabel(
      "overflowEllipsis=true: Very long sentence truncated with ellipsis.",
      ColorF(0.60f, 0.85f, 1.0f, 1.0f)
    );
    boxEllipsis.components.textLabel.multiline = false;
    boxEllipsis.components.textLabel.overflowEllipsis = true;

    // Single line with ellipsis = false (scissored by clipContents)
    auto boxNoEllipsis = new Widget(card, RectF(308, 54, 295, 48));
    auto szBne = new Size;
    szBne.width = Dimension(295, SizingMode.fixed);
    szBne.height = Dimension(48, SizingMode.fixed);
    szBne.padding = Insets(6, 10, 6, 10);
    boxNoEllipsis.components.size = szBne;
    boxNoEllipsis.clipContents = true;
    boxNoEllipsis.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    boxNoEllipsis.components.border = new Border(
      ColorF(0.65f, 0.35f, 0.40f, 1.0f),
      Border.Style.rect
    );
    boxNoEllipsis.components.border.width = 1.5f;
    boxNoEllipsis.components.textLabel = new TextLabel(
      "overflowEllipsis=false: Long sentence scissored without ellipsis dots.",
      ColorF(1.0f, 0.65f, 0.70f, 1.0f)
    );
    boxNoEllipsis.components.textLabel.multiline = false;
    boxNoEllipsis.components.textLabel.overflowEllipsis = false;

    auto sub2 = new Widget(card, RectF(12, 110, 591, 16));
    sub2.components.textLabel = new TextLabel(
      "Multiline vertical overflow (last visible line truncated with '...'):",
      ColorF(0.70f, 0.75f, 0.85f, 1.0f)
    );

    // Multiline vertical with ellipsis
    auto multiVertEllipsis = new Widget(card, RectF(12, 130, 288, 138));
    auto szMve = new Size;
    szMve.width = Dimension(288, SizingMode.fixed);
    szMve.height = Dimension(138, SizingMode.fixed);
    szMve.padding = Insets(8, 12, 8, 12);
    multiVertEllipsis.components.size = szMve;
    multiVertEllipsis.clipContents = true;
    multiVertEllipsis.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    multiVertEllipsis.components.border = new Border(
      ColorF(0.35f, 0.65f, 0.50f, 1.0f),
      Border.Style.rect
    );
    multiVertEllipsis.components.border.width = 1.5f;
    multiVertEllipsis.components.textLabel = new TextLabel(
      "Line 1: Primary line\nLine 2: Secondary line\n" ~
        "Line 3: Content line\nLine 4: Approaching boundary\n" ~
        "Line 5: Near container limit\n" ~
        "Line 6: Last visible truncated line\n" ~
        "Line 7: Overflow line\nLine 8: Clipped line\n" ~
        "Line 9: Invisible extra line",
      ColorF(0.70f, 1.0f, 0.80f, 1.0f)
    );
    multiVertEllipsis.components.textLabel.multiline = true;
    multiVertEllipsis.components.textLabel.overflowEllipsis = true;

    // Multiline vertical without ellipsis
    auto multiVertNoEllipsis = new Widget(card, RectF(308, 130, 295, 138));
    auto szMvne = new Size;
    szMvne.width = Dimension(295, SizingMode.fixed);
    szMvne.height = Dimension(138, SizingMode.fixed);
    szMvne.padding = Insets(8, 12, 8, 12);
    multiVertNoEllipsis.components.size = szMvne;
    multiVertNoEllipsis.clipContents = true;
    multiVertNoEllipsis.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    multiVertNoEllipsis.components.border = new Border(
      ColorF(0.65f, 0.50f, 0.30f, 1.0f),
      Border.Style.rect
    );
    multiVertNoEllipsis.components.border.width = 1.5f;
    multiVertNoEllipsis.components.textLabel = new TextLabel(
      "Line 1: Primary line\nLine 2: Secondary line\n" ~
        "Line 3: Content line\nLine 4: Approaching boundary\n" ~
        "Line 5: Near container limit\n" ~
        "Line 6: Last visible line (no ellipsis)\n" ~
        "Line 7: Overflow line\nLine 8: Clipped line\n" ~
        "Line 9: Invisible extra line",
      ColorF(1.0f, 0.85f, 0.60f, 1.0f)
    );
    multiVertNoEllipsis.components.textLabel.multiline = true;
    multiVertNoEllipsis.components.textLabel.overflowEllipsis = false;
  }

  void buildMultilineSection() {
    auto card = makeSectionCard(
      root,
      RectF(20, 356, 605, 290),
      "3. Multiline & Word Wrapping (wrapLine vs Single-Line)"
    );

    auto sub1 = new Widget(card, RectF(12, 34, 581, 16));
    sub1.components.textLabel = new TextLabel(
      "Automatic word wrapping & explicit newlines [multiline = true]:",
      ColorF(0.70f, 0.75f, 0.85f, 1.0f)
    );

    // Box 1: Auto word wrapping
    auto wrapBox = new Widget(card, RectF(12, 54, 285, 120));
    auto szWb = new Size;
    szWb.width = Dimension(285, SizingMode.fixed);
    szWb.height = Dimension(120, SizingMode.fixed);
    szWb.padding = Insets(8, 12, 8, 12);
    wrapBox.components.size = szWb;
    wrapBox.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    wrapBox.components.border = new Border(
      ColorF(0.35f, 0.45f, 0.65f, 1.0f),
      Border.Style.rect
    );
    wrapBox.components.border.width = 1.5f;
    wrapBox.components.textLabel = new TextLabel(
      "Word wrapping algorithm wraps lines cleanly at space delimiters " ~
        "when width is limited.",
      ColorF(0.85f, 0.90f, 1.0f, 1.0f)
    );
    wrapBox.components.textLabel.multiline = true;

    // Box 2: Explicit newlines
    auto newlinesBox = new Widget(card, RectF(307, 54, 286, 120));
    auto szNb = new Size;
    szNb.width = Dimension(286, SizingMode.fixed);
    szNb.height = Dimension(120, SizingMode.fixed);
    szNb.padding = Insets(8, 12, 8, 12);
    newlinesBox.components.size = szNb;
    newlinesBox.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    newlinesBox.components.border = new Border(
      ColorF(0.40f, 0.35f, 0.55f, 1.0f),
      Border.Style.rect
    );
    newlinesBox.components.border.width = 1.5f;
    newlinesBox.components.textLabel = new TextLabel(
      "Explicit newlines:\n" ~
        "• First item in list\n" ~
        "• Second item with line break\n" ~
        "• Third item preserved",
      ColorF(0.90f, 0.80f, 1.0f, 1.0f)
    );
    newlinesBox.components.textLabel.multiline = true;

    auto sub2 = new Widget(card, RectF(12, 180, 581, 16));
    sub2.components.textLabel = new TextLabel(
      "Multiline disabled comparison [multiline = false]:",
      ColorF(0.70f, 0.75f, 0.85f, 1.0f)
    );

    // Box 3: Single line sanitized comparison
    auto sanitizedBox = new Widget(card, RectF(12, 200, 581, 74));
    auto szSb = new Size;
    szSb.width = Dimension(581, SizingMode.fixed);
    szSb.height = Dimension(74, SizingMode.fixed);
    szSb.padding = Insets(8, 12, 8, 12);
    sanitizedBox.components.size = szSb;
    sanitizedBox.components.background = new Background(
      ColorF(0.10f, 0.12f, 0.15f, 1.0f),
      Background.Style.round
    );
    sanitizedBox.components.border = new Border(
      ColorF(0.65f, 0.50f, 0.25f, 1.0f),
      Border.Style.dashed
    );
    sanitizedBox.components.border.width = 1.5f;
    sanitizedBox.components.textLabel = new TextLabel(
      "Line 1\\nLine 2\\r\\nLine 3 (newlines sanitized into single spaces " ~
        "automatically when multiline=false, followed by overflow ellipsis)",
      ColorF(1.0f, 0.90f, 0.60f, 1.0f)
    );
    sanitizedBox.components.textLabel.multiline = false;
    sanitizedBox.components.textLabel.overflowEllipsis = true;
  }

  void buildPlaygroundSection() {
    auto card = makeSectionCard(
      root,
      RectF(645, 356, 615, 290),
      "4. Interactive TextLabel Playground (Keys: [M] [E] [L] [T])"
    );

    // Status banner
    interactiveStatusWidget = new Widget(card, RectF(12, 34, 591, 30));
    auto szIsw = new Size;
    szIsw.width = Dimension(591, SizingMode.fixed);
    szIsw.height = Dimension(30, SizingMode.fixed);
    szIsw.padding = Insets(4, 10, 4, 10);
    interactiveStatusWidget.components.size = szIsw;
    interactiveStatusWidget.components.background = new Background(
      ColorF(0.14f, 0.17f, 0.23f, 1.0f),
      Background.Style.round
    );
    interactiveStatusWidget.components.background.cornerRadius = 4.0f;
    interactiveStatusWidget.components.border = new Border(
      ColorF(0.35f, 0.45f, 0.65f, 1.0f),
      Border.Style.rect
    );
    interactiveStatusWidget.components.border.width = 1.0f;
    interactiveStatusWidget.components.textLabel = new TextLabel(
      "[M] Multiline: ON | [E] Ellipsis: ON | [L] Align: left | Sample: 1/3",
      ColorF(0.95f, 0.95f, 0.40f, 1.0f)
    );

    // Interactive Testbed Widget
    interactiveLabelWidget = new Widget(card, RectF(12, 70, 591, 148));
    auto szIlw = new Size;
    szIlw.width = Dimension(591, SizingMode.fixed);
    szIlw.height = Dimension(148, SizingMode.fixed);
    szIlw.padding = Insets(10, 14, 10, 14);
    interactiveLabelWidget.components.size = szIlw;
    interactiveLabelWidget.clipContents = true;
    interactiveLabelWidget.components.background = new Background(
      ColorF(0.09f, 0.11f, 0.15f, 1.0f),
      Background.Style.round
    );
    interactiveLabelWidget.components.background.cornerRadius = 6.0f;
    interactiveLabelWidget.components.border = new Border(
      ColorF(0.30f, 0.75f, 0.90f, 1.0f),
      Border.Style.dashed
    );
    interactiveLabelWidget.components.border.width = 2.0f;
    interactiveLabelWidget.components.border.dashLen = 6.0f;
    interactiveLabelWidget.components.border.gap = 3.0f;

    interactiveLabelWidget.components.textLabel = new TextLabel(
      labelInteractiveSamples[0],
      ColorF(1.0f, 1.0f, 1.0f, 1.0f)
    );
    interactiveLabelWidget.components.textLabel.multiline = true;
    interactiveLabelWidget.components.textLabel.overflowEllipsis = true;
    interactiveLabelWidget.components.textLabel.alignment =
      TextLabel.Alignment.left;
    interactiveLabelWidget.components.textLabel.fontSize = 15.0f;

    // Hint / controls info
    auto hint = new Widget(card, RectF(12, 226, 591, 52));
    auto szH = new Size;
    szH.width = Dimension(591, SizingMode.fixed);
    szH.height = Dimension(52, SizingMode.fixed);
    szH.padding = Insets(6, 10, 6, 10);
    hint.components.size = szH;
    hint.components.background = new Background(
      ColorF(0.11f, 0.13f, 0.17f, 1.0f),
      Background.Style.round
    );
    hint.components.background.cornerRadius = 4.0f;
    hint.components.border = new Border(
      ColorF(0.25f, 0.28f, 0.35f, 1.0f),
      Border.Style.rect
    );
    hint.components.border.width = 1.0f;
    hint.components.textLabel = new TextLabel(
      "[M] Toggle multiline | [E] Toggle ellipsis | [L] Cycle alignment\n" ~
        "[T] Cycle sample text | [Tab] or [1]/[2] Switch demo pages",
      ColorF(0.65f, 0.72f, 0.85f, 1.0f)
    );
    hint.components.textLabel.multiline = true;
    hint.components.textLabel.fontSize = 12.0f;
  }

  Widget root;
  Widget interactiveLabelWidget;
  Widget interactiveStatusWidget;
}
