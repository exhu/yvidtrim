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
 * 3. controls/button.d:
 *    - Plain push Button: press fade + caption sink animation, drag-off
 *      cancel, release-inside click, disabled state, fixed/auto sizing.
 * 4. render/canvas/ (via CustomDraw / WidgetBuilder.onDraw):
 *    - Path2d curves, arcs, ellipses, round rects; nonZero/evenOdd fills;
 *      caps, joins, miter limit, animated dashes; transforms; clips;
 *      linear/radial gradients; Canvas + Renderer interop.
 * 5. render/image.d & render/texture.d:
 *    - Embedded PNG decoded to Image; Texture drawn 1:1, 2x, as a src
 *      sub-rect and tinted (Canvas page slot 7, [I]); F12 screenshots.
 *
 * MAINTENANCE NOTE:
 * When adding new layout modes, drawing primitives, widgets, or components
 * to yguilib or yvidtrim (e.g. video rendering surfaces, timeline scrubbers),
 * update this demo with dedicated visual sections and interactive controls.
 *
 * KEYBOARD CONTROLS:
 *   [Tab]/[1-9,0] Switch demo page (Page 1: Layout, Page 2: TextLabel,
 *                 Page 3: Hover Ctrl, Page 4: Hover System,
 *                 Page 5: TabControl, Page 6: Scrollbars, Page 7: VirtList,
 *                 Page 8: Knob / cursor lock, Page 9: Button,
 *                 Page 10 ([0]): Canvas, Page 11: Gamepad)
 *   [Space]       Toggle Canvas page animation (Page 10)
 *   [I]           Swap Canvas interop / image section (Page 10)
 *   [M]           Toggle multiline on interactive TextLabel
 *   [E]           Toggle overflow ellipsis on interactive TextLabel
 *   [L]           Cycle horizontal alignment (left -> center -> right)
 *   [D]           Toggle FlexDirection (row <-> column)
 *   [J]           Cycle JustifyContent (start -> end -> center -> spaceBetween)
 *   [A]           Cycle AlignItems (stretch -> start -> end -> center)
 *   [G]           Cycle flex gap (0, 8, 16, 24 px)
 *   [V]           Toggle child widget visibility (demonstrates flex re-flow)
 *   [T]           Cycle text sample (auto-sizing / playground caption)
 *   [F1]          Cycle debug draw mode
 *   [F12]         Save screenshot-YYYYMMDD-HHMMSS.png to current directory
 *   [Q]/[Esc]     Quit demo
 */
module guidemo.guidemoapp;

import yguilib.app : App;
import yguilib.model : ModelTracker;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;

import guidemo.controller : DemoController, DemoControllerParams;
import guidemo.hover_button : HoverButtonController;
import yguilib.controls.hover_button_system : AnimatedHoverButtonSystem;
import guidemo.model : ButtonPageModel, ButtonSystemPageModel,
  CanvasPageModel, DemoModel, GamepadPageModel, KnobPageModel,
  LayoutPainterPageModel, SimpleButtonPageModel, TextLabelPageModel;
import guidemo.pages.button_controller : ButtonPageController;
import guidemo.pages.button_page : ButtonPage;
import guidemo.pages.button_system_controller : ButtonSystemPageController;
import guidemo.pages.button_system_page : ButtonSystemPage;
import guidemo.pages.canvas_controller : CanvasPageController;
import guidemo.pages.canvas_page : CanvasPage;
import guidemo.pages.gamepad_controller : GamepadPageController;
import guidemo.pages.gamepad_page : GamepadPage;
import guidemo.pages.knob_controller : KnobPageController;
import guidemo.pages.knob_page : KnobPage;
import guidemo.pages.layout_painter_controller : LayoutPainterPageController;
import guidemo.pages.layout_painter_page : LayoutPainterPage;
import guidemo.pages.scrollbars_controller : ScrollbarsPageController;
import guidemo.pages.scrollbars_page : ScrollbarsPage,
  ScrollbarsPageTrackers;
import guidemo.pages.simple_button_controller :
  SimpleButtonPageController;
import guidemo.pages.simple_button_page : SimpleButtonPage;
import guidemo.pages.tabcontrol_controller : TabControlPageController;
import guidemo.pages.tabcontrol_page : TabControlPage,
  TabControlPageTrackers;
import guidemo.pages.textlabel_controller : TextLabelPageController;
import guidemo.pages.textlabel_page : TextLabelPage;
import guidemo.pages.virtlist_controller : VirtListPageController;
import guidemo.pages.virtlist_page : VirtListPage, VirtListPageTrackers;
import yguilib.controls.scrollbars : registerScrollbars;
import yguilib.controls.tabcontrol : TabsModel, registerTabControl;
import yguilib.controls.tooltip : TooltipLayerBuilder, TooltipSystem;
import guidemo.view : DemoView, createHeaderTabsModel;
import yguilib.controls.virtlist : registerVirtList;

void main() {
  import std.logger : infof;

  auto app = App.makeAppWithTitleWh(
    "yguilib feature demo - guidemo", 1280, 720
  );
  // Register systems and reusable composite widget controllers.
  app.ui.registerWidgetSystem(new AnimatedHoverButtonSystem());
  app.ui.registerWidgetSystem(new TooltipSystem());
  app.ui.pushController(registerTabControl(app.ui));
  app.ui.pushController(registerScrollbars(app.ui));
  app.ui.pushController(registerVirtList(app.ui));
  auto hoverBtnController = new HoverButtonController(app.ui);
  app.ui.pushController(hoverBtnController);

  // Create models and shell view before DemoController.
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto tabsTracker = ModelTracker!TabsModel(createHeaderTabsModel());
  auto demoView = new DemoView(app.ui, demoTracker, tabsTracker);
  auto rootWidget = demoView.rootWidget();
  app.withRootWidget(rootWidget);

  DemoControllerParams params;
  params.withUi(app.ui)
    .withTracker(demoTracker)
    .withView(demoView)
    .withTabsTracker(tabsTracker);
  auto demoController = new DemoController(params);
  app.ui.pushController(demoController);

  registerDemoPages(app.ui, demoTracker, rootWidget, hoverBtnController);
  TooltipLayerBuilder tooltipLayerBuilder;
  tooltipLayerBuilder.name("demoTooltipLayer").build(app.ui, rootWidget);
  demoView.update();

  infof("ui = %s", app.ui.dumpInfo());
  infof("root = %s", app.ui.mainWindow.rootWidget.dumpTree(true));
  infof(
    "root simple = %s",
    app.ui.mainWindow.rootWidget.dumpSimpleTree(true)
  );
  app.run();
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

  registerLayoutPainterPage(ui, demoTracker, rootWidget);
  registerTextLabelPage(ui, demoTracker, rootWidget);
  registerButtonPage(ui, demoTracker, rootWidget, hoverBtnController);
  registerButtonSystemPage(ui, demoTracker, rootWidget);

  auto tabTrackers = TabControlPageTrackers.make();
  registerTrackedPage!(TabControlPage, TabControlPageController)(
    ui,
    demoTracker,
    rootWidget,
    tabTrackers
  );

  auto scrollTrackers = ScrollbarsPageTrackers.make();
  registerTrackedPage!(ScrollbarsPage, ScrollbarsPageController)(
    ui,
    demoTracker,
    rootWidget,
    scrollTrackers
  );

  auto virtListTrackers = VirtListPageTrackers.make();
  registerTrackedPage!(VirtListPage, VirtListPageController)(
    ui,
    demoTracker,
    rootWidget,
    virtListTrackers
  );

  registerKnobPage(ui, demoTracker, rootWidget);
  registerSimpleButtonPage(ui, demoTracker, rootWidget);
  registerCanvasPage(ui, demoTracker, rootWidget);
  registerGamepadPage(ui, demoTracker, rootWidget);
}

/**
 * Creates the view `P(ui, parent, trackers)`, params and controller `C`
 * sharing `trackers`, and pushes the controller. Returns the created view.
 */
P registerTrackedPage(P, C, T)(
  UiSystem ui,
  ref ModelTracker!DemoModel demoTracker,
  Widget rootWidget,
  ref T trackers
) {
  import guidemo.common : PageControllerParams;

  assert(ui !is null, "UiSystem must not be null");
  assert(rootWidget !is null, "rootWidget must not be null");
  auto page = new P(ui, rootWidget, trackers);
  PageControllerParams!(P, T) params;
  params.withUi(ui)
    .withDemoTracker(demoTracker)
    .withTrackers(trackers)
    .withPage(page);
  ui.pushController(new C(params));
  return page;
}

/**
 * Creates the page tracker, view `P`, params and controller `C` for a page
 * whose view ctor is `P(ui, parent, tracker)`, and pushes the controller.
 * Returns the created view.
 */
P registerSimplePage(P, C, M)(
  UiSystem ui,
  ref ModelTracker!DemoModel demoTracker,
  Widget rootWidget
) {
  auto pageTracker = ModelTracker!M(new M());
  return registerTrackedPage!(P, C, ModelTracker!M)(
    ui,
    demoTracker,
    rootWidget,
    pageTracker
  );
}

void registerLayoutPainterPage(
  UiSystem ui,
  ref ModelTracker!DemoModel demoTracker,
  Widget rootWidget
) {
  registerSimplePage!(
    LayoutPainterPage,
    LayoutPainterPageController,
    LayoutPainterPageModel
  )(ui, demoTracker, rootWidget);
}

void registerTextLabelPage(
  UiSystem ui,
  ref ModelTracker!DemoModel demoTracker,
  Widget rootWidget
) {
  registerSimplePage!(
    TextLabelPage,
    TextLabelPageController,
    TextLabelPageModel
  )(ui, demoTracker, rootWidget);
}

void registerButtonPage(
  UiSystem ui,
  ref ModelTracker!DemoModel demoTracker,
  Widget rootWidget,
  HoverButtonController hoverBtnController
) {
  assert(hoverBtnController !is null, "hoverBtnController must not be null");
  auto page = registerSimplePage!(
    ButtonPage,
    ButtonPageController,
    ButtonPageModel
  )(ui, demoTracker, rootWidget);
  page.registerWithController(hoverBtnController);
}

void registerButtonSystemPage(
  UiSystem ui,
  ref ModelTracker!DemoModel demoTracker,
  Widget rootWidget
) {
  registerSimplePage!(
    ButtonSystemPage,
    ButtonSystemPageController,
    ButtonSystemPageModel
  )(ui, demoTracker, rootWidget);
}

void registerKnobPage(
  UiSystem ui,
  ref ModelTracker!DemoModel demoTracker,
  Widget rootWidget
) {
  registerSimplePage!(KnobPage, KnobPageController, KnobPageModel)(
    ui,
    demoTracker,
    rootWidget
  );
}

void registerSimpleButtonPage(
  UiSystem ui,
  ref ModelTracker!DemoModel demoTracker,
  Widget rootWidget
) {
  registerSimplePage!(
    SimpleButtonPage,
    SimpleButtonPageController,
    SimpleButtonPageModel
  )(ui, demoTracker, rootWidget);
}

void registerCanvasPage(
  UiSystem ui,
  ref ModelTracker!DemoModel demoTracker,
  Widget rootWidget
) {
  registerSimplePage!(CanvasPage, CanvasPageController, CanvasPageModel)(
    ui,
    demoTracker,
    rootWidget
  );
}

void registerGamepadPage(
  UiSystem ui,
  ref ModelTracker!DemoModel demoTracker,
  Widget rootWidget
) {
  registerSimplePage!(GamepadPage, GamepadPageController, GamepadPageModel)(
    ui,
    demoTracker,
    rootWidget
  );
}
