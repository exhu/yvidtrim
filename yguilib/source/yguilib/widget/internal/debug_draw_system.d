module yguilib.widget.internal.debug_draw_system;

package(yguilib):

import yguilib.render : Renderer;
import yguilib.render.font : Font;
import yguilib.render.render_types : PointF, RectF, ColorF;
import yguilib.widget : Widget;
import yguilib.widget.drawing_components : DebugDrawComponent;
import yguilib.widget.system : SystemPhase, WidgetSystem,
  WidgetSystemContext;

/**
 * Render-phase system that draws debug outlines and widget labels over the
 * rendered widget tree.
 *
 * Registered only in debug builds and scheduled after WidgetPainterSystem
 * (`debugDrawSystemPriority`). Traverses `ctx.root` directly without clipping
 * so that hidden (`!w.visible`), off-screen, and parent-clipped widgets are
 * still visualized.
 */
final class DebugDrawSystem : WidgetSystem {
  this() nothrow @safe {
    super(debugDrawSystemPriority);
  }

  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.render;
  }

  override void render(ref WidgetSystemContext ctx) {
    if (ctx.renderer is null || ctx.root is null) {
      return;
    }
    drawTree(ctx.root, 0.0f, 0.0f, null, ctx.renderer);
  }

package(yguilib):
  static string formatLabel(const Widget w) {
    import std.format : format;

    string base = w.name.length > 0
      ? format("%s %s", w.uId, w.name)
      : format("%s", w.uId);
    if (!w.visible) {
      return base ~ " [hidden]";
    }
    return base;
  }

  static DebugDrawComponent resolveEffectiveComp(
    const Widget w,
    DebugDrawComponent inheritedComp
  ) {
    if (w.components.debugDraw !is null) {
      return cast(DebugDrawComponent) w.components.debugDraw;
    }
    return inheritedComp;
  }

  static DebugDrawComponent resolveNextInherited(
    const Widget w,
    DebugDrawComponent inheritedComp
  ) {
    if (w.components.debugDraw !is null) {
      auto own = cast(DebugDrawComponent) w.components.debugDraw;
      if (own.enabled && own.recursive) {
        return own;
      }
      return null;
    }
    return inheritedComp;
  }

private:
  static void drawTree(
    Widget w,
    float parentX,
    float parentY,
    DebugDrawComponent inheritedComp,
    Renderer r
  ) {
    if (w is null) {
      return;
    }

    const RectF absRect = RectF(
      parentX + w.rect.x,
      parentY + w.rect.y,
      w.rect.width,
      w.rect.height
    );

    DebugDrawComponent effective = resolveEffectiveComp(w, inheritedComp);
    if (effective !is null && effective.enabled) {
      drawWidgetDebug(w, absRect, effective, r);
    }

    DebugDrawComponent nextInherited = resolveNextInherited(w, inheritedComp);
    foreach (child; w.children) {
      drawTree(child, absRect.x, absRect.y, nextInherited, r);
    }
  }

  static void drawWidgetDebug(
    const Widget w,
    in RectF absRect,
    const DebugDrawComponent comp,
    Renderer r
  ) {

    if (!w.visible && !comp.drawHidden)
      return;

    ColorF fgColor = w.visible ? comp.fgColor : comp.hiddenFgColor;
    ColorF bgColor = w.visible ? comp.bgColor : comp.hiddenBgColor;

    if (w.visible) {
      r.drawRect(absRect, 1.0f, fgColor);
    } else {
      r.drawRectDashed(absRect, 1.0f, 4.0f, 3.0f, fgColor);
    }

    Font font = r.getDefaultFont();
    if (font is null) {
      return;
    }
    const string label = formatLabel(w);
    const PointF textExtent = r.measureText(label, font);
    r.drawFillRect(
      RectF(absRect.x, absRect.y, textExtent.x, textExtent.y),
      bgColor
    );
    r.drawText(label, PointF(absRect.x, absRect.y), fgColor, font);
  }
}

unittest {
  import yguilib.clibs.sdl3 : yguilib_sdl3_init, yguilib_sdl3_quit;
  import yguilib.widget.test_fixture : WidgetFixture;
  import yguilib.window : Window;

  auto sys = new DebugDrawSystem();
  assert(sys.priority == WidgetSystem.debugDrawSystemPriority);
  assert(sys.priority > WidgetSystem.painterSystemPriority);
  assert(sys.phases == SystemPhase.render);

  auto fix = new WidgetFixture();
  auto root = fix.makeRoot(RectF(0, 0, 320, 240));
  root.name = "rootBox";
  auto child = fix.makeChild(root, RectF(10, 20, 80, 40));
  child.name = "childBtn";
  auto hidden = fix.makeChild(root, RectF(100, 20, 60, 30));
  hidden.name = "hiddenPanel";
  hidden.visible = false;
  auto offscreen = fix.makeChild(root, RectF(500, 10, 50, 50));

  assert(DebugDrawSystem.formatLabel(root) == "1 rootBox");
  assert(DebugDrawSystem.formatLabel(hidden) == "3 hiddenPanel [hidden]");
  assert(DebugDrawSystem.formatLabel(offscreen) == "4");

  auto rootComp = new DebugDrawComponent();
  rootComp.recursive = true;
  root.components.debugDraw = rootComp;

  // Child inherits recursive DebugDrawComponent
  assert(DebugDrawSystem.resolveEffectiveComp(child, rootComp) is rootComp);
  assert(DebugDrawSystem.resolveNextInherited(root, null) is rootComp);

  // Child with own disabled DebugDrawComponent overrides parent recursive
  auto childDisable = new DebugDrawComponent();
  childDisable.enabled = false;
  child.components.debugDraw = childDisable;
  assert(DebugDrawSystem.resolveEffectiveComp(child, rootComp) is childDisable);
  assert(DebugDrawSystem.resolveNextInherited(child, rootComp) is null);

  // Render pass with real Window/Renderer exercises visible, hidden, offscreen
  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_debug_draw_system");
  win.create();
  scope(exit) win.destroy();

  auto renderer = new Renderer(320, 240);
  scope(exit) renderer.destroy();

  WidgetSystemContext ctx;
  ctx.root = root;
  ctx.renderer = renderer;
  sys.render(ctx);
}
