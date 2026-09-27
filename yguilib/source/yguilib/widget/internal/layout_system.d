module yguilib.widget.internal.layout_system;

package(yguilib):
import std.array : Appender;
import yguilib.render : Renderer;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.widget;
import yguilib.widget.layout_components;
import yguilib.widget.drawing_components;
import yguilib.widget.internal.collect_visible : VisibleWidgets, VisibleWidget;
import yguilib.widget.internal.layout_dimension : computeDimension;
import yguilib.widget.internal.layout_content_size : calcContentSize,
  calcPaddingAndBorder;
import yguilib.widget.internal.layout_flex : alignChildCrossAxis,
  arrangeMainAxis, calcContentRect, computeJustifyOffsets, resolveFractionSizes;

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

  Appender!(Widget[]) childBuf;

  package(yguilib) static void handleSizeComp(
    VisibleWidget vw,
    Renderer r = null
  ) {
    handleSizeComp(vw.widget, r);
  }

  package(yguilib) static void handleSizeComp(Widget w, Renderer r = null) {
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

  /// Arranges children for a visible widget's flex container component.
  void handleFlexContainerComp(VisibleWidget vw) {
    handleFlexContainerComp(vw.widget);
  }

  /// Arranges children of a flex container widget according to flexbox rules.
  package(yguilib) void handleFlexContainerComp(Widget w) {
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
