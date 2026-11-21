/**
 * view.d - Shell view for guidemo header and footer status bar.
 */
module guidemo.view;

import guidemo.demo_model_helpers : headerTabNames;
import guidemo.model : DebugDrawMode, DemoModel;
import yguilib.controls.tabcontrol : TabControlBuilder, TabsModel;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiRegistry, UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : DebugDrawComponent;
import yguilib.widget.layout_components : AlignItems, FlexDirection,
  JustifyContent, Size, SizingMode;

/// Event name emitted by the header TabControl on tab switch.
enum headerTabSwitchEvent = "headerTabSwitch";

/// Factory creating a default TabsModel initialized with header tab names.
TabsModel createHeaderTabsModel() {
  return new TabsModel(headerTabNames(), 0);
}

/// Shell view building and updating the shared demo frame (header and footer).
final class DemoView {
  @disable this();

  /// Constructs DemoView with non-null `ui` and external trackers.
  this(
    UiSystem ui,
    ref ModelTracker!DemoModel modelTracker,
    ref ModelTracker!TabsModel tabsModelTracker
  ) {
    assert(ui !is null, "UiSystem must not be null");
    this.ui = ui;
    tracker = ModelTracker!DemoModel.from(modelTracker);
    tabsTracker = ModelTracker!TabsModel.from(tabsModelTracker);

    // Root background
    view = WidgetBuilder.make(this.ui)
      .name("demoRoot")
      .rect(RectF(0, 0, 1280, 720))
      .bg(ColorF(0.08f, 0.09f, 0.11f, 1.0f))
      .build();

    buildHeader(this.ui);
    buildStatusBar();
  }

  invariant {
    assert(ui !is null);
    assert(view !is null);
    assert(tabControl !is null);
    assert(statusLabel !is null);
  }

  void update() {
    if (tracker.update()) {
      const auto m = tracker.model;
      updateDebugDraw(m);
      updateStatusBar(m.statusText);
    }
  }

  Widget getRootWidget() {
    return view;
  }

  Widget getHeaderTabControl() {
    return tabControl;
  }

private:
  void updateStatusBar(string statusText) {
    statusLabel.setCaption(statusText);
  }

  void updateDebugDraw(const DemoModel m) {
    if (m.debugDrawMode == appliedDebugDrawMode) {
      return;
    }

    view.components.debugDraw = null;

    Widget target = null;
    bool drawHidden = false;
    final switch (m.debugDrawMode) {
    case DebugDrawMode.off:
    case DebugDrawMode.activePageVisible:
    case DebugDrawMode.activePageWithHidden:
      break;
    case DebugDrawMode.allVisible:
      target = view;
      drawHidden = false;
      break;
    case DebugDrawMode.allWithHidden:
      target = view;
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
    view.update(WidgetUpdateScope.visuals);
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

    buildHeaderTitleBox(header);

    TabControlBuilder b;
    tabControl = b
      .name("headerTabControl")
      .modelTracker(tabsTracker)
      .event(headerTabSwitchEvent)
      .gap(10.0f)
      .build(ui, header, RectF(), registry);
    tabControl.components.size = Size.fraction(1.0f, 0.0f);
  }

  void buildHeaderTitleBox(Widget header) {
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
      .text(tracker.model.statusText)
      .textColor(ColorF(0.95f, 0.95f, 0.40f, 1.0f))
      .build();
  }

  UiSystem ui;
  Widget view;
  ModelTracker!DemoModel tracker;
  ModelTracker!TabsModel tabsTracker;

  Widget tabControl;
  Widget statusLabel;

  DebugDrawMode appliedDebugDrawMode = DebugDrawMode.off;
}

// View header layout construction test
unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto ui = new UiSystemImpl(null);
  auto model = new DemoModel();
  auto tracker = ModelTracker!DemoModel(model);
  auto tabsModel = createHeaderTabsModel();
  auto tabsTracker = ModelTracker!TabsModel(tabsModel);
  auto demoView = new DemoView(ui, tracker, tabsTracker);

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

  // Verify root-level debug draw mode synchronization and statusText updates
  assert(root.components.debugDraw is null);

  void applyMode(DebugDrawMode mode, string status) {
    auto m = tracker.edit();
    m.debugDrawMode = mode;
    m.statusText = status;
    tracker.commit(m);
    demoView.update();
  }

  applyMode(DebugDrawMode.allVisible, "Page 1 status");
  assert(root.components.debugDraw !is null);
  assert(root.components.debugDraw.enabled);
  assert(root.components.debugDraw.recursive);
  assert(!root.components.debugDraw.drawHidden);
  assert(demoView.statusLabel.components.textLabel.caption == "Page 1 status");

  applyMode(DebugDrawMode.allWithHidden, "Page 2 status");
  assert(root.components.debugDraw !is null);
  assert(root.components.debugDraw.enabled);
  assert(root.components.debugDraw.recursive);
  assert(root.components.debugDraw.drawHidden);
  assert(demoView.statusLabel.components.textLabel.caption == "Page 2 status");

  applyMode(DebugDrawMode.activePageVisible, "Page 2 status");
  assert(root.components.debugDraw is null);

  applyMode(DebugDrawMode.off, "Page 2 status");
  assert(root.components.debugDraw is null);
}
