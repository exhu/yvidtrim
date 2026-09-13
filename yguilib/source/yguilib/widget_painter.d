module yguilib.widget_painter;
import yguilib.widget;
import yguilib.render;

void drawWidget(Widget w, Renderer r) {
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

private:

void drawBackground(Widget w, Renderer r) {
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

void drawBorder(Widget w, Renderer r) {
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

void drawTextLabel(Widget w, Renderer r) {
  auto comp = w.components.textLabel;
  r.drawText(comp.caption, PointF(w.rect.x, w.rect.y), comp.color);
}
