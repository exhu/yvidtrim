module yguilib.widget.internal.widget_painter;

package(yguilib):

import std.array : Appender;
import yguilib.render : PointF, RectF, Renderer, intersectRects;
import yguilib.widget.widget : Background, Border, TextLabel, Widget;

struct VisibleWidget {
  Widget widget;
  RectF absRect;
  bool hasClip;
  RectF clipRect;
}

/**
 * System responsible for rendering visible widgets.
 *
 * Off-screen widgets and their children are culled during visibility
 * collection (taking parent-relative coordinates into account).
 * Therefore, if a parent widget is off-screen, neither the parent nor any of
 * its children are drawn, and no Renderer calls are performed for them.
 *
 * Widget.rect is parent-relative; the absolute screen rect is resolved by
 * collectVisible and passed to drawWidgets via VisibleWidget.absRect.
 */
final class WidgetPainterSystem {
  void drawTree(Widget root, Renderer r) {
    if (root is null || !root.visible || r is null) {
      return;
    }
    visibleBuf.clear();
    const float vw = r.getLogicWidth();
    const float vh = r.getLogicHeight();
    collectVisible(root, 0.0f, 0.0f, vw, vh);
    drawWidgets(visibleBuf[], r);
  }

private:
  void drawWidgets(VisibleWidget[] widgets, Renderer r) {
    foreach (ref vw; widgets) {
      if (vw.hasClip) {
        r.pushClipRect(vw.clipRect);
      }
      drawWidget(vw.widget, vw.absRect, r);
      if (vw.hasClip) {
        r.popClipRect();
      }
    }
  }

  void collectVisible(
    Widget w,
    float parentX,
    float parentY,
    float vw,
    float vh,
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
    if (w.clipChildren) {
      childClipRect = parentHasClip
        ? intersectRects(parentClipRect, absRect)
        : absRect;
      childHasClip = true;
    }

    foreach (child; w.children) {
      collectVisible(child, absX, absY, vw, vh, childHasClip, childClipRect);
    }
  }

  Appender!(VisibleWidget[]) visibleBuf;

  static void drawWidget(Widget w, in RectF absRect, Renderer r) {
    if (w.clipContents)
      r.pushClipRect(absRect);

      if (w.components.background !is null) {
        drawBackground(w, absRect, r);
      }
      if (w.components.textLabel !is null) {
        drawTextLabel(w, absRect, r);
      }
      if (w.components.border !is null) {
        drawBorder(w, absRect, r);
      }

    if (w.clipContents)
      r.popClipRect();

    w.dirty = false;
  }

  static void drawBackground(Widget w, in RectF absRect, Renderer r) {
    auto comp = w.components.background;
    final switch(comp.style) {
      case Background.Style.rect:
        r.drawFillRect(absRect, comp.color);
        break;
      case Background.Style.round:
        r.drawFillRoundRect(absRect, 15, comp.color);
        break;
      case Background.Style.none:{}
    }
  }

  static void drawBorder(Widget w, in RectF absRect, Renderer r) {
    auto comp = w.components.border;
    final switch(comp.style) {
      case Border.Style.rect:
        r.drawRect(absRect, comp.color);
        break;
      case Border.Style.round:
        r.drawRoundRect(absRect, 10, 2, comp.color);
        break;
      case Border.Style.roundDashed:
        r.drawRoundRectDashed(absRect, 10, 2, 3, 1, comp.color);
        break;
      case Border.Style.none:{}
    }
  }

  static void drawTextLabel(Widget w, in RectF absRect, Renderer r) {
    auto comp = w.components.textLabel;
    r.drawText(comp.caption, PointF(absRect.x, absRect.y), comp.color);
  }
}

// Verifies collectVisible culling of off-screen parents and their children.
unittest {
  auto painter = new WidgetPainterSystem;

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

  painter.visibleBuf.clear();
  painter.collectVisible(root, 0.0f, 0.0f, 640.0f, 480.0f);

  auto collected = painter.visibleBuf[];
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
  auto painter = new WidgetPainterSystem;

  auto root = new Widget(null, RectF(0, 0, 640, 480));
  root.clipChildren = false;

  auto parent = new Widget(root, RectF(50, 50, 200, 100));
  parent.clipChildren = true;

  auto child = new Widget(parent, RectF(10, 10, 300, 50));
  child.clipChildren = false;

  auto grandChild = new Widget(child, RectF(5, 5, 20, 20));

  auto sibling = new Widget(root, RectF(300, 50, 100, 100));

  painter.visibleBuf.clear();
  painter.collectVisible(root, 0.0f, 0.0f, 640.0f, 480.0f);

  auto collected = painter.visibleBuf[];
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
}
