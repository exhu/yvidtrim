module yguilib.widget.internal.widget_painter;

package(yguilib):

import std.array : Appender;
import std.math : isFinite;
import yguilib.render : Renderer;
import yguilib.render.font : Font, defaultFontPtSize;
import yguilib.render.render_types : DashPattern, PointF, RectF,
  intersectRects;
import yguilib.widget.drawing_components : Background, Border, TextLabel;
import yguilib.widget : Widget;
import yguilib.widget.system : SystemPhase, WidgetSystem,
  WidgetSystemContext;
import yguilib.widget.visible : VisibleWidgets;
import yguilib.widget.internal.layout_text : getLineStep;
import yguilib.widget.internal.text_label_cache : getLayoutLines;

interface CustomWidgetPainter {
  void drawBackground(Widget w, in RectF absRect, Renderer r);
  void drawContent(Widget w, in RectF absContentRect, Renderer r);
  void drawBorder(Widget w, in RectF absRect, Renderer r);
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
/// TODO support CustomWidgetPainter
final class WidgetPainterSystem : WidgetSystem {
  this() nothrow @safe {
    setPriority(painterSystemPriority);
  }

  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.render;
  }

  override void render(ref WidgetSystemContext ctx) {
    if (ctx.renderer is null || ctx.visibleWidgets.length == 0) {
      return;
    }
    drawWidgets(ctx.visibleWidgets, ctx.renderer);
  }

  void drawTree(VisibleWidgets widgets, Renderer r) {
    assert(widgets !is null);
    assert(r !is null);

    drawWidgets(widgets, r);
    r.flush();
    foreach (ref vw; widgets) {
      vw.widget.dirty = false;
    }
  }

private:
  void drawWidgets(VisibleWidgets widgets, Renderer r) {
    bool activeClip = false;
    RectF activeClipRect;
    scope(exit) {
      if (activeClip) {
        r.popClipRect();
      }
    }
    foreach (ref vw; widgets) {
      if (!vw.hasClip) {
        if (activeClip) {
          r.popClipRect();
          activeClip = false;
        }
      } else if (!activeClip || vw.clipRect != activeClipRect) {
        if (activeClip) {
          r.popClipRect();
        }
        r.pushClipRect(vw.clipRect);
        activeClip = true;
        activeClipRect = vw.clipRect;
      }
      drawWidget(vw.widget, vw.absRect, r);
    }
  }

  static void drawWidget(Widget w, in RectF absRect, Renderer r) {
    if (w.components.background !is null) {
      drawBackground(w, absRect, r);
    }

    // TODO CustomWidgetPainter.drawBackground

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
    // TODO CustomWidgetPainter.drawContent
    drawCustom(w, absContentRect, r);

    if (w.clipContents) {
      r.popClipRect();
    }

    if (w.components.border !is null) {
      drawBorder(w, absRect, r);
    }

    // TODO CustomWidgetPainter.drawBorder
  }

  /**
   * Invokes the `CustomDraw` delegate with the canvas translated to the
   * content rect origin, so the delegate draws in content-local coordinates
   * via `r.canvas()`; `Renderer` calls stay absolute.
   */
  static void drawCustom(Widget w, in RectF absContentRect, Renderer r) {
    auto cd = w.components.customDraw;
    if (cd is null || cd.drawFunc is null) {
      return;
    }
    auto c = r.canvas();
    if (c is null) {
      // renderer not initialized: nothing can be drawn
      return;
    }
    c.save();
    c.translate(PointF(absContentRect.x, absContentRect.y));
    cd.drawFunc(r, w);
    c.restore();
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
        r.drawRectWithWidth(absRect, comp.width, comp.color);
        break;
      case Border.Style.dashed:
        r.drawRectDashed(
          absRect, comp.width, DashPattern(comp.dashLen, comp.gap),
          comp.color
        );
        break;
      case Border.Style.round:
        r.drawRoundRect(absRect, comp.cornerRadius, comp.width, comp.color);
        break;
      case Border.Style.roundDashed:
        r.drawRoundRectDashed(
          absRect, comp.cornerRadius, comp.width,
          DashPattern(comp.dashLen, comp.gap), comp.color
        );
        break;
      case Border.Style.none:{}
    }
  }

  static void drawTextLabel(Widget w, in RectF absContentRect, Renderer r) {
    auto comp = w.components.textLabel;
    if (comp is null || comp.caption.length == 0 || r is null) {
      return;
    }
    Font font = r.font(comp.fontSize, comp.font);
    if (font is null) {
      return;
    }

    auto lines = getLayoutLines(
      comp.layoutCache, r, font, comp.font,
      comp.caption, comp.multiline, comp.overflowEllipsis,
      comp.alignment, absContentRect.width, absContentRect.height
    );

    const float lineStep = getLineStep(r, font);

    foreach (size_t i, const ref line; lines) {
      if (line.text.length == 0) {
        continue;
      }
      const float lineX = absContentRect.x + line.xOffset;
      const float lineY = absContentRect.y + cast(float)i * lineStep;
      r.drawTextWithFont(line.text, PointF(lineX, lineY), comp.color, font);
    }
  }
}

unittest {
  import yguilib.clibs.sdl3;
  import yguilib.render.font : defaultFontPtSize;
  import yguilib.render.render_types : ColorF;
  import yguilib.widget.drawing_components : Background, Border,
    CustomDraw, TextLabel;
  import yguilib.widget.internal.collect_visible : VisibleWidgetsCollector;
  import yguilib.widget.layout_components : Insets, Size;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_widget_painter");
  win.create();
  scope(exit) win.destroy();

  auto renderer = new Renderer(320, 240, 1.0f);
  scope(exit) renderer.destroy();

  auto w = new Widget(1);
  w.rect = RectF(10, 20, 100, 80);
  w.components.background = Background.rect(ColorF(0.2f, 0.2f, 0.2f, 1.0f));
  w.components.border = Border.rect(ColorF(1.0f, 0.0f, 0.0f, 1.0f), 2.0f);
  w.components.border.width = 2.0f;
  w.components.size = new Size();
  w.components.size.padding = Insets(5, 5, 5, 5);
  w.components.textLabel = new TextLabel(
    "Hello",
    ColorF(1.0f, 1.0f, 1.0f, 1.0f)
  );
  w.clipContents = true;

  auto collector = new VisibleWidgetsCollector;
  auto widgets = collector.collectVisibleWithViewport(w, 320.0f, 240.0f, false);

  auto painter = new WidgetPainterSystem;
  assert(painter.priority == WidgetSystem.painterSystemPriority);
  assert(painter.phases == SystemPhase.render);
  painter.drawTree(widgets, renderer);

  assert(!w.dirty);

  // Test TextLabel with custom fontSize (default font is never mutated)
  w.components.textLabel.fontSize = 24.0f;
  w.dirty = true;
  widgets = collector.collectVisibleWithViewport(w, 320.0f, 240.0f, false);
  painter.drawTree(widgets, renderer);
  assert(renderer.defaultFont().size == defaultFontPtSize);
  assert(renderer.font(24.0f, null).size == 24.0f);

  // Test fallback when fontSize is 0.0f
  w.components.textLabel.fontSize = 0.0f;
  w.dirty = true;
  widgets = collector.collectVisibleWithViewport(w, 320.0f, 240.0f, false);
  painter.drawTree(widgets, renderer);
  assert(renderer.defaultFont().size == defaultFontPtSize);

  // Test fallback when fontSize is negative
  w.components.textLabel.fontSize = -5.0f;
  w.dirty = true;
  widgets = collector.collectVisibleWithViewport(w, 320.0f, 240.0f, false);
  painter.drawTree(widgets, renderer);
  assert(renderer.defaultFont().size == defaultFontPtSize);

  // Test fallback when fontSize is infinity
  w.components.textLabel.fontSize = float.infinity;
  w.dirty = true;
  widgets = collector.collectVisibleWithViewport(w, 320.0f, 240.0f, false);
  painter.drawTree(widgets, renderer);
  assert(renderer.defaultFont().size == defaultFontPtSize);

  // Test fallback when fontSize is NaN
  w.components.textLabel.fontSize = float.nan;
  w.dirty = true;
  widgets = collector.collectVisibleWithViewport(w, 320.0f, 240.0f, false);
  painter.drawTree(widgets, renderer);
  assert(renderer.defaultFont().size == defaultFontPtSize);

  // Test multiple widgets with different font sizes
  auto root = new Widget(2);
  root.rect = RectF(0, 0, 320, 240);
  auto child1 = new Widget(3);
  child1.rect = RectF(0, 0, 100, 30);
  root.addChild(child1);
  child1.components.textLabel = new TextLabel("Title", ColorF(1, 1, 1, 1));
  child1.components.textLabel.fontSize = 18.0f;

  auto child2 = new Widget(4);
  child2.rect = RectF(0, 35, 100, 30);
  root.addChild(child2);
  child2.components.textLabel = new TextLabel("Subtitle", ColorF(1, 1, 1, 1));
  child2.components.textLabel.fontSize = 14.0f;

  auto rootWidgets = collector.collectVisibleWithViewport(
    root, 320.0f, 240.0f, false
  );
  painter.drawTree(rootWidgets, renderer);
  assert(!child1.dirty);
  assert(!child2.dirty);

  // Test TextLabel with multiline and alignment rendering
  auto multiW = new Widget(5);
  multiW.rect = RectF(0, 0, 150, 80);
  auto multiTl = new TextLabel("Hello\nWorld\nMultiline", ColorF(1, 1, 1, 1));
  multiTl.multiline = true;
  multiTl.alignment = TextLabel.Alignment.center;
  multiW.components.textLabel = multiTl;
  auto multiWidgets = collector.collectVisibleWithViewport(
    multiW, 320.0f, 240.0f, false
  );
  painter.drawTree(multiWidgets, renderer);
  assert(!multiW.dirty);

  // Test TextLabel with right alignment and overflowEllipsis
  auto rightW = new Widget(6);
  rightW.rect = RectF(0, 0, 50, 30);
  auto rightTl = new TextLabel(
    "Long text that truncates with ellipsis",
    ColorF(1, 1, 1, 1)
  );
  rightTl.alignment = TextLabel.Alignment.right;
  rightTl.overflowEllipsis = true;
  rightW.components.textLabel = rightTl;
  auto rightWidgets = collector.collectVisibleWithViewport(
    rightW, 320.0f, 240.0f, false
  );
  painter.drawTree(rightWidgets, renderer);
  assert(!rightW.dirty);

  // CustomDraw: called once per draw with the canvas translated to the
  // absolute content rect origin; canvas state is restored afterwards
  auto cdRoot = new Widget(7);
  cdRoot.rect = RectF(0, 0, 320, 240);
  auto cdW = new Widget(8);
  cdW.rect = RectF(30, 40, 100, 60);
  cdW.components.size = new Size();
  cdW.components.size.padding = Insets(4, 6, 4, 6);
  cdRoot.addChild(cdW);
  size_t calls = 0;
  float seenE = -1;
  float seenF = -1;
  auto cd = new CustomDraw();
  cd.drawFunc = (Renderer rr, in Widget ww) {
    ++calls;
    assert(ww is cdW);
    const xf = rr.canvas().transform();
    seenE = xf.e;
    seenF = xf.f;
  };
  cdW.components.customDraw = cd;
  auto cdWidgets = collector.collectVisibleWithViewport(
    cdRoot, 320.0f, 240.0f, false
  );
  painter.drawTree(cdWidgets, renderer);
  assert(calls == 1);
  const RectF ca = cdW.getContentArea();
  assert(seenE == 30 + ca.x);
  assert(seenF == 40 + ca.y);
  assert(renderer.canvas().transform().isIdentity());

  // a null drawFunc is skipped
  cd.drawFunc = null;
  painter.drawTree(cdWidgets, renderer);
  assert(calls == 1);

  // Consecutive clipped text-only sibling widgets share 1 flush.
  auto clipParent = new Widget(9);
  clipParent.rect = RectF(10, 10, 200, 150);
  clipParent.clipChildren = true;
  foreach (i; 0 .. 3) {
    auto lbl = new Widget(10 + i);
    lbl.rect = RectF(4, 4 + i * 24, 180, 20);
    lbl.clipContents = false;
    lbl.components.textLabel = new TextLabel(
      "Sibling", ColorF(1, 1, 1, 1)
    );
    clipParent.addChild(lbl);
  }
  auto clippedWidgets = collector.collectVisibleWithViewport(
    clipParent, 320.0f, 240.0f, false
  );
  renderer.resetTextBatchStats();
  painter.drawTree(clippedWidgets, renderer);
  assert(renderer.textBatchStats().flushes == 1);
  assert(renderer.textBatchStats().flushedQuads > 0);
}
