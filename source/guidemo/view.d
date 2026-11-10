/**
 * view.d - Shell view coordinating header, pages, and footer status bar.
 */
module guidemo.view;

import guidemo.model : DemoModel, defaultHeaderTabNames;
import guidemo.pages.button_page : ButtonPage;
import guidemo.pages.button_system_page : ButtonSystemPage;
import guidemo.pages.layout_painter_page : LayoutPainterPage;
import guidemo.pages.tabcontrol_page : TabControlPage;
import guidemo.pages.textlabel_page : TextLabelPage;
import guidemo.tabcontrol : TabControlBuilder, TabsModel;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiRegistry;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Background, Border, TextLabel;
import yguilib.widget.layout_components : AlignItems, FlexDirection, Insets,
  JustifyContent, Size;
import yguilib.widget.input_components : MouseEvent;

/// Event name emitted by the header TabControl on tab switch.
enum headerTabSwitchEvent = "headerTabSwitch";

/// Factory creating a default TabsModel initialized with header tab names.
TabsModel createHeaderTabsModel() {
  return new TabsModel(defaultHeaderTabNames.dup, 0);
}

/// View building and updating all demo widget hierarchies.
final class DemoView {
  this(ref ModelTracker!DemoModel modelTracker) {
    auto defaultTabsTracker = ModelTracker!TabsModel(
      createHeaderTabsModel()
    );
    this(modelTracker, defaultTabsTracker);
  }

  /// Constructs DemoView. `registry` is allowed to be null in headless tests.
  this(
    ref ModelTracker!DemoModel modelTracker,
    ref ModelTracker!TabsModel tabsModelTracker,
    UiRegistry registry = null
  ) {
    tracker = ModelTracker!DemoModel(modelTracker);
    tabsTracker = ModelTracker!TabsModel(tabsModelTracker);

    // Root background
    view = WidgetBuilder(RectF(0, 0, 1280, 720))
      .background(ColorF(0.08f, 0.09f, 0.11f, 1.0f))
      .build();

    buildHeader(registry);

    page1 = new LayoutPainterPage(view);
    page2 = new TextLabelPage(view);
    page2.setVisible(false);
    page3 = new ButtonPage(view);
    page3.setVisible(false);
    page4 = new ButtonSystemPage(view);
    page4.setVisible(false);
    page5 = new TabControlPage(view, registry);
    page5.setVisible(false);

    buildStatusBar();
  }

  void update() {
    if (!tracker.update()) {
      return;
    }

    const auto m = tracker.model;
    updatePageVisibilityAndContent(m);
    statusLabel.setCaption(formatStatusString(m));
  }

  Widget getRootWidget() {
    return view;
  }

  Widget getHeaderTabControl() {
    return tabControl;
  }

  ButtonPage getButtonPage() {
    return page3;
  }

  ButtonSystemPage getButtonSystemPage() {
    return page4;
  }

  TabControlPage getTabControlPage() {
    return page5;
  }

private:
  void updatePageVisibilityAndContent(const DemoModel m) {
    const bool p1Vis = (m.activePage == 0);
    const bool p2Vis = (m.activePage == 1);
    const bool p3Vis = (m.activePage == 2);
    const bool p4Vis = (m.activePage == 3);
    const bool p5Vis = (m.activePage == 4);
    if (page1.isVisible() != p1Vis ||
        page2.isVisible() != p2Vis ||
        page3.isVisible() != p3Vis ||
        page4.isVisible() != p4Vis ||
        page5.isVisible() != p5Vis) {
      page1.setVisible(p1Vis);
      page2.setVisible(p2Vis);
      page3.setVisible(p3Vis);
      page4.setVisible(p4Vis);
      page5.setVisible(p5Vis);
      view.update(WidgetUpdateScope.layout);
    }

    if (p1Vis) {
      page1.update(m);
    } else if (p2Vis) {
      page2.update(m);
    } else if (p3Vis) {
      page3.update(m);
    } else if (p4Vis) {
      page4.update(m);
    } else {
      page5.update(m);
    }
  }
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
      "[Tab/1-5] Page 4: Hover System | Clicks: %d | [Q/Esc] Quit",
      m.buttonClickCount
    );
  }

  static string formatPage5Status(const DemoModel m) {
    import std.format : format;
    return format(
      "[Tab/1-5] Page 5: TabControl | SubTab: %d | VertTab: %d | " ~
        "DynTabs: %d | LastEv: %s(%d) | [Q/Esc] Quit",
      m.page5SubTab,
      m.page5VerticalTab,
      m.page5DynamicTabCount,
      m.page5LastEventName,
      m.page5LastEventIndex
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
    if (m.activePage == 4) {
      return formatPage5Status(m);
    }
    return formatPage1Status(m);
  }

  void buildHeader(UiRegistry registry) {
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

    TabControlBuilder b;
    tabControl = b
      .model(tabsTracker)
      .event(headerTabSwitchEvent)
      .gap(10.0f)
      .build(header, RectF(495, 9, 730, 30), registry);
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
  ModelTracker!TabsModel tabsTracker;

  Widget tabControl;
  Widget statusLabel;

  LayoutPainterPage page1;
  TextLabelPage page2;
  ButtonPage page3;
  ButtonSystemPage page4;
  TabControlPage page5;
}
