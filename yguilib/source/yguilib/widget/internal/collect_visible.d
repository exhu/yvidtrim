module yguilib.widget.internal.collect_visible;

package(yguilib):
import std.array : Appender;
import yguilib.render;
import yguilib.render.render_types;
import yguilib.widget;
import yguilib.widget.visible : VisibleWidget, VisibleWidgets;

final class VisibleWidgetsCollector {
  /// recalculate visible list to use for layout and painter system.
  /// When ignoreClipChildren is true, Widget.clipChildren is ignored and
  /// clipping rectangles are not propagated to children.
  VisibleWidgets collectVisible(
    Widget root,
    Renderer r,
    bool ignoreClipChildren = false
  ) {
    assert(root !is null);
    assert(r !is null);
    return collectVisible(
      root, r.getLogicWidth(), r.getLogicHeight(), ignoreClipChildren
    );
  }

  /// recalculate visible list for specific viewport dimensions
  VisibleWidgets collectVisible(
    Widget root,
    float vw,
    float vh,
    bool ignoreClipChildren = false
  ) {
    assert(root !is null);
    visibleBuf.clear();
    collectVisiblePrivate(root, 0.0f, 0.0f, vw, vh, ignoreClipChildren);
    return visibleBuf[];
  }

  /// Clears internal buffers when widgets are released.
  void clearBuffer() {
    visibleBuf.clear();
  }

private:
  void collectVisiblePrivate(
    Widget w,
    float parentX,
    float parentY,
    float vw,
    float vh,
    bool ignoreClipChildren,
    bool parentHasClip = false,
    RectF parentClipRect = RectF.init
  ) {
    if (!w.visible) {
      return;
    }
    const float absX = parentX + w.rect.x;
    const float absY = parentY + w.rect.y;
    const RectF absRect = RectF(absX, absY, w.rect.width, w.rect.height);
    if (!ignoreClipChildren && !Renderer.isOnScreen(absRect, vw, vh)) {
      return;
    }

    visibleBuf ~= VisibleWidget(w, absRect, parentHasClip, parentClipRect);

    bool childHasClip = parentHasClip;
    RectF childClipRect = parentClipRect;
    if (!ignoreClipChildren && w.clipChildren) {
      const RectF contentArea = w.getContentArea();
      const RectF absContentRect = RectF(
        absX + contentArea.x,
        absY + contentArea.y,
        contentArea.width,
        contentArea.height
      );
      childClipRect = parentHasClip
        ? intersectRects(parentClipRect, absContentRect)
        : absContentRect;
      childHasClip = true;
    }

    foreach (child; w.children) {
      collectVisiblePrivate(
        child,
        absX,
        absY,
        vw,
        vh,
        ignoreClipChildren,
        childHasClip,
        childClipRect
      );
    }
  }
  Appender!(VisibleWidget[]) visibleBuf;
}

// Verifies collectVisible culling of off-screen parents and their children.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto collector = new VisibleWidgetsCollector;

  auto root = fix.makeRoot(RectF(0, 0, 640, 480));
  auto onScreenChild = fix.makeChild(root, RectF(10, 10, 100, 100));
  auto hiddenChild = fix.makeChild(root, RectF(120, 10, 50, 50));
  hiddenChild.visible = false;
  auto hiddenGrandChild = fix.makeChild(hiddenChild, RectF(5, 5, 20, 20));

  // Off-screen parent (x = 700 is outside 640 width)
  auto offScreenParent = fix.makeChild(root, RectF(700, 50, 100, 100));
  // Child has rect (5, 5) relative to offScreenParent (absX = 705)
  auto childOfOffScreen = fix.makeChild(offScreenParent, RectF(5, 5, 50, 50));

  // Relative positioned child moving on-screen relative to an on-screen parent
  auto nestedOnScreen = fix.makeChild(onScreenChild, RectF(10, 10, 40, 40));

  auto collected = collector.collectVisible(root, 640.0f, 480.0f);
  assert(collected.length == 3);
  assert(collected[0].widget is root);
  assert(collected[0].absRect == RectF(0, 0, 640, 480));
  assert(collected[1].widget is onScreenChild);
  assert(collected[1].absRect == RectF(10, 10, 100, 100));
  assert(collected[2].widget is nestedOnScreen);
  assert(collected[2].absRect == RectF(20, 20, 40, 40));
}

// Verifies collectVisible clipChildren propagation.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto collector = new VisibleWidgetsCollector;

  auto root = fix.makeRoot(RectF(0, 0, 640, 480));
  root.clipChildren = false;

  auto parent = fix.makeChild(root, RectF(50, 50, 200, 100));
  parent.clipChildren = true;

  auto child = fix.makeChild(parent, RectF(10, 10, 300, 50));
  child.clipChildren = false;

  auto grandChild = fix.makeChild(child, RectF(5, 5, 20, 20));

  auto sibling = fix.makeChild(root, RectF(300, 50, 100, 100));

  auto collected = collector.collectVisible(root, 640.0f, 480.0f);
  assert(collected.length == 5);

  // root: no clip
  assert(collected[0].widget is root);
  assert(!collected[0].hasClip);

  // parent: no clip (its ancestors do not clip)
  assert(collected[1].widget is parent);
  assert(!collected[1].hasClip);

  // child: should have parent's absRect as clipRect
  assert(collected[2].widget is child);
  assert(collected[2].hasClip);
  assert(collected[2].clipRect == RectF(50, 50, 200, 100));

  // grandChild: should also inherit parent's clipRect
  assert(collected[3].widget is grandChild);
  assert(collected[3].hasClip);
  assert(collected[3].clipRect == RectF(50, 50, 200, 100));

  // sibling: should not have clip
  assert(collected[4].widget is sibling);
  assert(!collected[4].hasClip);

  // When ignoreClipChildren is true, clipChildren is ignored
  auto collectedIgnored = collector.collectVisible(root, 640.0f, 480.0f, true);
  assert(collectedIgnored.length == 5);
  foreach (vw; collectedIgnored) {
    assert(!vw.hasClip);
  }
}
