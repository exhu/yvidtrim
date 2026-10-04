/**
 * view.d - Shell view coordinating header, pages, and footer status bar.
 */
module guidemo.view;

import std.format : format;

import guidemo.model : DemoModel;
import guidemo.pages.layout_painter_page : LayoutPainterPage;
import guidemo.pages.textlabel_page : TextLabelPage;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.widget : Widget;
import yguilib.widget.drawing_components : Background, Border, TextLabel;
import yguilib.widget.layout_components : AlignItems, FlexDirection, Insets,
  JustifyContent, Size;
import yguilib.widget.input_components : MouseEvent;

/// View building and updating all demo widget hierarchies.
final class DemoView {
  this(ref ModelTracker!DemoModel modelTracker) {
    tracker = ModelTracker!DemoModel(modelTracker);

    // Root background
    view = new Widget(null, RectF(0, 0, 1280, 720));
    view.components.background = new Background(
      ColorF(0.08f, 0.09f, 0.11f, 1.0f)
    );

    buildHeader();

    page1 = new LayoutPainterPage(view);
    page2 = new TextLabelPage(view);
    page2.setVisible(false);

    buildStatusBar();
  }

  void update() {
    if (!tracker.update()) {
      return;
    }

    const auto m = tracker.model;

    // 1. Update page visibility
    const bool p1Vis = (m.activePage == 0);
    const bool p2Vis = (m.activePage == 1);
    if (page1.isVisible() != p1Vis || page2.isVisible() != p2Vis) {
      page1.setVisible(p1Vis);
      page2.setVisible(p2Vis);
      view.update();
    }

    // 2. Update tab button highlights
    if (tab1Btn !is null && tab1Btn.components.background !is null) {
      const ColorF col1 = m.activePage == 0
        ? ColorF(0.20f, 0.45f, 0.85f, 1.0f)
        : ColorF(0.16f, 0.18f, 0.23f, 1.0f);
      if (tab1Btn.components.background.color != col1) {
        tab1Btn.components.background.color = col1;
        tab1Btn.update();
      }
    }
    if (tab2Btn !is null && tab2Btn.components.background !is null) {
      const ColorF col2 = m.activePage == 1
        ? ColorF(0.20f, 0.45f, 0.85f, 1.0f)
        : ColorF(0.16f, 0.18f, 0.23f, 1.0f);
      if (tab2Btn.components.background.color != col2) {
        tab2Btn.components.background.color = col2;
        tab2Btn.update();
      }
    }

    // 3. Delegate page-specific updates
    if (p1Vis) {
      page1.update(m);
    } else {
      page2.update(m);
    }

    // 4. Update HUD status label text
    if (statusLabel !is null && statusLabel.components.textLabel !is null) {
      const string statusStr = formatStatusString(m);
      if (statusLabel.components.textLabel.caption != statusStr) {
        statusLabel.components.textLabel.caption = statusStr;
        statusLabel.update();
      }
    }
  }

  Widget getRootWidget() {
    return view;
  }

private:
  static string formatStatusString(const DemoModel m) {
    if (m.activePage == 1) {
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
        "[Tab/1/2] Page 2: TextLabel | [M] Multiline: %s | " ~
        "[E] Ellipsis: %s | [L] Align: %s | [T] Sample: %d/3 | [Q/Esc] Quit",
        m.labelMultiline ? "ON" : "OFF",
        m.labelEllipsis ? "ON" : "OFF",
        alignStr,
        m.labelSampleIndex + 1
      );
    }

    string dirStr = m.direction == FlexDirection.row ? "row" : "col";
    string justStr;
    final switch (m.justify) {
    case JustifyContent.start:
      justStr = "start";
      break;
    case JustifyContent.end:
      justStr = "end";
      break;
    case JustifyContent.center:
      justStr = "center";
      break;
    case JustifyContent.spaceBetween:
      justStr = "spaceBetween";
      break;
    }

    string alignStr;
    final switch (m.alignItems) {
    case AlignItems.start:
      alignStr = "start";
      break;
    case AlignItems.end:
      alignStr = "end";
      break;
    case AlignItems.center:
      alignStr = "center";
      break;
    case AlignItems.stretch:
      alignStr = "stretch";
      break;
    }

    string visStr = m.child2Visible ? "visible" : "hidden";

    return format(
      "[Tab/1/2] Page 1: Layout | [D] Dir: %s | [J] Justify: %s | " ~
      "[A] Align: %s | [G] Gap: %.0f | [V] Box B: %s | [T] Text: %d | " ~
      "[Q/Esc] Quit",
      dirStr, justStr, alignStr, m.gap, visStr, m.textSampleIndex + 1
    );
  }

  void buildHeader() {
    auto header = new Widget(view, RectF(20, 12, 1240, 48));
    header.components.background = new Background(
      ColorF(0.11f, 0.13f, 0.17f, 1.0f),
      Background.Style.round
    );
    header.components.background.cornerRadius = 6.0f;
    header.components.border = new Border(
      ColorF(0.22f, 0.25f, 0.32f, 1.0f),
      Border.Style.rect
    );
    header.components.border.width = 1.0f;

    auto title = new Widget(header, RectF(14, 5, 780, 20));
    title.components.textLabel = new TextLabel(
      "yguilib GUI Feature Demo & Showcase (guidemo)",
      ColorF(1.0f, 1.0f, 1.0f, 1.0f)
    );
    title.components.textLabel.fontSize = 16.0f;

    auto sub = new Widget(header, RectF(14, 26, 780, 16));
    sub.components.textLabel = new TextLabel(
      "Verification for widget_painter.d, layout_system.d & " ~
        "drawing_components.d",
      ColorF(0.60f, 0.65f, 0.75f, 1.0f)
    );

    // Tab 1 button: Layout & Painter
    tab1Btn = new Widget(header, RectF(820, 9, 185, 30));
    auto szTab1 = new Size;
    szTab1.padding = Insets(5, 10, 5, 10);
    tab1Btn.components.size = szTab1;
    tab1Btn.components.background = new Background(
      ColorF(0.20f, 0.45f, 0.85f, 1.0f),
      Background.Style.round
    );
    tab1Btn.components.background.cornerRadius = 4.0f;
    tab1Btn.components.border = new Border(
      ColorF(0.40f, 0.70f, 1.0f, 1.0f),
      Border.Style.rect
    );
    tab1Btn.components.border.width = 1.0f;
    tab1Btn.components.textLabel = new TextLabel(
      "[1] Layout & Painter",
      ColorF(1.0f, 1.0f, 1.0f, 1.0f)
    );
    tab1Btn.components.textLabel.alignment = TextLabel.Alignment.center;

    // add mouse action
    tab1Btn.inputEnabled = true;
    tab1Btn.components.mouseEvent = new MouseEvent;
    tab1Btn.components.mouseEvent.mouseDown = "tab1Btn";


    // Tab 2 button: TextLabel Showcase
    tab2Btn = new Widget(header, RectF(1015, 9, 210, 30));
    auto szTab2 = new Size;
    szTab2.padding = Insets(5, 10, 5, 10);
    tab2Btn.components.size = szTab2;
    tab2Btn.components.background = new Background(
      ColorF(0.16f, 0.18f, 0.23f, 1.0f),
      Background.Style.round
    );
    tab2Btn.components.background.cornerRadius = 4.0f;
    tab2Btn.components.border = new Border(
      ColorF(0.30f, 0.35f, 0.45f, 1.0f),
      Border.Style.rect
    );
    tab2Btn.components.border.width = 1.0f;
    tab2Btn.components.textLabel = new TextLabel(
      "[2] TextLabel Showcase",
      ColorF(0.80f, 0.85f, 0.95f, 1.0f)
    );
    tab2Btn.components.textLabel.alignment = TextLabel.Alignment.center;

    // add mouse action
    tab2Btn.inputEnabled = true;
    tab2Btn.components.mouseEvent = new MouseEvent;
    tab2Btn.components.mouseEvent.mouseDown = "tab2Btn";
  }

  void buildStatusBar() {
    auto footer = new Widget(view, RectF(20, 656, 1240, 52));
    footer.components.background = new Background(
      ColorF(0.12f, 0.14f, 0.18f, 1.0f),
      Background.Style.round
    );
    footer.components.background.cornerRadius = 6.0f;
    footer.components.border = new Border(
      ColorF(0.25f, 0.30f, 0.40f, 1.0f),
      Border.Style.rect
    );
    footer.components.border.width = 1.0f;

    statusLabel = new Widget(footer, RectF(14, 16, 1210, 20));
    statusLabel.components.textLabel = new TextLabel(
      formatStatusString(tracker.model),
      ColorF(0.95f, 0.95f, 0.40f, 1.0f)
    );
  }

  Widget view;
  ModelTracker!DemoModel tracker;

  Widget tab1Btn;
  Widget tab2Btn;
  Widget statusLabel;

  LayoutPainterPage page1;
  TextLabelPage page2;
}
