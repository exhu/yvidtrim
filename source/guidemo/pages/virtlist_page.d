/**
 * virtlist_page.d - Page 7 showcase for vertical (10,000-item) and horizontal
 * (1,200-item) heterogeneous VirtList composite controls.
 */
module guidemo.pages.virtlist_page;

import guidemo.common : makeSectionCard;
import yguilib.controls.hover_button_system : AnimatedHoverButtonBuilder,
  HoverAnimConfig;
import guidemo.model : VirtListPageModel;
import yguilib.controls.virtlist : VirtListBuilder, VirtListModel,
  VirtListWidgetView, virtListWidgetViewName;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiRegistry, UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.layout_components : AlignItems, Dimension, FlexDirection,
  JustifyContent, SizingMode;
import yguilib.widget.virtlist_components : VirtListComponent, VirtListProvider;

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

/// Row kinds rendered by the single reusable template in VerticalMediaProvider.
enum VerticalItemKind : ubyte {
  header,
  video,
  image,
  file,
}

/// Logical metadata for one item in the vertical media & file browser list.
struct VerticalItemData {
  VerticalItemKind kind;
  bool expanded = false;
  uint itemId = 0;
}

/// Card kinds rendered by HorizontalStripProvider.
enum HorizontalItemKind : ubyte {
  keyframe,
  segment,
  marker,
}

/// Logical metadata for one item in the horizontal filmstrip list.
struct HorizontalItemData {
  HorizontalItemKind kind;
  bool resized = false;
  uint itemId = 0;
}

/// Page 7 widget container showcasing vertical and horizontal VirtLists.
final class VirtListPage {
  /// Constructs VirtListPage. `registry` is allowed to be null in headless
  /// tests.
  this(UiSystem ui, Widget parent, UiRegistry registry) {
    assert(ui !is null, "UiSystem must not be null");
    assert(parent !is null, "parent must not be null");
    this.ui = ui;
    this.registry = (registry !is null) ? registry : ui;
    tracker = ModelTracker!VirtListPageModel(new VirtListPageModel());
    root = new Widget(ui.nextWidgetId());
    root.name = "virtListPage";
    root.rect = RectF(0, 0, 1280, 720);
    parent.addChild(root);

    vListTracker = ModelTracker!VirtListModel(new VirtListModel(10000));
    hListTracker = ModelTracker!VirtListModel(new VirtListModel(1200));
    vProvider = new VerticalMediaProvider(ui);
    hProvider = new HorizontalStripProvider(ui);

    buildVerticalSection();
    buildHorizontalSection();
    syncTelemetry();
  }

  invariant {
    assert(root !is null);
    assert(vProvider !is null);
    assert(hProvider !is null);
  }

  ref ModelTracker!VirtListPageModel getTracker() return {
    return tracker;
  }

  void update() {
    if (!tracker.update()) {
      return;
    }
    updateTelemetryLabels();
  }

  /// Synchronizes live VirtList metrics and provider counters into page model.
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

  bool hasActiveVideos() const {
    return vProvider.activeVideoCount() > 0;
  }

  bool tickAnimations(float dt) {
    return vProvider.tickAnimations(dt);
  }

  /// Toggles expanded/oversized dimensions on a visible vertical row.
  void expandVisibleRow() {
    const auto vm = vListTracker.model;
    const size_t targetIdx = vProvider.toggleExpandNear(
      vm.firstVisibleIndex, vm.visibleItemsCount
    );
    if (targetIdx == size_t.max) {
      return;
    }
    auto m = vListTracker.edit();
    m.updateItem(targetIdx);
    vListTracker.commit(m);
  }

  /// Inserts a new video row at index 0 to test anchor stability above view.
  void insertAboveViewport() {
    vProvider.insertItemAt(0);
    auto m = vListTracker.edit();
    m.insertItems(0, 1);
    vListTracker.commit(m);
  }

  /// Inserts a new video row at the current first visible index.
  void insertAtCurrent() {
    const size_t idx = vListTracker.model.firstVisibleIndex;
    vProvider.insertItemAt(idx);
    auto m = vListTracker.edit();
    m.insertItems(idx, 1);
    vListTracker.commit(m);
  }

  /// Removes the item at the current first visible index.
  void removeAtCurrent() {
    const auto vm = vListTracker.model;
    if (vm.itemsCount == 0) {
      return;
    }
    const size_t idx = vm.firstVisibleIndex < vm.itemsCount
      ? vm.firstVisibleIndex
      : vm.itemsCount - 1;
    vProvider.removeItemAt(idx);
    auto m = vListTracker.edit();
    m.removeItems(idx, 1);
    vListTracker.commit(m);
  }

  /// Toggles vertical dataset size between 10,000 and 50 items.
  void toggleVerticalCount() {
    const size_t target = (vListTracker.model.itemsCount > 50) ? 50 : 10000;
    vProvider.resetItems(target);
    auto m = vListTracker.edit();
    m.itemsCount = target;
    m.requestScrollToIndex(0);
    vListTracker.commit(m);
  }

  /// Jumps the vertical list directly to index 5000 (or last item).
  void jumpToMiddle() {
    const size_t count = vListTracker.model.itemsCount;
    if (count == 0) {
      return;
    }
    const size_t target = (count > 5000) ? 5000 : (count / 2);
    auto m = vListTracker.edit();
    m.requestScrollToIndex(target);
    vListTracker.commit(m);
  }

  /// Toggles resized/oversized dimensions on a visible horizontal clip card.
  void resizeHorizontalItem() {
    const auto hm = hListTracker.model;
    const size_t targetIdx = hProvider.toggleResizeNear(
      hm.firstVisibleIndex, hm.visibleItemsCount
    );
    if (targetIdx == size_t.max) {
      return;
    }
    auto m = hListTracker.edit();
    m.updateItem(targetIdx);
    hListTracker.commit(m);
  }

  /// Inserts a wide GOP segment card at the first visible horizontal index.
  void insertHorizontalClip() {
    const size_t idx = hListTracker.model.firstVisibleIndex;
    hProvider.insertItemAt(idx);
    auto m = hListTracker.edit();
    m.insertItems(idx, 1);
    hListTracker.commit(m);
  }

  /// Removes the card at the first visible horizontal index.
  void removeHorizontalClip() {
    const auto hm = hListTracker.model;
    if (hm.itemsCount == 0) {
      return;
    }
    const size_t idx = hm.firstVisibleIndex < hm.itemsCount
      ? hm.firstVisibleIndex
      : hm.itemsCount - 1;
    hProvider.removeItemAt(idx);
    auto m = hListTracker.edit();
    m.removeItems(idx, 1);
    hListTracker.commit(m);
  }

  /// Narrows the horizontal VirtList container down to 300px.
  float narrowHorizontalViewport() {
    if (hListRoot !is null) {
      float curW = hListRoot.rect.width;
      if (curW > 300.0f) {
        curW -= 70.0f;
        if (curW < 300.0f) {
          curW = 300.0f;
        }
        hListRoot.rect.width = curW;
        hListRoot.update(WidgetUpdateScope.layout);
      }
      return curW;
    }
    return 583.0f;
  }

  /// Widens the horizontal VirtList container back toward 583px.
  float widenHorizontalViewport() {
    if (hListRoot !is null) {
      float curW = hListRoot.rect.width;
      if (curW < 583.0f) {
        curW += 70.0f;
        if (curW > 583.0f) {
          curW = 583.0f;
        }
        hListRoot.rect.width = curW;
        hListRoot.update(WidgetUpdateScope.layout);
      }
      return curW;
    }
    return 583.0f;
  }

  /// Resets horizontal filmstrip items and viewport width.
  void resetHorizontalList() {
    hProvider.resetItems(1200);
    auto m = hListTracker.edit();
    m.itemsCount = 1200;
    m.updateItems(0, 1200);
    m.requestScrollToIndex(0);
    hListTracker.commit(m);
    if (hListRoot !is null) {
      hListRoot.rect.width = 583.0f;
      hListRoot.update(WidgetUpdateScope.layout);
    }
  }

  Widget getRootWidget() {
    return root;
  }

  Widget getVerticalListRoot() {
    return vListRoot;
  }

  Widget getHorizontalListRoot() {
    return hListRoot;
  }

  void setVisible(bool visible) {
    root.setVisible(visible);
  }

  bool isVisible() const {
    return root.visible;
  }

private:
  void updateTelemetryLabels() {
    import std.format : format;

    const auto m = tracker.model;
    if (vTelemetryLabel !is null) {
      vTelemetryLabel.setCaption(
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
    }
    if (hTelemetryLabel !is null) {
      const float hw = (hListRoot !is null) ? hListRoot.rect.width : 583.0f;
      hTelemetryLabel.setCaption(
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
  }

  VirtListComponent findVirtListComponent(Widget listRoot) {
    if (listRoot is null) {
      return null;
    }
    if (registry !is null) {
      if (auto wv = registry.widgetViews.getByName(virtListWidgetViewName)) {
        if (auto vlv = cast(VirtListWidgetView) wv) {
          Widget vp = vlv.getViewport(listRoot);
          if (vp !is null) {
            return vp.components.virtList;
          }
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
      .build(ui, card, RectF(16, 100, 573, 404), registry);

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
      .build(ui, card, RectF(16, 100, 583, 244), registry);

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
  UiRegistry registry;
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

/**
 * Single-template heterogeneous provider for the vertical 10,000-item media
 * and file browser VirtList.
 */
final class VerticalMediaProvider : VirtListProvider {
  @disable this();

  this(UiSystem ui) {
    assert(ui !is null, "UiSystem must not be null");
    this.ui = ui;
    resetItems(10000);
  }

  invariant {
    assert(ui !is null);
  }

  /// Creates one reusable row widget tree containing 4 internal subtrees.
  /// `parent` is allowed to be null in isolated tests.
  override Widget createWidget(Widget parent) {
    auto row = WidgetBuilder.make(ui)
      .parent(parent)
      .name("vMediaRowTemplate")
      .rect(RectF(0, 0, 530, 56))
      .fixedSize(530, 56)
      .flexColumn()
      .clipContents(true)
      .clipChildren(true)
      .build();

    auto refs = new VerticalRowRefs();
    buildHeaderSubtree(row, refs);
    buildVideoSubtree(row, refs);
    buildImageSubtree(row, refs);
    buildFileSubtree(row, refs);
    rowRefs[row] = refs;
    return row;
  }

  override void updateWidgetAt(Widget w, size_t index) {
    if (w is null || index >= items.length) {
      return;
    }
    auto pRefs = w in rowRefs;
    if (pRefs is null) {
      return;
    }
    VerticalRowRefs refs = *pRefs;
    const VerticalItemData item = items[index];

    float wPx = 530.0f;
    float hPx = 38.0f;
    computeItemDimensions(item, wPx, hPx);
    applyRowDimensions(w, wPx, hPx);

    refs.headerSubtree.setVisible(item.kind == VerticalItemKind.header);
    refs.videoSubtree.setVisible(item.kind == VerticalItemKind.video);
    refs.imageSubtree.setVisible(item.kind == VerticalItemKind.image);
    refs.fileSubtree.setVisible(item.kind == VerticalItemKind.file);

    final switch (item.kind) {
    case VerticalItemKind.header:
      activeVideos.remove(w);
      bindHeaderSubtree(refs, item, index, wPx, hPx);
      break;
    case VerticalItemKind.video:
      bindVideoSubtree(w, refs, item, index, wPx, hPx);
      break;
    case VerticalItemKind.image:
      activeVideos.remove(w);
      bindImageSubtree(refs, item, index, wPx, hPx);
      break;
    case VerticalItemKind.file:
      activeVideos.remove(w);
      bindFileSubtree(refs, item, index, wPx, hPx);
      break;
    }
    w.update(WidgetUpdateScope.layout);
  }

  override void onWidgetRecycled(Widget w) {
    if (w is null) {
      return;
    }
    if (w in activeVideos) {
      activeVideos.remove(w);
      recycledStops += 1;
    }
  }

  /// Advances active video clip pulse/progress bars; returns true if animated.
  bool tickAnimations(float dt) {
    import std.math : abs;
    import std.math.remainder : fmod;

    if (activeVideos.length == 0 || dt <= 0.0f) {
      return false;
    }
    foreach (w, ref st; activeVideos) {
      st.phase = fmod(st.phase + dt * 0.45f, 1.0f);
      auto pRefs = w in rowRefs;
      if (pRefs is null) {
        continue;
      }
      VerticalRowRefs refs = *pRefs;
      const float pulse = 1.0f - abs(st.phase * 2.0f - 1.0f);
      if (refs.videoPulseBadge !is null &&
          refs.videoPulseBadge.components.background !is null) {
        refs.videoPulseBadge.components.background.color = ColorF(
          0.20f + 0.70f * pulse, 0.65f + 0.30f * pulse, 0.35f, 1.0f
        );
        refs.videoPulseBadge.update(WidgetUpdateScope.visuals);
      }
      if (refs.videoProgressFill !is null) {
        const float fillW = (st.trackWidth > 12.0f)
          ? (4.0f + (st.trackWidth - 4.0f) * st.phase)
          : 4.0f;
        refs.videoProgressFill.rect.width = fillW;
        refs.videoProgressFill.update(WidgetUpdateScope.layout);
      }
    }
    return true;
  }

  size_t activeVideoCount() const {
    return activeVideos.length;
  }

  size_t recycledStopCount() const {
    return recycledStops;
  }

  size_t itemsLength() const {
    return items.length;
  }

  /// Toggles expanded state on an expanded visible item, or first visible
  /// video row, or `firstVis`. Returns the modified index or `size_t.max`.
  size_t toggleExpandNear(size_t firstVis, size_t visCount) {
    if (items.length == 0) {
      return size_t.max;
    }
    const size_t start = (firstVis < items.length)
      ? firstVis
      : items.length - 1;
    const size_t end = (start + visCount <= items.length)
      ? (start + visCount)
      : items.length;
    foreach (i; start .. end) {
      if (items[i].expanded) {
        items[i].expanded = false;
        return i;
      }
    }
    foreach (i; start .. end) {
      if (items[i].kind == VerticalItemKind.video) {
        items[i].expanded = true;
        return i;
      }
    }
    items[start].expanded = !items[start].expanded;
    return start;
  }

  void insertItemAt(size_t idx) {
    import std.algorithm.comparison : min;
    const size_t clamped = min(idx, items.length);
    const auto inserted = VerticalItemData(
      VerticalItemKind.video, false, nextItemId++
    );
    items = items[0 .. clamped] ~ inserted ~ items[clamped .. $];
  }

  void removeItemAt(size_t idx) {
    if (idx >= items.length) {
      return;
    }
    items = items[0 .. idx] ~ items[idx + 1 .. $];
  }

  void resetItems(size_t count) {
    activeVideos.clear();
    items.length = count;
    foreach (i; 0 .. count) {
      items[i] = VerticalItemData(kindForIndex(i), false, cast(uint) i);
    }
    nextItemId = cast(uint) count;
  }

private:
  static VerticalItemKind kindForIndex(size_t idx) {
    if (idx % 12 == 0) {
      return VerticalItemKind.header;
    }
    if (idx % 4 == 1) {
      return VerticalItemKind.video;
    }
    if (idx % 4 == 2) {
      return VerticalItemKind.image;
    }
    return VerticalItemKind.file;
  }

  static void computeItemDimensions(
    in VerticalItemData item,
    out float wPx,
    out float hPx
  ) {
    final switch (item.kind) {
    case VerticalItemKind.header:
      wPx = item.expanded ? 640.0f : 530.0f;
      hPx = item.expanded ? 76.0f : 34.0f;
      break;
    case VerticalItemKind.video:
      wPx = item.expanded ? 700.0f : 530.0f;
      hPx = item.expanded ? 400.0f : 74.0f;
      break;
    case VerticalItemKind.image:
      if (item.expanded) {
        wPx = 700.0f;
        hPx = 220.0f;
      } else if (item.itemId % 24 == 10) {
        wPx = 680.0f;
        hPx = 380.0f;
      } else {
        wPx = (item.itemId % 8 == 2) ? 650.0f : 530.0f;
        hPx = 84.0f;
      }
      break;
    case VerticalItemKind.file:
      wPx = item.expanded ? 640.0f : 530.0f;
      hPx = item.expanded ? 110.0f : 38.0f;
      break;
    }
  }

  static void applyRowDimensions(Widget w, float wPx, float hPx) {
    w.rect.width = wPx;
    w.rect.height = hPx;
    if (w.components.size !is null) {
      w.components.size.width = Dimension(wPx, SizingMode.fixed);
      w.components.size.height = Dimension(hPx, SizingMode.fixed);
    }
  }

  void buildHeaderSubtree(Widget row, VerticalRowRefs refs) {
    refs.headerSubtree = WidgetBuilder.make(ui)
      .parent(row)
      .name("vHeaderSubtree")
      .rect(RectF(0, 0, 530, 34))
      .fixedSize(530, 34)
      .paddingVh(6, 12)
      .flexRow()
      .gap(8.0f)
      .justify(JustifyContent.spaceBetween)
      .alignItems(AlignItems.center)
      .roundBg(ColorF(0.16f, 0.21f, 0.30f, 1.0f))
      .bgRadius(4.0f)
      .border(ColorF(0.32f, 0.44f, 0.64f, 1.0f))
      .borderWidth(1.0f)
      .build();

    refs.headerTitleLabel = WidgetBuilder.make(ui)
      .parent(refs.headerSubtree)
      .name("vHeaderTitle")
      .rect(RectF(0, 0, 360, 20))
      .fixedSize(360, 20)
      .text("Section")
      .textColor(ColorF(0.92f, 0.96f, 1.0f, 1.0f))
      .fontSize(13.0f)
      .build();

    refs.headerCountLabel = WidgetBuilder.make(ui)
      .parent(refs.headerSubtree)
      .name("vHeaderCount")
      .rect(RectF(0, 0, 120, 18))
      .fixedSize(120, 18)
      .text("12 items")
      .textColor(ColorF(0.68f, 0.80f, 0.96f, 1.0f))
      .fontSize(11.0f)
      .build();
  }

  void buildVideoSubtree(Widget row, VerticalRowRefs refs) {
    refs.videoSubtree = WidgetBuilder.make(ui)
      .parent(row)
      .name("vVideoSubtree")
      .rect(RectF(0, 0, 530, 74))
      .fixedSize(530, 74)
      .paddingVh(8, 12)
      .flexColumn()
      .gap(6.0f)
      .roundBg(ColorF(0.12f, 0.18f, 0.22f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.24f, 0.56f, 0.50f, 1.0f))
      .borderWidth(1.0f)
      .build();

    buildVideoHeaderRow(refs);
    buildVideoProgressBar(refs);
  }

  void buildVideoHeaderRow(VerticalRowRefs refs) {
    auto top = WidgetBuilder.make(ui)
      .parent(refs.videoSubtree)
      .name("vVideoTopRow")
      .rect(RectF(0, 0, 506, 22))
      .fixedSize(506, 22)
      .flexRow()
      .gap(8.0f)
      .alignItems(AlignItems.center)
      .build();

    refs.videoPulseBadge = WidgetBuilder.make(ui)
      .parent(top)
      .name("vVideoPulseBadge")
      .rect(RectF(0, 0, 14, 14))
      .fixedSize(14, 14)
      .roundBg(ColorF(0.25f, 0.85f, 0.45f, 1.0f))
      .bgRadius(7.0f)
      .build();

    refs.videoTitleLabel = WidgetBuilder.make(ui)
      .parent(top)
      .name("vVideoTitle")
      .rect(RectF(0, 0, 470, 20))
      .fixedSize(470, 20)
      .text("Video Clip")
      .textColor(ColorF(0.95f, 0.98f, 1.0f, 1.0f))
      .fontSize(13.0f)
      .build();
  }

  void buildVideoProgressBar(VerticalRowRefs refs) {
    refs.videoMetaLabel = WidgetBuilder.make(ui)
      .parent(refs.videoSubtree)
      .name("vVideoMeta")
      .rect(RectF(0, 0, 506, 18))
      .fixedSize(506, 18)
      .text("H.264 1920x1080")
      .textColor(ColorF(0.72f, 0.84f, 0.86f, 1.0f))
      .fontSize(11.0f)
      .build();

    refs.videoProgressTrack = WidgetBuilder.make(ui)
      .parent(refs.videoSubtree)
      .name("vVideoProgressTrack")
      .rect(RectF(0, 0, 506, 10))
      .fixedSize(506, 10)
      .roundBg(ColorF(0.08f, 0.10f, 0.12f, 1.0f))
      .bgRadius(4.0f)
      .build();

    refs.videoProgressFill = WidgetBuilder.make(ui)
      .parent(refs.videoProgressTrack)
      .name("vVideoProgressFill")
      .rect(RectF(2, 2, 120, 6))
      .roundBg(ColorF(0.28f, 0.80f, 0.60f, 1.0f))
      .bgRadius(3.0f)
      .build();
  }

  void buildImageSubtree(Widget row, VerticalRowRefs refs) {
    refs.imageSubtree = WidgetBuilder.make(ui)
      .parent(row)
      .name("vImageSubtree")
      .rect(RectF(0, 0, 530, 84))
      .fixedSize(530, 84)
      .paddingVh(8, 10)
      .flexRow()
      .gap(10.0f)
      .alignItems(AlignItems.center)
      .roundBg(ColorF(0.17f, 0.14f, 0.22f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.50f, 0.36f, 0.68f, 1.0f))
      .borderWidth(1.0f)
      .build();

    refs.imageThumbBox = WidgetBuilder.make(ui)
      .parent(refs.imageSubtree)
      .name("vImageThumb")
      .rect(RectF(0, 0, 88, 64))
      .fixedSize(88, 64)
      .roundBg(ColorF(0.32f, 0.24f, 0.46f, 1.0f))
      .bgRadius(4.0f)
      .border(ColorF(0.65f, 0.50f, 0.85f, 1.0f))
      .borderWidth(1.0f)
      .text("IMG")
      .textColor(ColorF(0.95f, 0.90f, 1.0f, 1.0f))
      .fontSize(12.0f)
      .build();

    buildImageTextColumn(refs);
  }

  void buildImageTextColumn(VerticalRowRefs refs) {
    auto col = WidgetBuilder.make(ui)
      .parent(refs.imageSubtree)
      .name("vImageTextCol")
      .rect(RectF(0, 0, 410, 64))
      .fixedSize(410, 64)
      .flexColumn()
      .gap(6.0f)
      .build();

    refs.imageTitleLabel = WidgetBuilder.make(ui)
      .parent(col)
      .name("vImageTitle")
      .rect(RectF(0, 0, 410, 22))
      .fixedSize(410, 22)
      .text("Image")
      .textColor(ColorF(0.96f, 0.92f, 1.0f, 1.0f))
      .fontSize(13.0f)
      .build();

    refs.imageExifLabel = WidgetBuilder.make(ui)
      .parent(col)
      .name("vImageExif")
      .rect(RectF(0, 0, 410, 34))
      .fixedSize(410, 34)
      .text("EXIF")
      .textColor(ColorF(0.76f, 0.72f, 0.88f, 1.0f))
      .fontSize(11.0f)
      .multiline(true)
      .build();
  }

  void buildFileSubtree(Widget row, VerticalRowRefs refs) {
    refs.fileSubtree = WidgetBuilder.make(ui)
      .parent(row)
      .name("vFileSubtree")
      .rect(RectF(0, 0, 530, 38))
      .fixedSize(530, 38)
      .paddingVh(6, 10)
      .flexRow()
      .gap(8.0f)
      .alignItems(AlignItems.center)
      .roundBg(ColorF(0.11f, 0.13f, 0.17f, 1.0f))
      .bgRadius(4.0f)
      .border(ColorF(0.24f, 0.28f, 0.36f, 1.0f))
      .borderWidth(1.0f)
      .build();

    refs.fileIconBox = WidgetBuilder.make(ui)
      .parent(refs.fileSubtree)
      .name("vFileIcon")
      .rect(RectF(0, 0, 38, 24))
      .fixedSize(38, 24)
      .roundBg(ColorF(0.22f, 0.26f, 0.34f, 1.0f))
      .bgRadius(3.0f)
      .text("FILE")
      .textColor(ColorF(0.85f, 0.90f, 0.96f, 1.0f))
      .fontSize(10.0f)
      .build();

    refs.fileNameLabel = WidgetBuilder.make(ui)
      .parent(refs.fileSubtree)
      .name("vFileName")
      .rect(RectF(0, 0, 360, 20))
      .fixedSize(360, 20)
      .text("project_cut.mp4")
      .textColor(ColorF(0.88f, 0.92f, 0.98f, 1.0f))
      .fontSize(12.0f)
      .build();

    refs.fileSizeLabel = WidgetBuilder.make(ui)
      .parent(refs.fileSubtree)
      .name("vFileSize")
      .rect(RectF(0, 0, 96, 20))
      .fixedSize(96, 20)
      .text("42.8 MB")
      .textColor(ColorF(0.64f, 0.72f, 0.84f, 1.0f))
      .fontSize(11.0f)
      .build();
  }

  void bindHeaderSubtree(
    VerticalRowRefs refs,
    in VerticalItemData item,
    size_t index,
    float wPx,
    float hPx
  ) {
    import std.format : format;

    applyRowDimensions(refs.headerSubtree, wPx, hPx);
    refs.headerTitleLabel.setCaption(
      format(
        "Section #%d (Reel %d) [Row %d]%s",
        item.itemId / 12 + 1, item.itemId, index,
        item.expanded ? " [EXPANDED]" : ""
      )
    );
    refs.headerCountLabel.setCaption(
      format("%dx%d", cast(int) wPx, cast(int) hPx)
    );
  }

  void bindVideoSubtree(
    Widget row,
    VerticalRowRefs refs,
    in VerticalItemData item,
    size_t index,
    float wPx,
    float hPx
  ) {
    import std.format : format;

    applyRowDimensions(refs.videoSubtree, wPx, hPx);
    const float trackW = wPx - 24.0f;
    applyRowDimensions(refs.videoProgressTrack, trackW, 10.0f);
    if (refs.videoSubtree.children.length > 0) {
      applyRowDimensions(refs.videoSubtree.children[0], trackW, 22.0f);
    }
    applyRowDimensions(
      refs.videoMetaLabel, trackW, item.expanded ? 40.0f : 18.0f
    );

    refs.videoTitleLabel.setCaption(
      format(
        "LIVE Video Clip #%d (idx %d)%s",
        item.itemId, index,
        item.expanded ? " [OVERSIZED 700x400]" : ""
      )
    );
    refs.videoMetaLabel.setCaption(
      item.expanded
        ? format(
            "H.264 3840x2160 60fps | GOP: 2.0s | Smart-cut preview %dx%d",
            cast(int) wPx, cast(int) hPx
          )
        : format("H.264 1920x1080 | Duration 00:%02d.%d",
            cast(int) (item.itemId % 59 + 1), cast(int) (item.itemId % 9))
    );

    const float initPhase = cast(float) ((item.itemId % 10) * 0.1f);
    if (auto pSt = row in activeVideos) {
      pSt.trackWidth = trackW;
    } else {
      activeVideos[row] = VideoAnimState(initPhase, trackW);
    }
    refs.videoProgressFill.rect.width = 4.0f + (trackW - 4.0f) * initPhase;
  }

  void bindImageSubtree(
    VerticalRowRefs refs,
    in VerticalItemData item,
    size_t index,
    float wPx,
    float hPx
  ) {
    import std.format : format;

    applyRowDimensions(refs.imageSubtree, wPx, hPx);
    const bool wide = (wPx > 600.0f);
    if (refs.imageSubtree.children.length >= 2) {
      applyRowDimensions(
        refs.imageSubtree.children[1], wPx - 120.0f, hPx - 16.0f
      );
    }
    applyRowDimensions(refs.imageExifLabel, wPx - 120.0f, hPx - 44.0f);

    refs.imageTitleLabel.setCaption(
      format(
        "Still Frame #%d (idx %d) [%dx%d]",
        item.itemId, index, cast(int) wPx, cast(int) hPx
      )
    );
    refs.imageExifLabel.setCaption(
      wide
        ? format(
            "EXIF: 50mm f/1.8 ISO 200 | Wide metadata span exceeding " ~
              "viewport (%dpx)",
            cast(int) wPx
          )
        : "EXIF: 35mm f/2.8 ISO 100 | 1/500s sRGB"
    );
  }

  void bindFileSubtree(
    VerticalRowRefs refs,
    in VerticalItemData item,
    size_t index,
    float wPx,
    float hPx
  ) {
    import std.format : format;

    applyRowDimensions(refs.fileSubtree, wPx, hPx);
    refs.fileNameLabel.setCaption(
      format("media_take_%04d.mkv (idx %d)", item.itemId, index)
    );
    refs.fileSizeLabel.setCaption(
      format("%.1f MB", 12.4 + (item.itemId % 90) * 1.3)
    );
  }

  UiSystem ui;
  VerticalItemData[] items;
  uint nextItemId = 0;
  VerticalRowRefs[Widget] rowRefs;
  VideoAnimState[Widget] activeVideos;
  size_t recycledStops = 0;

  static final class VerticalRowRefs {
    Widget headerSubtree;
    Widget headerTitleLabel;
    Widget headerCountLabel;
    Widget videoSubtree;
    Widget videoPulseBadge;
    Widget videoTitleLabel;
    Widget videoMetaLabel;
    Widget videoProgressTrack;
    Widget videoProgressFill;
    Widget imageSubtree;
    Widget imageThumbBox;
    Widget imageTitleLabel;
    Widget imageExifLabel;
    Widget fileSubtree;
    Widget fileIconBox;
    Widget fileNameLabel;
    Widget fileSizeLabel;
  }

  static struct VideoAnimState {
    float phase = 0.0f;
    float trackWidth = 500.0f;
  }
}

/**
 * Single-template heterogeneous provider for the horizontal 1,200-item
 * filmstrip VirtList.
 */
final class HorizontalStripProvider : VirtListProvider {
  @disable this();

  this(UiSystem ui) {
    assert(ui !is null, "UiSystem must not be null");
    this.ui = ui;
    resetItems(1200);
  }

  invariant {
    assert(ui !is null);
  }

  /// Creates one reusable card widget with 3 internal subtrees.
  /// `parent` is allowed to be null in isolated tests.
  override Widget createWidget(Widget parent) {
    auto card = WidgetBuilder.make(ui)
      .parent(parent)
      .name("hStripCardTemplate")
      .rect(RectF(0, 0, 140, 180))
      .fixedSize(140, 180)
      .flexColumn()
      .clipContents(true)
      .clipChildren(true)
      .build();

    auto refs = new HorizontalCardRefs();
    buildKeyframeSubtree(card, refs);
    buildSegmentSubtree(card, refs);
    buildMarkerSubtree(card, refs);
    cardRefs[card] = refs;
    return card;
  }

  override void updateWidgetAt(Widget w, size_t index) {
    if (w is null || index >= items.length) {
      return;
    }
    auto pRefs = w in cardRefs;
    if (pRefs is null) {
      return;
    }
    HorizontalCardRefs refs = *pRefs;
    const HorizontalItemData item = items[index];

    float wPx = 140.0f;
    float hPx = 180.0f;
    computeCardDimensions(item, wPx, hPx);
    applyCardDimensions(w, wPx, hPx);

    refs.keyframeSubtree.setVisible(item.kind == HorizontalItemKind.keyframe);
    refs.segmentSubtree.setVisible(item.kind == HorizontalItemKind.segment);
    refs.markerSubtree.setVisible(item.kind == HorizontalItemKind.marker);

    final switch (item.kind) {
    case HorizontalItemKind.keyframe:
      bindKeyframeSubtree(refs, item, index, wPx, hPx);
      break;
    case HorizontalItemKind.segment:
      bindSegmentSubtree(refs, item, index, wPx, hPx);
      break;
    case HorizontalItemKind.marker:
      bindMarkerSubtree(refs, item, index, wPx, hPx);
      break;
    }
    w.update(WidgetUpdateScope.layout);
  }

  override void onWidgetRecycled(Widget w) {
  }

  size_t toggleResizeNear(size_t firstVis, size_t visCount) {
    if (items.length == 0) {
      return size_t.max;
    }
    const size_t start = (firstVis < items.length)
      ? firstVis
      : items.length - 1;
    const size_t end = (start + visCount <= items.length)
      ? (start + visCount)
      : items.length;
    foreach (i; start .. end) {
      if (items[i].resized) {
        items[i].resized = false;
        return i;
      }
    }
    foreach (i; start .. end) {
      if (items[i].kind == HorizontalItemKind.segment) {
        items[i].resized = true;
        return i;
      }
    }
    items[start].resized = !items[start].resized;
    return start;
  }

  void insertItemAt(size_t idx) {
    import std.algorithm.comparison : min;
    const size_t clamped = min(idx, items.length);
    const auto inserted = HorizontalItemData(
      HorizontalItemKind.segment, false, nextItemId++
    );
    items = items[0 .. clamped] ~ inserted ~ items[clamped .. $];
  }

  void removeItemAt(size_t idx) {
    if (idx >= items.length) {
      return;
    }
    items = items[0 .. idx] ~ items[idx + 1 .. $];
  }

  void resetItems(size_t count) {
    items.length = count;
    foreach (i; 0 .. count) {
      items[i] = HorizontalItemData(kindForIndex(i), false, cast(uint) i);
    }
    nextItemId = cast(uint) count;
  }

private:
  static HorizontalItemKind kindForIndex(size_t idx) {
    if (idx % 5 == 0) {
      return HorizontalItemKind.marker;
    }
    if (idx % 3 == 1) {
      return HorizontalItemKind.segment;
    }
    return HorizontalItemKind.keyframe;
  }

  static void computeCardDimensions(
    in HorizontalItemData item,
    out float wPx,
    out float hPx
  ) {
    final switch (item.kind) {
    case HorizontalItemKind.keyframe:
      wPx = item.resized ? 360.0f : 140.0f;
      hPx = item.resized ? 260.0f : 180.0f;
      break;
    case HorizontalItemKind.segment:
      wPx = item.resized ? 600.0f : 340.0f;
      hPx = item.resized ? 285.0f : 250.0f;
      break;
    case HorizontalItemKind.marker:
      wPx = item.resized ? 220.0f : 76.0f;
      hPx = item.resized ? 245.0f : 140.0f;
      break;
    }
  }

  static void applyCardDimensions(Widget w, float wPx, float hPx) {
    w.rect.width = wPx;
    w.rect.height = hPx;
    if (w.components.size !is null) {
      w.components.size.width = Dimension(wPx, SizingMode.fixed);
      w.components.size.height = Dimension(hPx, SizingMode.fixed);
    }
  }

  void buildKeyframeSubtree(Widget card, HorizontalCardRefs refs) {
    refs.keyframeSubtree = WidgetBuilder.make(ui)
      .parent(card)
      .name("hKeyframeSubtree")
      .rect(RectF(0, 0, 140, 180))
      .fixedSize(140, 180)
      .paddingVh(8, 8)
      .flexColumn()
      .gap(8.0f)
      .roundBg(ColorF(0.14f, 0.19f, 0.27f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.32f, 0.52f, 0.80f, 1.0f))
      .borderWidth(1.0f)
      .build();

    refs.keyframeTitleLabel = WidgetBuilder.make(ui)
      .parent(refs.keyframeSubtree)
      .name("hKeyframeTitle")
      .rect(RectF(0, 0, 124, 22))
      .fixedSize(124, 22)
      .text("Keyframe")
      .textColor(ColorF(0.95f, 0.98f, 1.0f, 1.0f))
      .fontSize(12.0f)
      .build();

    WidgetBuilder.make(ui)
      .parent(refs.keyframeSubtree)
      .name("hKeyframePreview")
      .rect(RectF(0, 0, 124, 90))
      .fixedSize(124, 90)
      .roundBg(ColorF(0.20f, 0.30f, 0.45f, 1.0f))
      .bgRadius(4.0f)
      .text("I-FRAME")
      .textColor(ColorF(0.76f, 0.88f, 1.0f, 1.0f))
      .fontSize(12.0f)
      .build();

    refs.keyframeSubLabel = WidgetBuilder.make(ui)
      .parent(refs.keyframeSubtree)
      .name("hKeyframeSub")
      .rect(RectF(0, 0, 124, 32))
      .fixedSize(124, 32)
      .text("TC 00:00:00")
      .textColor(ColorF(0.72f, 0.80f, 0.90f, 1.0f))
      .fontSize(11.0f)
      .multiline(true)
      .build();
  }

  void buildSegmentSubtree(Widget card, HorizontalCardRefs refs) {
    refs.segmentSubtree = WidgetBuilder.make(ui)
      .parent(card)
      .name("hSegmentSubtree")
      .rect(RectF(0, 0, 340, 250))
      .fixedSize(340, 250)
      .paddingVh(10, 12)
      .flexColumn()
      .gap(10.0f)
      .roundBg(ColorF(0.14f, 0.22f, 0.18f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.28f, 0.68f, 0.48f, 1.0f))
      .borderWidth(1.0f)
      .build();

    refs.segmentTitleLabel = WidgetBuilder.make(ui)
      .parent(refs.segmentSubtree)
      .name("hSegmentTitle")
      .rect(RectF(0, 0, 316, 24))
      .fixedSize(316, 24)
      .text("Multi-GOP Segment")
      .textColor(ColorF(0.95f, 1.0f, 0.96f, 1.0f))
      .fontSize(13.0f)
      .build();

    buildSegmentTracks(refs);
  }

  void buildSegmentTracks(HorizontalCardRefs refs) {
    WidgetBuilder.make(ui)
      .parent(refs.segmentSubtree)
      .name("hSegmentVideoTrack")
      .rect(RectF(0, 0, 316, 76))
      .fixedSize(316, 76)
      .roundBg(ColorF(0.20f, 0.36f, 0.30f, 1.0f))
      .bgRadius(4.0f)
      .text("Video Stream (Smart-Cut Copy)")
      .textColor(ColorF(0.82f, 0.96f, 0.88f, 1.0f))
      .fontSize(12.0f)
      .build();

    WidgetBuilder.make(ui)
      .parent(refs.segmentSubtree)
      .name("hSegmentAudioTrack")
      .rect(RectF(0, 0, 316, 54))
      .fixedSize(316, 54)
      .roundBg(ColorF(0.18f, 0.28f, 0.34f, 1.0f))
      .bgRadius(4.0f)
      .text("Audio PCM/AAC Waveform")
      .textColor(ColorF(0.76f, 0.88f, 0.96f, 1.0f))
      .fontSize(11.0f)
      .build();

    refs.segmentMetaLabel = WidgetBuilder.make(ui)
      .parent(refs.segmentSubtree)
      .name("hSegmentMeta")
      .rect(RectF(0, 0, 316, 40))
      .fixedSize(316, 40)
      .text("Oversized cross-axis card (250px > viewport height)")
      .textColor(ColorF(0.74f, 0.86f, 0.78f, 1.0f))
      .fontSize(11.0f)
      .multiline(true)
      .build();
  }

  void buildMarkerSubtree(Widget card, HorizontalCardRefs refs) {
    refs.markerSubtree = WidgetBuilder.make(ui)
      .parent(card)
      .name("hMarkerSubtree")
      .rect(RectF(0, 0, 76, 140))
      .fixedSize(76, 140)
      .paddingVh(8, 6)
      .flexColumn()
      .gap(8.0f)
      .alignItems(AlignItems.center)
      .roundBg(ColorF(0.24f, 0.18f, 0.12f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.78f, 0.56f, 0.24f, 1.0f))
      .borderWidth(1.0f)
      .build();

    refs.markerTitleLabel = WidgetBuilder.make(ui)
      .parent(refs.markerSubtree)
      .name("hMarkerTitle")
      .rect(RectF(0, 0, 62, 116))
      .fixedSize(62, 116)
      .text("CH")
      .textColor(ColorF(0.98f, 0.88f, 0.62f, 1.0f))
      .fontSize(12.0f)
      .multiline(true)
      .build();
  }

  void bindKeyframeSubtree(
    HorizontalCardRefs refs,
    in HorizontalItemData item,
    size_t index,
    float wPx,
    float hPx
  ) {
    import std.format : format;

    applyCardDimensions(refs.keyframeSubtree, wPx, hPx);
    refs.keyframeTitleLabel.setCaption(
      format("KF #%d (i:%d)", item.itemId, index)
    );
    refs.keyframeSubLabel.setCaption(
      format(
        "PTS %02d:%02d\n%dx%d",
        cast(int) ((item.itemId * 2) / 60),
        cast(int) ((item.itemId * 2) % 60),
        cast(int) wPx,
        cast(int) hPx
      )
    );
  }

  void bindSegmentSubtree(
    HorizontalCardRefs refs,
    in HorizontalItemData item,
    size_t index,
    float wPx,
    float hPx
  ) {
    import std.format : format;

    applyCardDimensions(refs.segmentSubtree, wPx, hPx);
    const float innerW = wPx - 24.0f;
    foreach (child; refs.segmentSubtree.children) {
      applyCardDimensions(child, innerW, child.rect.height);
    }
    refs.segmentTitleLabel.setCaption(
      format(
        "GOP Segment #%d (idx %d) [%dx%d]%s",
        item.itemId, index, cast(int) wPx, cast(int) hPx,
        item.resized ? " [WIDE]" : ""
      )
    );
    refs.segmentMetaLabel.setCaption(
      format(
        "Oversized card (%dx%d): exceeds viewport height (210px) -> " ~
          "activates vertical cross scrollbar.",
        cast(int) wPx, cast(int) hPx
      )
    );
  }

  void bindMarkerSubtree(
    HorizontalCardRefs refs,
    in HorizontalItemData item,
    size_t index,
    float wPx,
    float hPx
  ) {
    import std.format : format;

    applyCardDimensions(refs.markerSubtree, wPx, hPx);
    refs.markerTitleLabel.setCaption(
      format(
        "CH\n#%d\nidx\n%d\n%dx%d",
        item.itemId, index, cast(int) wPx, cast(int) hPx
      )
    );
  }

  UiSystem ui;
  HorizontalItemData[] items;
  uint nextItemId = 0;
  HorizontalCardRefs[Widget] cardRefs;

  static final class HorizontalCardRefs {
    Widget keyframeSubtree;
    Widget keyframeTitleLabel;
    Widget keyframeSubLabel;
    Widget segmentSubtree;
    Widget segmentTitleLabel;
    Widget segmentMetaLabel;
    Widget markerSubtree;
    Widget markerTitleLabel;
  }
}
