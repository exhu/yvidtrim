module yguilib.widget.internal.layout_anchor;

package(yguilib):
import std.typecons : Nullable;
import yguilib.render.render_types : RectF;
import yguilib.widget : Widget;
import yguilib.widget.layout_components : Anchor, Dimension, Insets, Size,
  SizingMode;
import yguilib.widget.internal.layout_dimension : clampDimension;

/// Positions and optionally sizes a widget according to its Anchor component.
/// `w` may be null (no-op).
void handleAnchorComp(Widget w) {
  if (w is null || w.components.anchor is null || w.parent is null) {
    return;
  }

  const Anchor anchor = w.components.anchor;
  const RectF contentRect = w.parent.contentArea();
  const Size szComp = w.components.size;

  resolveAxisAnchor(w, anchor, szComp, contentRect, true);
  resolveAxisAnchor(w, anchor, szComp, contentRect, false);
}

private:

void resolveAxisAnchor(
  Widget w,
  const Anchor anchor,
  const Size szComp,
  const RectF contentRect,
  bool isHorizontal
) {
  const Nullable!float startAnchor = isHorizontal ? anchor.left : anchor.top;
  const Nullable!float endAnchor = isHorizontal ? anchor.right : anchor.bottom;
  const float marginStart = szComp !is null
    ? (isHorizontal ? szComp.margin.left : szComp.margin.top)
    : 0.0f;
  const float marginEnd = szComp !is null
    ? (isHorizontal ? szComp.margin.right : szComp.margin.bottom)
    : 0.0f;
  const float contentPos = isHorizontal ? contentRect.x : contentRect.y;
  const float contentExtent = isHorizontal
    ? contentRect.width : contentRect.height;

  if (!startAnchor.isNull && !endAnchor.isNull) {
    const bool isFixed = szComp !is null && (
      isHorizontal
        ? szComp.width.mode == SizingMode.fixed
        : szComp.height.mode == SizingMode.fixed
    );
    if (!isFixed) {
      // Auto / unconstrained: stretches to fill between anchors
      const float totalInsets =
        startAnchor.get + endAnchor.get + marginStart + marginEnd;
      import std.algorithm.comparison : max;
      float targetExtent = max(0.0f, contentExtent - totalInsets);
      if (szComp !is null) {
        const float minVal = isHorizontal ? szComp.minWidth : szComp.minHeight;
        const float maxVal = isHorizontal ? szComp.maxWidth : szComp.maxHeight;
        targetExtent = clampDimension(targetExtent, minVal, maxVal);
      }
      if (isHorizontal) {
        w.rect.width = targetExtent;
      } else {
        w.rect.height = targetExtent;
      }
    }
    // Over-constrained fixed or stretched: start anchor takes precedence
    const float pos = contentPos + startAnchor.get + marginStart;
    if (isHorizontal) {
      w.rect.x = pos;
    } else {
      w.rect.y = pos;
    }
  } else if (!startAnchor.isNull) {
    const float pos = contentPos + startAnchor.get + marginStart;
    if (isHorizontal) {
      w.rect.x = pos;
    } else {
      w.rect.y = pos;
    }
  } else if (!endAnchor.isNull) {
    const float currentExtent = isHorizontal ? w.rect.width : w.rect.height;
    const float pos =
      contentPos + contentExtent - currentExtent - endAnchor.get - marginEnd;
    if (isHorizontal) {
      w.rect.x = pos;
    } else {
      w.rect.y = pos;
    }
  }
}

// Corner anchors positioning (top-right, bottom-left, bottom-right)
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto parent = fix.makeRootWithRect(RectF(10, 10, 200, 100));

  auto tr = fix.makeChildWithRect(parent, RectF(0, 0, 30, 20));
  auto aTR = new Anchor;
  aTR.right = 0.0f;
  aTR.top = 0.0f;
  tr.components.anchor = aTR;
  handleAnchorComp(tr);
  assert(tr.rect.x == 170); // 200 - 30
  assert(tr.rect.y == 0);

  auto bl = fix.makeChildWithRect(parent, RectF(0, 0, 30, 20));
  auto aBL = new Anchor;
  aBL.left = 0.0f;
  aBL.bottom = 0.0f;
  bl.components.anchor = aBL;
  handleAnchorComp(bl);
  assert(bl.rect.x == 0);
  assert(bl.rect.y == 80); // 100 - 20

  auto br = fix.makeChildWithRect(parent, RectF(0, 0, 30, 20));
  auto aBR = new Anchor;
  aBR.right = 5.0f;
  aBR.bottom = 10.0f;
  br.components.anchor = aBR;
  handleAnchorComp(br);
  assert(br.rect.x == 165); // 200 - 30 - 5
  assert(br.rect.y == 70);  // 100 - 20 - 10
}

// Anchoring inside parent with padding, border, and child margin
unittest {
  import yguilib.widget.drawing_components : Border;
  import yguilib.render.render_types : ColorF;
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto parent = fix.makeRootWithRect(RectF(0, 0, 300, 200));
  auto parentSz = new Size;
  parentSz.padding = Insets(10, 15, 10, 15);
  parent.components.size = parentSz;
  auto border = Border.rect(ColorF(1, 0, 0, 1), 5.0f);
  parent.components.border = border;

  // Content rect: startX = 20 (border 5 + pad 15), startY = 15 (5 + 10)
  // availW = 300 - 10 - 30 = 260, availH = 200 - 10 - 20 = 170

  auto child = fix.makeChildWithRect(parent, RectF(0, 0, 40, 30));
  auto childSz = new Size;
  childSz.margin = Insets(2, 3, 4, 5);
  child.components.size = childSz;

  auto a = new Anchor;
  a.right = 10.0f;
  a.bottom = 10.0f;
  child.components.anchor = a;
  handleAnchorComp(child);

  // x = startX (20) + availW (260) - width (40) - right (10)
  //   - margin.right (3) = 227
  assert(child.rect.x == 227);
  // y = startY (15) + availH (170) - height (30) - bottom (10)
  //   - margin.bottom (4) = 141
  assert(child.rect.y == 141);
}

// Dual anchors stretch auto mode and respect min/max constraints
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto parent = fix.makeRootWithRect(RectF(0, 0, 200, 150));

  auto child = fix.makeChildWithRect(parent, RectF(0, 0, 0, 0));
  auto a = new Anchor;
  a.left = 10.0f;
  a.right = 20.0f;
  a.top = 5.0f;
  a.bottom = 15.0f;
  child.components.anchor = a;

  handleAnchorComp(child);
  assert(child.rect.x == 10);
  assert(child.rect.width == 170); // 200 - 10 - 20
  assert(child.rect.y == 5);
  assert(child.rect.height == 130); // 150 - 5 - 15

  // With minWidth / maxWidth constraints
  auto sz = new Size;
  sz.maxWidth = 100.0f;
  sz.minHeight = 140.0f;
  child.components.size = sz;

  handleAnchorComp(child);
  assert(child.rect.width == 100); // clamped to maxWidth
  assert(child.rect.height == 140); // clamped to minHeight
}

// Dual anchors with fixed size: precedence rules (left and top win)
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto parent = fix.makeRootWithRect(RectF(0, 0, 300, 200));

  auto child = fix.makeChildWithRect(parent, RectF(0, 0, 50, 40));
  auto sz = new Size;
  sz.width = Dimension(50, SizingMode.fixed);
  sz.height = Dimension(40, SizingMode.fixed);
  child.components.size = sz;

  auto a = new Anchor;
  a.left = 15.0f;
  a.right = 10.0f;
  a.top = 25.0f;
  a.bottom = 20.0f;
  child.components.anchor = a;

  handleAnchorComp(child);
  assert(child.rect.x == 15);
  assert(child.rect.width == 50);
  assert(child.rect.y == 25);
  assert(child.rect.height == 40);
}
