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
 */
class WidgetPainterSystem {
  void drawWidgets(Widget[] widgets, Renderer r) {
    foreach(w; widgets)
      drawWidget(w, r);
  }
private:
  static void drawWidget(Widget w, Renderer r) {
    if (w.clipContents)
      r.pushClipRect(w.rect);

      if (w.components.background !is null) {
        drawBackground(w, r);
      }
      if (w.components.textLabel !is null) {
        drawTextLabel(w, r);
      }
      if (w.components.border !is null) {
        drawBorder(w, r);
      }

    if (w.clipContents)
      r.popClipRect();
  }

  static void drawBackground(Widget w, Renderer r) {
    auto comp = w.components.background;
    final switch(comp.style) {
      case Background.Style.rect:
        r.drawFillRect(w.rect, comp.color);
        break;
      case Background.Style.round:
        r.drawFillRoundRect(w.rect, 5, comp.color);
        break;
      case Background.Style.none:{}
    }
  }

  static void drawBorder(Widget w, Renderer r) {
    auto comp = w.components.border;
    final switch(comp.style) {
      case Border.Style.rect:
        r.drawRect(w.rect, comp.color);
        break;
      case Border.Style.round:
        r.drawRoundRect(w.rect, 5, 2, comp.color);
        break;
      case Border.Style.roundDashed:
        r.drawRoundRectDashed(w.rect, 5, 2, 3, 1, comp.color);
        break;
      case Border.Style.none:{}
    }
  }

  static void drawTextLabel(Widget w, Renderer r) {
    auto comp = w.components.textLabel;
    r.drawText(comp.caption, PointF(w.rect.x, w.rect.y), comp.color);
  }
}
