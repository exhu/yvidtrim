module yguilib.widget.internal.widget_painter;

package(yguilib):

import std.array : Appender;
import yguilib.render : Renderer;
import yguilib.render.render_types : PointF, RectF, intersectRects;
import yguilib.widget.drawing_components : Background, Border, TextLabel;
import yguilib.widget : Widget;
import yguilib.widget.internal.collect_visible : VisibleWidgets;

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
  void drawTree(VisibleWidgets widgets, Renderer r) {
    assert(widgets !is null);
    assert(r !is null);

    drawWidgets(widgets, r);
  }

private:
  void drawWidgets(VisibleWidgets widgets, Renderer r) {
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
        r.drawRoundRect(absRect, comp.cornerRadius, comp.width, comp.color);
        break;
      case Border.Style.roundDashed:
        r.drawRoundRectDashed(absRect, comp.cornerRadius, comp.width, 3, 1, comp.color);
        break;
      case Border.Style.none:{}
    }
  }

  static void drawTextLabel(Widget w, in RectF absRect, Renderer r) {
    auto comp = w.components.textLabel;
    r.drawText(comp.caption, PointF(absRect.x, absRect.y), comp.color);
  }
}
