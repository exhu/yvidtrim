module yguilib.widget.internal.layout_content_size;

package(yguilib):
import std.typecons : Nullable;
import yguilib.render : Renderer;
import yguilib.render.font : Font;
import yguilib.render.render_types : PointF;
import yguilib.widget;
import yguilib.widget.layout_components;
import yguilib.widget.drawing_components;
import yguilib.widget.internal.layout_axis : crossOuterSize,
  mainOuterSize;
import yguilib.widget.internal.layout_dimension : clampDimension;
import yguilib.widget.internal.text_label_cache : TextLayoutKey,
  textContentSize;

/// Returns border width if `borderComp` is non-null and visible, else 0.
/// `borderComp` may be null.
float borderWidthFromComponent(const Border borderComp) {
  import std.algorithm.comparison : max;
  if (borderComp !is null && borderComp.style != Border.Style.none) {
    return max(0.0f, borderComp.width);
  }
  return 0.0f;
}

/// Computes total horizontal and vertical padding + border inset.
/// `szComp` must not be null; `borderComp` may be null.
PointF calcPaddingAndBorder(
  const Size szComp,
  const Border borderComp
) {
  assert(szComp !is null);
  const float borderWidth = borderWidthFromComponent(borderComp);
  const float borderExtra = borderWidth * 2.0f;
  return PointF(
    szComp.padding.left + szComp.padding.right + borderExtra,
    szComp.padding.top + szComp.padding.bottom + borderExtra
  );
}

/// Computes intrinsic content size for `w`.
/// `r` may be null (text measurement yields (0, 0) when null).
PointF calcContentSize(Widget w, Renderer r) {
  if (w.components.scrollableArea !is null) {
    foreach (child; w.children) {
      if (child.visible && child.components.anchor is null) {
        return PointF(child.rect.width, child.rect.height);
      }
    }
  }

  FlexContainer flexComp = w.components.flexContainer;
  if (flexComp !is null) {
    const Nullable!PointF res = tryCalcFlexContentSize(w, flexComp);
    if (!res.isNull) {
      return res.get();
    }
  } else {
    const Nullable!PointF res = tryCalcChildrenBoundingBox(w);
    if (!res.isNull) {
      return res.get();
    }
  }

  float availableWidth = 0.0f;
  float availableHeight = 0.0f;

  if (w.components.size !is null) {
    const Size sz = w.components.size;
    const PointF padBorder = calcPaddingAndBorder(sz, w.components.border);
    availableWidth = availableTextExtent(
      sz.width, sz.minWidth, sz.maxWidth, padBorder.x
    );
    availableHeight = availableTextExtent(
      sz.height, sz.minHeight, sz.maxHeight, padBorder.y
    );
  }

  return calcTextContentSize(
    w.components.textLabel,
    r,
    availableWidth,
    availableHeight
  );
}

/// Computes intrinsic content size of a flex container's visible flow children.
Nullable!PointF tryCalcFlexContentSize(
  const Widget w,
  const FlexContainer flexComp
) {
  import std.algorithm.comparison : max;
  if (w.children.length == 0) {
    return Nullable!PointF.init;
  }

  size_t visibleCount = 0;
  float mainSum = 0.0f;
  float crossMax = 0.0f;
  const bool isRow = flexComp.direction == FlexDirection.row;

  foreach (child; w.children) {
    if (!child.visible || child.components.anchor !is null) {
      continue;
    }
    const float mainDim = mainOuterSize(child, isRow);
    const float crossDim = crossOuterSize(child, isRow);
    mainSum += mainDim;
    crossMax = max(crossMax, crossDim);
    visibleCount++;
  }

  if (visibleCount == 0) {
    return Nullable!PointF.init;
  }

  if (visibleCount > 1) {
    mainSum += flexComp.gap * (visibleCount - 1);
  }

  const PointF size = isRow
    ? PointF(mainSum, crossMax)
    : PointF(crossMax, mainSum);
  return Nullable!PointF(size);
}

/// Computes bounding box of visible non-anchored children including margins.
Nullable!PointF tryCalcChildrenBoundingBox(const Widget w) {
  if (w.children.length == 0) {
    return Nullable!PointF.init;
  }

  size_t visibleCount = 0;
  PointF boundingSize = PointF(0.0f, 0.0f);
  foreach (child; w.children) {
    if (!child.visible || child.components.anchor !is null) {
      continue;
    }
    import std.algorithm.comparison : max;
    const Size csz = child.components.size;
    const float mr = csz !is null ? csz.margin.right : 0.0f;
    const float mb = csz !is null ? csz.margin.bottom : 0.0f;
    boundingSize.x = max(boundingSize.x, child.rect.x + child.rect.width + mr);
    boundingSize.y = max(boundingSize.y, child.rect.y + child.rect.height + mb);
    visibleCount++;
  }

  if (visibleCount == 0) {
    return Nullable!PointF.init;
  }

  return Nullable!PointF(boundingSize);
}

/// Measures and caches text content size for `tl`.
/// `tl` and `r` may be null (returns (0, 0)).
PointF calcTextContentSize(
  TextLabel tl,
  Renderer r,
  float availableWidth,
  float availableHeight
) {
  if (tl is null || r is null || tl.caption.length == 0) {
    return PointF(0.0f, 0.0f);
  }

  Font font = r.font(tl.fontSize, tl.font);
  if (font is null) {
    return PointF(0.0f, 0.0f);
  }

  TextLayoutKey key;
  key.withSize(availableWidth, availableHeight)
    .withCaption(tl.caption)
    .withFont(font)
    .withMultiline(tl.multiline)
    .withEllipsis(tl.overflowEllipsis);

  return textContentSize(tl.contentSizeCache, r, font, key);
}

private:

float availableTextExtent(
  const Dimension dim,
  float minVal,
  float maxVal,
  float padBorder
) {
  import std.algorithm.comparison : max;
  if (dim.mode == SizingMode.fixed) {
    const float clamped = clampDimension(dim.value, minVal, maxVal);
    return max(0.0f, clamped - padBorder);
  }
  if (maxVal < float.infinity && maxVal > 0.0f) {
    return max(0.0f, maxVal - padBorder);
  }
  return 0.0f;
}

unittest {
  import yguilib.render.render_types : ColorF, RectF;
  import yguilib.widget.scroll_components : ScrollableArea;
  import yguilib.widget.test_fixture : WidgetFixture;

  // borderWidthFromComponent
  assert(borderWidthFromComponent(null) == 0.0f);
  auto bNone = new Border(ColorF(1, 1, 1, 1), 5.0f, Border.Style.none);
  assert(borderWidthFromComponent(bNone) == 0.0f);
  auto bRect = Border.rect(ColorF(1, 1, 1, 1), 3.0f);
  assert(borderWidthFromComponent(bRect) == 3.0f);

  // calcPaddingAndBorder
  auto sz = new Size;
  sz.padding = Insets(2, 4, 6, 8);
  assert(calcPaddingAndBorder(sz, bRect) == PointF(18.0f, 14.0f));

  auto fix = new WidgetFixture();

  // tryCalcChildrenBoundingBox includes child margins
  auto boxParent = fix.makeRootWithRect(RectF(0, 0, 0, 0));
  auto c1 = fix.makeChildWithRect(boxParent, RectF(10, 5, 40, 20));
  auto c1Sz = new Size;
  c1Sz.margin = Insets(1, 6, 8, 2); // right=6, bottom=8
  c1.components.size = c1Sz;
  const auto bbox = tryCalcChildrenBoundingBox(boxParent);
  assert(!bbox.isNull);
  assert(bbox.get() == PointF(56.0f, 33.0f));

  // calcContentSize prefers ScrollableArea child
  auto scrollParent = fix.makeRootWithRect(RectF(0, 0, 100, 100));
  scrollParent.components.scrollableArea = new ScrollableArea();
  fix.makeChildWithRect(scrollParent, RectF(0, 0, 250, 180));
  assert(calcContentSize(scrollParent, null) == PointF(250.0f, 180.0f));

  // calcContentSize with TextLabel caches result in contentSizeCache
  import yguilib.clibs.sdl3 : yguilib_sdl3_init, yguilib_sdl3_quit;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_layout_content_size");
  win.create();
  scope(exit) win.destroy();

  auto r = new Renderer(320, 240, 1.0f);
  scope(exit) r.destroy();

  auto textWidget = fix.makeRootWithRect(RectF(0, 0, 0, 0));
  auto textSz = new Size;
  textSz.width = Dimension(0, SizingMode.auto_);
  textSz.height = Dimension(0, SizingMode.auto_);
  textWidget.components.size = textSz;
  auto tl = new TextLabel("Cached", ColorF(1, 1, 1, 1));
  textWidget.components.textLabel = tl;

  const PointF measured = calcContentSize(textWidget, r);
  assert(measured.x > 0.0f);
  assert(tl.contentSizeCache.valid);
  assert(tl.contentSizeCache.size == measured);
}
