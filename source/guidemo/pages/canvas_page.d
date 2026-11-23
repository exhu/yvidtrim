/**
 * canvas_page.d - Page 10 showcase for the Canvas 2D API drawn through
 * `CustomDraw` (`WidgetBuilder.onDraw`).
 *
 * Each section card hosts one widget whose delegate draws in content-local
 * coordinates via `r.canvas()`; `Renderer` calls inside a delegate use
 * absolute coordinates (the origin is the canvas transform `e/f`).
 */
module guidemo.pages.canvas_page;

import guidemo.common : makeSectionCard;
import guidemo.model : CanvasPageModel;
import yguilib.model : ModelTracker;
import yguilib.render : Renderer;
import yguilib.render.canvas : Canvas, FillRule, FillStyle, LineCap,
  LineDash, LineJoin, LinearGradient, Path2d, RadialGradient, Shadow,
  Transform2d;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;

/// Page 10 widget container showcasing Canvas paths, paints and clips.
final class CanvasPage {
  @disable this();

  /// Constructs CanvasPage with an externally created `modelTracker`.
  this(
    UiSystem ui,
    Widget parent,
    ref ModelTracker!CanvasPageModel modelTracker
  ) {
    assert(ui !is null, "UiSystem must not be null");
    assert(parent !is null, "parent must not be null");
    this.ui = ui;
    tracker = ModelTracker!CanvasPageModel.from(modelTracker);
    root = new Widget(ui.nextWidgetId());
    root.name = "canvasPage";
    root.rect = RectF(0, 0, 1280, 720);
    parent.addChild(root);

    buildPaths();
    buildPaints();
    buildSections();
  }

  invariant {
    assert(root !is null);
  }

  /**
   * Marks the animated custom-draw widgets dirty when the model changed.
   * Returns true if they were invalidated.
   */
  bool update() {
    if (!tracker.update()) {
      return false;
    }
    strokesWidget.update(WidgetUpdateScope.visuals);
    transformsWidget.update(WidgetUpdateScope.visuals);
    return true;
  }

  /// Returns the status bar text (key hints) for this page.
  string formatStatus() {
    return tracker.model.animating
      ? "[Space] Pause animation"
      : "[Space] Resume animation";
  }

  /// Returns the page root widget.
  Widget rootWidget() {
    return root;
  }

  /// Returns the custom-draw widgets in section order.
  Widget[] drawWidgets() {
    return sectionWidgets;
  }

  /// Returns whether the page is visible.
  bool isVisible() const {
    return root.visible;
  }

private:
  alias DrawFunc = void delegate(Renderer r, in Widget w);

  void buildSections() {
    addSection(0, 0, "1. Paths", "canvasPaths", &drawPaths);
    addSection(1, 0, "2. Fill rules", "canvasFillRules", &drawFillRules);
    strokesWidget = addSection(
      2, 0, "3. Strokes (caps, joins, dashes)", "canvasStrokes",
      &drawStrokes
    );
    transformsWidget = addSection(
      3, 0, "4. Transforms", "canvasTransforms", &drawTransforms
    );
    addSection(0, 1, "5. Clip", "canvasClip", &drawClip);
    addSection(1, 1, "6. Gradients", "canvasGradients", &drawGradients);
    addSection(
      2, 1, "7. Canvas + Renderer interop", "canvasInterop", &drawInterop
    );
    addSection(3, 1, "8. Shadows", "canvasShadows", &drawShadows);
  }

  Widget addSection(
    size_t col,
    size_t row,
    string title,
    string name,
    DrawFunc func
  ) {
    const RectF cardRect = RectF(
      20 + col * (cardWidth + cardGap),
      68 + row * (cardHeight + cardGap),
      cardWidth,
      cardHeight
    );
    auto card = makeSectionCard(ui, root, cardRect, title, name ~ "Card");
    auto w = WidgetBuilder.make(ui)
      .parent(card)
      .name(name)
      .rect(RectF(12, 36, drawWidth, drawHeight))
      .clipContents(true)
      .onDraw(func)
      .build();
    sectionWidgets ~= w;
    return w;
  }

  void buildPaths() {
    import std.math : PI, cos, sin;

    curves = new Path2d();
    curves.moveTo(PointF(10, 50));
    curves.quadraticCurveTo(PointF(60, -10), PointF(110, 50));
    curves.moveTo(PointF(130, 50));
    curves.bezierCurveTo(
      PointF(160, -10), PointF(210, 100), PointF(250, 20)
    );

    arcs = new Path2d();
    arcs.moveTo(PointF(55, 115));
    arcs.arc(PointF(55, 115), 40, -0.25f * PI, 1.25f * PI, false);
    arcs.closePath();

    arcToPath = new Path2d();
    arcToPath.moveTo(PointF(130, 80));
    arcToPath.arcTo(PointF(240, 80), PointF(240, 150), 35);
    arcToPath.lineTo(PointF(240, 150));

    ellipsePath = new Path2d();
    ellipsePath.ellipse(
      PointF(60, 195), PointF(50, 25), 0.3f, 0, 2 * PI, false
    );

    roundRectPath = new Path2d();
    roundRectPath.roundRect(RectF(130, 170, 120, 50), 14);

    star = new Path2d();
    foreach (i; 0 .. 5) {
      const float a = -0.5f * PI + i * 4 * PI / 5;
      const PointF p = PointF(55 * cos(a), 55 * sin(a));
      if (i == 0) {
        star.moveTo(p);
      } else {
        star.lineTo(p);
      }
    }
    star.closePath();

    buildStrokePaths();
    buildMiscPaths();
  }

  void buildStrokePaths() {
    capLine = new Path2d();
    capLine.moveTo(PointF(0, 0));
    capLine.lineTo(PointF(90, 0));

    joinPath = new Path2d();
    joinPath.moveTo(PointF(0, 20));
    joinPath.lineTo(PointF(25, 0));
    joinPath.lineTo(PointF(50, 20));
    joinPath.lineTo(PointF(75, 0));

    sharpPath = new Path2d();
    sharpPath.moveTo(PointF(0, 0));
    sharpPath.lineTo(PointF(50, 10));
    sharpPath.lineTo(PointF(0, 20));

    dashLine = new Path2d();
    dashLine.moveTo(PointF(0, 0));
    dashLine.lineTo(PointF(246, 0));
  }

  void buildMiscPaths() {
    import std.math : PI;

    arrow = new Path2d();
    arrow.moveTo(PointF(-40, -15));
    arrow.lineTo(PointF(15, -15));
    arrow.lineTo(PointF(15, -30));
    arrow.lineTo(PointF(45, 0));
    arrow.lineTo(PointF(15, 30));
    arrow.lineTo(PointF(15, 15));
    arrow.lineTo(PointF(-40, 15));
    arrow.closePath();

    stripes = new Path2d();
    foreach (i; 0 .. 24) {
      stripes.rect(RectF(-60 + i * 16, -10, 8, 260));
    }

    circle = new Path2d();
    circle.arc(PointF(0, 0), 1, 0, 2 * PI, false);

    wave = new Path2d();
    wave.moveTo(PointF(10, 200));
    foreach (i; 0 .. 4) {
      const float x = 10 + i * 60;
      wave.bezierCurveTo(
        PointF(x + 20, 170), PointF(x + 40, 230), PointF(x + 60, 200)
      );
    }

    unitRect = new Path2d();
    unitRect.rect(RectF(0, 0, 1, 1));

    clipCircle = new Path2d();
    clipCircle.arc(PointF(70, 85), 60, 0, 2 * PI, false);
    nestedRect = new Path2d();
    nestedRect.rect(RectF(150, 25, 100, 120));
    nestedCircle = new Path2d();
    nestedCircle.arc(PointF(150, 85), 90, 0, 2 * PI, false);
    gradRect = new Path2d();
    gradRect.rect(RectF(10, 10, 110, 130));
    gradCircle = new Path2d();
    gradCircle.arc(PointF(195, 75), 60, 0, 2 * PI, false);

    shadowCard = new Path2d();
    shadowCard.roundRect(RectF(20, 20, 110, 80), 14);
    shadowBadge = new Path2d();
    shadowBadge.arc(PointF(200, 60), 38, 0, 2 * PI, false);
    shadowLine = new Path2d();
    shadowLine.moveTo(PointF(24, 160));
    shadowLine.bezierCurveTo(
      PointF(80, 120), PointF(160, 220), PointF(240, 160)
    );
  }

  void buildPaints() {
    LinearGradient lg;
    lg.p0 = PointF(10, 10);
    lg.p1 = PointF(120, 140);
    lg.addColorStop(0, ColorF(0.95f, 0.30f, 0.30f, 1))
      .addColorStop(0.5f, ColorF(0.95f, 0.90f, 0.30f, 1))
      .addColorStop(1, ColorF(0.30f, 0.60f, 0.95f, 1));
    linearFill = FillStyle.fromLinear(lg);

    // two-circle (focal) radial gradient: highlight off-center
    RadialGradient rg;
    rg.c0 = PointF(175, 55);
    rg.r0 = 4;
    rg.c1 = PointF(195, 75);
    rg.r1 = 60;
    rg.addColorStop(0, ColorF(1, 1, 1, 1))
      .addColorStop(0.4f, ColorF(0.50f, 0.80f, 0.95f, 1))
      .addColorStop(1, ColorF(0.10f, 0.20f, 0.50f, 1));
    radialFill = FillStyle.fromRadial(rg);

    LinearGradient sg;
    sg.p0 = PointF(10, 0);
    sg.p1 = PointF(250, 0);
    sg.addColorStop(0, ColorF(0.55f, 0.95f, 0.45f, 1))
      .addColorStop(1, ColorF(0.85f, 0.40f, 0.95f, 1));
    gradientStroke = FillStyle.fromLinear(sg);
  }

  // Section 1: quadratic/cubic curves, arc, arcTo, ellipse, roundRect.
  void drawPaths(Renderer r, in Widget w) {
    auto c = r.canvas();
    c.lineWidth(3);
    c.strokeStyle(FillStyle.solid(ColorF(0.40f, 0.75f, 1.0f, 1)));
    c.stroke(curves);
    c.fillStyle(FillStyle.solid(ColorF(0.95f, 0.55f, 0.25f, 1)));
    c.fill(arcs);
    c.strokeStyle(FillStyle.solid(ColorF(0.55f, 0.95f, 0.55f, 1)));
    c.stroke(arcToPath);
    c.fillStyle(FillStyle.solid(ColorF(0.80f, 0.45f, 0.95f, 1)));
    c.fill(ellipsePath);
    c.fillStyle(FillStyle.solid(ColorF(0.25f, 0.45f, 0.70f, 1)));
    c.fill(roundRectPath);
    c.lineWidth(2);
    c.strokeStyle(FillStyle.solid(ColorF(0.90f, 0.90f, 0.95f, 1)));
    c.stroke(roundRectPath);
  }

  // Section 2: the same self-intersecting star with both fill rules.
  void drawFillRules(Renderer r, in Widget w) {
    auto c = r.canvas();
    c.fillStyle(FillStyle.solid(ColorF(0.95f, 0.80f, 0.30f, 1)));
    c.strokeStyle(FillStyle.solid(ColorF(0.95f, 0.95f, 0.95f, 1)));
    c.lineWidth(1.5f);
    drawStarWithRule(c, PointF(66, 110), FillRule.nonZero);
    drawStarWithRule(c, PointF(198, 110), FillRule.evenOdd);
    labelAt(r, "nonZero", PointF(40, 190));
    labelAt(r, "evenOdd", PointF(172, 190));
  }

  void drawStarWithRule(Canvas c, PointF center, FillRule rule) {
    c.save();
    c.translate(center);
    c.fillRule(rule);
    c.fill(star);
    c.stroke(star);
    c.restore();
  }

  // Section 3: caps, joins, miter limit and animated dashes.
  void drawStrokes(Renderer r, in Widget w) {
    auto c = r.canvas();
    c.strokeStyle(FillStyle.solid(ColorF(0.40f, 0.85f, 0.95f, 1)));
    c.lineWidth(10);
    static immutable LineCap[3] caps = [
      LineCap.butt, LineCap.round, LineCap.square,
    ];
    foreach (i, cap; caps) {
      c.save();
      c.translate(PointF(14, 12 + i * 24));
      c.lineCap(cap);
      c.stroke(capLine);
      c.restore();
    }
    static immutable LineJoin[3] joins = [
      LineJoin.miter, LineJoin.round, LineJoin.bevel,
    ];
    c.strokeStyle(FillStyle.solid(ColorF(0.95f, 0.65f, 0.35f, 1)));
    c.lineWidth(8);
    foreach (i, join; joins) {
      c.save();
      c.translate(PointF(160, 2 + i * 26));
      c.lineJoin(join);
      c.stroke(joinPath);
      c.restore();
    }
    drawMiterSamples(c);
    drawDashSamples(c);
  }

  void drawMiterSamples(Canvas c) {
    c.strokeStyle(FillStyle.solid(ColorF(0.75f, 0.90f, 0.45f, 1)));
    c.lineWidth(6);
    c.lineJoin(LineJoin.miter);
    static immutable float[2] limits = [10.0f, 1.5f];
    foreach (i, limit; limits) {
      c.save();
      c.translate(PointF(20 + i * 130, 90));
      c.miterLimit(limit);
      c.stroke(sharpPath);
      c.restore();
    }
  }

  void drawDashSamples(Canvas c) {
    const float offset = tracker.model.dashOffset;
    static immutable float[2] dash0 = [14.0f, 6.0f];
    static immutable float[4] dash1 = [2.0f, 6.0f, 10.0f, 6.0f];
    c.save();
    c.lineWidth(4);
    c.lineCap(LineCap.butt);
    c.lineDashOffset(offset);
    c.strokeStyle(FillStyle.solid(ColorF(0.95f, 0.95f, 0.55f, 1)));
    c.lineDash(LineDash.fromSegments(dash0[]));
    c.translate(PointF(10, 140));
    c.stroke(dashLine);
    c.lineCap(LineCap.round);
    c.lineDash(LineDash.fromSegments(dash1[]));
    c.translate(PointF(0, 24));
    c.stroke(dashLine);
    c.lineDashOffset(-offset);
    c.lineWidth(8);
    c.lineCap(LineCap.butt);
    c.strokeStyle(FillStyle.solid(ColorF(0.85f, 0.45f, 0.85f, 1)));
    c.lineDash(LineDash.fromSegments(dash0[]));
    c.translate(PointF(0, 26));
    c.stroke(dashLine);
    c.restore();
  }

  // Section 4: rotation from the model plus a mirrored copy.
  void drawTransforms(Renderer r, in Widget w) {
    auto c = r.canvas();
    c.save();
    c.translate(PointF(70, 85));
    c.rotate(tracker.model.rotation);
    c.fillStyle(FillStyle.solid(ColorF(0.35f, 0.75f, 0.95f, 1)));
    c.fill(arrow);
    c.restore();

    c.save();
    c.translate(PointF(195, 85));
    c.scale(PointF(-1, 1));
    c.fillStyle(FillStyle.solid(ColorF(0.95f, 0.55f, 0.35f, 1)));
    c.fill(arrow);
    c.restore();

    c.save();
    c.translate(PointF(133, 180));
    c.rotate(-tracker.model.rotation);
    c.scale(PointF(1.1f, 0.5f));
    c.fillStyle(FillStyle.solid(ColorF(0.60f, 0.90f, 0.50f, 1)));
    c.fill(arrow);
    c.restore();
    labelAt(r, "rotate", PointF(48, 0));
    labelAt(r, "scale(-1, 1)", PointF(155, 0));
  }

  // Section 5: stripes inside a circle clip, plus a nested clip.
  void drawClip(Renderer r, in Widget w) {
    auto c = r.canvas();
    c.save();
    c.clip(clipCircle);
    c.fillStyle(FillStyle.solid(ColorF(0.95f, 0.80f, 0.30f, 1)));
    c.translate(PointF(70, 110));
    c.rotate(0.5f);
    c.translate(PointF(-70, -110));
    c.fill(stripes);
    c.restore();

    // nested clip: square, then circle (intersection)
    c.save();
    c.clip(nestedRect);
    c.clip(nestedCircle);
    c.fillStyle(FillStyle.solid(ColorF(0.40f, 0.85f, 0.95f, 1)));
    c.fill(stripes);
    c.restore();
    labelAt(r, "circle", PointF(45, 180));
    labelAt(r, "rect + circle", PointF(150, 180));
  }

  // Section 6: linear and two-circle radial fills, gradient stroke.
  void drawGradients(Renderer r, in Widget w) {
    auto c = r.canvas();
    c.fillStyle(linearFill);
    c.fill(gradRect);
    c.fillStyle(radialFill);
    c.fill(gradCircle);
    c.strokeStyle(gradientStroke);
    c.lineWidth(8);
    c.lineCap(LineCap.round);
    c.stroke(wave);
  }

  // Section 7: Renderer primitives interleaved with Canvas fills.
  void drawInterop(Renderer r, in Widget w) {
    auto c = r.canvas();
    const PointF o = origin(c);
    r.drawFillRoundRect(
      RectF(o.x + 10, o.y + 20, 150, 90), 12,
      ColorF(0.20f, 0.35f, 0.55f, 1)
    );
    c.fillStyle(FillStyle.solid(ColorF(0.95f, 0.55f, 0.25f, 0.85f)));
    c.save();
    c.translate(PointF(150, 95));
    c.scale(PointF(60, 60));
    c.fill(circle);
    c.restore();
    r.drawTextWithFont(
      "Renderer text over Canvas", PointF(o.x + 20, o.y + 85),
      ColorF(1, 1, 1, 1), r.getFont(14.0f, null)
    );
    c.fillStyle(FillStyle.solid(ColorF(0.55f, 0.95f, 0.55f, 0.5f)));
    c.save();
    c.translate(PointF(60, 160));
    c.scale(PointF(200, 50));
    c.fill(unitRect);
    c.restore();
    r.drawFillRoundRect(
      RectF(o.x + 30, o.y + 175, 120, 24), 6,
      ColorF(0.85f, 0.40f, 0.85f, 0.9f)
    );
  }

  // Section 8: blurred, hard (blur 0) and stroke shadows.
  void drawShadows(Renderer r, in Widget w) {
    auto c = r.canvas();
    c.save();
    Shadow soft;
    soft.offset = PointF(4, 6);
    soft.blur = 14;
    soft.color = ColorF(0, 0, 0, 0.75f);
    c.shadow(soft);
    c.fillStyle(FillStyle.solid(ColorF(0.35f, 0.60f, 0.90f, 1)));
    c.fill(shadowCard);

    Shadow hard;
    hard.offset = PointF(8, 8);
    hard.color = ColorF(0.95f, 0.45f, 0.25f, 0.9f);
    c.shadow(hard);
    c.fillStyle(FillStyle.solid(ColorF(0.95f, 0.85f, 0.35f, 1)));
    c.fill(shadowBadge);

    Shadow glow;
    glow.offset = PointF(0, 4);
    glow.blur = 8;
    glow.color = ColorF(0.30f, 0.95f, 0.55f, 0.8f);
    c.shadow(glow);
    c.strokeStyle(FillStyle.solid(ColorF(0.85f, 1, 0.90f, 1)));
    c.lineWidth(6);
    c.lineCap(LineCap.round);
    c.stroke(shadowLine);
    c.restore();
    labelAt(r, "blur 14", PointF(48, 108));
    labelAt(r, "blur 0", PointF(178, 108));
    labelAt(r, "stroke", PointF(110, 205));
  }

  /// Absolute logic position of the current canvas origin.
  static PointF origin(Canvas c) {
    return c.transform().apply(PointF(0, 0));
  }

  /// Draws `text` with the Renderer at canvas-local `pos`.
  static void labelAt(Renderer r, string text, PointF pos) {
    const Transform2d xf = r.canvas().transform();
    r.drawTextWithFont(
      text, xf.apply(pos), ColorF(0.80f, 0.85f, 0.92f, 1),
      r.getFont(13.0f, null)
    );
  }

  enum float cardWidth = 290;
  enum float cardHeight = 280;
  enum float cardGap = 20;
  enum float drawWidth = 266;
  enum float drawHeight = 232;

  UiSystem ui;
  ModelTracker!CanvasPageModel tracker;
  Widget root;
  Widget strokesWidget;
  Widget transformsWidget;
  Widget[] sectionWidgets;
  Path2d curves;
  Path2d arcs;
  Path2d arcToPath;
  Path2d ellipsePath;
  Path2d roundRectPath;
  Path2d star;
  Path2d capLine;
  Path2d joinPath;
  Path2d sharpPath;
  Path2d dashLine;
  Path2d arrow;
  Path2d stripes;
  Path2d circle;
  Path2d wave;
  Path2d unitRect;
  Path2d clipCircle;
  Path2d nestedRect;
  Path2d nestedCircle;
  Path2d gradRect;
  Path2d gradCircle;
  Path2d shadowCard;
  Path2d shadowBadge;
  Path2d shadowLine;
  FillStyle linearFill;
  FillStyle radialFill;
  FillStyle gradientStroke;
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto ui = new UiSystemImpl(null);
  auto root = new Widget(ui.nextWidgetId());
  auto tracker = ModelTracker!CanvasPageModel(new CanvasPageModel());
  auto page = new CanvasPage(ui, root, tracker);
  assert(page.rootWidget().parent is root);
  assert(page.drawWidgets().length == 8);
  foreach (w; page.drawWidgets()) {
    assert(w.components.customDraw !is null);
    assert(w.components.customDraw.drawFunc !is null);
  }
  assert(page.formatStatus() == "[Space] Pause animation");

  // a model change marks the animated widgets dirty
  page.update();
  assert(!page.update());
  auto m = tracker.edit();
  m.rotation = 1.0f;
  tracker.commit(m);
  assert(page.update());
  assert(!page.update());
}
