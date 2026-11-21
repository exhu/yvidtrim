/**
 * guidemoapp.d - Interactive GUI feature showcase and testbed for yguilib.
 *
 * PURPOSE:
 * This optional demo application serves as a visual verification tool and
 * interactive playground to test new GUI features as they are implemented
 * in yguilib (and eventually yvidtrim, such as video playback components).
 *
 * CURRENT FEATURE COVERAGE:
 * 1. widget_painter.d & drawing_components.d:
 *    - Background styles: Style.rect, Style.round, Style.none.
 *    - Border styles: Style.rect, Style.dashed, Style.round, Style.roundDashed,
 *      and Style.none.
 *    - TextLabel: text rendering, custom colors, auto-measurement.
 *    - TextLabel options: multiline wrapping, explicit newlines, overflow
 *      ellipsis, horizontal alignment (left, center, right), live playground.
 *    - Alpha transparency: animated alpha blending.
 *    - Clipping: Widget.clipChildren and Widget.clipContents scissoring.
 *    - Visibility culling: toggling Widget.visible dynamically.
 * 2. layout_system.d (and flex/anchor/dimension subsystems):
 *    - SizingMode: fixed, auto_ (content-driven), and fraction (flex-grow).
 *    - Size bounds: minWidth, maxWidth, minHeight, maxHeight constraints.
 *    - Insets: Size.padding (inner) and Size.margin (outer clearance).
 *    - FlexContainer: FlexDirection (row, column), gap spacing.
 *    - JustifyContent: start, end, center, spaceBetween.
 *    - AlignItems: start, end, center, stretch.
 *    - Anchor: out-of-flow pinning (top, bottom, left, right) relative to
 *      parent bounds, including out-of-flow anchors inside flex containers.
 *
 * MAINTENANCE NOTE:
 * When adding new layout modes, drawing primitives, widgets, or components
 * to yguilib or yvidtrim (e.g. video rendering surfaces, timeline scrubbers),
 * update this demo with dedicated visual sections and interactive controls.
 *
 * KEYBOARD CONTROLS:
 *   [Tab]/[1-7]   Switch demo page (Page 1: Layout, Page 2: TextLabel,
 *                 Page 3: Hover Ctrl, Page 4: Hover System,
 *                 Page 5: TabControl, Page 6: Scrollbars, Page 7: VirtList)
 *   [M]           Toggle multiline on interactive TextLabel
 *   [E]           Toggle overflow ellipsis on interactive TextLabel
 *   [L]           Cycle horizontal alignment (left -> center -> right)
 *   [D]           Toggle FlexDirection (row <-> column)
 *   [J]           Cycle JustifyContent (start -> end -> center -> spaceBetween)
 *   [A]           Cycle AlignItems (stretch -> start -> end -> center)
 *   [G]           Cycle flex gap (0, 8, 16, 24 px)
 *   [V]           Toggle child widget visibility (demonstrates flex re-flow)
 *   [T]           Cycle text sample (auto-sizing / playground caption)
 *   [Q]/[Esc]     Quit demo
 */
module guidemo.guidemoapp;

import yguilib.app : App;
import yguilib.model : ModelTracker;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;

import guidemo.controller : DemoController, DemoControllerParams;
import guidemo.hover_button : HoverButtonController;
import guidemo.hover_button_system : AnimatedHoverButtonSystem;
import guidemo.model : DemoModel;
import guidemo.pages.button_controller : ButtonPageController;
import guidemo.pages.button_page : ButtonPage;
import guidemo.pages.button_system_controller : ButtonSystemPageController;
import guidemo.pages.button_system_page : ButtonSystemPage;
import guidemo.pages.layout_painter_controller : LayoutPainterPageController;
import guidemo.pages.layout_painter_page : LayoutPainterPage;
import guidemo.pages.scrollbars_controller : ScrollbarsPageController;
import guidemo.pages.scrollbars_page : ScrollbarsPage;
import guidemo.pages.tabcontrol_controller : TabControlPageController;
import guidemo.pages.tabcontrol_page : TabControlPage;
import guidemo.pages.textlabel_controller : TextLabelPageController;
import guidemo.pages.textlabel_page : TextLabelPage;
import guidemo.pages.virtlist_controller : VirtListPageController;
import guidemo.pages.virtlist_page : VirtListPage;
import guidemo.scrollbars : registerScrollbars;
import guidemo.tabcontrol : TabsModel, registerTabControl;
import guidemo.view : DemoView, createHeaderTabsModel;
import guidemo.virtlist : registerVirtList;

void main() {
  import std.logger : infof;

  auto app = App.makeAppWithTitleWh(
    "yguilib feature demo - guidemo", 1280, 720
  );
  // Register systems and reusable composite widget controllers.
  app.ui.registerWidgetSystem(new AnimatedHoverButtonSystem());
  app.ui.pushController(registerTabControl(app.ui));
  app.ui.pushController(registerScrollbars(app.ui));
  app.ui.pushController(registerVirtList(app.ui));
  auto hoverBtnController = new HoverButtonController(app.ui);
  app.ui.pushController(hoverBtnController);

  // Create models and shell view before DemoController.
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto tabsTracker = ModelTracker!TabsModel(createHeaderTabsModel());
  auto demoView = new DemoView(app.ui, demoTracker, tabsTracker);
  auto rootWidget = demoView.getRootWidget();
  app.ui.mainWindow().rootWidget = rootWidget;

  DemoControllerParams params;
  params.withUi(app.ui)
    .withTracker(demoTracker)
    .withView(demoView)
    .withTabsTracker(tabsTracker);
  auto demoController = new DemoController(params);

  registerDemoPages(app.ui, demoTracker, rootWidget, hoverBtnController);

  infof("ui = %s", app.ui.dumpInfo());
  infof("root = %s", app.ui.mainWindow.rootWidget.dumpTree(true));
  infof(
    "root simple = %s",
    app.ui.mainWindow.rootWidget.dumpSimpleTree(true)
  );
  app.run(demoController);
}

private:

void registerDemoPages(
  UiSystem ui,
  ref ModelTracker!DemoModel demoTracker,
  Widget rootWidget,
  HoverButtonController hoverBtnController
) {
  assert(ui !is null, "UiSystem must not be null");
  assert(rootWidget !is null, "rootWidget must not be null");
  assert(hoverBtnController !is null, "hoverBtnController must not be null");

  auto layoutPage = new LayoutPainterPage(ui, rootWidget);
  ui.pushController(
    new LayoutPainterPageController(ui, demoTracker, layoutPage)
  );

  auto textPage = new TextLabelPage(ui, rootWidget);
  ui.pushController(
    new TextLabelPageController(ui, demoTracker, textPage)
  );

  auto buttonPage = new ButtonPage(ui, rootWidget);
  buttonPage.registerWithController(hoverBtnController);
  ui.pushController(
    new ButtonPageController(ui, demoTracker, buttonPage)
  );

  auto buttonSysPage = new ButtonSystemPage(ui, rootWidget);
  ui.pushController(
    new ButtonSystemPageController(ui, demoTracker, buttonSysPage)
  );

  auto tabPage = new TabControlPage(ui, rootWidget, ui);
  ui.pushController(
    new TabControlPageController(ui, demoTracker, tabPage)
  );

  auto scrollPage = new ScrollbarsPage(ui, rootWidget, ui);
  ui.pushController(
    new ScrollbarsPageController(ui, demoTracker, scrollPage)
  );

  auto virtListPage = new VirtListPage(ui, rootWidget, ui);
  ui.pushController(
    new VirtListPageController(ui, demoTracker, virtListPage)
  );
}
