module yguilib.widget.internal.layout_content_size;

package(yguilib):
import std.algorithm.comparison : max, min;
import yguilib.render : Renderer;
import yguilib.render.font : Font;
import yguilib.render.render_types : PointF;
import yguilib.widget;
import yguilib.widget.layout_components;
import yguilib.widget.drawing_components;
import yguilib.widget.internal.layout_axis : getCrossOuterSize,
  getMainOuterSize;
import yguilib.widget.internal.layout_text : measureTextContentSize;
import yguilib.widget.internal.text_label_cache : getTextContentSize;

float getBorderWidth(const Border borderComp) {
  if (borderComp !is null && borderComp.style != Border.Style.none) {
    return max(0.0f, borderComp.width);
  }
  return 0.0f;
}

PointF calcPaddingAndBorder(
  const Size szComp,
  const Border borderComp
) {
  const float borderWidth = getBorderWidth(borderComp);
  const float borderExtra = borderWidth * 2.0f;
  return PointF(
    szComp.padding.left + szComp.padding.right + borderExtra,
    szComp.padding.top + szComp.padding.bottom + borderExtra
  );
}

PointF calcContentSize(Widget w, Renderer r) {
  PointF size = PointF(0.0f, 0.0f);

  FlexContainer flexComp = w.components.flexContainer;
  if (flexComp !is null) {
    if (tryCalcFlexContentSize(w, flexComp, size)) {
      return size;
    }
  } else {
    if (tryCalcChildrenBoundingBox(w, size)) {
      return size;
    }
  }

  float availableWidth = 0.0f;
  float availableHeight = 0.0f;

  if (w.components.size !is null) {
    const Size sz = w.components.size;
    const PointF padBorder = calcPaddingAndBorder(sz, w.components.border);

    if (sz.width.mode == SizingMode.fixed) {
      float wVal = sz.width.value;
      if (sz.maxWidth < float.infinity && sz.maxWidth >= 0.0f) {
        wVal = min(wVal, sz.maxWidth);
      }
      if (sz.minWidth > 0.0f) {
        wVal = max(wVal, sz.minWidth);
      }
      availableWidth = max(0.0f, wVal - padBorder.x);
    } else if (sz.maxWidth < float.infinity && sz.maxWidth > 0.0f) {
      availableWidth = max(0.0f, sz.maxWidth - padBorder.x);
    }

    if (sz.height.mode == SizingMode.fixed) {
      float hVal = sz.height.value;
      if (sz.maxHeight < float.infinity && sz.maxHeight >= 0.0f) {
        hVal = min(hVal, sz.maxHeight);
      }
      if (sz.minHeight > 0.0f) {
        hVal = max(hVal, sz.minHeight);
      }
      availableHeight = max(0.0f, hVal - padBorder.y);
    } else if (sz.maxHeight < float.infinity && sz.maxHeight > 0.0f) {
      availableHeight = max(0.0f, sz.maxHeight - padBorder.y);
    }
  }

  return calcTextContentSize(
    w.components.textLabel,
    r,
    availableWidth,
    availableHeight
  );
}

bool tryCalcFlexContentSize(
  const Widget w,
  const FlexContainer flexComp,
  out PointF size
) {
  if (w.children.length == 0) {
    return false;
  }

  size_t visibleCount = 0;
  float mainSum = 0.0f;
  float crossMax = 0.0f;
  const bool isRow = flexComp.direction == FlexDirection.row;

  foreach (child; w.children) {
    if (!child.visible || child.components.anchor !is null) {
      continue;
    }
    const float mainDim = getMainOuterSize(child, isRow);
    const float crossDim = getCrossOuterSize(child, isRow);
    mainSum += mainDim;
    crossMax = max(crossMax, crossDim);
    visibleCount++;
  }

  if (visibleCount == 0) {
    return false;
  }

  if (visibleCount > 1) {
    mainSum += flexComp.gap * (visibleCount - 1);
  }

  size = isRow ? PointF(mainSum, crossMax) : PointF(crossMax, mainSum);
  return true;
}

bool tryCalcChildrenBoundingBox(
  const Widget w,
  out PointF size
) {
  if (w.children.length == 0) {
    return false;
  }

  size_t visibleCount = 0;
  PointF boundingSize = PointF(0.0f, 0.0f);
  foreach (child; w.children) {
    if (!child.visible || child.components.anchor !is null) {
      continue;
    }
    boundingSize.x = max(boundingSize.x, child.rect.x + child.rect.width);
    boundingSize.y = max(boundingSize.y, child.rect.y + child.rect.height);
    visibleCount++;
  }

  if (visibleCount == 0) {
    return false;
  }

  size = boundingSize;
  return true;
}

PointF calcTextContentSize(
  TextLabel tl,
  Renderer r,
  float availableWidth = 0.0f,
  float availableHeight = 0.0f
) {
  if (tl is null || r is null || tl.caption.length == 0) {
    return PointF(0.0f, 0.0f);
  }

  Font font = r.getFont(tl.fontSize, tl.font);
  if (font is null) {
    return PointF(0.0f, 0.0f);
  }

  return getTextContentSize(
    tl.contentSizeCache, r, font, tl.font,
    tl.caption, tl.multiline, tl.overflowEllipsis,
    availableWidth, availableHeight
  );
}

PointF calcTextContentSize(
  const TextLabel tl,
  Renderer r,
  float availableWidth = 0.0f,
  float availableHeight = 0.0f
) {
  if (tl is null || r is null || tl.caption.length == 0) {
    return PointF(0.0f, 0.0f);
  }

  Font font = r.getFont(tl.fontSize, tl.font);
  if (font is null) {
    return PointF(0.0f, 0.0f);
  }

  return measureTextContentSize(
    r,
    font,
    tl.caption,
    tl.multiline,
    tl.overflowEllipsis,
    availableWidth,
    availableHeight
  );
}
