module yguilib.widget.internal.layout_content_size;

package(yguilib):
import std.algorithm.comparison : max;
import yguilib.render : Renderer;
import yguilib.render.render_types : PointF;
import yguilib.widget;
import yguilib.widget.layout_components;
import yguilib.widget.drawing_components;

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

  return calcTextContentSize(w.components.textLabel, r);
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
    if (!child.visible) {
      continue;
    }
    const float mainDim = isRow ? child.rect.width : child.rect.height;
    const float crossDim = isRow ? child.rect.height : child.rect.width;
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
    if (!child.visible) {
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
  const TextLabel tl,
  Renderer r
) {
  if (tl !is null && r !is null && tl.caption.length > 0) {
    const PointF textSize = r.measureText(tl.caption);
    return PointF(max(0.0f, textSize.x), max(0.0f, textSize.y));
  }
  return PointF(0.0f, 0.0f);
}
