module yguilib.widget.internal.layout_flex;

package(yguilib):
import std.algorithm.comparison : max;
import std.math : round;
import yguilib.render : Renderer;
import yguilib.render.render_types : PointF, RectF;
import yguilib.widget : Widget;
import yguilib.widget.layout_components;
import yguilib.widget.drawing_components : Border;
import yguilib.widget.internal.layout_axis;
import yguilib.widget.internal.layout_content_size : calcPaddingAndBorder,
  calcTextContentSize;
import yguilib.widget.internal.layout_dimension : clampDimension;

/// Computes inner content area bounds deducting padding and border.
RectF calcContentRect(const Widget w) {
  return w.getContentArea();
}

/// Re-measures and updates auto-height for a child with TextLabel after its
/// width has been resolved or stretched by flex container layout.
void updateFlexChildTextHeight(Widget child, Renderer r) {
  if (child is null || r is null || child.components.textLabel is null) {
    return;
  }
  const Size sz = child.components.size;
  if (sz is null || sz.height.mode != SizingMode.auto_) {
    return;
  }

  const PointF padBorder = calcPaddingAndBorder(sz, child.components.border);
  const float availW = max(0.0f, child.rect.width - padBorder.x);
  const float availH = (sz.maxHeight < float.infinity && sz.maxHeight > 0.0f)
    ? max(0.0f, sz.maxHeight - padBorder.y)
    : 0.0f;

  const PointF textSize = calcTextContentSize(
    child.components.textLabel,
    r,
    availW,
    availH
  );

  child.rect.height = clampDimension(
    textSize.y + padBorder.y,
    sz.minHeight,
    sz.maxHeight
  );
}

/// Distributes remaining main-axis space to fraction sizing children.
void resolveFractionSizes(
  Widget[] children,
  bool isRow,
  float contentMainExtent,
  float gap
) {
  float fixedSum = 0.0f;
  float totalWeight = 0.0f;
  size_t fractionCount = 0;

  foreach (child; children) {
    const Size szComp = child.components.size;
    const bool isFraction = szComp !is null && (
      isRow
        ? szComp.width.mode == SizingMode.fraction
        : szComp.height.mode == SizingMode.fraction
    );

    if (isFraction) {
      const float wVal = isRow ? szComp.width.value : szComp.height.value;
      totalWeight += wVal > 0.0f ? wVal : 1.0f;
      fractionCount++;
    } else {
      fixedSum += getMainOuterSize(child, isRow);
    }
  }

  if (fractionCount == 0) {
    return;
  }

  const float totalGaps = children.length > 1
    ? gap * (children.length - 1)
    : 0.0f;
  const float freeSpace = max(
    0.0f,
    contentMainExtent - fixedSum - totalGaps
  );

  foreach (child; children) {
    const Size szComp = child.components.size;
    const bool isFraction = szComp !is null && (
      isRow
        ? szComp.width.mode == SizingMode.fraction
        : szComp.height.mode == SizingMode.fraction
    );

    if (!isFraction) {
      continue;
    }

    const float wVal = isRow ? szComp.width.value : szComp.height.value;
    const float weight = wVal > 0.0f ? wVal : 1.0f;
    float allocated = totalWeight > 0.0f
      ? (freeSpace * weight) / totalWeight
      : 0.0f;

    const float minVal = isRow ? szComp.minWidth : szComp.minHeight;
    const float maxVal = isRow ? szComp.maxWidth : szComp.maxHeight;
    allocated = clampDimension(allocated, minVal, maxVal);

    setMainSize(child, isRow, allocated);
  }
}

/// Computes start offset and gap between children for JustifyContent modes.
void computeJustifyOffsets(
  JustifyContent justify,
  Widget[] children,
  bool isRow,
  float contentMainPos,
  float contentMainExtent,
  float gap,
  out float startOffset,
  out float gapBetween
) {
  float totalChildrenSize = 0.0f;
  foreach (child; children) {
    totalChildrenSize += getMainOuterSize(child, isRow);
  }

  const size_t count = children.length;
  const float totalGaps = count > 1 ? gap * (count - 1) : 0.0f;
  const float freeSpace = contentMainExtent - totalChildrenSize - totalGaps;

  final switch (justify) {
  case JustifyContent.start:
    startOffset = contentMainPos;
    gapBetween = gap;
    break;

  case JustifyContent.end:
    startOffset = contentMainPos + max(0.0f, freeSpace);
    gapBetween = gap;
    break;

  case JustifyContent.center:
    startOffset = contentMainPos + round(max(0.0f, freeSpace) * 0.5f);
    gapBetween = gap;
    break;

  case JustifyContent.spaceBetween:
    startOffset = contentMainPos;
    if (count > 1 && freeSpace > 0.0f) {
      gapBetween = gap + (freeSpace / (count - 1));
    } else {
      gapBetween = count > 1 ? gap : 0.0f;
    }
    break;
  }
}

/// Positions children sequentially along the main axis.
void arrangeMainAxis(
  Widget[] children,
  bool isRow,
  float startOffset,
  float gapBetween
) {
  float currentPos = startOffset;
  foreach (child; children) {
    setMainPos(child, isRow, currentPos + getMainMarginStart(child, isRow));
    currentPos += getMainOuterSize(child, isRow) + gapBetween;
  }
}

/// Positions and sizes child along cross axis according to AlignItems.
void alignChildCrossAxis(
  Widget child,
  bool isRow,
  AlignItems alignItems,
  float contentCrossPos,
  float contentCrossExtent
) {
  final switch (alignItems) {
  case AlignItems.start:
    setCrossPos(
      child,
      isRow,
      contentCrossPos + getCrossMarginStart(child, isRow)
    );
    break;

  case AlignItems.end:
    setCrossPos(
      child,
      isRow,
      contentCrossPos + contentCrossExtent
        - getCrossMarginEnd(child, isRow)
        - getCrossSize(child, isRow)
    );
    break;

  case AlignItems.center:
    const float crossMs = getCrossMarginStart(child, isRow);
    const float crossMe = getCrossMarginEnd(child, isRow);
    const float innerExtent = contentCrossExtent - crossMs - crossMe;
    const float offset = (
      innerExtent - getCrossSize(child, isRow)
    ) * 0.5f;
    setCrossPos(child, isRow, contentCrossPos + crossMs + round(offset));
    break;

  case AlignItems.stretch:
    setCrossPos(
      child,
      isRow,
      contentCrossPos + getCrossMarginStart(child, isRow)
    );
    float targetSize = max(
      0.0f,
      contentCrossExtent - getCrossMarginStart(child, isRow)
        - getCrossMarginEnd(child, isRow)
    );
    const Size szComp = child.components.size;
    if (szComp !is null) {
      const float minCross = isRow ? szComp.minHeight : szComp.minWidth;
      const float maxCross = isRow ? szComp.maxHeight : szComp.maxWidth;
      targetSize = clampDimension(targetSize, minCross, maxCross);
    }
    setCrossSize(child, isRow, targetSize);
    break;
  }
}

// FlexContainer row JustifyContent modes
unittest {
  import yguilib.render.render_types : RectF;
  import yguilib.widget.internal.layout_system : LayoutSystem;

  auto ls = new LayoutSystem;
  auto parent = new Widget(null, RectF(0, 0, 200, 100));
  auto flex = new FlexContainer;
  flex.direction = FlexDirection.row;
  flex.gap = 10;
  parent.components.flexContainer = flex;

  auto c1 = new Widget(parent, RectF(0, 0, 40, 20));
  auto c2 = new Widget(parent, RectF(0, 0, 50, 30));

  // JustifyContent.start
  flex.justify = JustifyContent.start;
  flex.alignItems = AlignItems.start;
  ls.handleFlexContainerComp(parent);
  assert(c1.rect.x == 0);
  assert(c1.rect.y == 0);
  assert(c2.rect.x == 50); // 40 + gap(10)
  assert(c2.rect.y == 0);

  // JustifyContent.end: free space = 200 - (40 + 50 + 10) = 100
  flex.justify = JustifyContent.end;
  ls.handleFlexContainerComp(parent);
  assert(c1.rect.x == 100);
  assert(c2.rect.x == 150);

  // JustifyContent.center: offset = 100 * 0.5 = 50
  flex.justify = JustifyContent.center;
  ls.handleFlexContainerComp(parent);
  assert(c1.rect.x == 50);
  assert(c2.rect.x == 100);

  // JustifyContent.spaceBetween: gap = 10 + 100 / (2 - 1) = 110
  flex.justify = JustifyContent.spaceBetween;
  ls.handleFlexContainerComp(parent);
  assert(c1.rect.x == 0);
  assert(c2.rect.x == 150); // 200 - 50 = 150
}

// FlexContainer AlignItems modes in row
unittest {
  import yguilib.render.render_types : RectF;
  import yguilib.widget.internal.layout_system : LayoutSystem;

  auto ls = new LayoutSystem;
  auto parent = new Widget(null, RectF(0, 0, 200, 100));
  auto flex = new FlexContainer;
  flex.direction = FlexDirection.row;
  parent.components.flexContainer = flex;

  auto c = new Widget(parent, RectF(0, 0, 40, 20));

  // AlignItems.start
  flex.alignItems = AlignItems.start;
  ls.handleFlexContainerComp(parent);
  assert(c.rect.y == 0);
  assert(c.rect.height == 20);

  // AlignItems.end
  flex.alignItems = AlignItems.end;
  ls.handleFlexContainerComp(parent);
  assert(c.rect.y == 80); // 100 - 20

  // AlignItems.center
  flex.alignItems = AlignItems.center;
  ls.handleFlexContainerComp(parent);
  assert(c.rect.y == 40); // (100 - 20) / 2

  // AlignItems.stretch
  flex.alignItems = AlignItems.stretch;
  ls.handleFlexContainerComp(parent);
  assert(c.rect.y == 0);
  assert(c.rect.height == 100);
}

// FlexContainer column layout
unittest {
  import yguilib.render.render_types : RectF;
  import yguilib.widget.internal.layout_system : LayoutSystem;

  auto ls = new LayoutSystem;
  auto parent = new Widget(null, RectF(0, 0, 100, 200));
  auto flex = new FlexContainer;
  flex.direction = FlexDirection.column;
  flex.gap = 10;
  parent.components.flexContainer = flex;

  auto c1 = new Widget(parent, RectF(0, 0, 30, 40));
  auto c2 = new Widget(parent, RectF(0, 0, 50, 50));

  // JustifyContent.start, AlignItems.center
  flex.justify = JustifyContent.start;
  flex.alignItems = AlignItems.center;
  ls.handleFlexContainerComp(parent);
  assert(c1.rect.y == 0);
  assert(c1.rect.x == 35); // (100 - 30) / 2
  assert(c2.rect.y == 50); // 40 + 10
  assert(c2.rect.x == 25); // (100 - 50) / 2

  // JustifyContent.spaceBetween: freeSpace = 200 - (40 + 50 + 10) = 100
  // total gap = 10 + 100 = 110
  flex.justify = JustifyContent.spaceBetween;
  ls.handleFlexContainerComp(parent);
  assert(c1.rect.y == 0);
  assert(c2.rect.y == 150); // 200 - 50
}

// FlexContainer SizingMode.fraction distribution
unittest {
  import std.math : isClose;
  import yguilib.render.render_types : RectF;
  import yguilib.widget.internal.layout_system : LayoutSystem;

  auto ls = new LayoutSystem;
  auto parent = new Widget(null, RectF(0, 0, 320, 100));
  auto flex = new FlexContainer;
  flex.direction = FlexDirection.row;
  flex.gap = 10;
  parent.components.flexContainer = flex;

  // Fixed child: 50
  auto cFixed = new Widget(parent, RectF(0, 0, 50, 40));
  auto szFixed = new Size;
  szFixed.width = Dimension(50, SizingMode.fixed);
  cFixed.components.size = szFixed;

  // Fraction child 1: weight 1
  auto cFrac1 = new Widget(parent, RectF(0, 0, 0, 40));
  auto szFrac1 = new Size;
  szFrac1.width = Dimension(1, SizingMode.fraction);
  cFrac1.components.size = szFrac1;

  // Fraction child 2: weight 2
  auto cFrac2 = new Widget(parent, RectF(0, 0, 0, 40));
  auto szFrac2 = new Size;
  szFrac2.width = Dimension(2, SizingMode.fraction);
  cFrac2.components.size = szFrac2;

  // Total free space: 320 - 50 (fixed) - 20 (2 gaps of 10) = 250
  // Total weight: 1 + 2 = 3
  // cFrac1: 250 * 1/3 = 83.333...
  // cFrac2: 250 * 2/3 = 166.666...
  ls.handleFlexContainerComp(parent);
  assert(cFixed.rect.width == 50);
  assert(isClose(cFrac1.rect.width, 250.0f / 3.0f, 0.01f));
  assert(isClose(cFrac2.rect.width, 500.0f / 3.0f, 0.01f));
  assert(cFixed.rect.x == 0);
  assert(cFrac1.rect.x == 60);
  assert(isClose(cFrac2.rect.x, 60.0f + 250.0f / 3.0f + 10.0f, 0.01f));
}

// Invisible child is ignored in flex layout
unittest {
  import yguilib.render.render_types : RectF;
  import yguilib.widget.internal.layout_system : LayoutSystem;

  auto ls = new LayoutSystem;
  auto parent = new Widget(null, RectF(0, 0, 200, 100));
  auto flex = new FlexContainer;
  flex.direction = FlexDirection.row;
  flex.gap = 10;
  parent.components.flexContainer = flex;

  auto c1 = new Widget(parent, RectF(0, 0, 40, 20));
  auto cHidden = new Widget(parent, RectF(0, 0, 80, 20));
  cHidden.visible = false;
  auto c2 = new Widget(parent, RectF(0, 0, 50, 30));

  ls.handleFlexContainerComp(parent);
  assert(c1.rect.x == 0);
  // cHidden is skipped, so gap is only between c1 and c2
  assert(c2.rect.x == 50); // 40 + 10
}

// Parent padding and border offset children and shrink content area
unittest {
  import yguilib.render.render_types : ColorF, RectF;
  import yguilib.widget.drawing_components : Border;
  import yguilib.widget.internal.layout_system : LayoutSystem;

  auto ls = new LayoutSystem;
  auto parent = new Widget(null, RectF(0, 0, 200, 100));
  auto flex = new FlexContainer;
  flex.direction = FlexDirection.row;
  parent.components.flexContainer = flex;

  auto sz = new Size;
  sz.padding = Insets(10, 15, 20, 25); // top=10, right=15, bottom=20, left=25
  parent.components.size = sz;

  auto border = new Border(ColorF(1, 0, 0, 1), Border.Style.rect);
  border.width = 5.0f;
  parent.components.border = border;

  // Inset left = 25 + 5 = 30, inset top = 10 + 5 = 15
  // Content width = 200 - (30 + 15 + 5) = 150
  // Content height = 100 - (15 + 20 + 5) = 60
  auto c = new Widget(parent, RectF(0, 0, 50, 20));
  ls.handleFlexContainerComp(parent);

  assert(c.rect.x == 30);
  assert(c.rect.y == 15);

  flex.alignItems = AlignItems.stretch;
  ls.handleFlexContainerComp(parent);
  assert(c.rect.height == 60);
}

// Child margins on main axis in row
unittest {
  import yguilib.render.render_types : RectF;
  import yguilib.widget.internal.layout_system : LayoutSystem;

  auto ls = new LayoutSystem;
  auto parent = new Widget(null, RectF(0, 0, 200, 100));
  auto flex = new FlexContainer;
  flex.direction = FlexDirection.row;
  flex.gap = 10;
  parent.components.flexContainer = flex;

  auto c1 = new Widget(parent, RectF(0, 0, 40, 20));
  auto sz1 = new Size;
  sz1.margin = Insets(0, 15, 0, 5); // left=5, right=15
  c1.components.size = sz1;

  auto c2 = new Widget(parent, RectF(0, 0, 50, 30));
  auto sz2 = new Size;
  sz2.margin = Insets(0, 20, 0, 10); // left=10, right=20
  c2.components.size = sz2;

  ls.handleFlexContainerComp(parent);
  // c1: x = 0 + left_margin(5) = 5
  assert(c1.rect.x == 5);
  assert(c1.rect.width == 40);
  // c2: x = outer_c1(5 + 40 + 15 = 60) + gap(10) + left_margin(10) = 80
  assert(c2.rect.x == 80);
  assert(c2.rect.width == 50);
}

// Child margins on cross axis with AlignItems modes
unittest {
  import yguilib.render.render_types : RectF;
  import yguilib.widget.internal.layout_system : LayoutSystem;

  auto ls = new LayoutSystem;
  auto parent = new Widget(null, RectF(0, 0, 200, 100));
  auto flex = new FlexContainer;
  flex.direction = FlexDirection.row;
  parent.components.flexContainer = flex;

  auto c = new Widget(parent, RectF(0, 0, 40, 20));
  auto sz = new Size;
  sz.margin = Insets(10, 0, 20, 0); // top=10, bottom=20
  c.components.size = sz;

  // AlignItems.start: top margin offset
  flex.alignItems = AlignItems.start;
  ls.handleFlexContainerComp(parent);
  assert(c.rect.y == 10);
  assert(c.rect.height == 20);

  // AlignItems.end: bottom margin offset (100 - 20(margin) - 20(height) = 60)
  flex.alignItems = AlignItems.end;
  ls.handleFlexContainerComp(parent);
  assert(c.rect.y == 60);

  // AlignItems.center:
  // innerExtent = 100 - 10 - 20 = 70
  // offset = (70 - 20) / 2 = 25
  // y = 10 + 25 = 35
  flex.alignItems = AlignItems.center;
  ls.handleFlexContainerComp(parent);
  assert(c.rect.y == 35);

  // AlignItems.stretch:
  // y = 10, height = 100 - 10 - 20 = 70
  flex.alignItems = AlignItems.stretch;
  ls.handleFlexContainerComp(parent);
  assert(c.rect.y == 10);
  assert(c.rect.height == 70);
}

// Free space and fraction sizing respects sibling margins
unittest {
  import yguilib.render.render_types : RectF;
  import yguilib.widget.internal.layout_system : LayoutSystem;

  auto ls = new LayoutSystem;
  auto parent = new Widget(null, RectF(0, 0, 320, 100));
  auto flex = new FlexContainer;
  flex.direction = FlexDirection.row;
  flex.gap = 10;
  parent.components.flexContainer = flex;

  auto cFixed = new Widget(parent, RectF(0, 0, 50, 40));
  auto szFixed = new Size;
  szFixed.width = Dimension(50, SizingMode.fixed);
  szFixed.margin = Insets(0, 10, 0, 10); // outer width = 10 + 50 + 10 = 70
  cFixed.components.size = szFixed;

  auto cFrac = new Widget(parent, RectF(0, 0, 0, 40));
  auto szFrac = new Size;
  szFrac.width = Dimension(1, SizingMode.fraction);
  szFrac.margin = Insets(0, 5, 0, 5);
  cFrac.components.size = szFrac;

  // Free space = 320 - outerFixed(70) - gap(10) = 240
  // cFrac width = 240
  ls.handleFlexContainerComp(parent);
  assert(cFixed.rect.x == 10);
  assert(cFixed.rect.width == 50);
  assert(cFrac.rect.width == 240);
  // cFrac pos: outerFixed(70) + gap(10) + fracMarginLeft(5) = 85
  assert(cFrac.rect.x == 85);
}

// Auto-size of parent flex container includes child margins
unittest {
  import yguilib.render.render_types : RectF;
  import yguilib.widget.internal.layout_system : LayoutSystem;

  auto ls = new LayoutSystem;
  auto parent = new Widget(null, RectF(0, 0, 0, 0));

  auto parentSz = new Size;
  parentSz.width = Dimension(0, SizingMode.auto_);
  parentSz.height = Dimension(0, SizingMode.auto_);
  parent.components.size = parentSz;

  auto flex = new FlexContainer;
  flex.direction = FlexDirection.row;
  flex.gap = 10;
  parent.components.flexContainer = flex;

  auto c1 = new Widget(parent, RectF(0, 0, 40, 20));
  auto sz1 = new Size;
  sz1.margin = Insets(5, 10, 15, 20); // top=5, right=10, bottom=15, left=20
  c1.components.size = sz1;

  auto c2 = new Widget(parent, RectF(0, 0, 50, 30));
  auto sz2 = new Size;
  sz2.margin = Insets(10, 5, 5, 15); // top=10, right=5, bottom=5, left=15
  c2.components.size = sz2;

  // Row:
  // c1 outer: width = 40 + 20 + 10 = 70, height = 20 + 5 + 15 = 40
  // c2 outer: width = 50 + 15 + 5 = 70, height = 30 + 10 + 5 = 45
  // Parent width = 70 + 70 + gap(10) = 150
  // Parent height = max(40, 45) = 45
  ls.handleSizeComp(parent);
  assert(parent.rect.width == 150);
  assert(parent.rect.height == 45);
}
