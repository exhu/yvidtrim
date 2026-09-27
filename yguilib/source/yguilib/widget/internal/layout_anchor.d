module yguilib.widget.internal.layout_anchor;

package(yguilib):
import std.algorithm.comparison : max;
import yguilib.render.render_types : RectF;
import yguilib.widget : Widget;
import yguilib.widget.layout_components : Anchor, Dimension, Insets, Size,
  SizingMode;
import yguilib.widget.internal.layout_dimension : clampDimension;
import yguilib.widget.internal.layout_flex : calcContentRect;

/// Positions and optionally sizes a widget according to its Anchor component.
void handleAnchorComp(Widget w) {
  if (w is null || w.components.anchor is null || w.parent is null) {
    return;
  }

  const Anchor anchor = w.components.anchor;
  const RectF contentRect = calcContentRect(w.parent);
  const Size szComp = w.components.size;

  resolveHorizontalAnchor(w, anchor, szComp, contentRect);
  resolveVerticalAnchor(w, anchor, szComp, contentRect);
}

private:

void resolveHorizontalAnchor(
  Widget w,
  const Anchor anchor,
  const Size szComp,
  const RectF contentRect
) {
  const float ml = szComp !is null ? szComp.margin.left : 0.0f;
  const float mr = szComp !is null ? szComp.margin.right : 0.0f;

  if (!anchor.left.isNull && !anchor.right.isNull) {
    const bool isFixed = szComp !is null &&
      szComp.width.mode == SizingMode.fixed;
    if (isFixed) {
      // Over-constrained: left takes precedence in LTR
      w.rect.x = contentRect.x + anchor.left.get + ml;
    } else {
      // Auto / unconstrained: stretches to fill between anchors
      const float totalInsets = anchor.left.get + anchor.right.get + ml + mr;
      float targetWidth = max(0.0f, contentRect.width - totalInsets);
      if (szComp !is null) {
        targetWidth = clampDimension(
          targetWidth, szComp.minWidth, szComp.maxWidth
        );
      }
      w.rect.width = targetWidth;
      w.rect.x = contentRect.x + anchor.left.get + ml;
    }
  } else if (!anchor.left.isNull) {
    w.rect.x = contentRect.x + anchor.left.get + ml;
  } else if (!anchor.right.isNull) {
    w.rect.x = contentRect.x + contentRect.width
      - w.rect.width - anchor.right.get - mr;
  }
}

void resolveVerticalAnchor(
  Widget w,
  const Anchor anchor,
  const Size szComp,
  const RectF contentRect
) {
  const float mt = szComp !is null ? szComp.margin.top : 0.0f;
  const float mb = szComp !is null ? szComp.margin.bottom : 0.0f;

  if (!anchor.top.isNull && !anchor.bottom.isNull) {
    const bool isFixed = szComp !is null &&
      szComp.height.mode == SizingMode.fixed;
    if (isFixed) {
      // Over-constrained: top takes precedence
      w.rect.y = contentRect.y + anchor.top.get + mt;
    } else {
      // Auto / unconstrained: stretches to fill between anchors
      const float totalInsets = anchor.top.get + anchor.bottom.get + mt + mb;
      float targetHeight = max(0.0f, contentRect.height - totalInsets);
      if (szComp !is null) {
        targetHeight = clampDimension(
          targetHeight, szComp.minHeight, szComp.maxHeight
        );
      }
      w.rect.height = targetHeight;
      w.rect.y = contentRect.y + anchor.top.get + mt;
    }
  } else if (!anchor.top.isNull) {
    w.rect.y = contentRect.y + anchor.top.get + mt;
  } else if (!anchor.bottom.isNull) {
    w.rect.y = contentRect.y + contentRect.height
      - w.rect.height - anchor.bottom.get - mb;
  }
}

// Corner anchors positioning (top-right, bottom-left, bottom-right)
unittest {
  auto parent = new Widget(null, RectF(10, 10, 200, 100));

  auto tr = new Widget(parent, RectF(0, 0, 30, 20));
  auto aTR = new Anchor;
  aTR.right = 0.0f;
  aTR.top = 0.0f;
  tr.components.anchor = aTR;
  handleAnchorComp(tr);
  assert(tr.rect.x == 170); // 200 - 30
  assert(tr.rect.y == 0);

  auto bl = new Widget(parent, RectF(0, 0, 30, 20));
  auto aBL = new Anchor;
  aBL.left = 0.0f;
  aBL.bottom = 0.0f;
  bl.components.anchor = aBL;
  handleAnchorComp(bl);
  assert(bl.rect.x == 0);
  assert(bl.rect.y == 80); // 100 - 20

  auto br = new Widget(parent, RectF(0, 0, 30, 20));
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

  auto parent = new Widget(null, RectF(0, 0, 300, 200));
  auto parentSz = new Size;
  parentSz.padding = Insets(10, 15, 10, 15);
  parent.components.size = parentSz;
  auto border = new Border(ColorF(1, 0, 0, 1), Border.Style.rect);
  border.width = 5.0f;
  parent.components.border = border;

  // Content rect: startX = 20 (border 5 + pad 15), startY = 15 (5 + 10)
  // availW = 300 - 10 - 30 = 260, availH = 200 - 10 - 20 = 170

  auto child = new Widget(parent, RectF(0, 0, 40, 30));
  auto childSz = new Size;
  childSz.margin = Insets(2, 3, 4, 5);
  child.components.size = childSz;

  auto a = new Anchor;
  a.right = 10.0f;
  a.bottom = 10.0f;
  child.components.anchor = a;
  handleAnchorComp(child);

  // x = startX (20) + availW (260) - width (40) - right (10) - margin.right (3) = 227
  assert(child.rect.x == 227);
  // y = startY (15) + availH (170) - height (30) - bottom (10) - margin.bottom (4) = 141
  assert(child.rect.y == 141);
}

// Dual anchors stretch auto mode and respect min/max constraints
unittest {
  auto parent = new Widget(null, RectF(0, 0, 200, 150));

  auto child = new Widget(parent, RectF(0, 0, 0, 0));
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
  auto parent = new Widget(null, RectF(0, 0, 300, 200));

  auto child = new Widget(parent, RectF(0, 0, 50, 40));
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
