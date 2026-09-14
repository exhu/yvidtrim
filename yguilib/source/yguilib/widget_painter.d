module yguilib.widget_painter;
import yguilib.widget;
import yguilib.render;

/**
 * System responsible for rendering visible widgets.
 *
 * Off-screen widgets and their children are culled during visibility
 * collection in UiSystem (taking parent-relative coordinates into account).
 * Therefore, if a parent widget is off-screen, neither the parent nor any of
 * its children are drawn, and no Renderer calls are performed for them.
 *
 * Widget.rect is parent-relative; the absolute screen rect is resolved by
 * UiSystem.collectVisible and passed here via VisibleWidget.absRect.
 */
class WidgetPainterSystem {
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
private:
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
