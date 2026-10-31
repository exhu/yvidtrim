/**
 * view.d - Shell view coordinating header, pages, and footer status bar.
 */
module guidemo.view;

import guidemo.model : DemoModel;
import guidemo.pages.button_page : ButtonPage;
import guidemo.pages.button_system_page : ButtonSystemPage;
import guidemo.pages.layout_painter_page : LayoutPainterPage;
import guidemo.pages.textlabel_page : TextLabelPage;
import guidemo.tab_button : createTabButton, updateTabButtonState;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.widget : Widget, WidgetUpdateScope;
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
    page3 = new ButtonPage(view);
    page3.setVisible(false);
    page4 = new ButtonSystemPage(view);
    page4.setVisible(false);

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
    const bool p3Vis = (m.activePage == 2);
    const bool p4Vis = (m.activePage == 3);
    if (page1.isVisible() != p1Vis ||
        page2.isVisible() != p2Vis ||
        page3.isVisible() != p3Vis ||
        page4.isVisible() != p4Vis) {
      page1.setVisible(p1Vis);
      page2.setVisible(p2Vis);
      page3.setVisible(p3Vis);
      page4.setVisible(p4Vis);
      view.update(WidgetUpdateScope.layout);
    }

    // 2. Update tab button highlights
    updateTabButtonState(tab1Btn, m.activePage == 0);
    updateTabButtonState(tab2Btn, m.activePage == 1);
    updateTabButtonState(tab3Btn, m.activePage == 2);
    updateTabButtonState(tab4Btn, m.activePage == 3);

    // 3. Delegate page-specific updates
    if (p1Vis) {
      page1.update(m);
    } else if (p2Vis) {
      page2.update(m);
    } else if (p3Vis) {
      page3.update(m);
    } else {
      page4.update(m);
    }

    // 4. Update HUD status label text
    statusLabel.setCaption(formatStatusString(m));
  }

  Widget getRootWidget() {
    return view;
  }

  ButtonPage getButtonPage() {
    return page3;
  }

  ButtonSystemPage getButtonSystemPage() {
    return page4;
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
      "[Tab/1-4] Page 2: TextLabel | [M] Multiline: %s | " ~
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
      "[Tab/1-4] Page 1: Layout | [D] Dir: %s | [J] Justify: %s | " ~
      "[A] Align: %s | [G] Gap: %.0f | [V] Box B: %s | [T] Text: %d | " ~
      "[Q/Esc] Quit",
      dirStr, justStr, alignStr, m.gap, visStr, m.textSampleIndex + 1
    );
  }

  static string formatPage3Status(const DemoModel m) {
    import std.format : format;
    return format(
      "[Tab/1-4] Page 3: Hover Buttons | Clicks: %d | [Q/Esc] Quit",
      m.buttonClickCount
    );
  }

  static string formatPage4Status(const DemoModel m) {
    import std.format : format;
    return format(
      "[Tab/1-4] Page 4: Hover System | Clicks: %d | [Q/Esc] Quit",
      m.buttonClickCount
    );
  }

  static string formatStatusString(const DemoModel m) {
    if (m.activePage == 1) {
      return formatPage2Status(m);
    }
    if (m.activePage == 2) {
      return formatPage3Status(m);
    }
    if (m.activePage == 3) {
      return formatPage4Status(m);
    }
    return formatPage1Status(m);
  }

  void buildHeader() {
    auto header = WidgetBuilder(view, RectF(20, 12, 1240, 48))
      .roundBackground(ColorF(0.11f, 0.13f, 0.17f, 1.0f), 6.0f)
      .border(ColorF(0.22f, 0.25f, 0.32f, 1.0f), 1.0f)
      .build();

    WidgetBuilder(header, RectF(14, 5, 470, 20))
      .text(
        "yguilib GUI Feature Demo & Showcase (guidemo)",
        ColorF(1.0f, 1.0f, 1.0f, 1.0f),
        16.0f
      )
      .build();

    WidgetBuilder(header, RectF(14, 26, 470, 16))
      .text(
        "Verification for widget_painter.d, layout_system.d & " ~
          "input_components.d",
        ColorF(0.60f, 0.65f, 0.75f, 1.0f)
      )
      .build();

    auto tabContainer = WidgetBuilder(header, RectF(495, 9, 730, 30))
      .flex(
        FlexDirection.row,
        10.0f,
        JustifyContent.start,
        AlignItems.center
      )
      .build();

    tab1Btn = createTabButton(
      tabContainer, "[1] Layout & Paint", "tab1Btn", true
    );
    tab2Btn = createTabButton(
      tabContainer, "[2] TextLabel Demo", "tab2Btn"
    );
    tab3Btn = createTabButton(
      tabContainer, "[3] Hover (Ctrl)", "tab3Btn"
    );
    tab4Btn = createTabButton(
      tabContainer, "[4] Hover (System)", "tab4Btn"
    );
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
  Widget tab3Btn;
  Widget tab4Btn;
  Widget statusLabel;

  LayoutPainterPage page1;
  TextLabelPage page2;
  ButtonPage page3;
  ButtonSystemPage page4;
}
