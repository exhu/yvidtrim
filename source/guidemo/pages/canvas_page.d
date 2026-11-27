/**
 * canvas_page.d - Page 10 showcase for the Canvas 2D API drawn through
 * `CustomDraw` (`WidgetBuilder.onDraw`).
 *
 * Each section card hosts one widget whose delegate draws in content-local
 * coordinates via `r.canvas()`; `Renderer` calls inside a delegate use
 * absolute coordinates (the origin is the canvas transform `e/f`).
 *
 * Slot 7 cycles ([I]) through the Renderer interop section, the image
 * section (`Renderer.drawImage`/`drawImageRegion` and `Canvas.drawImage`
 * with a transform, a clip, a shadow and a tint), the offscreen section
 * (a cached `RenderTarget` drawing blitted several times) and the patterns
 * section (`Pattern` fills/strokes with repeat modes, transforms, tints and
 * a `RenderTarget` texture) and the text section (`fillText` alignment and
 * baselines, rotation, gradient fill, `strokeText`, shadow, maxWidth).
 * The sample PNG is decoded once; its `Texture` and the `RenderTarget`
 * are created lazily on the first draw and released by
 * `releaseGpuResources()` (main thread). A [P] request in the model is
 * saved as a PNG by the offscreen draw. The shadows section's hard shadow
 * blur comes from the model (cycled with [S]).
 */
module guidemo.pages.canvas_page;

import guidemo.assets : sampleImagePng;
import guidemo.common : makeSectionCard;
import guidemo.model : CanvasPageModel, CanvasSlot7;
import yguilib.model : ModelTracker;
import yguilib.render : Renderer;
import yguilib.render.canvas : Canvas;
import yguilib.render.canvas.path2d : Path2d;
import yguilib.render.canvas.types : FillRule, FillStyle, FontSpec, LineCap,
  LineDash, LineJoin, LinearGradient, Pattern, PatternRepeat, RadialGradient,
  Shadow, TextAlign, TextBaseline, TextDirection, Transform2d;
import yguilib.render.image : Image;
import yguilib.render.render_target : RenderTarget;
import yguilib.render.texture : Texture;
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

    // logs an error and returns null on failure; drawImages handles it
    sampleImage = Image.loadFromMemory(sampleImagePng);
    buildPaths();
    buildPaints();
    buildSections();
    syncSlot7();
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
    syncSlot7();
    strokesWidget.update(WidgetUpdateScope.visuals);
    transformsWidget.update(WidgetUpdateScope.visuals);
    // the blits rotate and a [P] request is consumed by the draw
    offscreenWidget.update(WidgetUpdateScope.visuals);
    patternsWidget.update(WidgetUpdateScope.visuals);
    textWidget.update(WidgetUpdateScope.visuals);
    // [S] changes the hard shadow blur
    shadowsWidget.update(WidgetUpdateScope.visuals);
    return true;
  }

  /// Returns the status bar text (key hints) for this page.
  string formatStatus() {
    const string anim = tracker.model.animating
      ? "[Space] Pause animation"
      : "[Space] Resume animation";
    static immutable string[CanvasSlot7.max + 1] next = [
      CanvasSlot7.interop: " | [I] Show images",
      CanvasSlot7.images: " | [I] Show offscreen",
      CanvasSlot7.offscreen: " | [I] Show patterns",
      CanvasSlot7.patterns: " | [I] Show text",
      CanvasSlot7.text: " | [I] Show interop",
    ];
    return anim ~ next[tracker.model.slot7] ~ statusTail;
  }

  /**
   * Destroys the GPU texture and render target; call on the main thread
   * with a live GL context. They are recreated by the next draw.
   */
  void releaseGpuResources() {
    if (sampleTexture !is null) {
      sampleTexture.destroy();
      sampleTexture = null;
    }
    if (offscreen !is null) {
      offscreen.destroy();
      offscreen = null;
    }
  }

  /// Returns the decoded sample image, or null if decoding failed.
  inout(Image) image() inout {
    return sampleImage;
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
  bool visible() const {
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
    interopWidget = addSection(
      2, 1, "7. Canvas + Renderer interop", "canvasInterop", &drawInterop
    );
    shadowsWidget = addSection(
      3, 1, "8. Shadows", "canvasShadows", &drawShadows
    );
    // share slot 7 with the interop section, cycled with [I]
    imagesWidget = addSection(
      2, 1, "9. Images (drawImage)", "canvasImages", &drawImages
    );
    offscreenWidget = addSection(
      2, 1, "10. Offscreen (RenderTarget)", "canvasOffscreen",
      &drawOffscreen
    );
    patternsWidget = addSection(
      2, 1, "11. Patterns", "canvasPatterns", &drawPatterns
    );
    textWidget = addSection(
      2, 1, "12. Text (fillText)", "canvasText", &drawText
    );
  }

  /// Shows the slot 7 card selected by the model, hides the others.
  void syncSlot7() {
    const CanvasSlot7 s = tracker.model.slot7;
    void syncCard(Widget card, bool vis) {
      if (card.visible != vis) {
        card.visible = vis;
        card.update(WidgetUpdateScope.layout);
      }
    }
    syncCard(interopWidget.parent, s == CanvasSlot7.interop);
    syncCard(imagesWidget.parent, s == CanvasSlot7.images);
    syncCard(offscreenWidget.parent, s == CanvasSlot7.offscreen);
    syncCard(patternsWidget.parent, s == CanvasSlot7.patterns);
    syncCard(textWidget.parent, s == CanvasSlot7.text);
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
    buildImagePaths();
    buildPatternPaths();
    buildTextPaths();
  }

  void buildImagePaths() {
    import std.math : PI;

    imageClip = new Path2d();
    imageClip.arc(PointF(236, 128), 26, 0, 2 * PI, false);
  }

  void buildTextPaths() {
    textGuideV = new Path2d();
    textGuideV.moveTo(PointF(133, 0));
    textGuideV.lineTo(PointF(133, 56));
    textGuideH = new Path2d();
    textGuideH.moveTo(PointF(0, 80));
    textGuideH.lineTo(PointF(130, 80));
  }

  void buildPatternPaths() {
    import std.math : PI;

    patternTileRect = new Path2d();
    patternTileRect.roundRect(RectF(8, 16, 120, 74), 10);

    patternStripX = new Path2d();
    patternStripX.rect(RectF(142, 16, 116, 36));

    patternOnceRect = new Path2d();
    patternOnceRect.rect(RectF(142, 72, 116, 36));

    patternRotCircle = new Path2d();
    patternRotCircle.arc(PointF(46, 152), 36, 0, 2 * PI, false);

    patternStrokeWave = new Path2d();
    patternStrokeWave.moveTo(PointF(10, 218));
    patternStrokeWave.bezierCurveTo(
      PointF(34, 198), PointF(58, 236), PointF(83, 218)
    );
    patternStrokeWave.bezierCurveTo(
      PointF(108, 198), PointF(132, 236), PointF(156, 218)
    );

    patternRtRect = new Path2d();
    patternRtRect.roundRect(RectF(168, 134, 90, 90), 8);
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

    // star-local coordinates (radius 55 around the origin)
    LinearGradient og;
    og.p0 = PointF(-55, -55);
    og.p1 = PointF(55, 55);
    og.addColorStop(0, ColorF(1.0f, 0.85f, 0.30f, 1))
      .addColorStop(0.5f, ColorF(0.95f, 0.40f, 0.45f, 1))
      .addColorStop(1, ColorF(0.45f, 0.35f, 0.95f, 1));
    offscreenFill = FillStyle.fromLinear(og);

    LinearGradient tg;
    tg.p0 = PointF(130, 0);
    tg.p1 = PointF(250, 0);
    tg.addColorStop(0, ColorF(0.95f, 0.35f, 0.35f, 1))
      .addColorStop(0.5f, ColorF(0.95f, 0.90f, 0.30f, 1))
      .addColorStop(1, ColorF(0.35f, 0.65f, 0.95f, 1));
    textGradient = FillStyle.fromLinear(tg);
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
      ColorF(1, 1, 1, 1), r.font(14.0f, null)
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
    hard.blur = tracker.model.hardShadowBlur;
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
    labelAt(r, hardBlurLabel(), PointF(178, 108));
    labelAt(r, "stroke", PointF(110, 205));
  }

  /// "blur N" label of the hard shadow, cached until the blur changes.
  string hardBlurLabel() {
    import std.conv : to;

    const int blur = tracker.model.hardShadowBlur;
    if (hardBlurText is null || hardBlurTextValue != blur) {
      hardBlurText = "blur " ~ blur.to!string;
      hardBlurTextValue = blur;
    }
    return hardBlurText;
  }

  // Section 9: the sample texture 1:1, tinted, src quadrant and 2x.
  void drawImages(Renderer r, in Widget w) {
    if (sampleImage is null) {
      labelAt(r, "sample.png failed to decode", PointF(8, 0));
      return;
    }
    if (sampleTexture is null) {
      sampleTexture = r.createTexture(sampleImage);
    }
    const ColorF opaque = ColorF(1, 1, 1, 1);
    const float w1 = sampleImage.width();
    const float h1 = sampleImage.height();
    labelAt(r, "1:1", PointF(8, 0));
    r.drawImage(sampleTexture, destAt(r, PointF(8, 16), w1, h1), opaque);
    labelAt(r, "tint 50%", PointF(88, 0));
    r.drawImage(
      sampleTexture, destAt(r, PointF(88, 16), w1, h1),
      ColorF(1, 1, 1, 0.5f)
    );
    labelAt(r, "src quadrant", PointF(168, 0));
    r.drawImageRegion(
      sampleTexture, destAt(r, PointF(168, 16), w1, h1),
      RectF(0, 0, w1 / 2, h1 / 2), opaque
    );
    labelAt(r, "2x", PointF(8, 88));
    r.drawImage(
      sampleTexture, destAt(r, PointF(8, 104), w1 * 2, h1 * 2), opaque
    );
    drawCanvasImages(r.canvas(), w1, h1);
    labelAt(r, "Canvas", PointF(150, 84));
    labelAt(r, "shadow+tint", PointF(196, 176));
  }

  // Section 9, right column: Canvas.drawImage transformed, clipped and
  // shadowed + tinted.
  void drawCanvasImages(Canvas c, float w1, float h1) {
    c.save();
    c.translate(PointF(176, 130));
    c.rotate(0.45f);
    c.scale(PointF(0.6f, 0.6f));
    c.drawImage(sampleTexture, RectF(-w1 / 2, -h1 / 2, w1, h1));
    c.restore();

    c.save();
    c.clip(imageClip);
    c.drawImage(sampleTexture, RectF(204, 96, w1, h1));
    c.restore();

    c.save();
    Shadow soft;
    soft.offset = PointF(4, 5);
    soft.blur = 8;
    soft.color = ColorF(0, 0, 0, 0.8f);
    c.shadow(soft);
    c.drawImageTinted(
      sampleTexture, RectF(150, 170, 40, 40),
      ColorF(0.55f, 0.85f, 1.0f, 0.9f)
    );
    c.restore();
  }

  // Section 10: a cached offscreen drawing blitted with Canvas.drawImage.
  void drawOffscreen(Renderer r, in Widget w) {
    if (!syncOffscreen(r)) {
      labelAt(r, "render target unavailable", PointF(8, 0));
      return;
    }
    Texture t = offscreen.texture();
    auto c = r.canvas();
    labelAt(r, "1:1", PointF(8, 0));
    c.drawImage(t, RectF(8, 16, offscreenSize, offscreenSize));

    labelAt(r, "rotate", PointF(150, 0));
    c.save();
    c.translate(PointF(186, 70));
    c.rotate(tracker.model.rotation);
    c.drawImage(t, RectF(-40, -40, offscreenSize, offscreenSize));
    c.restore();

    labelAt(r, "small", PointF(8, 108));
    c.drawImage(t, RectF(8, 124, 32, 32));
    c.drawImageTinted(t, RectF(48, 124, 32, 32), ColorF(1, 1, 1, 0.5f));

    labelAt(r, "shadow 1.2x", PointF(130, 130));
    c.save();
    Shadow soft;
    soft.offset = PointF(5, 6);
    soft.blur = 10;
    soft.color = ColorF(0, 0, 0, 0.8f);
    c.shadow(soft);
    c.drawImageRegion(t, pixelRect(offscreen), RectF(150, 140, 96, 96));
    c.restore();
    saveOffscreenIfRequested();
  }

  // Section 11: Pattern fills/strokes (repeat modes, transform, tint, RT).
  void drawPatterns(Renderer r, in Widget w) {
    if (sampleImage is null) {
      labelAt(r, "sample.png failed to decode", PointF(8, 0));
      return;
    }
    if (sampleTexture is null) {
      sampleTexture = r.createTexture(sampleImage);
    }
    auto c = r.canvas();
    drawPatternRepeats(r, c);
    drawPatternAnimAndStroke(r, c);
    if (syncOffscreen(r)) {
      drawRtPattern(r, c);
    }
  }

  void drawPatternRepeats(Renderer r, Canvas c) {
    // 1. repeat (0.4x) in a rounded rect with a soft drop shadow
    labelAt(r, "repeat", PointF(8, 0));
    c.save();
    Shadow soft;
    soft.offset = PointF(3, 4);
    soft.blur = 8;
    soft.color = ColorF(0, 0, 0, 0.7f);
    c.shadow(soft);
    auto repPat = Pattern.fromTexture(sampleTexture, PatternRepeat.repeat)
      .withTransform(
        Transform2d.translation(PointF(8, 16))
          * Transform2d.scaling(PointF(0.4f, 0.4f))
      );
    c.fillStyle(FillStyle.fromPattern(repPat));
    c.fill(patternTileRect);
    c.restore();

    // 2. repeatX strip and noRepeat single tile (0.5x)
    labelAt(r, "repeatX", PointF(142, 0));
    auto stripPat = Pattern.fromTexture(sampleTexture, PatternRepeat.repeatX)
      .withTransform(
        Transform2d.translation(PointF(142, 16))
          * Transform2d.scaling(PointF(0.5f, 0.5f))
      );
    c.fillStyle(FillStyle.fromPattern(stripPat));
    c.fill(patternStripX);

    labelAt(r, "noRepeat", PointF(142, 56));
    auto oncePat = Pattern.fromTexture(sampleTexture, PatternRepeat.noRepeat)
      .withTransform(
        Transform2d.translation(PointF(142, 72))
          * Transform2d.scaling(PointF(0.5f, 0.5f))
      );
    c.fillStyle(FillStyle.fromPattern(oncePat));
    c.fill(patternOnceRect);
    c.strokeStyle(FillStyle.solid(ColorF(0.45f, 0.50f, 0.58f, 0.6f)));
    c.lineWidth(1);
    c.stroke(patternOnceRect);
  }

  void drawPatternAnimAndStroke(Renderer r, Canvas c) {
    // 3. animated rotated pattern with a blue-ish tint
    labelAt(r, "rot+tint", PointF(8, 98));
    const Transform2d rotXf = Transform2d.translation(PointF(46, 152))
      * Transform2d.rotation(tracker.model.rotation)
      * Transform2d.scaling(PointF(0.45f, 0.45f));
    auto rotPat = Pattern.fromTexture(sampleTexture, PatternRepeat.repeat)
      .withTransform(rotXf)
      .withTint(ColorF(0.60f, 0.85f, 1.0f, 1.0f));
    c.fillStyle(FillStyle.fromPattern(rotPat));
    c.fill(patternRotCircle);

    // 4. pattern stroke along a wave
    labelAt(r, "stroke", PointF(8, 194));
    c.save();
    auto strokePat = Pattern.fromTexture(sampleTexture, PatternRepeat.repeat)
      .withTransform(Transform2d.scaling(PointF(0.35f, 0.35f)));
    c.strokeStyle(FillStyle.fromPattern(strokePat));
    c.lineWidth(10);
    c.lineCap(LineCap.round);
    c.stroke(patternStrokeWave);
    c.restore();
  }

  void drawRtPattern(Renderer r, Canvas c) {
    Texture rtTex = offscreen.texture();
    if (rtTex is null || rtTex.width() <= 0 || rtTex.height() <= 0) {
      return;
    }
    labelAt(r, "RT pattern", PointF(168, 118));
    const float sx = 32.0f / rtTex.width();
    const float sy = 32.0f / rtTex.height();
    auto rtPat = Pattern.fromTexture(rtTex, PatternRepeat.repeat)
      .withTransform(
        Transform2d.translation(PointF(168, 134))
          * Transform2d.scaling(PointF(sx, sy))
      );
    c.fillStyle(FillStyle.fromPattern(rtPat));
    c.fill(patternRtRect);
  }

  // Section 12: alignment/baseline guides, rotation, gradient fill, outline
  // stroke, shadow and maxWidth squeezing.
  void drawText(Renderer r, in Widget w) {
    auto c = r.canvas();
    drawTextAlignments(c);
    drawTextEffects(c);
  }

  void drawTextAlignments(Canvas c) {
    c.save();
    c.fontSpec(FontSpec(13.0f, null));
    // guide lines at the anchor
    c.lineWidth(1);
    c.strokeStyle(FillStyle.solid(ColorF(0.95f, 0.45f, 0.45f, 0.7f)));
    c.stroke(textGuideV);
    c.stroke(textGuideH);
    c.fillStyle(FillStyle.solid(ColorF(0.90f, 0.92f, 0.98f, 1)));
    static immutable TextAlign[3] aligns = [
      TextAlign.left, TextAlign.center, TextAlign.right,
    ];
    foreach (i, a; aligns) {
      c.textAlign(a);
      c.textBaseline(TextBaseline.alphabetic);
      c.fillText(textAlignNames[i], PointF(133, 18 + i * 16));
    }
    c.textAlign(TextAlign.left);
    static immutable TextBaseline[3] bases = [
      TextBaseline.top, TextBaseline.middle, TextBaseline.alphabetic,
    ];
    foreach (i, b; bases) {
      c.textBaseline(b);
      c.fillText(textBaseNames[i], PointF(8 + i * 40, 80));
    }
    c.textBaseline(TextBaseline.alphabetic);
    c.direction(TextDirection.rtl);
    c.textAlign(TextAlign.start);
    c.fillText("rtl start", PointF(258, 100));
    c.restore();
  }

  void drawTextEffects(Canvas c) {
    c.save();
    c.fontSpec(FontSpec(22.0f, null));
    c.textBaseline(TextBaseline.middle);
    c.textAlign(TextAlign.center);

    // rotated text around its anchor
    c.save();
    c.translate(PointF(60, 160));
    c.rotate(tracker.model.rotation);
    c.fillStyle(FillStyle.solid(ColorF(0.95f, 0.80f, 0.30f, 1)));
    c.fillText("Rotate", PointF(0, 0));
    c.restore();

    // gradient fill
    c.fillStyle(textGradient);
    c.fontSpec(FontSpec(26.0f, null));
    c.fillText("Gradient", PointF(190, 130));

    // outline-only stroked text, then filled text with a drop shadow
    c.save();
    c.fontSpec(FontSpec(26.0f, null));
    c.lineWidth(1.5f);
    c.strokeStyle(FillStyle.solid(ColorF(0.55f, 0.90f, 1.0f, 1)));
    c.strokeText("Stroke", PointF(60, 205));
    Shadow sh;
    sh.offset = PointF(3, 4);
    sh.blur = 5;
    sh.color = ColorF(0, 0, 0, 0.85f);
    c.shadow(sh);
    c.fillStyle(FillStyle.solid(ColorF(0.95f, 0.55f, 0.35f, 1)));
    c.fillText("Shadow", PointF(190, 170));
    c.restore();

    // maxWidth squeezes the text horizontally
    c.fontSpec(FontSpec(16.0f, null));
    c.fillStyle(FillStyle.solid(ColorF(0.60f, 0.95f, 0.60f, 1)));
    c.fillTextWithMaxWidth("maxWidth 60 squeezed", PointF(190, 210), 60);
    c.restore();
  }

  /**
   * Creates the render target or keeps it in sync with the display scale,
   * redrawing it when it is new or was reallocated.
   * Returns: false if no valid target is available.
   */
  bool syncOffscreen(Renderer r) {
    bool dirty = false;
    if (offscreen is null) {
      offscreen = r.createRenderTarget(offscreenSize, offscreenSize, true);
      if (offscreen is null) {
        return false;
      }
      dirty = true;
    } else {
      const int pw = offscreen.pixelWidth();
      const int ph = offscreen.pixelHeight();
      r.resizeRenderTarget(offscreen, offscreenSize, offscreenSize);
      dirty = pw != offscreen.pixelWidth() || ph != offscreen.pixelHeight();
    }
    if (!offscreen.isValid()) {
      return false;
    }
    if (dirty) {
      renderOffscreen(r);
    }
    return true;
  }

  /// Draws the gradient star, its stroke and a label into the target.
  void renderOffscreen(Renderer r) {
    r.beginTarget(offscreen, true);
    auto c = r.canvas();
    c.save();
    c.translate(PointF(40, 42));
    c.scale(PointF(0.62f, 0.62f));
    c.fillStyle(offscreenFill);
    c.fill(star);
    c.lineWidth(4);
    c.lineJoin(LineJoin.round);
    c.strokeStyle(FillStyle.solid(ColorF(1, 1, 1, 0.9f)));
    c.stroke(star);
    c.restore();
    r.drawTextWithFont(
      "RT", PointF(31, 34), ColorF(0.10f, 0.10f, 0.20f, 1),
      r.font(14.0f, null)
    );
    r.endTarget();
  }

  /// Saves the target as a PNG once per new [P] request in the model.
  void saveOffscreenIfRequested() {
    import std.logger : errorf, infof;

    const uint serial = tracker.model.offscreenSaveSerial;
    if (serial == savedSerial) {
      return;
    }
    savedSerial = serial;
    const string path = tracker.model.offscreenSavePath;
    auto img = offscreen.toImage();
    if (img is null || !img.savePng(path)) {
      errorf("offscreen: failed to save %s", path);
      return;
    }
    infof("offscreen: saved %dx%d image to %s", img.width(), img.height(),
      path);
  }

  /// Whole texture of `rt` in pixels.
  static RectF pixelRect(RenderTarget rt) {
    return RectF(0, 0, rt.pixelWidth(), rt.pixelHeight());
  }

  /// Absolute logic rect of size `w` x `h` at canvas-local `pos`.
  static RectF destAt(Renderer r, PointF pos, float w, float h) {
    const PointF p = r.canvas().transform().apply(pos);
    return RectF(p.x, p.y, w, h);
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
      r.font(13.0f, null)
    );
  }

  /// Status hints after the [I] hint.
  enum string statusTail = " | [P] Save offscreen PNG | [S] Shadow blur";
  enum float cardWidth = 290;
  enum float cardHeight = 280;
  enum float cardGap = 20;
  enum float drawWidth = 266;
  enum float drawHeight = 232;
  /// Offscreen target size in logic units (square).
  enum float offscreenSize = 80;

  UiSystem ui;
  ModelTracker!CanvasPageModel tracker;
  Widget root;
  Widget strokesWidget;
  Widget transformsWidget;
  Widget interopWidget;
  Widget shadowsWidget;
  Widget imagesWidget;
  Widget offscreenWidget;
  Widget patternsWidget;
  Widget textWidget;
  Widget[] sectionWidgets;
  Image sampleImage;
  Texture sampleTexture;
  /// Cached offscreen drawing (section 10), null until the first draw.
  RenderTarget offscreen;
  /// Last `offscreenSaveSerial` handled by the offscreen draw.
  uint savedSerial;
  /// Cached `hardBlurLabel()` text and the blur it was built for.
  string hardBlurText;
  int hardBlurTextValue;
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
  Path2d imageClip;
  Path2d patternTileRect;
  Path2d patternStripX;
  Path2d patternOnceRect;
  Path2d patternRotCircle;
  Path2d patternStrokeWave;
  Path2d patternRtRect;
  Path2d textGuideV;
  Path2d textGuideH;
  static immutable string[3] textAlignNames = [
    "left", "center", "right",
  ];
  static immutable string[3] textBaseNames = [
    "top", "mid", "alpha",
  ];
  FillStyle linearFill;
  FillStyle radialFill;
  FillStyle gradientStroke;
  FillStyle offscreenFill;
  FillStyle textGradient;
}

unittest {
  import yguilib.uisystem : makeHeadlessUiSystem;

  auto ui = makeHeadlessUiSystem();
  auto root = new Widget(ui.nextWidgetId());
  auto tracker = ModelTracker!CanvasPageModel(new CanvasPageModel());
  auto page = new CanvasPage(ui, root, tracker);
  assert(page.rootWidget().parent is root);
  assert(page.drawWidgets().length == 12);
  foreach (w; page.drawWidgets()) {
    assert(w.components.customDraw !is null);
    assert(w.components.customDraw.drawFunc !is null);
  }
  assert(
    page.formatStatus()
      == "[Space] Pause animation | [I] Show offscreen"
      ~ " | [P] Save offscreen PNG | [S] Shadow blur"
  );

  // the sample PNG decodes once; slot 7 shows images, others are hidden
  assert(page.image() !is null);
  assert(page.image().width() == 64 && page.image().height() == 64);
  const Widget imagesCard = page.imagesWidget.parent;
  const Widget interopCard = page.interopWidget.parent;
  const Widget offscreenCard = page.offscreenWidget.parent;
  const Widget patternsCard = page.patternsWidget.parent;
  const Widget textCard = page.textWidget.parent;
  assert(imagesCard.visible && !interopCard.visible);
  assert(!offscreenCard.visible && !patternsCard.visible);
  assert(imagesCard.rect == interopCard.rect);
  assert(offscreenCard.rect == interopCard.rect);
  assert(patternsCard.rect == interopCard.rect);
  assert(textCard.rect == interopCard.rect && !textCard.visible);
  // the top-left corner is red (orientation marker)
  const ubyte[] px = page.image().pixels;
  assert(px[0] > 200 && px[1] < 80 && px[2] < 80 && px[3] == 255);
  page.releaseGpuResources();

  // a model change marks the animated widgets dirty
  page.update();
  assert(!page.update());
  auto m = tracker.edit();
  m.rotation = 1.0f;
  tracker.commit(m);
  assert(page.update());
  assert(!page.update());

  // the slot 7 model value selects exactly one card
  m = tracker.edit();
  m.slot7 = CanvasSlot7.interop;
  tracker.commit(m);
  assert(page.update());
  assert(!imagesCard.visible && interopCard.visible);
  assert(!offscreenCard.visible && !patternsCard.visible);
  assert(
    page.formatStatus() == "[Space] Pause animation | [I] Show images"
      ~ " | [P] Save offscreen PNG | [S] Shadow blur"
  );
  m = tracker.edit();
  m.slot7 = CanvasSlot7.offscreen;
  tracker.commit(m);
  assert(page.update());
  assert(!imagesCard.visible && !interopCard.visible);
  assert(offscreenCard.visible && !patternsCard.visible);
  assert(
    page.formatStatus() == "[Space] Pause animation | [I] Show patterns"
      ~ " | [P] Save offscreen PNG | [S] Shadow blur"
  );
  m = tracker.edit();
  m.slot7 = CanvasSlot7.patterns;
  tracker.commit(m);
  assert(page.update());
  assert(!imagesCard.visible && !interopCard.visible);
  assert(!offscreenCard.visible && patternsCard.visible);
  assert(
    page.formatStatus() == "[Space] Pause animation | [I] Show text"
      ~ " | [P] Save offscreen PNG | [S] Shadow blur"
  );
  m = tracker.edit();
  m.slot7 = CanvasSlot7.text;
  tracker.commit(m);
  assert(page.update());
  assert(textCard.visible && !patternsCard.visible);

  // the hard shadow label follows the model blur
  assert(page.hardBlurLabel() == "blur 0");
  m = tracker.edit();
  m.hardShadowBlur = 12;
  tracker.commit(m);
  assert(page.update());
  assert(page.hardBlurLabel() == "blur 12");
  assert(
    page.formatStatus() == "[Space] Pause animation | [I] Show interop"
      ~ " | [P] Save offscreen PNG | [S] Shadow blur"
  );
}
