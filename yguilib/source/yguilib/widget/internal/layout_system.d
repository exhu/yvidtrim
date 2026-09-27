module yguilib.widget.internal.layout_system;

package(yguilib):
import std.algorithm.comparison : max, min;
import std.array : Appender;
import std.math : round;
import yguilib.render : Renderer;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.widget;
import yguilib.widget.layout_components;
import yguilib.widget.drawing_components;
import yguilib.widget.internal.collect_visible : VisibleWidgets, VisibleWidget;

final class LayoutSystem {
  /// expects visibleWidgets to include clipped children as well
  void layoutTree(Widget root, Renderer r, VisibleWidgets visibleWidgets) {
    assert(root !is null);
    assert(r !is null);
    assert(visibleWidgets !is null);

    if (!root.visible || visibleWidgets.length == 0) {
      return;
    }

    // compute initial sizes: leaf to root
    foreach_reverse(VisibleWidget vw; visibleWidgets) {
      handleSizeComp(vw, r);
    }

    // compute position and sizes by flexContainers: root to leaf
    foreach(VisibleWidget vw; visibleWidgets) {
      handleFlexContainerComp(vw);
    }
  }
private:

  static void handleSizeComp(VisibleWidget vw, Renderer r = null) {
    handleSizeComp(vw.widget, r);
  }

  static void handleSizeComp(Widget w, Renderer r = null) {
    Size szComp = w.components.size;
    if (szComp is null) {
      return;
    }

    PointF contentSize;
    if (szComp.width.mode == SizingMode.auto_ ||
        szComp.height.mode == SizingMode.auto_) {
      contentSize = calcContentSize(w, r);
    }

    const PointF padBorder = calcPaddingAndBorder(szComp, w.components.border);

    w.rect.width = computeDimension(
      szComp.width,
      w.rect.width,
      contentSize.x,
      padBorder.x,
      szComp.minWidth,
      szComp.maxWidth
    );
    w.rect.height = computeDimension(
      szComp.height,
      w.rect.height,
      contentSize.y,
      padBorder.y,
      szComp.minHeight,
      szComp.maxHeight
    );
  }

  static float getBorderWidth(const Border borderComp) {
    if (borderComp !is null && borderComp.style != Border.Style.none) {
      return max(0.0f, borderComp.width);
    }
    return 0.0f;
  }

  static PointF calcPaddingAndBorder(
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

  static float resolveDimension(
    const Dimension dim,
    float currentVal,
    float contentDim,
    float padBorder,
    float minVal
  ) {
    switch (dim.mode) {
    case SizingMode.fixed:
      return dim.value;
    case SizingMode.auto_:
      return contentDim + padBorder;
    case SizingMode.fraction:
      return minVal;
    default:
      return currentVal;
    }
  }

  static float clampDimension(
    float val,
    float minVal,
    float maxVal
  ) {
    if (val > maxVal) {
      val = maxVal;
    }
    if (val < minVal) {
      val = minVal;
    }
    if (val < 0.0f) {
      val = 0.0f;
    }
    return val;
  }

  static float computeDimension(
    const Dimension dim,
    float currentVal,
    float contentDim,
    float padBorder,
    float minVal,
    float maxVal
  ) {
    const float resolved = resolveDimension(
      dim,
      currentVal,
      contentDim,
      padBorder,
      minVal
    );
    return clampDimension(resolved, minVal, maxVal);
  }

  static PointF calcContentSize(Widget w, Renderer r) {
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

  static bool tryCalcFlexContentSize(
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

  static bool tryCalcChildrenBoundingBox(
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

  static PointF calcTextContentSize(
    const TextLabel tl,
    Renderer r
  ) {
    if (tl !is null && r !is null && tl.caption.length > 0) {
      const PointF textSize = r.measureText(tl.caption);
      return PointF(max(0.0f, textSize.x), max(0.0f, textSize.y));
    }
    return PointF(0.0f, 0.0f);
  }


  Appender!(Widget[]) childBuf;

  /// Arranges children for a visible widget's flex container component.
  void handleFlexContainerComp(VisibleWidget vw) {
    handleFlexContainerComp(vw.widget);
  }

  /// Arranges children of a flex container widget according to flexbox rules.
  void handleFlexContainerComp(Widget w) {
    if (w is null) {
      return;
    }
    FlexContainer flexComp = w.components.flexContainer;
    if (flexComp is null || w.children.length == 0) {
      return;
    }

    childBuf.clear();
    foreach (child; w.children) {
      if (child.visible) {
        childBuf ~= child;
      }
    }
    Widget[] visibleChildren = childBuf[];
    if (visibleChildren.length == 0) {
      return;
    }

    const bool isRow = flexComp.direction == FlexDirection.row;
    const RectF contentRect = calcContentRect(w);
    const float contentMainPos = isRow ? contentRect.x : contentRect.y;
    const float contentMainExtent = isRow ? contentRect.width :
      contentRect.height;
    const float contentCrossPos = isRow ? contentRect.y : contentRect.x;
    const float contentCrossExtent = isRow ? contentRect.height :
      contentRect.width;

    resolveFractionSizes(
      visibleChildren,
      isRow,
      contentMainExtent,
      flexComp.gap
    );

    float startOffset = 0.0f;
    float gapBetween = 0.0f;
    computeJustifyOffsets(
      flexComp.justify,
      visibleChildren,
      isRow,
      contentMainPos,
      contentMainExtent,
      flexComp.gap,
      startOffset,
      gapBetween
    );

    arrangeMainAxis(visibleChildren, isRow, startOffset, gapBetween);

    foreach (child; visibleChildren) {
      alignChildCrossAxis(
        child,
        isRow,
        flexComp.alignItems,
        contentCrossPos,
        contentCrossExtent
      );
    }
  }

  /// Computes inner content area bounds deducting padding and border.
  private static RectF calcContentRect(const Widget w) {
    const float borderWidth = getBorderWidth(w.components.border);
    float padLeft = 0.0f;
    float padRight = 0.0f;
    float padTop = 0.0f;
    float padBottom = 0.0f;

    const Size szComp = w.components.size;
    if (szComp !is null) {
      padLeft = szComp.padding.left;
      padRight = szComp.padding.right;
      padTop = szComp.padding.top;
      padBottom = szComp.padding.bottom;
    }

    const float startX = borderWidth + padLeft;
    const float startY = borderWidth + padTop;
    const float availW = max(
      0.0f,
      w.rect.width - (borderWidth * 2.0f + padLeft + padRight)
    );
    const float availH = max(
      0.0f,
      w.rect.height - (borderWidth * 2.0f + padTop + padBottom)
    );

    return RectF(startX, startY, availW, availH);
  }

  /// Returns child's size on main axis (width for row, height for column).
  static float getMainSize(const Widget w, bool isRow) {
    return isRow ? w.rect.width : w.rect.height;
  }

  /// Sets child's size on main axis (width for row, height for column).
  static void setMainSize(Widget w, bool isRow, float val) {
    if (isRow) {
      w.rect.width = val;
    } else {
      w.rect.height = val;
    }
  }

  /// Returns child's size on cross axis (height for row, width for column).
  static float getCrossSize(const Widget w, bool isRow) {
    return isRow ? w.rect.height : w.rect.width;
  }

  /// Sets child's size on cross axis (height for row, width for column).
  static void setCrossSize(Widget w, bool isRow, float val) {
    if (isRow) {
      w.rect.height = val;
    } else {
      w.rect.width = val;
    }
  }

  /// Sets child's position on main axis (x for row, y for column).
  static void setMainPos(Widget w, bool isRow, float val) {
    if (isRow) {
      w.rect.x = val;
    } else {
      w.rect.y = val;
    }
  }

  /// Sets child's position on cross axis (y for row, x for column).
  static void setCrossPos(Widget w, bool isRow, float val) {
    if (isRow) {
      w.rect.y = val;
    } else {
      w.rect.x = val;
    }
  }

  /// Distributes remaining main-axis space to fraction sizing children.
  static void resolveFractionSizes(
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
        fixedSum += getMainSize(child, isRow);
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
  static void computeJustifyOffsets(
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
      totalChildrenSize += getMainSize(child, isRow);
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
  static void arrangeMainAxis(
    Widget[] children,
    bool isRow,
    float startOffset,
    float gapBetween
  ) {
    float currentPos = startOffset;
    foreach (child; children) {
      setMainPos(child, isRow, currentPos);
      currentPos += getMainSize(child, isRow) + gapBetween;
    }
  }

  /// Positions and sizes child along cross axis according to AlignItems.
  static void alignChildCrossAxis(
    Widget child,
    bool isRow,
    AlignItems alignItems,
    float contentCrossPos,
    float contentCrossExtent
  ) {
    final switch (alignItems) {
    case AlignItems.start:
      setCrossPos(child, isRow, contentCrossPos);
      break;

    case AlignItems.end:
      setCrossPos(
        child,
        isRow,
        contentCrossPos + contentCrossExtent - getCrossSize(child, isRow)
      );
      break;

    case AlignItems.center:
      const float offset = (
        contentCrossExtent - getCrossSize(child, isRow)
      ) * 0.5f;
      setCrossPos(child, isRow, contentCrossPos + round(offset));
      break;

    case AlignItems.stretch:
      setCrossPos(child, isRow, contentCrossPos);
      float targetSize = contentCrossExtent;
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
}

// Fixed sizing and null Size component handling
unittest {
  auto ls = new LayoutSystem;
  auto w = new Widget(null, RectF(10, 10, 50, 50));

  // No Size component -> rect remains untouched
  ls.handleSizeComp(w);
  assert(w.rect.width == 50);
  assert(w.rect.height == 50);

  // Fixed sizing
  auto sz = new Size;
  sz.width = Dimension(120, SizingMode.fixed);
  sz.height = Dimension(80, SizingMode.fixed);
  w.components.size = sz;

  ls.handleSizeComp(w);
  assert(w.rect.width == 120);
  assert(w.rect.height == 80);
}

// Auto sizing with padding and border
unittest {
  auto ls = new LayoutSystem;
  auto w = new Widget(null, RectF(0, 0, 0, 0));

  auto sz = new Size;
  sz.width = Dimension(0, SizingMode.auto_);
  sz.height = Dimension(0, SizingMode.auto_);
  sz.padding = Insets(5, 10, 15, 20); // top=5, right=10, bottom=15, left=20
  w.components.size = sz;

  auto border = new Border(ColorF(1, 0, 0, 1), Border.Style.rect);
  border.width = 3.0f;
  w.components.border = border;

  // Horizontal: padding (20+10) + border (3*2) = 36
  // Vertical: padding (5+15) + border (3*2) = 26
  ls.handleSizeComp(w);
  assert(w.rect.width == 36);
  assert(w.rect.height == 26);

  // Border.Style.none should not contribute to size
  border.style = Border.Style.none;
  ls.handleSizeComp(w);
  assert(w.rect.width == 30);
  assert(w.rect.height == 20);
}

// Min and max constraints and fraction initial sizing
unittest {
  auto ls = new LayoutSystem;
  auto w = new Widget(null, RectF(0, 0, 0, 0));

  auto sz = new Size;
  sz.width = Dimension(20, SizingMode.fixed);
  sz.height = Dimension(200, SizingMode.fixed);
  sz.minWidth = 50;
  sz.maxWidth = 100;
  sz.minHeight = 50;
  sz.maxHeight = 100;
  w.components.size = sz;

  // Clamped by minWidth (20 -> 50) and maxHeight (200 -> 100)
  ls.handleSizeComp(w);
  assert(w.rect.width == 50);
  assert(w.rect.height == 100);

  // Fraction mode sets initial size to minWidth / minHeight
  sz.width = Dimension(1, SizingMode.fraction);
  sz.height = Dimension(1, SizingMode.fraction);
  sz.minWidth = 40;
  sz.minHeight = 60;
  sz.maxWidth = 200;
  sz.maxHeight = 200;
  ls.handleSizeComp(w);
  assert(w.rect.width == 40);
  assert(w.rect.height == 60);

  // If minWidth > maxWidth, minWidth takes precedence
  sz.width = Dimension(80, SizingMode.fixed);
  sz.minWidth = 120;
  sz.maxWidth = 100;
  ls.handleSizeComp(w);
  assert(w.rect.width == 120);
}

// FlexContainer children intrinsic size calculation (row, column, gaps)
unittest {
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

  auto c1 = new Widget(parent, RectF(0, 0, 40, 25));
  auto c2 = new Widget(parent, RectF(0, 0, 60, 35));
  auto cHidden = new Widget(parent, RectF(0, 0, 100, 100));
  cHidden.visible = false;

  // Row: width = 40 + 60 + 10 = 110, height = max(25, 35) = 35
  ls.handleSizeComp(parent);
  assert(parent.rect.width == 110);
  assert(parent.rect.height == 35);

  // Column: width = max(40, 60) = 60, height = 25 + 35 + 10 = 70
  flex.direction = FlexDirection.column;
  ls.handleSizeComp(parent);
  assert(parent.rect.width == 60);
  assert(parent.rect.height == 70);
}

// Non-flex container with children: bounding box
unittest {
  auto ls = new LayoutSystem;
  auto parent = new Widget(null, RectF(0, 0, 0, 0));

  auto sz = new Size;
  sz.width = Dimension(0, SizingMode.auto_);
  sz.height = Dimension(0, SizingMode.auto_);
  parent.components.size = sz;

  auto c1 = new Widget(parent, RectF(10, 5, 40, 20)); // right=50, bottom=25
  auto c2 = new Widget(parent, RectF(20, 15, 60, 30)); // right=80, bottom=45

  ls.handleSizeComp(parent);
  assert(parent.rect.width == 80);
  assert(parent.rect.height == 45);
}

// TextLabel measurement and layoutTree bottom-up flow
unittest {
  import yguilib.clibs.sdl3 : yguilib_sdl3_init, yguilib_sdl3_quit;
  import yguilib.window : Window;
  import yguilib.widget.internal.collect_visible : VisibleWidgetsCollector;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_layout_text");
  win.create();
  scope(exit) win.destroy();

  auto r = new Renderer(320, 240);
  scope(exit) r.destroy();

  auto ls = new LayoutSystem;
  auto collector = new VisibleWidgetsCollector;

  auto labelWidget = new Widget(null, RectF(0, 0, 10, 10));
  auto labelSz = new Size;
  labelSz.width = Dimension(0, SizingMode.auto_);
  labelSz.height = Dimension(0, SizingMode.auto_);
  labelSz.padding = Insets(2, 4, 2, 4);
  labelWidget.components.size = labelSz;
  labelWidget.components.textLabel = new TextLabel("Test", ColorF(1, 1, 1, 1));

  PointF textDims = r.measureText("Test");
  assert(textDims.x > 0);
  assert(textDims.y > 0);

  auto visible = collector.collectVisible(labelWidget, r, true);
  ls.layoutTree(labelWidget, r, visible);

  assert(labelWidget.rect.width == textDims.x + 8);
  assert(labelWidget.rect.height == textDims.y + 4);
}

// FlexContainer row JustifyContent modes
unittest {
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
  import std.math : isClose;
  assert(cFixed.rect.width == 50);
  assert(isClose(cFrac1.rect.width, 250.0f / 3.0f, 0.01f));
  assert(isClose(cFrac2.rect.width, 500.0f / 3.0f, 0.01f));
  assert(cFixed.rect.x == 0);
  assert(cFrac1.rect.x == 60);
  assert(isClose(cFrac2.rect.x, 60.0f + 250.0f / 3.0f + 10.0f, 0.01f));
}

// Invisible child is ignored in flex layout
unittest {
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
