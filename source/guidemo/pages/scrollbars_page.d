/**
 * scrollbars_page.d - Page 6 showcase for horizontal and vertical Scrollbar
 * composite widgets, mouse drag with cursor capture, and model modes.
 */
module guidemo.pages.scrollbars_page;

import guidemo.common : makeSectionCard;
import yguilib.controls.hover_button_system : AnimatedHoverButtonBuilder,
  HoverAnimConfig;
import guidemo.model : ScrollbarsPageModel;
import yguilib.controls.scrollbars : ScrollbarBuilder, ScrollbarModel,
  ScrollbarStyle;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.uisystem : UiRegistry, UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : TextLabel;
import yguilib.widget.layout_components : AlignItems, FlexDirection,
  JustifyContent;

/// View event names emitted by Page 6 scrollbars and playground controls.
enum page6HorizScrollEvent = "page6HScroll";
enum page6VertScrollEvent = "page6VScroll";
enum page6LiveScrollEvent = "page6LiveScroll";
enum page6ReleaseScrollEvent = "page6ReleaseScroll";
enum page6PlaygroundScrollEvent = "page6PlaygroundScroll";
enum page6VisDecEvent = "page6VisDec";
enum page6VisIncEvent = "page6VisInc";
enum page6RangeToggleEvent = "page6RangeToggle";
enum page6NarrowBarEvent = "page6NarrowBar";
enum page6WidenBarEvent = "page6WidenBar";
enum page6ResetBarEvent = "page6ResetBar";

/// Page 6 widget container showcasing horizontal and vertical Scrollbars.
final class ScrollbarsPage {
  /// Constructs ScrollbarsPage. `registry` is allowed to be null in headless
  /// tests.
  this(UiSystem ui, Widget parent, UiRegistry registry) {
    assert(ui !is null, "UiSystem must not be null");
    assert(parent !is null, "parent must not be null");
    this.ui = ui;
    this.registry = (registry !is null) ? registry : ui;
    tracker = ModelTracker!ScrollbarsPageModel(new ScrollbarsPageModel());
    root = new Widget(ui.nextWidgetId());
    root.name = "scrollbarsPage";
    root.rect = RectF(0, 0, 1280, 720);
    parent.addChild(root);

    hScrollTracker = ModelTracker!ScrollbarModel(
      new ScrollbarModel().withRange(0, 542).withVisibleSize(538)
        .withStepSize(36)
    );
    vScrollTracker = ModelTracker!ScrollbarModel(
      new ScrollbarModel().withRange(0, 364).withVisibleSize(176)
        .withStepSize(24)
    );
    liveTracker = ModelTracker!ScrollbarModel(
      new ScrollbarModel().withRange(0, 1000).withValue(250)
        .withVisibleSize(150).withStepSize(25)
    );
    releaseTracker = ModelTracker!ScrollbarModel(
      new ScrollbarModel().withRange(0, 1000).withValue(250)
        .withVisibleSize(150).withStepSize(25).withReportOnReleaseOnly(true)
    );
    playgroundTracker = ModelTracker!ScrollbarModel(
      new ScrollbarModel().withRange(0, 1000).withValue(200)
        .withVisibleSize(200).withStepSize(50)
    );

    buildViewportSection();
    buildReportingModeSection();
    buildPlaygroundSection();
    buildArchitectureSection();
  }

  invariant {
    assert(root !is null);
  }

  ref ModelTracker!ScrollbarsPageModel getTracker() return {
    return tracker;
  }

  void update() {
    import std.format : format;

    if (!tracker.update()) {
      return;
    }

    const auto m = tracker.model;
    if (viewportArea !is null) {
      viewportArea.setScrollOffset(
        PointF(cast(float) m.hScroll, cast(float) m.vScroll)
      );
    }
    if (viewportStatusLabel !is null) {
      viewportStatusLabel.setCaption(
        format(
          "Offset: (%d, %d) | Content: 1080x540 | Viewport: 538x176",
          m.hScroll,
          m.vScroll
        )
      );
    }

    if (liveStatusLabel !is null) {
      liveStatusLabel.setCaption(
        format(
          "Live (reportOnReleaseOnly=false) | Value: %d | Events: %d",
          m.liveValue,
          m.liveEventCount
        )
      );
    }
    if (releaseStatusLabel !is null) {
      releaseStatusLabel.setCaption(
        format(
          "On-Release (reportOnReleaseOnly=true) | Value: %d | Events: %d",
          m.releaseValue,
          m.releaseEventCount
        )
      );
    }

    if (playgroundStatusLabel !is null) {
      updatePlaygroundStatus(m.playgroundValue);
    }
  }

  void updatePlaygroundStatus(long playgroundValue) {
    import std.format : format;

    const auto pm = playgroundTracker.model;
    const double ratio = cast(double) pm.visibleSize /
      cast(double) ((pm.max - pm.min) + pm.visibleSize);
    playgroundStatusLabel.setCaption(
      format(
        "Value: %d | Range: [%d..%d] | VisibleSize: %d\n" ~
          "Container Width: %.0fpx | Thumb Ratio: %.1f%% (min 20px)",
        playgroundValue,
        pm.min,
        pm.max,
        pm.visibleSize,
        getPlaygroundWidth(),
        ratio * 100.0
      )
    );
  }

  string formatStatus() {
    import std.format : format;

    const auto m = tracker.model;
    return format(
      "Viewport: (%d,%d) | Live: %d (%d) | Rel: %d (%d)",
      m.hScroll,
      m.vScroll,
      m.liveValue,
      m.liveEventCount,
      m.releaseValue,
      m.releaseEventCount
    );
  }

  void shrinkVisibleSize() {
    auto m = playgroundTracker.edit();
    if (m.visibleSize > 20) {
      m.visibleSize = (m.visibleSize > 100) ? (m.visibleSize / 2) : 20;
    }
    playgroundTracker.commit(m);
  }

  void growVisibleSize() {
    auto m = playgroundTracker.edit();
    if (m.visibleSize < 1000) {
      m.visibleSize = (m.visibleSize < 500) ? (m.visibleSize * 2) : 1000;
    }
    playgroundTracker.commit(m);
  }

  void togglePlaygroundRange() {
    auto m = playgroundTracker.edit();
    m.max = (m.max <= 1000) ? 10000 : 1000;
    if (m.value > m.max) {
      m.value = m.max;
    }
    playgroundTracker.commit(m);
  }

  long getPlaygroundValue() {
    return playgroundTracker.model.value;
  }

  float narrowPlaygroundBar() {
    if (playgroundScrollbar !is null) {
      float curW = playgroundScrollbar.rect.width;
      if (curW > 260.0f) {
        curW -= 75.0f;
        if (curW < 260.0f) {
          curW = 260.0f;
        }
        playgroundScrollbar.rect.width = curW;
        playgroundScrollbar.update(WidgetUpdateScope.layout);
      }
      return curW;
    }
    return 570.0f;
  }

  float widenPlaygroundBar() {
    if (playgroundScrollbar !is null) {
      float curW = playgroundScrollbar.rect.width;
      if (curW < 570.0f) {
        curW += 75.0f;
        if (curW > 570.0f) {
          curW = 570.0f;
        }
        playgroundScrollbar.rect.width = curW;
        playgroundScrollbar.update(WidgetUpdateScope.layout);
      }
      return curW;
    }
    return 570.0f;
  }

  void resetPlayground() {
    auto m = playgroundTracker.edit();
    m.min = 0;
    m.max = 1000;
    m.value = 200;
    m.visibleSize = 200;
    m.stepSize = 50;
    playgroundTracker.commit(m);
    if (playgroundScrollbar !is null) {
      playgroundScrollbar.rect.width = 570.0f;
      playgroundScrollbar.update(WidgetUpdateScope.layout);
    }
  }

  float getPlaygroundWidth() const {
    if (playgroundScrollbar !is null) {
      return playgroundScrollbar.rect.width;
    }
    return 570.0f;
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

private:
  void buildViewportSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(20, 68, 605, 280),
      "1. 2D Scrollable Viewport (Horizontal + Vertical Scrollbars)",
      "sbViewportCard"
    );

    viewportArea = WidgetBuilder.make(ui)
      .parent(card)
      .name("sbViewportArea")
      .rect(RectF(16, 40, 540, 178))
      .roundBg(ColorF(0.08f, 0.10f, 0.13f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.24f, 0.30f, 0.40f, 1.0f))
      .borderWidth(1.0f)
      .scrollableArea()
      .scrollOffset(0.0f, 0.0f)
      .build();

    buildTimelineGrid(viewportArea);

    ScrollbarBuilder vb;
    vb.name("sbViewportVBar")
      .modelTracker(vScrollTracker)
      .event(page6VertScrollEvent)
      .direction(FlexDirection.column)
      .build(ui, card, RectF(564, 40, 22, 178), registry);

    ScrollbarBuilder hb;
    hb.name("sbViewportHBar")
      .modelTracker(hScrollTracker)
      .event(page6HorizScrollEvent)
      .direction(FlexDirection.row)
      .build(ui, card, RectF(16, 224, 540, 22), registry);

    viewportStatusLabel = WidgetBuilder.make(ui)
      .parent(card)
      .name("sbViewportStatusLabel")
      .rect(RectF(16, 252, 570, 20))
      .text("Offset: (0, 0) | Content: 1080x540 | Viewport: 538x176")
      .textColor(ColorF(0.95f, 0.90f, 0.40f, 1.0f))
      .fontSize(12.0f)
      .build();
  }

  void buildTimelineGrid(Widget parent) {
    import std.format : format;

    auto content = WidgetBuilder.make(ui)
      .parent(parent)
      .name("sbGridContent")
      .rect(RectF(0, 0, 1080, 540))
      .fixedSize(1080, 540)
      .paddingAll(12.0f)
      .flexColumn()
      .gap(10.0f)
      .build();

    static immutable ColorF[5] rowColors = [
      ColorF(0.16f, 0.28f, 0.48f, 1.0f),
      ColorF(0.14f, 0.38f, 0.32f, 1.0f),
      ColorF(0.36f, 0.24f, 0.44f, 1.0f),
      ColorF(0.42f, 0.28f, 0.16f, 1.0f),
      ColorF(0.22f, 0.30f, 0.40f, 1.0f),
    ];

    foreach (r; 0 .. 5) {
      auto row = WidgetBuilder.make(ui)
        .parent(content)
        .name(format("sbGridRow%d", r))
        .rect(RectF(0, 0, 1056, 94))
        .fixedSize(1056, 94)
        .flexRow()
        .gap(10.0f)
        .build();

      foreach (c; 0 .. 6) {
        WidgetBuilder.make(ui)
          .parent(row)
          .name(format("sbGridCell_%d_%d", r, c))
          .rect(RectF(0, 0, 166, 94))
          .fixedSize(166, 94)
          .roundBg(rowColors[r])
          .bgRadius(6.0f)
          .border(ColorF(0.42f, 0.50f, 0.64f, 1.0f))
          .borderWidth(1.0f)
          .text(format("Track %d\nSeg %d", r + 1, c + 1))
          .textColor(ColorF(0.95f, 0.97f, 1.0f, 1.0f))
          .fontSize(13.0f)
          .multiline(true)
          .textAlign(TextLabel.Alignment.center)
          .build();
      }
    }
  }

  void buildReportingModeSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(645, 68, 615, 280),
      "2. Live vs. On-Release Event Reporting (Drag Outside Bounds)",
      "sbReportingCard"
    );

    liveStatusLabel = WidgetBuilder.make(ui)
      .parent(card)
      .name("sbLiveStatusLabel")
      .rect(RectF(16, 44, 580, 20))
      .text("Live (reportOnReleaseOnly=false) | Value: 250 | Events: 0")
      .textColor(ColorF(0.45f, 0.90f, 0.65f, 1.0f))
      .fontSize(13.0f)
      .build();

    ScrollbarBuilder lb;
    lb.name("sbLiveBar")
      .modelTracker(liveTracker)
      .event(page6LiveScrollEvent)
      .direction(FlexDirection.row)
      .build(ui, card, RectF(16, 70, 580, 24), registry);

    releaseStatusLabel = WidgetBuilder.make(ui)
      .parent(card)
      .name("sbReleaseStatusLabel")
      .rect(RectF(16, 116, 580, 20))
      .text("On-Release (reportOnReleaseOnly=true) | Value: 250 | Events: 0")
      .textColor(ColorF(0.95f, 0.78f, 0.40f, 1.0f))
      .fontSize(13.0f)
      .build();

    ScrollbarStyle amberStyle;
    amberStyle.thumbBg = ColorF(0.66f, 0.46f, 0.18f, 1.0f);
    amberStyle.thumbBorder = ColorF(0.92f, 0.70f, 0.32f, 1.0f);
    amberStyle.thumbDragBg = ColorF(0.84f, 0.60f, 0.24f, 1.0f);
    amberStyle.thumbDragBorder = ColorF(1.0f, 0.85f, 0.45f, 1.0f);

    ScrollbarBuilder rb;
    rb.name("sbReleaseBar")
      .modelTracker(releaseTracker)
      .event(page6ReleaseScrollEvent)
      .direction(FlexDirection.row)
      .style(amberStyle)
      .build(ui, card, RectF(16, 142, 580, 24), registry);

    buildReportingInfoBox(card);
  }

  void buildReportingInfoBox(Widget card) {
    auto infoBox = WidgetBuilder.make(ui)
      .parent(card)
      .name("sbReportingInfoBox")
      .rect(RectF(16, 184, 583, 80))
      .roundBg(ColorF(0.09f, 0.11f, 0.14f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.20f, 0.23f, 0.28f, 1.0f))
      .borderWidth(1.0f)
      .build();

    WidgetBuilder.make(ui)
      .parent(infoBox)
      .name("sbReportingInfoBody")
      .rect(RectF(12, 10, 559, 60))
      .text(
        "- Dragging the thumb captures the mouse cursor via " ~
          "SDL_CaptureMouse\n" ~
          "- Live bar emits position events continuously while dragging\n" ~
          "- On-Release bar moves thumb visually, emitting once on mouseUp"
      )
      .textColor(ColorF(0.74f, 0.80f, 0.88f, 1.0f))
      .fontSize(12.0f)
      .build();
  }

  void buildPlaygroundSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(20, 360, 605, 284),
      "3. Resizable Geometry & Dynamic ScrollbarModel Playground",
      "sbPlaygroundCard"
    );

    WidgetBuilder.make(ui)
      .parent(card)
      .name("sbPlaygroundDesc")
      .rect(RectF(16, 36, 570, 20))
      .text(
        "Resize container or mutate visibleSize/max; thumb clamps >= 20px."
      )
      .textColor(ColorF(0.70f, 0.75f, 0.85f, 1.0f))
      .fontSize(12.0f)
      .build();

    ScrollbarStyle emeraldStyle;
    emeraldStyle.thumbBg = ColorF(0.18f, 0.50f, 0.36f, 1.0f);
    emeraldStyle.thumbBorder = ColorF(0.35f, 0.80f, 0.58f, 1.0f);
    emeraldStyle.thumbDragBg = ColorF(0.26f, 0.68f, 0.48f, 1.0f);
    emeraldStyle.thumbDragBorder = ColorF(0.50f, 0.95f, 0.72f, 1.0f);

    ScrollbarBuilder pb;
    playgroundScrollbar = pb
      .name("sbPlaygroundBar")
      .modelTracker(playgroundTracker)
      .event(page6PlaygroundScrollEvent)
      .direction(FlexDirection.row)
      .style(emeraldStyle)
      .build(ui, card, RectF(16, 66, 570, 24), registry);

    buildPlaygroundButtons(card);
    buildPlaygroundInfoBox(card);
  }

  void buildPlaygroundInfoBox(Widget card) {
    auto infoBox = WidgetBuilder.make(ui)
      .parent(card)
      .name("sbPlaygroundInfoBox")
      .rect(RectF(16, 160, 573, 108))
      .roundBg(ColorF(0.09f, 0.11f, 0.14f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.20f, 0.23f, 0.28f, 1.0f))
      .borderWidth(1.0f)
      .build();

    playgroundStatusLabel = WidgetBuilder.make(ui)
      .parent(infoBox)
      .name("sbPlaygroundStatusLabel")
      .rect(RectF(12, 10, 549, 44))
      .text(
        "Value: 200 | Range: [0..1000] | VisibleSize: 200\n" ~
          "Container Width: 570px | Thumb Ratio: 16.7% (min 20px)"
      )
      .textColor(ColorF(0.45f, 0.95f, 0.70f, 1.0f))
      .fontSize(13.0f)
      .build();

    WidgetBuilder.make(ui)
      .parent(infoBox)
      .name("sbPlaygroundHelp")
      .rect(RectF(12, 58, 549, 42))
      .text(
        "- Click track free area on either side of thumb to page +/- " ~
          "visibleSize\n" ~
          "- Click < or > arrows to step +/- 50 units (disabled at bounds)"
      )
      .textColor(ColorF(0.70f, 0.75f, 0.85f, 1.0f))
      .fontSize(12.0f)
      .build();
  }

  void buildPlaygroundButtons(Widget card) {
    auto btnRow = WidgetBuilder.make(ui)
      .parent(card)
      .name("sbPlaygroundBtnRow")
      .rect(RectF(16, 106, 573, 40))
      .flexRow()
      .gap(8.0f)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.center)
      .build();

    buildPlaygroundVisButtons(btnRow);
    buildPlaygroundGeomButtons(btnRow);
  }

  void buildPlaygroundVisButtons(Widget btnRow) {
    makePlaygroundBtn(
      btnRow,
      "sbVisDecBtn",
      "- Vis",
      76.0f,
      ColorF(0.24f, 0.14f, 0.16f, 1.0f),
      ColorF(0.65f, 0.24f, 0.28f, 1.0f),
      ColorF(0.95f, 0.45f, 0.50f, 1.0f),
      "page6VisDec"
    );
    makePlaygroundBtn(
      btnRow,
      "sbVisIncBtn",
      "+ Vis",
      76.0f,
      ColorF(0.14f, 0.24f, 0.18f, 1.0f),
      ColorF(0.22f, 0.56f, 0.36f, 1.0f),
      ColorF(0.40f, 0.88f, 0.60f, 1.0f),
      "page6VisInc"
    );
    makePlaygroundBtn(
      btnRow,
      "sbRangeBtn",
      "Max 1K/10K",
      110.0f,
      ColorF(0.16f, 0.20f, 0.28f, 1.0f),
      ColorF(0.28f, 0.44f, 0.75f, 1.0f),
      ColorF(0.50f, 0.72f, 1.0f, 1.0f),
      "page6RangeToggle"
    );
  }

  void buildPlaygroundGeomButtons(Widget btnRow) {
    makePlaygroundBtn(
      btnRow,
      "sbNarrowBtn",
      "- Narrow",
      95.0f,
      ColorF(0.24f, 0.18f, 0.10f, 1.0f),
      ColorF(0.55f, 0.40f, 0.18f, 1.0f),
      ColorF(0.85f, 0.65f, 0.35f, 1.0f),
      "page6NarrowBar"
    );
    makePlaygroundBtn(
      btnRow,
      "sbWidenBtn",
      "+ Widen",
      95.0f,
      ColorF(0.18f, 0.14f, 0.26f, 1.0f),
      ColorF(0.35f, 0.30f, 0.55f, 1.0f),
      ColorF(0.65f, 0.55f, 0.90f, 1.0f),
      "page6WidenBar"
    );
    makePlaygroundBtn(
      btnRow,
      "sbResetBtn",
      "Reset",
      78.0f,
      ColorF(0.18f, 0.20f, 0.25f, 1.0f),
      ColorF(0.32f, 0.38f, 0.48f, 1.0f),
      ColorF(0.55f, 0.65f, 0.80f, 1.0f),
      "page6ResetBar"
    );
  }

  void makePlaygroundBtn(
    Widget parent,
    string btnName,
    string caption,
    float width,
    ColorF bgCol,
    ColorF hoverBg,
    ColorF hoverBorder,
    string actionEvent
  ) {
    HoverAnimConfig cfg;
    cfg.hoverBg = hoverBg;
    cfg.pressBg = ColorF(
      hoverBg.r * 0.6f,
      hoverBg.g * 0.6f,
      hoverBg.b * 0.6f,
      1.0f
    );
    cfg.hoverBorder = hoverBorder;
    cfg.actionEvent = actionEvent;

    AnimatedHoverButtonBuilder b;
    b.name(btnName)
      .text(caption)
      .bg(bgCol)
      .border(hoverBorder, 1.0f)
      .fixedSize(width, 34.0f)
      .anim(cfg)
      .build(ui, parent, RectF(0, 0, width, 34));
  }

  void buildArchitectureSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(645, 360, 615, 284),
      "4. Scrollbar Architecture, Drag Capture & Event Pipeline",
      "sbArchCard"
    );

    auto archBox = WidgetBuilder.make(ui)
      .parent(card)
      .name("sbArchBox")
      .rect(RectF(16, 40, 583, 224))
      .roundBg(ColorF(0.09f, 0.11f, 0.14f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.20f, 0.23f, 0.28f, 1.0f))
      .borderWidth(1.0f)
      .build();

    WidgetBuilder.make(ui)
      .parent(archBox)
      .name("sbArchTitle")
      .rect(RectF(14, 12, 555, 22))
      .text("Composite Tree, InputSystem Drag & Model Synchronization:")
      .textColor(ColorF(0.45f, 0.80f, 1.0f, 1.0f))
      .fontSize(13.0f)
      .build();

    buildArchBody(archBox);
  }

  void buildArchBody(Widget archBox) {
    WidgetBuilder.make(ui)
      .parent(archBox)
      .name("sbArchBody")
      .rect(RectF(14, 40, 555, 172))
      .text(
        "1. Tree: Root Flex (View) -> DecBtn, Track (ScrollableArea), " ~
          "IncBtn;\n" ~
          "   Track holds Thumb (Anchor + MouseEvent.mouseDrag + " ~
          "captureCursor).\n" ~
          "2. Drag Capture: InputSystem tracks pressedWidgets across " ~
          "motion,\n" ~
          "   calling yguilib_sdl3_capture_mouse() while captureCursor " ~
          "is set.\n" ~
          "3. Sizing: Thumb ratio = visibleSize / ((max - min) + " ~
          "visibleSize),\n" ~
          "   clamped to >= minThumbSize (20px) and recalculated on " ~
          "resize.\n" ~
          "4. Controller: ScrollbarWidgetViewController translates " ~
          "clicks/drags\n" ~
          "   to ScrollbarModel updates and emits position change AppEvents."
      )
      .textColor(ColorF(0.75f, 0.80f, 0.88f, 1.0f))
      .fontSize(12.0f)
      .build();
  }

  UiSystem ui;
  ModelTracker!ScrollbarsPageModel tracker;
  Widget root;
  UiRegistry registry;

  ModelTracker!ScrollbarModel hScrollTracker;
  ModelTracker!ScrollbarModel vScrollTracker;
  ModelTracker!ScrollbarModel liveTracker;
  ModelTracker!ScrollbarModel releaseTracker;
  ModelTracker!ScrollbarModel playgroundTracker;

  Widget viewportArea;
  Widget viewportStatusLabel;
  Widget liveStatusLabel;
  Widget releaseStatusLabel;
  Widget playgroundScrollbar;
  Widget playgroundStatusLabel;
}
