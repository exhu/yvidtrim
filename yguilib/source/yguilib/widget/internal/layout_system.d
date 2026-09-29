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
  arrangeMainAxis, calcContentRect, computeJustifyOffsets, resolveFractionSizes,
  updateFlexChildTextHeight;
import yguilib.widget.internal.layout_anchor : handleAnchorComp;

final class LayoutSystem {
  /// expects visibleWidgets to include clipped children as well
  void layoutTree(Widget root, Renderer r, VisibleWidgets visibleWidgets) {
    assert(root !is null);
    assert(r !is null);
    assert(visibleWidgets !is null);

    if (!root.visible || visibleWidgets.length == 0) {
      return;
    }

    oldRectBuf.clear();
    foreach (ref vw; visibleWidgets) {
      oldRectBuf ~= vw.widget.rect;
    }
    const RectF[] oldRects = oldRectBuf[];

    // compute initial sizes: leaf to root
    foreach_reverse (VisibleWidget vw; visibleWidgets) {
      handleSizeComp(vw, r);
    }

    // compute position and sizes: root to leaf
    foreach (VisibleWidget vw; visibleWidgets) {
      handleAnchorComp(vw);
      handleFlexContainerComp(vw, r);
    }

    // Mark dirty if rect changed, and reset layoutDirty
    foreach (size_t i, ref vw; visibleWidgets) {
      if (vw.widget.rect != oldRects[i]) {
        vw.widget.dirty = true;
      }
      vw.widget.layoutDirty = false;
    }
    root.layoutDirty = false;
  }
private:

  Appender!(Widget[]) childBuf;
  Appender!(RectF[]) oldRectBuf;

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

  package(yguilib) static void handleAnchorComp(VisibleWidget vw) {
    handleAnchorComp(vw.widget);
  }

  package(yguilib) static void handleAnchorComp(Widget w) {
    .handleAnchorComp(w);
  }

  /// Arranges children for a visible widget's flex container component.
  void handleFlexContainerComp(VisibleWidget vw, Renderer r = null) {
    handleFlexContainerComp(vw.widget, r);
  }

  /// Arranges children of a flex container widget according to flexbox rules.
  package(yguilib) void handleFlexContainerComp(Widget w, Renderer r = null) {
    if (w is null) {
      return;
    }
    FlexContainer flexComp = w.components.flexContainer;
    if (flexComp is null || w.children.length == 0) {
      return;
    }

    childBuf.clear();
    foreach (child; w.children) {
      if (child.visible && child.components.anchor is null) {
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

    if (isRow) {
      if (r !is null) {
        foreach (child; visibleChildren) {
          updateFlexChildTextHeight(child, r);
        }
      }
    } else {
      if (flexComp.alignItems == AlignItems.stretch) {
        foreach (child; visibleChildren) {
          alignChildCrossAxis(
            child,
            isRow,
            flexComp.alignItems,
            contentCrossPos,
            contentCrossExtent
          );
          if (r !is null) {
            updateFlexChildTextHeight(child, r);
          }
        }
      }
    }

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

  // Test TextLabel with custom fontSize (24pt)
  auto bigLabelWidget = new Widget(null, RectF(0, 0, 10, 10));
  auto bigLabelSz = new Size;
  bigLabelSz.width = Dimension(0, SizingMode.auto_);
  bigLabelSz.height = Dimension(0, SizingMode.auto_);
  bigLabelSz.padding = Insets(2, 4, 2, 4);
  bigLabelWidget.components.size = bigLabelSz;
  bigLabelWidget.components.textLabel =
    new TextLabel("Test", ColorF(1, 1, 1, 1));
  bigLabelWidget.components.textLabel.fontSize = 24.0f;

  PointF bigTextDims = r.measureText("Test", 24.0f);
  assert(bigTextDims.x > textDims.x);
  assert(bigTextDims.y > textDims.y);

  auto bigVisible = collector.collectVisible(bigLabelWidget, r, true);
  ls.layoutTree(bigLabelWidget, r, bigVisible);

  assert(bigLabelWidget.rect.width == bigTextDims.x + 8);
  assert(bigLabelWidget.rect.height == bigTextDims.y + 4);
}

// Anchored widget inside flex container is out-of-flow
unittest {
  auto ls = new LayoutSystem;
  auto parent = new Widget(null, RectF(0, 0, 200, 100));

  auto flex = new FlexContainer;
  flex.direction = FlexDirection.row;
  flex.gap = 10;
  parent.components.flexContainer = flex;

  // Regular flex children
  auto c1 = new Widget(parent, RectF(0, 0, 40, 20));
  auto c2 = new Widget(parent, RectF(0, 0, 50, 20));

  // Anchored child positioned at bottom-right
  auto anchorChild = new Widget(parent, RectF(0, 0, 30, 30));
  auto a = new Anchor;
  a.right = 0.0f;
  a.bottom = 0.0f;
  anchorChild.components.anchor = a;

  ls.handleAnchorComp(anchorChild);
  ls.handleFlexContainerComp(parent);

  // Flex children are laid out sequentially along main axis ignoring
  // the out-of-flow anchorChild.
  assert(c1.rect.x == 0);
  assert(c2.rect.x == 50); // 40 + gap 10

  // Anchored child is at bottom-right of parent
  assert(anchorChild.rect.x == 170); // 200 - 30
  assert(anchorChild.rect.y == 70);  // 100 - 30
}

// Multiline TextLabel auto-height layout
unittest {
  import yguilib.clibs.sdl3 : yguilib_sdl3_init, yguilib_sdl3_quit;
  import yguilib.window : Window;
  import yguilib.widget.internal.collect_visible : VisibleWidgetsCollector;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_layout_multiline");
  win.create();
  scope(exit) win.destroy();

  auto r = new Renderer(320, 240);
  scope(exit) r.destroy();

  auto ls = new LayoutSystem;
  auto collector = new VisibleWidgetsCollector;

  // Single line TextLabel with newline when multiline is false
  auto sWidget = new Widget(null, RectF(0, 0, 10, 10));
  auto sSize = new Size;
  sSize.width = Dimension(0, SizingMode.auto_);
  sSize.height = Dimension(0, SizingMode.auto_);
  sWidget.components.size = sSize;
  sWidget.components.textLabel = new TextLabel(
    "Hello\r\nWorld",
    ColorF(1, 1, 1, 1)
  );

  auto sVisible = collector.collectVisible(sWidget, r, true);
  ls.layoutTree(sWidget, r, sVisible);
  PointF expectedSingle = r.measureText("Hello World");
  assert(sWidget.rect.width == expectedSingle.x);
  assert(sWidget.rect.height == expectedSingle.y);

  // Multiline TextLabel with explicit breaks
  auto mWidget = new Widget(null, RectF(0, 0, 10, 10));
  auto mSize = new Size;
  mSize.width = Dimension(0, SizingMode.auto_);
  mSize.height = Dimension(0, SizingMode.auto_);
  mWidget.components.size = mSize;
  auto mLabel = new TextLabel("Line 1\nLine 2", ColorF(1, 1, 1, 1));
  mLabel.multiline = true;
  mWidget.components.textLabel = mLabel;

  auto mVisible = collector.collectVisible(mWidget, r, true);
  ls.layoutTree(mWidget, r, mVisible);
  assert(mWidget.rect.height > expectedSingle.y);

  // Multiline TextLabel with fixed width and auto height (wrapping)
  auto wrapWidget = new Widget(null, RectF(0, 0, 10, 10));
  auto wrapSize = new Size;
  float line1W = r.measureText("Word one word two").x;
  wrapSize.width = Dimension(line1W + 5.0f, SizingMode.fixed);
  wrapSize.height = Dimension(0, SizingMode.auto_);
  wrapWidget.components.size = wrapSize;
  auto wrapLabel = new TextLabel(
    "Word one word two word three word four",
    ColorF(1, 1, 1, 1)
  );
  wrapLabel.multiline = true;
  wrapWidget.components.textLabel = wrapLabel;

  auto wrapVisible = collector.collectVisible(wrapWidget, r, true);
  ls.layoutTree(wrapWidget, r, wrapVisible);
  assert(wrapWidget.rect.width == line1W + 5.0f);
  assert(wrapWidget.rect.height > expectedSingle.y);
}

// TextLabel with Size.maxWidth under SizingMode.auto_ and flex column stretch
unittest {
  import yguilib.clibs.sdl3 : yguilib_sdl3_init, yguilib_sdl3_quit;
  import yguilib.window : Window;
  import yguilib.widget.internal.collect_visible : VisibleWidgetsCollector;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_layout_max_width");
  win.create();
  scope(exit) win.destroy();

  auto r = new Renderer(320, 240);
  scope(exit) r.destroy();

  auto ls = new LayoutSystem;
  auto collector = new VisibleWidgetsCollector;

  // Single-line with Size.maxWidth and ellipsis
  auto singleW = new Widget(null, RectF(0, 0, 10, 10));
  auto singleSz = new Size;
  singleSz.width = Dimension(0, SizingMode.auto_);
  singleSz.height = Dimension(0, SizingMode.auto_);
  const float fullW = r.measureText("A very long text that must truncate").x;
  singleSz.maxWidth = fullW * 0.5f;
  singleW.components.size = singleSz;
  auto singleLabel = new TextLabel(
    "A very long text that must truncate",
    ColorF(1, 1, 1, 1)
  );
  singleLabel.overflowEllipsis = true;
  singleW.components.textLabel = singleLabel;

  auto singleVis = collector.collectVisible(singleW, r, true);
  ls.layoutTree(singleW, r, singleVis);
  assert(singleW.rect.width <= singleSz.maxWidth);

  // Multiline with Size.maxWidth and auto width/height
  auto multiW = new Widget(null, RectF(0, 0, 10, 10));
  auto multiSz = new Size;
  multiSz.width = Dimension(0, SizingMode.auto_);
  multiSz.height = Dimension(0, SizingMode.auto_);
  const float twoWordsW = r.measureText("Word one word two").x;
  multiSz.maxWidth = twoWordsW + 5.0f;
  multiW.components.size = multiSz;
  auto multiLabel = new TextLabel(
    "Word one word two word three word four",
    ColorF(1, 1, 1, 1)
  );
  multiLabel.multiline = true;
  multiW.components.textLabel = multiLabel;

  auto multiVis = collector.collectVisible(multiW, r, true);
  ls.layoutTree(multiW, r, multiVis);
  assert(multiW.rect.width <= multiSz.maxWidth);
  const float singleH = r.measureText("Word").y;
  assert(multiW.rect.height > singleH);

  // Flex column with stretch and multiline text child
  auto colParent = new Widget(null, RectF(0, 0, twoWordsW + 10.0f, 300));
  auto colSz = new Size;
  colSz.width = Dimension(twoWordsW + 10.0f, SizingMode.fixed);
  colSz.height = Dimension(300, SizingMode.fixed);
  colParent.components.size = colSz;

  auto flex = new FlexContainer;
  flex.direction = FlexDirection.column;
  flex.alignItems = AlignItems.stretch;
  flex.gap = 5.0f;
  colParent.components.flexContainer = flex;

  auto textChild = new Widget(colParent, RectF(0, 0, 10, 10));
  auto textSz = new Size;
  textSz.width = Dimension(0, SizingMode.auto_);
  textSz.height = Dimension(0, SizingMode.auto_);
  textChild.components.size = textSz;
  auto label = new TextLabel(
    "Word one word two word three word four",
    ColorF(1, 1, 1, 1)
  );
  label.multiline = true;
  textChild.components.textLabel = label;

  auto secondChild = new Widget(colParent, RectF(0, 0, 10, 20));
  auto secondSz = new Size;
  secondSz.width = Dimension(0, SizingMode.auto_);
  secondSz.height = Dimension(20, SizingMode.fixed);
  secondChild.components.size = secondSz;

  auto colVis = collector.collectVisible(colParent, r, true);
  ls.layoutTree(colParent, r, colVis);

  assert(textChild.rect.width == twoWordsW + 10.0f);
  assert(textChild.rect.height > singleH);
  // secondChild must be below textChild, without overlap!
  assert(secondChild.rect.y >= textChild.rect.height + 5.0f);
}

