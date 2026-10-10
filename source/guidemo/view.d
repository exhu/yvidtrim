/**
 * view.d - Shell view coordinating header, pages, and footer status bar.
 */
module guidemo.view;

import guidemo.model : DemoModel;
import guidemo.pages.layout_painter_page : LayoutPainterPage;
import guidemo.pages.textlabel_page : TextLabelPage;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Background, Border, TextLabel;
import yguilib.widget.layout_components : AlignItems, FlexDirection, Insets,
  JustifyContent, Size;
import yguilib.widget.input_components : MouseEvent;

/// View building and updating all demo widget hierarchies.
final class DemoView {
  this(ref ModelTracker!DemoModel modelTracker) {
    tracker = ModelTracker!DemoModel(modelTracker);

    // Root background
    view = WidgetBuilder(RectF(0, 0, 1280, 720))
      .background(ColorF(0.08f, 0.09f, 0.11f, 1.0f))
      .build();

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
    const ColorF col1 = m.activePage == 0
      ? ColorF(0.20f, 0.45f, 0.85f, 1.0f)
      : ColorF(0.16f, 0.18f, 0.23f, 1.0f);
    tab1Btn.setBackgroundColor(col1);

    const ColorF col2 = m.activePage == 1
      ? ColorF(0.20f, 0.45f, 0.85f, 1.0f)
      : ColorF(0.16f, 0.18f, 0.23f, 1.0f);
    tab2Btn.setBackgroundColor(col2);

    // 3. Delegate page-specific updates
    if (p1Vis) {
      page1.update(m);
    } else {
      page2.update(m);
    }

    // 4. Update HUD status label text
    statusLabel.setCaption(formatStatusString(m));
  }

  Widget getRootWidget() {
    return view;
  }

private:
  static string formatPage2Status(const DemoModel m) {
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
      "[Tab/1/2] Page 2: TextLabel | [M] Multiline: %s | " ~
      "[E] Ellipsis: %s | [L] Align: %s | [T] Sample: %d/3 | [Q/Esc] Quit",
      m.labelMultiline ? "ON" : "OFF",
      m.labelEllipsis ? "ON" : "OFF",
      alignStr,
      m.labelSampleIndex + 1
    );
  }

  static string formatPage1Status(const DemoModel m) {
    import std.format : format;

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

  static string formatStatusString(const DemoModel m) {
    return m.activePage == 1 ? formatPage2Status(m) : formatPage1Status(m);
  }

  void buildHeader() {
    auto header = WidgetBuilder(view, RectF(20, 12, 1240, 48))
      .roundBackground(ColorF(0.11f, 0.13f, 0.17f, 1.0f), 6.0f)
      .border(ColorF(0.22f, 0.25f, 0.32f, 1.0f), 1.0f)
      .build();

    WidgetBuilder(header, RectF(14, 5, 780, 20))
      .text(
        "yguilib GUI Feature Demo & Showcase (guidemo)",
        ColorF(1.0f, 1.0f, 1.0f, 1.0f),
        16.0f
      )
      .build();

    WidgetBuilder(header, RectF(14, 26, 780, 16))
      .text(
        "Verification for widget_painter.d, layout_system.d & " ~
          "drawing_components.d",
        ColorF(0.60f, 0.65f, 0.75f, 1.0f)
      )
      .build();

    // Tab 1 button: Layout & Painter
    tab1Btn = WidgetBuilder(header, RectF(820, 9, 185, 30))
      .padding(5, 10, 5, 10)
      .roundBackground(ColorF(0.20f, 0.45f, 0.85f, 1.0f), 4.0f)
      .border(ColorF(0.40f, 0.70f, 1.0f, 1.0f), 1.0f)
      .text(
        "[1] Layout & Painter",
        ColorF(1.0f, 1.0f, 1.0f, 1.0f),
        14.0f,
        TextLabel.Alignment.center
      )
      .onMouseDown("tab1Btn")
      .build();

    // Tab 2 button: TextLabel Showcase
    tab2Btn = WidgetBuilder(header, RectF(1015, 9, 210, 30))
      .padding(5, 10, 5, 10)
      .roundBackground(ColorF(0.16f, 0.18f, 0.23f, 1.0f), 4.0f)
      .border(ColorF(0.30f, 0.35f, 0.45f, 1.0f), 1.0f)
      .text(
        "[2] TextLabel Showcase",
        ColorF(0.80f, 0.85f, 0.95f, 1.0f),
        14.0f,
        TextLabel.Alignment.center
      )
      .onMouseDown("tab2Btn")
      .build();
  }

  void buildStatusBar() {
    auto footer = WidgetBuilder(view, RectF(20, 656, 1240, 52))
      .roundBackground(ColorF(0.12f, 0.14f, 0.18f, 1.0f), 6.0f)
      .border(ColorF(0.25f, 0.30f, 0.40f, 1.0f), 1.0f)
      .build();

    statusLabel = WidgetBuilder(footer, RectF(14, 16, 1210, 20))
      .text(
        formatStatusString(tracker.model),
        ColorF(0.95f, 0.95f, 0.40f, 1.0f)
      )
      .build();
  }

  Widget view;
  ModelTracker!DemoModel tracker;

  Widget tab1Btn;
  Widget tab2Btn;
  Widget statusLabel;

  LayoutPainterPage page1;
  TextLabelPage page2;
}
