module yguilib.widget.internal.widget_painter;

package(yguilib):

import std.array : Appender;
import std.math : isFinite;
import yguilib.render : Renderer;
import yguilib.render.font : Font, defaultFontPtSize;
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
    if (w.components.background !is null) {
      drawBackground(w, absRect, r);
    }

    const RectF contentArea = w.getContentArea();
    const RectF absContentRect = RectF(
      absRect.x + contentArea.x,
      absRect.y + contentArea.y,
      contentArea.width,
      contentArea.height
    );

    if (w.clipContents) {
      r.pushClipRect(absContentRect);
    }

    if (w.components.textLabel !is null) {
      drawTextLabel(w, absContentRect, r);
    }

    if (w.clipContents) {
      r.popClipRect();
    }

    if (w.components.border !is null) {
      drawBorder(w, absRect, r);
    }

    w.dirty = false;
  }

  static void drawBackground(Widget w, in RectF absRect, Renderer r) {
    auto comp = w.components.background;
    final switch(comp.style) {
      case Background.Style.rect:
        r.drawFillRect(absRect, comp.color);
        break;
      case Background.Style.round:
        r.drawFillRoundRect(absRect, comp.cornerRadius, comp.color);
        break;
      case Background.Style.none:{}
    }
  }

  static void drawBorder(Widget w, in RectF absRect, Renderer r) {
    auto comp = w.components.border;
    final switch(comp.style) {
      case Border.Style.rect:
        r.drawRect(absRect, comp.width, comp.color);
        break;
      case Border.Style.dashed:
        r.drawRectDashed(
          absRect, comp.width, comp.dashLen, comp.gap, comp.color
        );
        break;
      case Border.Style.round:
        r.drawRoundRect(absRect, comp.cornerRadius, comp.width, comp.color);
        break;
      case Border.Style.roundDashed:
        r.drawRoundRectDashed(
          absRect, comp.cornerRadius, comp.width, comp.dashLen, comp.gap,
          comp.color
        );
        break;
      case Border.Style.none:{}
    }
  }

  static void drawTextLabel(Widget w, in RectF absContentRect, Renderer r) {
    auto comp = w.components.textLabel;
    Font font = r.getFont(comp.fontSize, comp.font);
    r.drawText(
      comp.caption,
      PointF(absContentRect.x, absContentRect.y),
      comp.color,
      font
    );
  }
}

unittest {
  import yguilib.clibs.sdl3;
  import yguilib.render.font : defaultFontPtSize;
  import yguilib.render.render_types : ColorF;
  import yguilib.widget.drawing_components : Background, Border, TextLabel;
  import yguilib.widget.internal.collect_visible : VisibleWidgetsCollector;
  import yguilib.widget.layout_components : Insets, Size;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_widget_painter");
  win.create();
  scope(exit) win.destroy();

  auto renderer = new Renderer(320, 240);
  scope(exit) renderer.destroy();

  auto w = new Widget(null, RectF(10, 20, 100, 80));
  w.components.background = new Background(ColorF(0.2f, 0.2f, 0.2f, 1.0f));
  w.components.border = new Border(ColorF(1.0f, 0.0f, 0.0f, 1.0f));
  w.components.border.width = 2.0f;
  w.components.size = new Size();
  w.components.size.padding = Insets(5, 5, 5, 5);
  w.components.textLabel = new TextLabel(
    "Hello",
    ColorF(1.0f, 1.0f, 1.0f, 1.0f)
  );
  w.clipContents = true;

  auto collector = new VisibleWidgetsCollector;
  auto widgets = collector.collectVisible(w, 320.0f, 240.0f);

  auto painter = new WidgetPainterSystem;
  painter.drawTree(widgets, renderer);

  assert(!w.dirty);

  // Test TextLabel with custom fontSize (default font is never mutated)
  w.components.textLabel.fontSize = 24.0f;
  w.dirty = true;
  widgets = collector.collectVisible(w, 320.0f, 240.0f);
  painter.drawTree(widgets, renderer);
  assert(renderer.getDefaultFont().size == defaultFontPtSize);
  assert(renderer.getFont(24.0f).size == 24.0f);

  // Test fallback when fontSize is 0.0f
  w.components.textLabel.fontSize = 0.0f;
  w.dirty = true;
  widgets = collector.collectVisible(w, 320.0f, 240.0f);
  painter.drawTree(widgets, renderer);
  assert(renderer.getDefaultFont().size == defaultFontPtSize);

  // Test fallback when fontSize is negative
  w.components.textLabel.fontSize = -5.0f;
  w.dirty = true;
  widgets = collector.collectVisible(w, 320.0f, 240.0f);
  painter.drawTree(widgets, renderer);
  assert(renderer.getDefaultFont().size == defaultFontPtSize);

  // Test fallback when fontSize is infinity
  w.components.textLabel.fontSize = float.infinity;
  w.dirty = true;
  widgets = collector.collectVisible(w, 320.0f, 240.0f);
  painter.drawTree(widgets, renderer);
  assert(renderer.getDefaultFont().size == defaultFontPtSize);

  // Test fallback when fontSize is NaN
  w.components.textLabel.fontSize = float.nan;
  w.dirty = true;
  widgets = collector.collectVisible(w, 320.0f, 240.0f);
  painter.drawTree(widgets, renderer);
  assert(renderer.getDefaultFont().size == defaultFontPtSize);

  // Test multiple widgets with different font sizes
  auto root = new Widget(null, RectF(0, 0, 320, 240));
  auto child1 = new Widget(root, RectF(0, 0, 100, 30));
  child1.components.textLabel = new TextLabel("Title", ColorF(1, 1, 1, 1));
  child1.components.textLabel.fontSize = 18.0f;

  auto child2 = new Widget(root, RectF(0, 35, 100, 30));
  child2.components.textLabel = new TextLabel("Subtitle", ColorF(1, 1, 1, 1));
  child2.components.textLabel.fontSize = 14.0f;

  auto rootWidgets = collector.collectVisible(root, 320.0f, 240.0f);
  painter.drawTree(rootWidgets, renderer);
  assert(!child1.dirty);
  assert(!child2.dirty);
}
