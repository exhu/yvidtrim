module yguilib.widget.internal.collect_visible;

package(yguilib):
import std.array : Appender;
import yguilib.render;
import yguilib.render.render_types;
import yguilib.widget;

struct VisibleWidget {
  Widget widget;
  RectF absRect;
  bool hasClip;
  RectF clipRect;
}

alias VisibleWidgets = VisibleWidget[];

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
    if (!Renderer.isOnScreen(absRect, vw, vh)) {
      return;
    }

    visibleBuf ~= VisibleWidget(w, absRect, parentHasClip, parentClipRect);

    bool childHasClip = parentHasClip;
    RectF childClipRect = parentClipRect;
    if (!ignoreClipChildren && w.clipChildren) {
      childClipRect = parentHasClip
        ? intersectRects(parentClipRect, absRect)
        : absRect;
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
  auto collector = new VisibleWidgetsCollector;

  auto root = new Widget(null, RectF(0, 0, 640, 480));
  auto onScreenChild = new Widget(root, RectF(10, 10, 100, 100));
  auto hiddenChild = new Widget(root, RectF(120, 10, 50, 50));
  hiddenChild.visible = false;
  auto hiddenGrandChild = new Widget(hiddenChild, RectF(5, 5, 20, 20));

  // Off-screen parent (x = 700 is outside 640 width)
  auto offScreenParent = new Widget(root, RectF(700, 50, 100, 100));
  // Child has rect (5, 5) relative to offScreenParent (absX = 705)
  auto childOfOffScreen = new Widget(offScreenParent, RectF(5, 5, 50, 50));

  // Relative positioned child moving on-screen relative to an on-screen parent
  auto nestedOnScreen = new Widget(onScreenChild, RectF(10, 10, 40, 40));

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
  auto collector = new VisibleWidgetsCollector;

  auto root = new Widget(null, RectF(0, 0, 640, 480));
  root.clipChildren = false;

  auto parent = new Widget(root, RectF(50, 50, 200, 100));
  parent.clipChildren = true;

  auto child = new Widget(parent, RectF(10, 10, 300, 50));
  child.clipChildren = false;

  auto grandChild = new Widget(child, RectF(5, 5, 20, 20));

  auto sibling = new Widget(root, RectF(300, 50, 100, 100));

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
