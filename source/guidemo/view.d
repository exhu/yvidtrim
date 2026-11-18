/**
 * view.d - Shell view coordinating header, pages, and footer status bar.
 */
module guidemo.view;

import guidemo.model : DebugDrawMode, DemoModel, defaultHeaderTabNames;
import guidemo.pages.button_page : ButtonPage;
import guidemo.pages.button_system_page : ButtonSystemPage;
import guidemo.pages.layout_painter_page : LayoutPainterPage;
import guidemo.pages.scrollbars_page : ScrollbarsPage;
import guidemo.pages.tabcontrol_page : TabControlPage;
import guidemo.pages.textlabel_page : TextLabelPage;
import guidemo.tabcontrol : TabControlBuilder, TabsModel;
import yguilib.internal.uisystem_impl : UiSystemImpl;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiRegistry, UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Background, Border,
  DebugDrawComponent, TextLabel;
import yguilib.widget.layout_components : AlignItems, FlexContainer,
  FlexDirection, Insets, JustifyContent, Size, SizingMode;
import yguilib.widget.input_components : MouseEvent;

/// Event name emitted by the header TabControl on tab switch.
enum headerTabSwitchEvent = "headerTabSwitch";

/// Factory creating a default TabsModel initialized with header tab names.
TabsModel createHeaderTabsModel() {
  return new TabsModel(defaultHeaderTabNames.dup, 0);
}

/// View building and updating all demo widget hierarchies.
final class DemoView {
  /// Constructs DemoView. `ui` is allowed to be null in headless tests.
  this(
    ref ModelTracker!DemoModel modelTracker,
    ref ModelTracker!TabsModel tabsModelTracker,
    UiSystem ui = null
  ) {
    this.ui = (ui !is null) ? ui : new UiSystemImpl(null);
    tracker = ModelTracker!DemoModel.from(modelTracker);
    tabsTracker = ModelTracker!TabsModel.from(tabsModelTracker);

    // Root background
    view = WidgetBuilder.make(this.ui)
      .name("demoRoot")
      .rect(RectF(0, 0, 1280, 720))
      .bg(ColorF(0.08f, 0.09f, 0.11f, 1.0f))
      .build();

    buildHeader(this.ui);

    page1 = new LayoutPainterPage(this.ui, view);
    page2 = new TextLabelPage(this.ui, view);
    page2.setVisible(false);
    page3 = new ButtonPage(this.ui, view);
    page3.setVisible(false);
    page4 = new ButtonSystemPage(this.ui, view);
    page4.setVisible(false);
    page5 = new TabControlPage(this.ui, view, this.ui);
    page5.setVisible(false);
    page6 = new ScrollbarsPage(this.ui, view, this.ui);
    page6.setVisible(false);

    buildStatusBar();
  }

  void update() {
    if (tracker.update()) {
      const auto m = tracker.model;
      updatePageVisibility(m);
      updateDebugDraw(m);
    }
    updateActivePageContent(tracker.model.activePage);
    updateStatusBar();
  }

  void updateStatusBar() {
    statusLabel.setCaption(formatStatusString(tracker.model.activePage));
  }

  Widget getRootWidget() {
    return view;
  }

  Widget getHeaderTabControl() {
    return tabControl;
  }

  LayoutPainterPage getLayoutPainterPage() {
    return page1;
  }

  TextLabelPage getTextLabelPage() {
    return page2;
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

  ScrollbarsPage getScrollbarsPage() {
    return page6;
  }

private:
  void updatePageVisibility(const DemoModel m) {
    const bool p1Vis = (m.activePage == 0);
    const bool p2Vis = (m.activePage == 1);
    const bool p3Vis = (m.activePage == 2);
    const bool p4Vis = (m.activePage == 3);
    const bool p5Vis = (m.activePage == 4);
    const bool p6Vis = (m.activePage == 5);
    if (page1.isVisible() != p1Vis ||
        page2.isVisible() != p2Vis ||
        page3.isVisible() != p3Vis ||
        page4.isVisible() != p4Vis ||
        page5.isVisible() != p5Vis ||
        page6.isVisible() != p6Vis) {
      page1.setVisible(p1Vis);
      page2.setVisible(p2Vis);
      page3.setVisible(p3Vis);
      page4.setVisible(p4Vis);
      page5.setVisible(p5Vis);
      page6.setVisible(p6Vis);
      view.update(WidgetUpdateScope.layout);
    }
  }

  void updateActivePageContent(size_t activePage) {
    if (activePage == 0) {
      page1.update();
    } else if (activePage == 1) {
      page2.update();
    } else if (activePage == 2) {
      page3.update();
    } else if (activePage == 3) {
      page4.update();
    } else if (activePage == 4) {
      page5.update();
    } else {
      page6.update();
    }
  }
  void updateDebugDraw(const DemoModel m) {
    if (m.debugDrawMode == appliedDebugDrawMode &&
        m.activePage == appliedDebugDrawPage) {
      return;
    }

    view.components.debugDraw = null;
    foreach (size_t i; 0 .. 6) {
      auto pageRoot = getPageRoot(i);
      if (pageRoot !is null) {
        pageRoot.components.debugDraw = null;
      }
    }

    Widget target = null;
    bool drawHidden = false;
    final switch (m.debugDrawMode) {
    case DebugDrawMode.off:
      break;
    case DebugDrawMode.allVisible:
      target = view;
      drawHidden = false;
      break;
    case DebugDrawMode.allWithHidden:
      target = view;
      drawHidden = true;
      break;
    case DebugDrawMode.activePageVisible:
      target = getPageRoot(m.activePage);
      drawHidden = false;
      break;
    case DebugDrawMode.activePageWithHidden:
      target = getPageRoot(m.activePage);
      drawHidden = true;
      break;
    }

    if (target !is null) {
      auto comp = new DebugDrawComponent();
      comp.enabled = true;
      comp.recursive = true;
      comp.drawHidden = drawHidden;
      target.components.debugDraw = comp;
    }

    appliedDebugDrawMode = m.debugDrawMode;
    appliedDebugDrawPage = m.activePage;
    view.update(WidgetUpdateScope.visuals);
  }

  Widget getPageRoot(size_t pageIdx) {
    switch (pageIdx) {
    case 0:
      return page1.getRootWidget();
    case 1:
      return page2.getRootWidget();
    case 2:
      return page3.getRootWidget();
    case 3:
      return page4.getRootWidget();
    case 4:
      return page5.getRootWidget();
    case 5:
      return page6.getRootWidget();
    default:
      return null;
    }
  }

  string formatStatusString(size_t activePage) {
    if (activePage == 1) {
      return page2.formatStatus();
    }
    if (activePage == 2) {
      return page3.formatStatus();
    }
    if (activePage == 3) {
      return page4.formatStatus();
    }
    if (activePage == 4) {
      return page5.formatStatus();
    }
    if (activePage == 5) {
      return page6.formatStatus();
    }
    return page1.formatStatus();
  }

  void buildHeader(UiRegistry registry) {
    auto header = WidgetBuilder.make(ui)
      .parent(view)
      .name("header")
      .rect(RectF(20, 12, 1240, 48))
      .fixedSize(1240, 48)
      .paddingVh(0, 14)
      .flexRow()
      .gap(12.0f)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.center)
      .roundBg(ColorF(0.11f, 0.13f, 0.17f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.22f, 0.25f, 0.32f, 1.0f))
      .borderWidth(1.0f)
      .build();

    auto titleBox = WidgetBuilder.make(ui)
      .parent(header)
      .name("headerTitleBox")
      .rect(RectF())
      .flexColumn()
      .gap(2.0f)
      .justify(JustifyContent.center)
      .alignItems(AlignItems.start)
      .autoSize()
      .build();

    WidgetBuilder.make(ui)
      .parent(titleBox)
      .name("headerTitle")
      .rect(RectF())
      .autoSize()
      .text("yguilib GUI Feature Demo & Showcase (guidemo)")
      .textColor(ColorF(1.0f, 1.0f, 1.0f, 1.0f))
      .fontSize(16.0f)
      .build();

    WidgetBuilder.make(ui)
      .parent(titleBox)
      .name("headerSubtitle")
      .rect(RectF())
      .autoSize()
      .text(
        "Verification for widget_painter.d, layout_system.d & " ~
          "input_components.d"
      )
      .textColor(ColorF(0.60f, 0.65f, 0.75f, 1.0f))
      .build();

    TabControlBuilder b;
    tabControl = b
      .name("headerTabControl")
      .model(tabsTracker)
      .event(headerTabSwitchEvent)
      .gap(10.0f)
      .build(ui, header, RectF(), registry);
    tabControl.components.size = Size.fraction(1.0f, 0.0f);
  }

  void buildStatusBar() {
    auto footer = WidgetBuilder.make(ui)
      .parent(view)
      .name("footer")
      .rect(RectF(20, 656, 1240, 52))
      .roundBg(ColorF(0.12f, 0.14f, 0.18f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.25f, 0.30f, 0.40f, 1.0f))
      .borderWidth(1.0f)
      .build();

    statusLabel = WidgetBuilder.make(ui)
      .parent(footer)
      .name("statusLabel")
      .rect(RectF(14, 16, 1210, 20))
      .text(formatStatusString(tracker.model.activePage))
      .textColor(ColorF(0.95f, 0.95f, 0.40f, 1.0f))
      .build();
  }

  UiSystem ui;
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
  ScrollbarsPage page6;

  DebugDrawMode appliedDebugDrawMode = DebugDrawMode.off;
  size_t appliedDebugDrawPage = 0;
}

// View header layout construction test
unittest {
  auto model = new DemoModel();
  auto tracker = ModelTracker!DemoModel(model);
  auto tabsModel = createHeaderTabsModel();
  auto tabsTracker = ModelTracker!TabsModel(tabsModel);
  auto demoView = new DemoView(tracker, tabsTracker);

  auto root = demoView.getRootWidget();
  assert(root !is null);
  assert(root.children.length > 0);

  auto header = root.children[0];
  assert(header.components.size !is null);
  assert(header.components.size.width.mode == SizingMode.fixed);
  assert(header.components.size.width.value == 1240);
  assert(header.components.size.height.mode == SizingMode.fixed);
  assert(header.components.size.height.value == 48);
  assert(header.components.flexContainer !is null);
  assert(header.components.flexContainer.direction == FlexDirection.row);
  assert(header.children.length == 2);

  auto titleBox = header.children[0];
  assert(titleBox.components.flexContainer !is null);
  assert(titleBox.components.flexContainer.direction == FlexDirection.column);
  assert(titleBox.children.length == 2);

  auto tabCtrl = demoView.getHeaderTabControl();
  assert(tabCtrl !is null);
  assert(tabCtrl is header.children[1]);
  assert(tabCtrl.components.size !is null);
  assert(tabCtrl.components.size.width.mode == SizingMode.fraction);

  // Verify every widget in DemoView's tree has a non-empty name.
  void verifyAllNamed(Widget w) {
    assert(w.name.length > 0, "Widget missing name");
    foreach (child; w.children) {
      verifyAllNamed(child);
    }
  }
  verifyAllNamed(root);

  // Verify debug draw mode synchronization across all 6 pages
  assert(root.components.debugDraw is null);
  foreach (size_t i; 0 .. 6) {
    assert(demoView.getPageRoot(i).components.debugDraw is null);
  }

  void applyMode(DebugDrawMode mode, size_t pageIdx = 0) {
    auto m = tracker.edit();
    m.debugDrawMode = mode;
    m.activePage = pageIdx;
    tracker.commit(m);
    demoView.update();
  }

  applyMode(DebugDrawMode.allVisible);
  assert(root.components.debugDraw !is null);
  assert(root.components.debugDraw.enabled);
  assert(root.components.debugDraw.recursive);
  assert(!root.components.debugDraw.drawHidden);
  foreach (size_t i; 0 .. 6) {
    assert(demoView.getPageRoot(i).components.debugDraw is null);
  }

  applyMode(DebugDrawMode.allWithHidden);
  assert(root.components.debugDraw !is null);
  assert(root.components.debugDraw.enabled);
  assert(root.components.debugDraw.recursive);
  assert(root.components.debugDraw.drawHidden);

  applyMode(DebugDrawMode.activePageVisible, 1);
  assert(root.components.debugDraw is null);
  assert(demoView.getPageRoot(0).components.debugDraw is null);
  assert(demoView.getPageRoot(1).components.debugDraw !is null);
  assert(demoView.getPageRoot(1).components.debugDraw.enabled);
  assert(demoView.getPageRoot(1).components.debugDraw.recursive);
  assert(!demoView.getPageRoot(1).components.debugDraw.drawHidden);

  // Switching page moves DebugDrawComponent to the new active page
  applyMode(DebugDrawMode.activePageWithHidden, 3);
  assert(root.components.debugDraw is null);
  assert(demoView.getPageRoot(1).components.debugDraw is null);
  assert(demoView.getPageRoot(3).components.debugDraw !is null);
  assert(demoView.getPageRoot(3).components.debugDraw.enabled);
  assert(demoView.getPageRoot(3).components.debugDraw.recursive);
  assert(demoView.getPageRoot(3).components.debugDraw.drawHidden);

  applyMode(DebugDrawMode.off, 3);
  assert(root.components.debugDraw is null);
  foreach (size_t i; 0 .. 6) {
    assert(demoView.getPageRoot(i).components.debugDraw is null);
  }
}
