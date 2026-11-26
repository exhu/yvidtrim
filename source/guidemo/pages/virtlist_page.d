/**
 * virtlist_page.d - Page 7 showcase for vertical (10,000-item) and horizontal
 * (1,200-item) heterogeneous VirtList composite controls.
 */
module guidemo.pages.virtlist_page;

import guidemo.common : makeSectionCard;
import yguilib.controls.hover_button_system : AnimatedHoverButtonBuilder,
  HoverAnimConfig;
import guidemo.model : VirtListPageModel;
import guidemo.pages.virtlist_items : HorizontalItemsModel,
  VerticalItemsModel;
import guidemo.pages.virtlist_providers : HorizontalStripProvider,
  VerticalMediaProvider;
import yguilib.controls.virtlist : VirtListBuilder, VirtListModel,
  VirtListWidgetView, virtListWidgetViewName;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.layout_components : AlignItems, FlexDirection,
  JustifyContent;
import yguilib.widget.virtlist_components : VirtListComponent;

/// View event names emitted by Page 7 VirtLists and action buttons.
enum page7VertChangedEvent = "page7VertChanged";
enum page7HorizChangedEvent = "page7HorizChanged";
enum page7ExpandRowEvent = "page7ExpandRow";
enum page7InsertAboveEvent = "page7InsertAbove";
enum page7InsertHereEvent = "page7InsertHere";
enum page7RemoveHereEvent = "page7RemoveHere";
enum page7ToggleCountEvent = "page7ToggleCount";
enum page7Jump5000Event = "page7Jump5000";
enum page7HorizResizeEvent = "page7HorizResize";
enum page7HorizInsertEvent = "page7HorizInsert";
enum page7HorizRemoveEvent = "page7HorizRemove";
enum page7HorizNarrowEvent = "page7HorizNarrow";
enum page7HorizWidenEvent = "page7HorizWiden";
enum page7HorizResetEvent = "page7HorizReset";

/// Initial vertical VirtList item count.
enum size_t vListDefaultCount = 10000;
/// Initial horizontal VirtList item count.
enum size_t hListDefaultCount = 1200;
/// Default (and maximum) horizontal VirtList viewport width in pixels.
enum float hViewportDefaultWidth = 583.0f;

/// Trackers shared between VirtListPage and VirtListPageController.
struct VirtListPageTrackers {
  ModelTracker!VirtListPageModel page;
  ModelTracker!VirtListModel vList;
  ModelTracker!VirtListModel hList;
  ModelTracker!VerticalItemsModel vItems;
  ModelTracker!HorizontalItemsModel hItems;

  /// Creates trackers with default models.
  static VirtListPageTrackers make() {
    VirtListPageTrackers t;
    t.page = ModelTracker!VirtListPageModel(new VirtListPageModel());
    t.vList = ModelTracker!VirtListModel(
      new VirtListModel(vListDefaultCount)
    );
    t.hList = ModelTracker!VirtListModel(
      new VirtListModel(hListDefaultCount)
    );
    auto vItems = new VerticalItemsModel();
    vItems.resetItems(vListDefaultCount);
    t.vItems = ModelTracker!VerticalItemsModel(vItems);
    auto hItems = new HorizontalItemsModel();
    hItems.resetItems(hListDefaultCount);
    t.hItems = ModelTracker!HorizontalItemsModel(hItems);
    return t;
  }

  /// Copies `other` with independent per-holder versions.
  static VirtListPageTrackers from(ref VirtListPageTrackers other) {
    VirtListPageTrackers t;
    t.page = ModelTracker!VirtListPageModel.from(other.page);
    t.vList = ModelTracker!VirtListModel.from(other.vList);
    t.hList = ModelTracker!VirtListModel.from(other.hList);
    t.vItems = ModelTracker!VerticalItemsModel.from(other.vItems);
    t.hItems = ModelTracker!HorizontalItemsModel.from(other.hItems);
    return t;
  }
}

/// Page 7 widget container showcasing vertical and horizontal VirtLists.
final class VirtListPage {
  @disable this();

  /// Constructs VirtListPage sharing models with `trackers`.
  this(UiSystem ui, Widget parent, ref VirtListPageTrackers trackers) {
    assert(ui !is null, "UiSystem must not be null");
    assert(parent !is null, "parent must not be null");
    this.ui = ui;
    tracker = ModelTracker!VirtListPageModel.from(trackers.page);
    vListTracker = ModelTracker!VirtListModel.from(trackers.vList);
    hListTracker = ModelTracker!VirtListModel.from(trackers.hList);
    root = new Widget(ui.nextWidgetId());
    root.name = "virtListPage";
    root.rect = RectF(0, 0, 1280, 720);
    parent.addChild(root);

    vProvider = new VerticalMediaProvider(ui, trackers.vItems);
    hProvider = new HorizontalStripProvider(ui, trackers.hItems);

    buildVerticalSection();
    buildHorizontalSection();
    syncTelemetry();
  }

  invariant {
    assert(root !is null);
    assert(vProvider !is null);
    assert(hProvider !is null);
  }

  /// Syncs widgets from the page model when it changed.
  void update() {
    if (!tracker.update()) {
      return;
    }
    applyHorizontalViewportWidth(tracker.model.hViewportWidth);
    updateTelemetryLabels();
  }

  /// Synchronizes live VirtList metrics and provider counters into page model.
  /// Returns true if the page model changed.
  bool syncTelemetry() {
    const auto vm = vListTracker.model;
    const auto hm = hListTracker.model;
    const VirtListComponent vComp = findVirtListComponent(vListRoot);
    const VirtListComponent hComp = findVirtListComponent(hListRoot);
    const size_t vAct = (vComp !is null) ? vComp.activeWidgetsCount : 0;
    const size_t vPool = (vComp !is null) ? vComp.pooledWidgetsCount : 0;
    const size_t hAct = (hComp !is null) ? hComp.activeWidgetsCount : 0;
    const size_t hPool = (hComp !is null) ? hComp.pooledWidgetsCount : 0;
    const size_t stops = vProvider.recycledStopCount();
    const size_t videos = vProvider.activeVideoCount();

    const auto cur = tracker.model;
    if (cur.vItemsCount == vm.itemsCount &&
        cur.vFirstVisible == vm.firstVisibleIndex &&
        cur.vVisibleCount == vm.visibleItemsCount &&
        cur.vActiveWidgets == vAct &&
        cur.vPooledWidgets == vPool &&
        cur.hItemsCount == hm.itemsCount &&
        cur.hFirstVisible == hm.firstVisibleIndex &&
        cur.hVisibleCount == hm.visibleItemsCount &&
        cur.hActiveWidgets == hAct &&
        cur.hPooledWidgets == hPool &&
        cur.recycledStopsCount == stops &&
        cur.activeVideosCount == videos) {
      return false;
    }

    auto ed = tracker.edit();
    ed.vItemsCount = vm.itemsCount;
    ed.vFirstVisible = vm.firstVisibleIndex;
    ed.vVisibleCount = vm.visibleItemsCount;
    ed.vActiveWidgets = vAct;
    ed.vPooledWidgets = vPool;
    ed.hItemsCount = hm.itemsCount;
    ed.hFirstVisible = hm.firstVisibleIndex;
    ed.hVisibleCount = hm.visibleItemsCount;
    ed.hActiveWidgets = hAct;
    ed.hPooledWidgets = hPool;
    ed.recycledStopsCount = stops;
    ed.activeVideosCount = videos;
    tracker.commit(ed);
    return true;
  }

  /// Returns the status bar text for this page.
  string formatStatus() {
    import std.format : format;

    const auto m = tracker.model;
    return format(
      "Vert: %d (vis %d) | Horiz: %d (vis %d) | Videos: %d | Stops: %d",
      m.vItemsCount,
      m.vFirstVisible,
      m.hItemsCount,
      m.hFirstVisible,
      m.activeVideosCount,
      m.recycledStopsCount
    );
  }

  /// Returns whether any vertical video row is animating.
  bool hasActiveVideos() const {
    return vProvider.activeVideoCount() > 0;
  }

  /// Advances video row animations by `dt`; returns true if changed.
  bool tickAnimations(float dt) {
    return vProvider.tickAnimations(dt);
  }

  /// Returns the page root widget.
  Widget rootWidget() {
    return root;
  }

  /// Returns the vertical VirtList root widget.
  Widget verticalListRoot() {
    return vListRoot;
  }

  /// Returns the horizontal VirtList root widget.
  Widget horizontalListRoot() {
    return hListRoot;
  }

  /// Shows or hides the page.
  void visible(bool visible) {
    if (root.visible != visible) {
      root.visible = visible;
      root.update(WidgetUpdateScope.layout);
    }
  }

  /// Returns whether the page is visible.
  bool visible() const {
    return root.visible;
  }

private:
  static void updateCaption(Widget w, string text) {
    if (w !is null && w.components.textLabel !is null &&
        w.components.textLabel.caption != text) {
      w.components.textLabel.caption = text;
      w.update(WidgetUpdateScope.content);
    }
  }

  void applyHorizontalViewportWidth(float width) {
    if (hListRoot is null || hListRoot.rect.width == width) {
      return;
    }
    hListRoot.rect.width = width;
    hListRoot.update(WidgetUpdateScope.layout);
  }

  void updateTelemetryLabels() {
    import std.format : format;

    const auto m = tracker.model;
    updateCaption(
      vTelemetryLabel,
      format(
        "Items: %d | FirstVis: %d | VisCount: %d | Active: %d | " ~
          "Pooled: %d\n" ~
          "ActiveVideos: %d | AnimsStopped: %d | Expand Row -> 700x400px",
        m.vItemsCount,
        m.vFirstVisible,
        m.vVisibleCount,
        m.vActiveWidgets,
        m.vPooledWidgets,
        m.activeVideosCount,
        m.recycledStopsCount
      )
    );
    const float hw = m.hViewportWidth;
    updateCaption(
      hTelemetryLabel,
      format(
        "Items: %d | FirstVis: %d | VisCount: %d | Active: %d | " ~
          "Pooled: %d\n" ~
          "ViewportWidth: %.0fpx | Resize Item / - Narrow tests overflow",
        m.hItemsCount,
        m.hFirstVisible,
        m.hVisibleCount,
        m.hActiveWidgets,
        m.hPooledWidgets,
        hw
      )
    );
  }

  VirtListComponent findVirtListComponent(Widget listRoot) {
    if (listRoot is null) {
      return null;
    }
    if (auto wv = ui.widgetViews.findByName(virtListWidgetViewName)) {
      if (auto vlv = cast(VirtListWidgetView) wv) {
        Widget vp = vlv.viewport(listRoot);
        if (vp !is null) {
          return vp.components.virtList;
        }
      }
    }
    if (listRoot.children.length > 0 &&
        listRoot.children[0].children.length > 0) {
      return listRoot.children[0].children[0].components.virtList;
    }
    return null;
  }

  void buildVerticalSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(20, 68, 605, 576),
      "1. Vertical Media & File Browser (10,000 Heterogeneous Items)",
      "vListCard"
    );

    WidgetBuilder.make(ui)
      .parent(card)
      .name("vListDesc")
      .rect(RectF(16, 34, 573, 18))
      .text(
        "Single template switching 4 subtrees; oversized rows & live pulse."
      )
      .textColor(ColorF(0.70f, 0.76f, 0.86f, 1.0f))
      .fontSize(12.0f)
      .build();

    buildVerticalButtons(card);

    VirtListBuilder vb;
    vListRoot = vb
      .name("verticalMediaVirtList")
      .modelTracker(vListTracker)
      .provider(vProvider)
      .event(page7VertChangedEvent)
      .direction(FlexDirection.column)
      .gap(6.0f)
      .defaultItemSize(56.0f)
      .stretchCrossAxis(false)
      .build(ui, card, RectF(16, 100, 573, 404), ui);

    buildVerticalTelemetryBox(card);
  }

  void buildVerticalButtons(Widget card) {
    auto row = WidgetBuilder.make(ui)
      .parent(card)
      .name("vListBtnRow")
      .rect(RectF(16, 58, 573, 36))
      .flexRow()
      .gap(6.0f)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.center)
      .build();

    makeActionBtn(
      row, "vExpandRowBtn", "Expand Row", 92.0f,
      ColorF(0.16f, 0.22f, 0.30f, 1.0f),
      ColorF(0.28f, 0.48f, 0.78f, 1.0f), page7ExpandRowEvent
    );
    makeActionBtn(
      row, "vInsertAboveBtn", "+ Ins Above", 94.0f,
      ColorF(0.12f, 0.24f, 0.18f, 1.0f),
      ColorF(0.20f, 0.56f, 0.36f, 1.0f), page7InsertAboveEvent
    );
    makeActionBtn(
      row, "vInsertHereBtn", "+ Ins Here", 88.0f,
      ColorF(0.14f, 0.24f, 0.22f, 1.0f),
      ColorF(0.22f, 0.58f, 0.50f, 1.0f), page7InsertHereEvent
    );
    makeActionBtn(
      row, "vRemoveHereBtn", "- Rem Here", 90.0f,
      ColorF(0.26f, 0.13f, 0.15f, 1.0f),
      ColorF(0.66f, 0.22f, 0.26f, 1.0f), page7RemoveHereEvent
    );
    makeActionBtn(
      row, "vToggleCountBtn", "10K / 50", 78.0f,
      ColorF(0.22f, 0.18f, 0.12f, 1.0f),
      ColorF(0.58f, 0.42f, 0.18f, 1.0f), page7ToggleCountEvent
    );
    makeActionBtn(
      row, "vJump5000Btn", "Jump 5000", 96.0f,
      ColorF(0.20f, 0.16f, 0.28f, 1.0f),
      ColorF(0.40f, 0.32f, 0.68f, 1.0f), page7Jump5000Event
    );
  }

  void buildVerticalTelemetryBox(Widget card) {
    auto box = WidgetBuilder.make(ui)
      .parent(card)
      .name("vTelemetryBox")
      .rect(RectF(16, 512, 573, 50))
      .roundBg(ColorF(0.09f, 0.11f, 0.14f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.20f, 0.24f, 0.30f, 1.0f))
      .borderWidth(1.0f)
      .build();

    vTelemetryLabel = WidgetBuilder.make(ui)
      .parent(box)
      .name("vTelemetryLabel")
      .rect(RectF(10, 6, 553, 38))
      .text("Items: 10000 | FirstVis: 0 | VisCount: 0 | Active: 0 | Pooled: 0")
      .textColor(ColorF(0.45f, 0.92f, 0.68f, 1.0f))
      .fontSize(12.0f)
      .multiline(true)
      .build();
  }

  void buildHorizontalSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(645, 68, 615, 576),
      "2. Horizontal Filmstrip & Timeline (1,200 Variable Clips)",
      "hListCard"
    );

    WidgetBuilder.make(ui)
      .parent(card)
      .name("hListDesc")
      .rect(RectF(16, 34, 583, 18))
      .text(
        "Single template switching keyframe, GOP segment & marker cards."
      )
      .textColor(ColorF(0.70f, 0.76f, 0.86f, 1.0f))
      .fontSize(12.0f)
      .build();

    buildHorizontalButtons(card);

    VirtListBuilder hb;
    hListRoot = hb
      .name("horizontalStripVirtList")
      .modelTracker(hListTracker)
      .provider(hProvider)
      .event(page7HorizChangedEvent)
      .direction(FlexDirection.row)
      .gap(8.0f)
      .defaultItemSize(140.0f)
      .stretchCrossAxis(false)
      .build(
        ui, card, RectF(16, 100, hViewportDefaultWidth, 244), ui
      );

    buildHorizontalTelemetryBox(card);
    buildArchitectureNotesBox(card);
  }

  void buildHorizontalButtons(Widget card) {
    auto row = WidgetBuilder.make(ui)
      .parent(card)
      .name("hListBtnRow")
      .rect(RectF(16, 58, 583, 36))
      .flexRow()
      .gap(6.0f)
      .justify(JustifyContent.start)
      .alignItems(AlignItems.center)
      .build();

    makeActionBtn(
      row, "hResizeItemBtn", "Resize Item", 98.0f,
      ColorF(0.16f, 0.22f, 0.30f, 1.0f),
      ColorF(0.28f, 0.48f, 0.78f, 1.0f), page7HorizResizeEvent
    );
    makeActionBtn(
      row, "hInsertClipBtn", "+ Ins Clip", 86.0f,
      ColorF(0.12f, 0.24f, 0.18f, 1.0f),
      ColorF(0.20f, 0.56f, 0.36f, 1.0f), page7HorizInsertEvent
    );
    makeActionBtn(
      row, "hRemoveClipBtn", "- Rem Clip", 88.0f,
      ColorF(0.26f, 0.13f, 0.15f, 1.0f),
      ColorF(0.66f, 0.22f, 0.26f, 1.0f), page7HorizRemoveEvent
    );
    makeActionBtn(
      row, "hNarrowBtn", "- Narrow", 84.0f,
      ColorF(0.24f, 0.18f, 0.10f, 1.0f),
      ColorF(0.55f, 0.40f, 0.18f, 1.0f), page7HorizNarrowEvent
    );
    makeActionBtn(
      row, "hWidenBtn", "+ Widen", 84.0f,
      ColorF(0.18f, 0.14f, 0.26f, 1.0f),
      ColorF(0.35f, 0.30f, 0.55f, 1.0f), page7HorizWidenEvent
    );
    makeActionBtn(
      row, "hResetBtn", "Reset", 72.0f,
      ColorF(0.18f, 0.20f, 0.25f, 1.0f),
      ColorF(0.34f, 0.40f, 0.52f, 1.0f), page7HorizResetEvent
    );
  }

  void buildHorizontalTelemetryBox(Widget card) {
    auto box = WidgetBuilder.make(ui)
      .parent(card)
      .name("hTelemetryBox")
      .rect(RectF(16, 352, 583, 50))
      .roundBg(ColorF(0.09f, 0.11f, 0.14f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.20f, 0.24f, 0.30f, 1.0f))
      .borderWidth(1.0f)
      .build();

    hTelemetryLabel = WidgetBuilder.make(ui)
      .parent(box)
      .name("hTelemetryLabel")
      .rect(RectF(10, 6, 563, 38))
      .text("Items: 1200 | FirstVis: 0 | VisCount: 0 | Active: 0 | Pooled: 0")
      .textColor(ColorF(0.95f, 0.86f, 0.42f, 1.0f))
      .fontSize(12.0f)
      .multiline(true)
      .build();
  }

  void buildArchitectureNotesBox(Widget card) {
    auto box = WidgetBuilder.make(ui)
      .parent(card)
      .name("virtListNotesBox")
      .rect(RectF(16, 412, 583, 150))
      .roundBg(ColorF(0.09f, 0.11f, 0.14f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.20f, 0.23f, 0.28f, 1.0f))
      .borderWidth(1.0f)
      .build();

    WidgetBuilder.make(ui)
      .parent(box)
      .name("virtListNotesTitle")
      .rect(RectF(12, 10, 559, 20))
      .text("VirtList Recycling, Subtree Switching & Oversized Item Flow:")
      .textColor(ColorF(0.45f, 0.80f, 1.0f, 1.0f))
      .fontSize(13.0f)
      .build();

    WidgetBuilder.make(ui)
      .parent(box)
      .name("virtListNotesBody")
      .rect(RectF(12, 34, 559, 108))
      .text(
        "- Single reusable widget template per VirtListProvider; " ~
          "updateWidgetAt()\n" ~
          "  toggles child subtree visibility (header / video / image / " ~
          "file).\n" ~
          "- onWidgetRecycled(w) stops video pulse timers & increments " ~
          "AnimsStopped.\n" ~
          "- + Ins Above shifts anchor index so visible rows stay locked in " ~
          "place.\n" ~
          "- Oversized items (> viewport width & height) drive both " ~
          "scrollbars."
      )
      .textColor(ColorF(0.75f, 0.80f, 0.88f, 1.0f))
      .fontSize(12.0f)
      .multiline(true)
      .build();
  }

  void makeActionBtn(
    Widget parent,
    string btnName,
    string caption,
    float width,
    ColorF bgCol,
    ColorF hoverBg,
    string actionEvent
  ) {
    HoverAnimConfig cfg;
    cfg.hoverBg = hoverBg;
    cfg.pressBg = ColorF(
      hoverBg.r * 0.6f, hoverBg.g * 0.6f, hoverBg.b * 0.6f, 1.0f
    );
    cfg.hoverBorder = ColorF(
      hoverBg.r + 0.18f, hoverBg.g + 0.18f, hoverBg.b + 0.18f, 1.0f
    );
    cfg.actionEvent = actionEvent;

    AnimatedHoverButtonBuilder b;
    b.name(btnName)
      .text(caption)
      .bg(bgCol)
      .border(cfg.hoverBorder, 1.0f)
      .fixedSize(width, 32.0f)
      .anim(cfg)
      .build(ui, parent, RectF(0, 0, width, 32));
  }

  UiSystem ui;
  Widget root;
  ModelTracker!VirtListPageModel tracker;
  ModelTracker!VirtListModel vListTracker;
  ModelTracker!VirtListModel hListTracker;
  VerticalMediaProvider vProvider;
  HorizontalStripProvider hProvider;
  Widget vListRoot;
  Widget hListRoot;
  Widget vTelemetryLabel;
  Widget hTelemetryLabel;
}
