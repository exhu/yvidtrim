/**
 * virtlist_providers.d - Page 7 VirtListProvider implementations binding
 * reusable row/card widget templates to the vertical and horizontal item
 * models.
 */
module guidemo.pages.virtlist_providers;

import guidemo.pages.virtlist_items : HorizontalItemData, HorizontalItemKind,
  HorizontalItemsModel, VerticalItemData, VerticalItemKind,
  VerticalItemsModel;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.layout_components : AlignItems, Dimension,
  JustifyContent, SizingMode;
import yguilib.widget.virtlist_components : VirtListProvider;

/**
 * Single-template heterogeneous provider for the vertical 10,000-item media
 * and file browser VirtList.
 */
final class VerticalMediaProvider : VirtListProvider {
  @disable this();

  /// Constructs the provider bound to `ui` reading rows from `itemsTracker`.
  this(UiSystem ui, ref ModelTracker!VerticalItemsModel itemsTracker) {
    assert(ui !is null, "UiSystem must not be null");
    this.ui = ui;
    this.itemsTracker = ModelTracker!VerticalItemsModel.from(itemsTracker);
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
    dropStaleAnimations();
    const auto items = itemsTracker.model.items;
    if (w is null || index >= items.length) {
      return;
    }
    auto pRefs = w in rowRefs;
    if (pRefs is null) {
      return;
    }
    VerticalRowRefs refs = *pRefs;
    const VerticalItemData item = items[index];

    const ItemDimensions dims = computeItemDimensions(item);
    applyRowDimensions(w, dims.width, dims.height);

    refs.headerSubtree.setVisible(item.kind == VerticalItemKind.header);
    refs.videoSubtree.setVisible(item.kind == VerticalItemKind.video);
    refs.imageSubtree.setVisible(item.kind == VerticalItemKind.image);
    refs.fileSubtree.setVisible(item.kind == VerticalItemKind.file);

    final switch (item.kind) {
    case VerticalItemKind.header:
      activeVideos.remove(w);
      bindHeaderSubtree(refs, item, index, dims.width, dims.height);
      break;
    case VerticalItemKind.video:
      bindVideoSubtree(w, refs, item, index, dims.width, dims.height);
      break;
    case VerticalItemKind.image:
      activeVideos.remove(w);
      bindImageSubtree(refs, item, index, dims.width, dims.height);
      break;
    case VerticalItemKind.file:
      activeVideos.remove(w);
      bindFileSubtree(refs, item, index, dims.width, dims.height);
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

    dropStaleAnimations();
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

  /// Returns the number of animating video rows.
  size_t activeVideoCount() const {
    return activeVideos.length;
  }

  /// Returns how many video animations were stopped by recycling.
  size_t recycledStopCount() const {
    return recycledStops;
  }

private:
  /// Clears video animation state after the items model was reset.
  void dropStaleAnimations() {
    const size_t gen = itemsTracker.model.resetGeneration;
    if (gen == seenResetGeneration) {
      return;
    }
    seenResetGeneration = gen;
    activeVideos.clear();
  }

  static ItemDimensions computeItemDimensions(in VerticalItemData item) {
    final switch (item.kind) {
    case VerticalItemKind.header:
      return ItemDimensions(
        item.expanded ? 640.0f : 530.0f,
        item.expanded ? 76.0f : 34.0f
      );
    case VerticalItemKind.video:
      return ItemDimensions(
        item.expanded ? 700.0f : 530.0f,
        item.expanded ? 400.0f : 74.0f
      );
    case VerticalItemKind.image:
      if (item.expanded) {
        return ItemDimensions(700.0f, 220.0f);
      } else if (item.itemId % 24 == 10) {
        return ItemDimensions(680.0f, 380.0f);
      } else {
        return ItemDimensions(
          (item.itemId % 8 == 2) ? 650.0f : 530.0f,
          84.0f
        );
      }
    case VerticalItemKind.file:
      return ItemDimensions(
        item.expanded ? 640.0f : 530.0f,
        item.expanded ? 110.0f : 38.0f
      );
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
  ModelTracker!VerticalItemsModel itemsTracker;
  size_t seenResetGeneration = 0;
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

  /// Constructs the provider bound to `ui` reading cards from
  /// `itemsTracker`.
  this(UiSystem ui, ref ModelTracker!HorizontalItemsModel itemsTracker) {
    assert(ui !is null, "UiSystem must not be null");
    this.ui = ui;
    this.itemsTracker = ModelTracker!HorizontalItemsModel.from(itemsTracker);
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
    const auto items = itemsTracker.model.items;
    if (w is null || index >= items.length) {
      return;
    }
    auto pRefs = w in cardRefs;
    if (pRefs is null) {
      return;
    }
    HorizontalCardRefs refs = *pRefs;
    const HorizontalItemData item = items[index];

    const ItemDimensions dims = computeCardDimensions(item);
    applyCardDimensions(w, dims.width, dims.height);

    refs.keyframeSubtree.setVisible(item.kind == HorizontalItemKind.keyframe);
    refs.segmentSubtree.setVisible(item.kind == HorizontalItemKind.segment);
    refs.markerSubtree.setVisible(item.kind == HorizontalItemKind.marker);

    final switch (item.kind) {
    case HorizontalItemKind.keyframe:
      bindKeyframeSubtree(refs, item, index, dims.width, dims.height);
      break;
    case HorizontalItemKind.segment:
      bindSegmentSubtree(refs, item, index, dims.width, dims.height);
      break;
    case HorizontalItemKind.marker:
      bindMarkerSubtree(refs, item, index, dims.width, dims.height);
      break;
    }
    w.update(WidgetUpdateScope.layout);
  }

  override void onWidgetRecycled(Widget w) {
  }

private:
  static ItemDimensions computeCardDimensions(in HorizontalItemData item) {
    final switch (item.kind) {
    case HorizontalItemKind.keyframe:
      return ItemDimensions(
        item.resized ? 360.0f : 140.0f,
        item.resized ? 260.0f : 180.0f
      );
    case HorizontalItemKind.segment:
      return ItemDimensions(
        item.resized ? 600.0f : 340.0f,
        item.resized ? 285.0f : 250.0f
      );
    case HorizontalItemKind.marker:
      return ItemDimensions(
        item.resized ? 220.0f : 76.0f,
        item.resized ? 245.0f : 140.0f
      );
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
  ModelTracker!HorizontalItemsModel itemsTracker;
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

private:

struct ItemDimensions {
  float width;
  float height;
}
