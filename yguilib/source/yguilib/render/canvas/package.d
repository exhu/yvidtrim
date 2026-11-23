/** 2d drawing api similar to HTML canvas 2d api or svg. Reduced in features,
    simplified, uses float, int and other efficient types.
    https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial

    A radial gradient with a negative radius, or a negative path radius, draws
    nothing instead of raising an error.

    Square caps on zero-length segments: they stay axis-aligned instead of
    rotating with the path, which shows on diagonal lines.
*/
module yguilib.render.canvas;

import std.array : Appender;
import yguilib.render : Renderer;
import yguilib.render.canvas.path2d : Path2d;
import yguilib.render.font : Font, defaultFontPtSize;
import yguilib.render.canvas.types;
import yguilib.render.internal.offscreen : SavedTargetState;
import yguilib.render.internal.path_flatten : Contours;
import yguilib.render.internal.pipelines : GradientUniforms, PatternUniforms,
  TextureMode;
import yguilib.render.render_types;
import yguilib.render.texture : Texture;

/**
 * canvas context
 *
 * Fills and strokes `Path2d` with the Renderer's color or gradient
 * pipeline using stencil-then-cover (exact `nonZero` / `evenOdd`); the
 * current transform is applied on the CPU (gradients get its inverse).
 * `clip()` lives in stencil bit 7 and affects only Canvas calls: the
 * Canvas enables `GL_STENCIL_TEST` only inside its own calls, so Renderer
 * `draw*` calls ignore the Canvas clip and transform. The Renderer
 * scissor clip (`pushClipRect`) limits both. `Renderer.clearFrame`
 * resets the Canvas state.
 *
 * `drawImage*` blits textures (images and `RenderTarget.texture()`) as
 * textured triangles honoring the transform, clip and shadow, unlike
 * `Renderer.drawImage`, which ignores all three.
 */
final class Canvas {
// do not replicate standalone path functions, like ctx.arc or ctx.beginPath,
// the user is expected to use Path2d instead to draw paths

  /// Created by `Renderer`; `r` must not be null.
  this(Renderer r) {
    assert(r !is null);
    fRenderer = r;
    fRectPath = new Path2d();
  }

  invariant {
    assert(fRenderer !is null);
    assert(fRectPath !is null);
  }

  /**
   * Sets `rect` (transformed by the current transform) to transparent
   * black, honoring the Canvas clip and the scissor.
   */
  void clearRect(RectF rect) {
    fRectPath.clear();
    fRectPath.rect(rect);
    fillWithRule(
      fRectPath, FillRule.nonZero, FillStyle.solid(ColorF(0, 0, 0, 0)),
      false
    );
  }

  void fillStyle(FillStyle style) {
    st.fill = style;
  }

  FillStyle fillStyle() const {
    return st.fill;
  }

  void strokeStyle(StrokeStyle style) {
    st.stroke = style;
  }

  StrokeStyle strokeStyle() const {
    return st.stroke;
  }

  /// Ignores zero, negative and non-finite widths.
  void lineWidth(float w) {
    import std.math : isFinite;

    if (isFinite(w) && w > 0) {
      st.lineWidth = w;
    }
  }

  float lineWidth() const {
    return st.lineWidth;
  }

  void lineCap(LineCap cap) {
    st.cap = cap;
  }

  LineCap lineCap() const {
    return st.cap;
  }

  void lineJoin(LineJoin join) {
    st.join = join;
  }

  LineJoin lineJoin() const {
    return st.join;
  }

  /// Ignores zero, negative and non-finite limits.
  void miterLimit(float miter) {
    import std.math : isFinite;

    if (isFinite(miter) && miter > 0) {
      st.miterLimit = miter;
    }
  }

  float miterLimit() const {
    return st.miterLimit;
  }

  /// Stores a normalized copy (see `LineDash.fromSegments`).
  void lineDash(LineDash dash) {
    st.dash = LineDash.fromSegments(dash.segments);
  }

  LineDash lineDash() const {
    return LineDash.fromSegments(st.dash.segments);
  }

  /// Ignores non-finite offsets.
  void lineDashOffset(float offset) {
    import std.math : isFinite;

    if (isFinite(offset)) {
      st.dashOffset = offset;
    }
  }

  float lineDashOffset() const {
    return st.dashOffset;
  }

  void fillRule(FillRule rule) {
    st.fillRule = rule;
  }

  FillRule fillRule() const {
    return st.fillRule;
  }

  /**
   * Sets the shadow of later fills and strokes; ignored when `s` has a
   * non-finite offset or blur, or a negative blur.
   */
  void shadow(Shadow s) {
    import std.math : isFinite;

    if (finitePoint(s.offset) && isFinite(s.blur) && s.blur >= 0) {
      st.shadow = s;
    }
  }

  Shadow shadow() const {
    return st.shadow;
  }

  /// Fills `path` with `fillStyle` using `fillRule`.
  void fill(Path2d path) {
    fillWithRule(path, st.fillRule, st.fill, true);
  }

  /// Strokes `path` with `strokeStyle`; overlaps are painted once.
  void stroke(Path2d path) {
    import glad2.gles2 : GL_TRIANGLES;
    import yguilib.render.internal.path_flatten : flattenPath;
    import yguilib.render.internal.path_stroker : StrokeParams,
      strokeContours;
    import yguilib.render.internal.stencil_ops : beginResetLow,
      beginStrokeOnce, endStencil;

    assert(path !is null);
    if (!canDraw(path) || !paintVisible(st.stroke)
      || !patternDrawable(st.stroke)) {
      return;
    }
    const float tol = tolerance(st.xf);
    flattenPath(path, tol, fContours);
    StrokeParams p;
    p.width = st.lineWidth;
    p.cap = st.cap;
    p.join = st.join;
    p.miterLimit = st.miterLimit;
    p.dash = st.dash.segments;
    p.dashOffset = st.dashOffset;
    p.tolerance = tol;
    fLocalTris.clear();
    strokeContours(fContours, p, fLocalTris);
    transformVerts(fLocalTris[], st.xf);
    if (fVerts[].length == 0) {
      return;
    }
    if (st.shadow.isVisible()) {
      drawShadow(ShadowShape.stroke, FillRule.nonZero, st.stroke);
    }
    beginStrokeOnce(clipActive());
    drawPaint(fVerts[], st.stroke);
    beginResetLow();
    drawVerts(fVerts[], ColorF(0, 0, 0, 0));
    endStencil();
  }

  /**
   * Draws the whole texture `t` stretched to `dest` (user space, mapped
   * by the current transform), honoring the Canvas clip and shadow
   * (HTML `drawImage(img, dx, dy, dw, dh)`). A null `t` (allowed) is a
   * no-op. See `drawImageRegionTinted`.
   */
  void drawImage(Texture t, RectF dest) {
    drawImageTinted(t, dest, ColorF(1, 1, 1, 1));
  }

  /**
   * Like `drawImage`, multiplied by `tint` (straight alpha; `tint.a`
   * acts as a global alpha). A null `t` (allowed) is a no-op.
   */
  void drawImageTinted(Texture t, RectF dest, ColorF tint) {
    if (t is null) {
      return;
    }
    drawImageRegionTinted(
      t, RectF(0, 0, t.width(), t.height()), dest, tint
    );
  }

  /**
   * Draws the `srcPx` region (texture pixels, top-left origin) of `t`
   * stretched to `dest` (HTML `drawImage(img, sx, sy, sw, sh, dx, dy,
   * dw, dh)`). A null `t` (allowed) is a no-op.
   */
  void drawImageRegion(Texture t, RectF srcPx, RectF dest) {
    drawImageRegionTinted(t, srcPx, dest, ColorF(1, 1, 1, 1));
  }

  /**
   * Draws the `srcPx` region (texture pixels, top-left origin, not
   * clamped: sampling clamps to the edge) of `t` stretched to `dest`
   * (user space, mapped by the current transform), multiplied by `tint`
   * (straight alpha). Honors the Canvas clip and shadow (the shadow mask
   * is the texture alpha * `tint.a`). Premultiplied and bottom-up
   * textures (render targets) are handled. Draws nothing when `t` is null
   * (allowed) or destroyed, `srcPx` or `dest` is empty or non-finite, or
   * `tint.a <= 0`. `t` must not be the texture of an active render
   * target.
   */
  void drawImageRegionTinted(
    Texture t,
    RectF srcPx,
    RectF dest,
    ColorF tint
  ) {
    import yguilib.render.internal.pipelines : TextureMode;
    import yguilib.render.internal.stencil_ops : beginClipTest, endStencil;

    if (!fRenderer.isInitialized() || t is null || !t.isValid()
      || !rectDrawable(srcPx) || !rectDrawable(dest) || !(tint.a > 0)) {
      return;
    }
    assert(!fRenderer.isActiveTargetTexture(t),
      "drawing the texture of an active render target (feedback loop)");
    buildImageVerts(t, srcPx, dest);
    if (st.shadow.isVisible()) {
      drawImageShadow(t, tint.a);
    }
    const TextureMode mode = t.premultiplied()
      ? TextureMode.premultiplied : TextureMode.straight;
    beginClipTest(clipActive());
    fRenderer.texturePipelineRef().drawTexturedTriangles(
      t.id(), fImageVerts[], tint, mode, fRenderer.logicWidth(),
      fRenderer.logicHeight()
    );
    endStencil();
  }

  // push state
  void save() {
    State copy = st;
    copy.clips = st.clips.dup;
    fStack.put(copy);
  }

  // pop state
  void restore() {
    const size_t n = fStack[].length;
    if (n == 0) {
      return;
    }
    const bool clipsChanged = fStack[][n - 1].clips.length
      != st.clips.length;
    st = fStack[][n - 1];
    fStack.shrinkTo(n - 1);
    if (clipsChanged) {
      rebuildClip();
    }
  }

  void translate(PointF offset) {
    if (finitePoint(offset)) {
      st.xf = st.xf * Transform2d.translation(offset);
    }
  }

  void rotate(float radians) {
    import std.math : isFinite;

    if (isFinite(radians)) {
      st.xf = st.xf * Transform2d.rotation(radians);
    }
  }

  /// supports negative for axis mirroring
  void scale(PointF factor) {
    if (finitePoint(factor)) {
      st.xf = st.xf * Transform2d.scaling(factor);
    }
  }

  /// to the identity matrix
  void resetTransform() {
    st.xf = Transform2d.identity();
  }

  /// Current transform (local to logic coordinates).
  Transform2d transform() const {
    return st.xf;
  }

  /// sets clipping mask; use save() and then restore() to undo clipping.
  void clip(Path2d path) {
    assert(path !is null);
    auto copy = new Path2d();
    copy.addPath(path, Transform2d.identity());
    ClipEntry e = ClipEntry(copy, st.xf, st.clipRule);
    const bool first = st.clips.length == 0;
    st.clips ~= e;
    if (!fRenderer.isInitialized()) {
      return;
    }
    const bool scissor = disableScissor();
    if (first) {
      clearClipBit(true);
    }
    applyClip(e);
    restoreScissor(scissor);
  }

  void clipFillRule(FillRule rule) {
    st.clipRule = rule;
  }

  FillRule clipFillRule() const {
    return st.clipRule;
  }

  /// Font used by text calls; invalid sizes (non-finite, <= 0) are ignored.
  void fontSpec(FontSpec spec) {
    import std.math : isFinite;

    if (isFinite(spec.ptSize) && spec.ptSize > 0) {
      st.fontSpec = spec;
    }
  }

  FontSpec fontSpec() const {
    return st.fontSpec;
  }

  void textAlign(TextAlign a) {
    st.textAlign = a;
  }

  TextAlign textAlign() const {
    return st.textAlign;
  }

  void textBaseline(TextBaseline b) {
    st.textBaseline = b;
  }

  TextBaseline textBaseline() const {
    return st.textBaseline;
  }

  void direction(TextDirection d) {
    st.direction = d;
  }

  TextDirection direction() const {
    return st.direction;
  }

  /**
   * Measures `text` with the current font in logic units. Returns zeros
   * when the renderer is uninitialized or `text` is empty.
   */
  TextMetrics measureText(string text) {
    TextMetrics res;
    if (!fRenderer.isInitialized() || text.length == 0) {
      return res;
    }
    const spec = st.fontSpec;
    const PointF sz = fRenderer.measureTextWithFontName(
      text, spec.ptSize, spec.name
    );
    res.width = sz.x;
    Font f = fRenderer.font(spec.ptSize, spec.name);
    if (f !is null) {
      import std.math : abs;

      res.fontAscent = fRenderer.logicFromPixelsFloat(f.ascent);
      res.fontDescent = fRenderer.logicFromPixelsFloat(abs(f.descent));
    }
    return res;
  }

package(yguilib.render):
  /// Resets to the default state with an empty save stack (new frame).
  void resetFrame() {
    st = State.init;
    fStack.clear();
  }

  /// Drawing state and save stack kept across a render target pass.
  struct FrameState {
    private State st;
    private State[] stack;
  }

  /**
   * Copies the current state and save stack (`Renderer.beginTarget`
   * calls `resetFrame()` afterwards).
   */
  FrameState saveFrameState() {
    FrameState s;
    s.st = st;
    s.stack = fStack[].dup;
    return s;
  }

  /**
   * Restores a state saved by `saveFrameState`. The clip bit is not
   * rebuilt: it still lives in the stencil of the restored framebuffer.
   */
  void restoreFrameState(FrameState s) {
    st = s.st;
    fStack.clear();
    foreach (ref e; s.stack) {
      fStack.put(e);
    }
  }

private:
  /// One `clip()` call, replayed to rebuild the clip bit on `restore()`.
  struct ClipEntry {
    Path2d path;
    Transform2d xf;
    FillRule rule;
  }

  /// Drawing state saved by `save()`.
  struct State {
    FillStyle fill;
    StrokeStyle stroke;
    float lineWidth = 1;
    LineCap cap = LineCap.butt;
    LineJoin join = LineJoin.miter;
    float miterLimit = 10;
    LineDash dash;
    float dashOffset = 0;
    FillRule fillRule = FillRule.nonZero;
    FillRule clipRule = FillRule.nonZero;
    Transform2d xf;
    ClipEntry[] clips;
    Shadow shadow;
    FontSpec fontSpec;
    TextAlign textAlign = TextAlign.start;
    TextBaseline textBaseline = TextBaseline.alphabetic;
    TextDirection direction = TextDirection.ltr;
  }

  /// Geometry in `fVerts` for `drawShadow`.
  enum ShadowShape {
    /// fan triangles filled by stencil-then-cover with a fill rule
    fill,
    /// stroke triangles drawn directly
    stroke,
  }

  /// Pixel rectangle of a shadow pass (origin top-left, y down).
  struct PixelBox {
    int x;
    int y;
    int width;
    int height;
  }

  Renderer fRenderer;
  State st;
  Appender!(State[]) fStack;
  /// Reused scratch buffers (no per-call GC churn).
  Contours fContours;
  Appender!(float[]) fLocalTris;
  Appender!(float[]) fVerts;
  Appender!(float[]) fShadowVerts;
  /// (x, y, u, v) triangles of the last `drawImageRegionTinted`.
  Appender!(float[]) fImageVerts;
  Path2d fRectPath;

  bool clipActive() const {
    return st.clips.length > 0;
  }

  bool canDraw(const Path2d path) const {
    return fRenderer.isInitialized() && !path.isEmpty();
  }

  float tolerance(in Transform2d xf) const {
    import yguilib.render.internal.path_flatten : flattenTolerance;

    return flattenTolerance(fRenderer.totalScaling(), xf);
  }

  static bool finitePoint(PointF p) {
    import std.math : isFinite;

    return isFinite(p.x) && isFinite(p.y);
  }

  /// True when `r` is finite with a positive width and height.
  static bool rectDrawable(in RectF r) {
    import std.math : isFinite;

    return isFinite(r.x) && isFinite(r.y) && isFinite(r.width)
      && isFinite(r.height) && r.width > 0 && r.height > 0;
  }

  /// True when `m` has a finite non-zero determinant.
  static bool isInvertible(in Transform2d m) nothrow @safe @nogc {
    import std.math : abs, isFinite;

    const float det = m.a * m.d - m.b * m.c;
    return isFinite(det) && abs(det) >= 1e-12f;
  }

  /**
   * False when `s` cannot paint anything: transparent color, gradient
   * without visible stops, radial gradient with a negative radius, or an
   * invalid/transparent pattern.
   */
  static bool paintVisible(in FillStyle s) {
    final switch (s.kind) {
    case FillStyle.Kind.color:
      return s.color.a > 0;
    case FillStyle.Kind.linearGradient:
      return stopsVisible(s.linear.stops);
    case FillStyle.Kind.radialGradient:
      return s.radial.r0 >= 0 && s.radial.r1 >= 0
        && stopsVisible(s.radial.stops);
    case FillStyle.Kind.pattern:
      return s.pattern.texture !is null && s.pattern.texture.isValid()
        && s.pattern.texture.width() > 0 && s.pattern.texture.height() > 0
        && s.pattern.tint.a > 0 && isInvertible(s.pattern.transform);
    }
  }

  /// False when `s` is a pattern whose combined transform is singular.
  bool patternDrawable(in FillStyle s) const {
    if (s.kind != FillStyle.Kind.pattern) {
      return true;
    }
    return isInvertible(st.xf * s.pattern.transform);
  }

  static bool stopsVisible(in GradientStops stops) {
    foreach (ref stop; stops.items()) {
      if (stop.color.a > 0) {
        return true;
      }
    }
    return false;
  }

  /**
   * Gradient shader uniforms of gradient style `s`; `invXf` maps logic
   * coordinates to the gradient's user space.
   */
  static GradientUniforms gradientUniforms(
    in FillStyle s,
    in Transform2d invXf
  ) {
    const bool linear = s.kind == FillStyle.Kind.linearGradient;
    GradientUniforms u;
    u.invXf = [invXf.a, invXf.b, 0, invXf.c, invXf.d, 0, invXf.e,
      invXf.f, 1];
    const(GradientStop)[] items;
    if (linear) {
      u.kind = 0;
      u.p0 = s.linear.p0;
      u.p1 = s.linear.p1;
      items = s.linear.stops.items();
    } else {
      u.kind = 1;
      u.p0 = s.radial.c0;
      u.p1 = s.radial.c1;
      u.r0 = s.radial.r0;
      u.r1 = s.radial.r1;
      items = s.radial.stops.items();
    }
    static assert(GradientUniforms.maxStops == maxGradientStops);
    foreach (i, ref stop; items) {
      u.stopOffsets[i] = stop.offset;
      u.stopColors[i * 4 .. i * 4 + 4] = [stop.color.r, stop.color.g,
        stop.color.b, stop.color.a];
    }
    u.stopCount = cast(int)items.length;
    return u;
  }

  /**
   * Pattern shader uniforms of `p`; `logicToPattern` maps logic coordinates
   * to pattern pixel space.
   */
  static PatternUniforms patternUniforms(
    in Pattern p,
    in Transform2d logicToPattern,
    TextureMode mode
  ) {
    const float tw = p.texture.width();
    const float th = p.texture.height();
    const Transform2d uvXf =
      Transform2d.scaling(PointF(1.0f / tw, 1.0f / th)) * logicToPattern;
    PatternUniforms u;
    u.textureId = p.texture.id();
    u.invXf = [uvXf.a, uvXf.b, 0, uvXf.c, uvXf.d, 0, uvXf.e, uvXf.f, 1];
    u.tint = p.tint;
    u.repeat = cast(int)p.repeat;
    u.mode = mode;
    u.bottomUp = p.texture.bottomUp();
    return u;
  }

  /**
   * Colored pass of a fill (cover) or stroke: solid styles use the color
   * pipeline, gradients the gradient pipeline, and patterns the pattern
   * pipeline with the inverse of the combined transform. The stencil state
   * must already be set.
   */
  void drawPaint(const(float)[] verts, in FillStyle style) {
    if (verts.length == 0) {
      return;
    }
    final switch (style.kind) {
    case FillStyle.Kind.color:
      drawVerts(verts, style.color);
      return;
    case FillStyle.Kind.linearGradient:
    case FillStyle.Kind.radialGradient:
      const GradientUniforms u = gradientUniforms(style, st.xf.inverse());
      fRenderer.gradientPipelineRef().drawTriangles(
        verts, u, fRenderer.logicWidth(), fRenderer.logicHeight()
      );
      return;
    case FillStyle.Kind.pattern:
      assert(!fRenderer.isActiveTargetTexture(style.pattern.texture),
        "drawing the texture of an active render target (feedback loop)");
      const Transform2d logicToPat =
        (st.xf * style.pattern.transform).inverse();
      const TextureMode mode = style.pattern.texture.premultiplied()
        ? TextureMode.premultiplied : TextureMode.straight;
      const PatternUniforms u = patternUniforms(
        style.pattern, logicToPat, mode
      );
      fRenderer.patternPipelineRef().drawTriangles(
        verts, u, fRenderer.logicWidth(), fRenderer.logicHeight()
      );
      return;
    }
  }

  /**
   * Stencil-then-cover fill of `path`. With `blend` false the cover pass
   * overwrites pixels with the solid color of `style` (used by
   * `clearRect`); with `blend` true an invisible `style` draws nothing.
   */
  void fillWithRule(
    Path2d path,
    FillRule rule,
    in FillStyle style,
    bool blend
  ) {
    import glad2.gles2 : GL_BLEND, GL_TRIANGLES, glDisable;
    import yguilib.render.internal.path_flatten : flattenPath;
    import yguilib.render.internal.stencil_ops : beginCover, beginWinding,
      endStencil;

    assert(path !is null);
    if (!canDraw(path) || (blend && (!paintVisible(style)
      || !patternDrawable(style)))) {
      return;
    }
    flattenPath(path, tolerance(st.xf), fContours);
    buildFan(st.xf);
    if (fVerts[].length == 0) {
      return;
    }
    if (blend && st.shadow.isVisible()) {
      drawShadow(ShadowShape.fill, rule, style);
    }
    const float[12] cover = quadFromRect(boundsOfVerts(fVerts[]));
    beginWinding(rule);
    drawVerts(fVerts[], ColorF(0, 0, 0, 0));
    beginCover(rule, clipActive());
    if (blend) {
      drawPaint(cover[], style);
    } else {
      glDisable(GL_BLEND);
      fRenderer.colorPipelineRef().drawArraysWithCurrentState(
        GL_TRIANGLES, cover[], style.color, fRenderer.logicWidth(),
        fRenderer.logicHeight()
      );
      // the next draw re-enables blending via setupAlphaBlendState
    }
    endStencil();
  }

  /**
   * Shadow of `fVerts` (logic coordinates): a mask of `shape` carrying the
   * alpha of `style` in offscreen target 0 over the padded device bounds,
   * blurred through target 1, then composited with `st.shadow.color` at
   * the offset under the Canvas clip, so shadow alpha = shadow color alpha
   * * paint alpha (as in HTML canvas). Framebuffer, viewport, scissor and
   * clear color are saved before and restored after the offscreen passes.
   */
  void drawShadow(ShadowShape shape, FillRule rule, in FillStyle style) {
    const pass = beginShadowPass();
    if (pass.isNull) {
      return;
    }
    drawShadowMask(shape, rule, style, pass.get.box, pass.get.scale);
    endShadowPass(pass.get);
  }

  /**
   * Shadow of the `fImageVerts` image triangles (`fVerts` gets their xy
   * for `shadowBox`): the mask is the alpha of texture `t` * `alpha`, so
   * shadow alpha = shadow color alpha * image alpha * tint alpha.
   */
  void drawImageShadow(Texture t, float alpha) {
    const(float)[] xyuv = fImageVerts[];
    fVerts.clear();
    for (size_t i = 0; i + 3 < xyuv.length; i += 4) {
      fVerts.put(xyuv[i]);
      fVerts.put(xyuv[i + 1]);
    }
    const pass = beginShadowPass();
    if (pass.isNull) {
      return;
    }
    drawImageShadowMask(t, alpha, pass.get.box, pass.get.scale);
    endShadowPass(pass.get);
  }

  /// Offscreen shadow pass in progress (see `beginShadowPass`).
  struct ShadowPass {
    PixelBox box;
    float scale;
    float sigma;
    SavedTargetState saved;
  }

  /**
   * Saves the target state and binds the cleared region of offscreen
   * target 0 for the shadow box of `fVerts`. Null (nothing bound) when
   * the box is empty.
   */
  auto beginShadowPass() {
    import std.typecons : Nullable;
    import yguilib.render.internal.offscreen : OffscreenTarget;

    const float scale = fRenderer.totalScaling();
    const float sigma = st.shadow.blur * 0.5f * scale;
    const box = shadowBox(sigma, scale);
    Nullable!ShadowPass res;
    if (box.isNull) {
      return res;
    }
    const PixelBox b = box.get;
    OffscreenTarget* a = &fRenderer.offscreenTargetRef(0);
    res = ShadowPass(b, scale, sigma, SavedTargetState.capture());
    a.ensureSize(b.width, b.height);
    a.bindRegion(b.width, b.height, true);
    return res;
  }

  /// Blurs the drawn mask, restores the target state and composites.
  void endShadowPass(in ShadowPass p) {
    if (p.sigma > 0) {
      blurShadow(p.box, p.sigma);
    }
    p.saved.restore();
    compositeShadow(p.box, p.scale);
  }

  /**
   * Device box of the shadow pass: `fVerts` bounds in pixels padded by
   * 3 sigma (+1), limited to what can reach the viewport after the
   * offset. Null when empty.
   */
  auto shadowBox(float sigma, float scale) {
    import std.algorithm : max, min;
    import std.math : ceil, floor;
    import std.typecons : Nullable;

    const RectF r = boundsOfVerts(fVerts[]);
    const float pad = ceil(3 * sigma) + 1;
    const float offX = st.shadow.offset.x * scale;
    const float offY = st.shadow.offset.y * scale;
    const float pw = fRenderer.pixelWidth();
    const float ph = fRenderer.pixelHeight();
    const float x0 = max(floor(r.x * scale), floor(-offX)) - pad;
    const float y0 = max(floor(r.y * scale), floor(-offY)) - pad;
    const float x1 = min(ceil((r.x + r.width) * scale), ceil(pw - offX))
      + pad;
    const float y1 = min(ceil((r.y + r.height) * scale), ceil(ph - offY))
      + pad;
    Nullable!PixelBox res;
    if (x1 > x0 && y1 > y0) {
      res = PixelBox(cast(int)x0, cast(int)y0, cast(int)(x1 - x0),
        cast(int)(y1 - y0));
    }
    return res;
  }

  /**
   * Draws `fVerts` shifted to the origin of box `b` into the bound
   * offscreen region (no Canvas clip there). The colored pass runs with
   * blending disabled so the mask alpha equals the paint alpha of `style`
   * (blending onto the cleared target would square it).
   */
  void drawShadowMask(
    ShadowShape shape,
    FillRule rule,
    in FillStyle style,
    in PixelBox b,
    float scale
  ) {
    import glad2.gles2 : GL_TRIANGLES;
    import yguilib.render.internal.pipelines : ColorPipeline;
    import yguilib.render.internal.stencil_ops : beginCover, beginWinding,
      endStencil;

    const float ox = b.x / scale;
    const float oy = b.y / scale;
    const float vw = b.width / scale;
    const float vh = b.height / scale;
    const(float)[] verts = fVerts[];
    fShadowVerts.clear();
    for (size_t i = 0; i + 1 < verts.length; i += 2) {
      fShadowVerts.put(verts[i] - ox);
      fShadowVerts.put(verts[i + 1] - oy);
    }
    ColorPipeline* color = &fRenderer.colorPipelineRef();
    final switch (shape) {
    case ShadowShape.fill:
      beginWinding(rule);
      color.drawArrays(GL_TRIANGLES, fShadowVerts[], ColorF(0, 0, 0, 0),
        vw, vh);
      beginCover(rule, false);
      const float[12] cover = quadFromRect(RectF(0, 0, vw, vh));
      drawMaskPaint(cover[], style, PointF(ox, oy), vw, vh);
      endStencil();
      break;
    case ShadowShape.stroke:
      // no blending: overlapping triangles rewrite the same alpha
      drawMaskPaint(fShadowVerts[], style, PointF(ox, oy), vw, vh);
      break;
    }
  }

  /**
   * Writes the alpha of `style` (white RGB for solid colors) over `verts`
   * with blending disabled. `origin` is the logic position of the mask
   * region origin, so gradients and patterns map mask coordinates back to
   * user or pattern space.
   */
  void drawMaskPaint(
    const(float)[] verts,
    in FillStyle style,
    PointF origin,
    float vw,
    float vh
  ) {
    import glad2.gles2 : GL_BLEND, GL_TRIANGLES, glDisable;

    glDisable(GL_BLEND);
    // the next draw re-enables blending via setupAlphaBlendState
    final switch (style.kind) {
    case FillStyle.Kind.color:
      fRenderer.colorPipelineRef().drawArraysWithCurrentState(
        GL_TRIANGLES, verts, ColorF(1, 1, 1, style.color.a), vw, vh
      );
      return;
    case FillStyle.Kind.linearGradient:
    case FillStyle.Kind.radialGradient:
      const Transform2d inv =
        st.xf.inverse() * Transform2d.translation(origin);
      GradientUniforms u = gradientUniforms(style, inv);
      // the composite tints the mask RGB too: keep only the stop alphas
      foreach (i; 0 .. u.stopCount) {
        u.stopColors[i * 4 .. i * 4 + 3] = 1.0f;
      }
      fRenderer.gradientPipelineRef().drawTrianglesWithCurrentState(
        verts, u, vw, vh
      );
      return;
    case FillStyle.Kind.pattern:
      assert(!fRenderer.isActiveTargetTexture(style.pattern.texture),
        "drawing the texture of an active render target (feedback loop)");
      const Transform2d logicToPat =
        (st.xf * style.pattern.transform).inverse()
        * Transform2d.translation(origin);
      const PatternUniforms u = patternUniforms(
        style.pattern, logicToPat, TextureMode.alphaMask
      );
      fRenderer.patternPipelineRef().drawTrianglesWithCurrentState(
        verts, u, vw, vh
      );
      return;
    }
  }

  /**
   * Draws the `fImageVerts` triangles shifted to the origin of box `b`
   * into the bound offscreen region with blending disabled, writing the
   * texture alpha * `alpha` (`TextureMode.alphaMask`).
   */
  void drawImageShadowMask(
    Texture t,
    float alpha,
    in PixelBox b,
    float scale
  ) {
    import glad2.gles2 : GL_BLEND, glDisable;
    import yguilib.render.internal.pipelines : TextureMode;

    const float ox = b.x / scale;
    const float oy = b.y / scale;
    const(float)[] xyuv = fImageVerts[];
    fShadowVerts.clear();
    for (size_t i = 0; i + 3 < xyuv.length; i += 4) {
      const float[4] v = [xyuv[i] - ox, xyuv[i + 1] - oy, xyuv[i + 2],
        xyuv[i + 3]];
      fShadowVerts.put(v[]);
    }
    glDisable(GL_BLEND);
    // the next draw re-enables blending via setupAlphaBlendState
    fRenderer.texturePipelineRef().drawTexturedTrianglesWithCurrentState(
      t.id(), fShadowVerts[], ColorF(1, 1, 1, alpha), TextureMode.alphaMask,
      b.width / scale, b.height / scale
    );
  }

  /**
   * `fImageVerts` = two (x, y, u, v) triangles of `dest` transformed by
   * the current transform, sampling `srcPx` of `t`.
   */
  void buildImageVerts(Texture t, in RectF srcPx, in RectF dest) {
    import yguilib.render.internal.pipelines : quadVertices;

    const float[24] local = quadVertices(dest, Renderer.textureUv(t, srcPx));
    fImageVerts.clear();
    for (size_t i = 0; i < local.length; i += 4) {
      const PointF p = st.xf.apply(PointF(local[i], local[i + 1]));
      const float[4] v = [p.x, p.y, local[i + 2], local[i + 3]];
      fImageVerts.put(v[]);
    }
  }

  /// Blurs region `b` of target 0 horizontally into 1, vertically back.
  void blurShadow(in PixelBox b, float sigma) {
    import yguilib.render.internal.offscreen : OffscreenTarget;
    import yguilib.render.internal.pipelines : BlurPass;

    OffscreenTarget* a = &fRenderer.offscreenTargetRef(0);
    OffscreenTarget* t = &fRenderer.offscreenTargetRef(1);
    t.ensureSize(b.width, b.height);
    BlurPass p;
    p.width = b.width;
    p.height = b.height;
    p.sigma = sigma;
    p.source = a.texture;
    p.textureWidth = a.width;
    p.textureHeight = a.height;
    p.vertical = false;
    t.bindRegion(b.width, b.height, false);
    fRenderer.blurPipelineRef().draw(p);
    p.source = t.texture;
    p.textureWidth = t.width;
    p.textureHeight = t.height;
    p.vertical = true;
    a.bindRegion(b.width, b.height, false);
    fRenderer.blurPipelineRef().draw(p);
  }

  /// Draws region `b` of target 0 tinted at `b` + offset (logic units).
  void compositeShadow(in PixelBox b, float scale) {
    import yguilib.render.internal.offscreen : OffscreenTarget;
    import yguilib.render.internal.pipelines : TextureMode, TexturedQuad;
    import yguilib.render.internal.stencil_ops : beginClipTest, endStencil;

    const OffscreenTarget* a = &fRenderer.offscreenTargetRef(0);
    const float tw = a.width;
    const float th = a.height;
    TexturedQuad q;
    q.dest = RectF(
      b.x / scale + st.shadow.offset.x, b.y / scale + st.shadow.offset.y,
      b.width / scale, b.height / scale
    );
    // GL rows grow upward while logic y grows downward: flip v
    q.uv = RectF(0, b.height / th, b.width / tw, -b.height / th);
    q.color = st.shadow.color;
    beginClipTest(clipActive());
    fRenderer.texturePipelineRef().drawTexturedQuad(
      a.texture, q, fRenderer.logicWidth(), fRenderer.logicHeight(),
      TextureMode.straight
    );
    endStencil();
  }

  /// Intersects the clip bit with clip entry `e` (scissor must be off).
  void applyClip(in ClipEntry e) {
    import yguilib.render.internal.path_flatten : flattenPath;
    import yguilib.render.internal.stencil_ops : beginClipIntersect,
      beginResetLow, beginWinding, endStencil;

    flattenPath(e.path, tolerance(e.xf), fContours);
    buildFan(e.xf);
    const ColorF none = ColorF(0, 0, 0, 0);
    beginWinding(e.rule);
    drawVerts(fVerts[], none);
    beginClipIntersect(e.rule);
    const float[12] all = quadFromRect(RectF(
      -1, -1, fRenderer.logicWidth() + 2,
      fRenderer.logicHeight() + 2
    ));
    drawVerts(all[], none);
    if (fVerts[].length > 0) {
      const float[12] cover = quadFromRect(boundsOfVerts(fVerts[]));
      beginResetLow();
      drawVerts(cover[], none);
    }
    endStencil();
  }

  /// Rebuilds the clip bit from `st.clips` after `restore()`.
  void rebuildClip() {
    if (!fRenderer.isInitialized()) {
      return;
    }
    const bool scissor = disableScissor();
    clearClipBit(st.clips.length > 0);
    foreach (ref e; st.clips) {
      applyClip(e);
    }
    restoreScissor(scissor);
  }

  /// Sets (`inside` true) or clears stencil bit 7 in the whole viewport.
  static void clearClipBit(bool inside) {
    import glad2.gles2 : GL_STENCIL_BUFFER_BIT, glClear, glClearStencil,
      glStencilMask;
    import yguilib.render.internal.stencil_ops : clipBit;

    glStencilMask(clipBit);
    glClearStencil(inside ? clipBit : 0);
    glClear(GL_STENCIL_BUFFER_BIT);
    glClearStencil(0);
    glStencilMask(0xFF);
  }

  /**
   * Disables the scissor so the clip bit is valid in the whole viewport
   * (also outside a later, larger scissor). Returns the previous state.
   */
  static bool disableScissor() {
    import glad2.gles2 : GL_SCISSOR_TEST, GL_TRUE, glDisable, glIsEnabled;

    const bool was = glIsEnabled(GL_SCISSOR_TEST) == GL_TRUE;
    glDisable(GL_SCISSOR_TEST);
    return was;
  }

  static void restoreScissor(bool enabled) {
    import glad2.gles2 : GL_SCISSOR_TEST, glEnable;

    if (enabled) {
      glEnable(GL_SCISSOR_TEST);
    }
  }

  void drawVerts(const(float)[] verts, ColorF color) {
    import glad2.gles2 : GL_TRIANGLES;

    if (verts.length == 0) {
      return;
    }
    fRenderer.colorPipelineRef().drawArrays(
      GL_TRIANGLES, verts, color, fRenderer.logicWidth(),
      fRenderer.logicHeight()
    );
  }

  /// Fan triangles of every `fContours` contour, transformed into `fVerts`.
  void buildFan(in Transform2d xf) {
    fVerts.clear();
    const PointF[] pts = fContours.points[];
    foreach (info; fContours.infos[]) {
      if (info.count < 3) {
        continue;
      }
      const PointF p0 = xf.apply(pts[info.start]);
      PointF prev = xf.apply(pts[info.start + 1]);
      foreach (i; info.start + 2 .. info.start + info.count) {
        const PointF cur = xf.apply(pts[i]);
        const float[6] tri = [p0.x, p0.y, prev.x, prev.y, cur.x, cur.y];
        fVerts.put(tri[]);
        prev = cur;
      }
    }
  }

  /// `fVerts` = `local` (x, y pairs) transformed by `xf`.
  void transformVerts(const(float)[] local, in Transform2d xf) {
    fVerts.clear();
    for (size_t i = 0; i + 1 < local.length; i += 2) {
      const PointF p = xf.apply(PointF(local[i], local[i + 1]));
      fVerts.put(p.x);
      fVerts.put(p.y);
    }
  }

  /// Bounds of `verts` grown by 1 unit so the cover hits edge samples.
  static RectF boundsOfVerts(const(float)[] verts) {
    float x0 = verts[0];
    float y0 = verts[1];
    float x1 = x0;
    float y1 = y0;
    for (size_t i = 2; i + 1 < verts.length; i += 2) {
      x0 = verts[i] < x0 ? verts[i] : x0;
      x1 = verts[i] > x1 ? verts[i] : x1;
      y0 = verts[i + 1] < y0 ? verts[i + 1] : y0;
      y1 = verts[i + 1] > y1 ? verts[i + 1] : y1;
    }
    return RectF(x0 - 1, y0 - 1, x1 - x0 + 2, y1 - y0 + 2);
  }

  static float[12] quadFromRect(RectF r) {
    const float x0 = r.x;
    const float y0 = r.y;
    const float x1 = r.x + r.width;
    const float y1 = r.y + r.height;
    return [x0, y0, x1, y0, x0, y1, x0, y1, x1, y0, x1, y1];
  }
}

// Canvas GL rendering (stencil-then-cover, transforms, strokes, clips)
unittest {
  import glad2.gles2;
  import std.math : PI, cos, sin;
  import yguilib.clibs.sdl3;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_canvas");
  win.create();
  scope(exit) win.destroy();
  win.setDisplayScaling(1.0f);
  auto r = win.renderer;
  r.viewport(320, 240);
  auto cv = r.canvas();
  assert(cv !is null);

  GLint stencilBits = 0;
  glGetIntegerv(GL_STENCIL_BITS, &stencilBits);
  assert(stencilBits >= 8);

  // logic (x, y) with y down; GL y = 240 - y
  ubyte[4] px(int x, int y) {
    ubyte[4] p;
    glReadPixels(x, 240 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p.ptr);
    return p;
  }

  bool isRgb(int x, int y, int cr, int cg, int cb) {
    const p = px(x, y);
    return p[0] == cr && p[1] == cg && p[2] == cb;
  }

  Path2d rectPath(RectF rc) {
    auto p = new Path2d();
    p.rect(rc);
    return p;
  }

  const black = ColorF(0, 0, 0, 1);
  const red = ColorF(1, 0, 0, 1);
  const green = FillStyle.solid(ColorF(0, 1, 0, 1));
  const blue = FillStyle.solid(ColorF(0, 0, 1, 1));
  auto full = rectPath(RectF(0, 0, 320, 240));

  // 1. rect fill
  r.clearFrame(red);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(20, 20, 60, 40)));
  assert(isRgb(50, 40, 0, 255, 0));
  assert(isRgb(150, 150, 255, 0, 0));

  // 2. self-intersecting star: nonZero fills the center, evenOdd not
  auto star = new Path2d();
  foreach (k; 0 .. 5) {
    const float a = cast(float)(-PI / 2 + k * 4 * PI / 5);
    const PointF pt = PointF(160 + 80 * cos(a), 120 + 80 * sin(a));
    if (k == 0) {
      star.moveTo(pt);
    } else {
      star.lineTo(pt);
    }
  }
  star.closePath();
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.fill(star);
  assert(isRgb(160, 120, 0, 255, 0));
  assert(isRgb(160, 60, 0, 255, 0));
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.fillRule(FillRule.evenOdd);
  cv.fill(star);
  assert(isRgb(160, 120, 0, 0, 0));
  assert(isRgb(160, 60, 0, 255, 0));
  cv.fillRule(FillRule.nonZero);

  // 3. transforms and save/restore
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.save();
  cv.translate(PointF(100, 50));
  cv.rotate(cast(float)(PI / 4));
  cv.fill(rectPath(RectF(-10, -10, 20, 20)));
  cv.restore();
  assert(cv.transform().isIdentity());
  assert(isRgb(100, 50, 0, 255, 0));
  assert(isRgb(112, 50, 0, 255, 0)); // inside the rotated diamond only
  assert(isRgb(108, 42, 0, 0, 0)); // unrotated corner area
  cv.save();
  cv.scale(PointF(2, 3));
  cv.fill(rectPath(RectF(10, 10, 10, 10))); // -> (20, 30, 20, 30)
  assert(!cv.transform().isIdentity());
  cv.restore();
  assert(isRgb(30, 45, 0, 255, 0));
  assert(isRgb(15, 45, 0, 0, 0));
  assert(isRgb(30, 65, 0, 0, 0));
  cv.restore(); // empty stack: no-op
  cv.fill(rectPath(RectF(200, 200, 10, 10)));
  assert(isRgb(205, 205, 0, 255, 0));

  // 4. self-overlapping stroke is painted once
  r.clearFrame(black);
  auto cross = new Path2d();
  cross.moveTo(PointF(50, 50));
  cross.lineTo(PointF(200, 200));
  cross.lineTo(PointF(200, 50));
  cross.lineTo(PointF(50, 200));
  cv.strokeStyle(FillStyle.solid(ColorF(1, 1, 1, 0.5f)));
  cv.lineWidth(10);
  cv.stroke(cross);
  const ov = px(125, 125);
  assert(ov[0] >= 125 && ov[0] <= 131);
  const single = px(80, 80);
  assert(single[0] >= 125 && single[0] <= 131);

  // 5. dashes: [20, 20] along y = 100 from x = 20
  r.clearFrame(black);
  cv.strokeStyle(FillStyle.solid(ColorF(1, 1, 1, 1)));
  cv.lineWidth(6);
  cv.lineDash(LineDash([20.0f, 20]));
  assert(cv.lineDash().segments == [20.0f, 20]);
  auto line = new Path2d();
  line.moveTo(PointF(20, 100));
  line.lineTo(PointF(220, 100));
  cv.stroke(line);
  assert(isRgb(30, 100, 255, 255, 255));
  assert(isRgb(50, 100, 0, 0, 0));
  assert(isRgb(70, 100, 255, 255, 255));
  assert(isRgb(30, 110, 0, 0, 0));
  cv.lineDash(LineDash.init);
  cv.lineWidth(1);

  // 6. circle clip; restore() removes it
  r.clearFrame(black);
  auto circle = new Path2d();
  circle.arc(PointF(160, 120), 60, 0, cast(float)(2 * PI), false);
  cv.fillStyle(blue);
  cv.save();
  cv.clip(circle);
  cv.fill(full);
  assert(isRgb(160, 120, 0, 0, 255));
  assert(isRgb(5, 5, 0, 0, 0));
  assert(isRgb(315, 235, 0, 0, 0));
  assert(isRgb(160, 50, 0, 0, 0));
  cv.restore();
  cv.fillStyle(green);
  cv.fill(full);
  assert(isRgb(5, 5, 0, 255, 0));
  assert(isRgb(160, 120, 0, 255, 0));

  // 7. nested clips intersect; restoring one level keeps the outer clip
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.save();
  cv.clip(rectPath(RectF(20, 20, 100, 100)));
  cv.save();
  cv.clip(rectPath(RectF(70, 70, 100, 100)));
  cv.fill(full);
  assert(isRgb(90, 90, 0, 255, 0));
  assert(isRgb(40, 40, 0, 0, 0));
  assert(isRgb(150, 150, 0, 0, 0));
  cv.restore();
  cv.fillStyle(blue);
  cv.fill(full);
  assert(isRgb(40, 40, 0, 0, 255));
  assert(isRgb(150, 150, 0, 0, 0));
  // 8. Renderer draws ignore the Canvas clip
  r.drawFillRect(RectF(0, 0, 320, 240), ColorF(1, 0, 0, 1));
  assert(isRgb(150, 150, 255, 0, 0));
  assert(isRgb(5, 5, 255, 0, 0));
  cv.restore();

  // evenOdd clip with the star excludes its center
  r.clearFrame(black);
  cv.save();
  cv.clipFillRule(FillRule.evenOdd);
  cv.clip(star);
  cv.fillStyle(green);
  cv.fill(full);
  assert(isRgb(160, 120, 0, 0, 0));
  assert(isRgb(160, 60, 0, 255, 0));
  assert(isRgb(5, 5, 0, 0, 0));
  cv.restore();
  assert(cv.clipFillRule() == FillRule.nonZero);

  // 9. Renderer scissor limits Canvas fills
  r.clearFrame(black);
  cv.fillStyle(green);
  r.pushClipRect(RectF(50, 50, 50, 50));
  cv.fill(full);
  r.popClipRect();
  assert(isRgb(60, 60, 0, 255, 0));
  assert(isRgb(10, 10, 0, 0, 0));
  assert(isRgb(150, 150, 0, 0, 0));

  // 10. clearRect overwrites with transparent black
  r.clearFrame(ColorF(1, 1, 1, 1));
  cv.clearRect(RectF(10, 10, 50, 50));
  assert(isRgb(30, 30, 0, 0, 0));
  assert(isRgb(100, 100, 255, 255, 255));
  // and the next Renderer draw blends again
  r.drawFillRect(RectF(0, 0, 320, 240), ColorF(1, 1, 1, 0.5f));
  const half = px(100, 100);
  assert(half[0] == 255);

  // clearFrame resets the Canvas state
  cv.save();
  cv.translate(PointF(5, 5));
  cv.clip(rectPath(RectF(0, 0, 1, 1)));
  r.clearFrame(black);
  assert(cv.transform().isIdentity());
  assert(cv.fillStyle().color == ColorF(0, 0, 0, 1));
  cv.fillStyle(green);
  cv.fill(full);
  assert(isRgb(100, 100, 0, 255, 0));

  assert(glGetError() == GL_NO_ERROR);
}

// Canvas gradients (linear, multi-stop, radial, transformed, stroke)
unittest {
  import glad2.gles2;
  import std.math : abs;
  import yguilib.clibs.sdl3;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_canvas_gradients");
  win.create();
  scope(exit) win.destroy();
  win.setDisplayScaling(1.0f);
  auto r = win.renderer;
  r.viewport(320, 240);
  auto cv = r.canvas();

  // logic (x, y) with y down; GL y = 240 - y
  ubyte[4] px(int x, int y) {
    ubyte[4] p;
    glReadPixels(x, 240 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p.ptr);
    return p;
  }

  bool near(int x, int y, int cr, int cg, int cb, int tol) {
    const p = px(x, y);
    return abs(p[0] - cr) <= tol && abs(p[1] - cg) <= tol
      && abs(p[2] - cb) <= tol;
  }

  Path2d rectPath(RectF rc) {
    auto p = new Path2d();
    p.rect(rc);
    return p;
  }

  const black = ColorF(0, 0, 0, 1);
  const red = ColorF(1, 0, 0, 1);
  const green = ColorF(0, 1, 0, 1);
  const blue = ColorF(0, 0, 1, 1);

  LinearGradient rb;
  rb.p0 = PointF(0, 0);
  rb.p1 = PointF(200, 0);
  rb.addColorStop(0, red).addColorStop(1, blue);

  // 1. linear red -> blue across a 200-wide rect
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromLinear(rb));
  cv.fill(rectPath(RectF(0, 0, 200, 50)));
  assert(near(10, 25, 242, 0, 13, 6));
  assert(near(190, 25, 13, 0, 242, 6));
  assert(near(100, 25, 128, 0, 128, 4));
  assert(near(250, 25, 0, 0, 0, 0)); // outside the rect

  // 2. three stops: the middle stop's color shows at offset 0.5
  LinearGradient rgb;
  rgb.p0 = PointF(0, 0);
  rgb.p1 = PointF(200, 0);
  rgb.addColorStop(0, red).addColorStop(0.5f, green).addColorStop(1, blue);
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromLinear(rgb));
  cv.fill(rectPath(RectF(0, 0, 200, 50)));
  assert(near(100, 25, 0, 255, 0, 3));
  assert(near(50, 25, 128, 128, 0, 4));

  // degenerate linear gradient (p0 == p1) draws nothing
  LinearGradient flat;
  flat.addColorStop(0, red);
  cv.fillStyle(FillStyle.fromLinear(flat));
  cv.fill(rectPath(RectF(0, 0, 200, 50)));
  assert(near(100, 25, 0, 255, 0, 3));

  // 3. radial: center is the first stop, near r1 the last, padded outside
  RadialGradient rad;
  rad.c0 = PointF(160, 120);
  rad.c1 = PointF(160, 120);
  rad.r0 = 0;
  rad.r1 = 50;
  rad.addColorStop(0, red).addColorStop(1, blue);
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromRadial(rad));
  cv.fill(rectPath(RectF(0, 0, 320, 240)));
  assert(near(160, 120, 255, 0, 0, 6));
  assert(near(205, 120, 25, 0, 230, 8));
  assert(near(160, 165, 25, 0, 230, 8));
  assert(near(240, 120, 0, 0, 255, 0));
  assert(near(5, 5, 0, 0, 255, 0));

  // 4. gradient follows the transform at the time of the fill
  r.clearFrame(black);
  cv.save();
  cv.translate(PointF(100, 0));
  cv.fillStyle(FillStyle.fromLinear(rb));
  cv.fill(rectPath(RectF(0, 0, 200, 50)));
  cv.restore();
  assert(near(110, 25, 242, 0, 13, 6));
  assert(near(290, 25, 13, 0, 242, 6));
  assert(near(200, 25, 128, 0, 128, 4));
  assert(near(50, 25, 0, 0, 0, 0));

  // 5. gradient stroke
  LinearGradient sg;
  sg.p0 = PointF(20, 0);
  sg.p1 = PointF(220, 0);
  sg.addColorStop(0, red).addColorStop(1, blue);
  r.clearFrame(black);
  cv.strokeStyle(FillStyle.fromLinear(sg));
  cv.lineWidth(10);
  auto line = new Path2d();
  line.moveTo(PointF(20, 150));
  line.lineTo(PointF(220, 150));
  cv.stroke(line);
  assert(near(30, 150, 242, 0, 13, 6));
  assert(near(210, 150, 13, 0, 242, 6));
  assert(near(120, 150, 128, 0, 128, 4));
  assert(near(120, 170, 0, 0, 0, 0));

  assert(glGetError() == GL_NO_ERROR);
}

// Canvas shadows (offscreen mask, blur, clip, scissor and state restore)
unittest {
  import glad2.gles2;
  import yguilib.clibs.sdl3;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_canvas_shadows");
  win.create();
  scope(exit) win.destroy();
  win.setDisplayScaling(1.0f);
  auto r = win.renderer;
  r.viewport(320, 240);
  auto cv = r.canvas();

  // logic (x, y) with y down; GL y = 240 - y
  ubyte[4] px(int x, int y) {
    ubyte[4] p;
    glReadPixels(x, 240 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p.ptr);
    return p;
  }

  bool isRgb(int x, int y, int cr, int cg, int cb) {
    const p = px(x, y);
    return p[0] == cr && p[1] == cg && p[2] == cb;
  }

  Path2d rectPath(RectF rc) {
    auto p = new Path2d();
    p.rect(rc);
    return p;
  }

  const black = ColorF(0, 0, 0, 1);
  const green = FillStyle.solid(ColorF(0, 1, 0, 1));
  // right angle at the top-left: catches flipped shadow textures
  auto tri = new Path2d();
  tri.moveTo(PointF(50, 50));
  tri.lineTo(PointF(110, 50));
  tri.lineTo(PointF(50, 90));
  tri.closePath();

  // 1. invisible shadow (alpha 0) takes no FBO path, same pixels
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.fill(tri);
  ubyte[] plain = new ubyte[320 * 240 * 4];
  glReadPixels(0, 0, 320, 240, GL_RGBA, GL_UNSIGNED_BYTE, plain.ptr);
  Shadow hidden;
  hidden.offset = PointF(10, 10);
  hidden.blur = 4;
  cv.shadow(hidden);
  assert(!cv.shadow().isVisible());
  r.clearFrame(black); // resets the shadow too
  assert(cv.shadow().blur == 0);
  cv.shadow(hidden);
  cv.fillStyle(green);
  cv.fill(tri);
  ubyte[] same = new ubyte[320 * 240 * 4];
  glReadPixels(0, 0, 320, 240, GL_RGBA, GL_UNSIGNED_BYTE, same.ptr);
  assert(plain == same);
  assert(r.offscreenTargetRef(0).fbo == 0);

  // 2. hard shadow (blur 0) at offset (10, 10) under the shape
  Shadow hard;
  hard.offset = PointF(10, 10);
  hard.color = ColorF(1, 0, 0, 1);
  r.clearFrame(black);
  cv.save();
  cv.shadow(hard);
  assert(cv.shadow().isVisible());
  cv.fillStyle(green);
  cv.fill(tri);
  cv.restore();
  assert(!cv.shadow().isVisible());
  assert(r.offscreenTargetRef(0).fbo != 0);
  assert(isRgb(55, 55, 0, 255, 0)); // shape over the shadow
  assert(isRgb(65, 65, 0, 255, 0));
  assert(isRgb(115, 62, 255, 0, 0)); // shadow outside the shape
  assert(isRgb(62, 98, 255, 0, 0));
  assert(isRgb(115, 95, 0, 0, 0));
  assert(isRgb(45, 45, 0, 0, 0));
  // 2b. shadow alpha = shadow color alpha * paint alpha
  bool near(int v, int expected) {
    return v >= expected - 3 && v <= expected + 3;
  }

  r.clearFrame(black);
  cv.shadow(hard);
  cv.fillStyle(FillStyle.solid(ColorF(0, 1, 0, 0.5f)));
  cv.fill(tri);
  // shadow only: red at 0.5 over black
  auto halfShadow = px(115, 62);
  assert(near(halfShadow[0], 128) && halfShadow[1] == 0);
  // overlap: 0.5 green over the 0.5 red shadow
  auto overlap = px(65, 65);
  assert(near(overlap[0], 64) && near(overlap[1], 128));
  // gradient paint fading to transparent: the shadow fades the same way
  r.clearFrame(black);
  cv.shadow(hard);
  LinearGradient fade;
  fade.p0 = PointF(100, 0);
  fade.p1 = PointF(200, 0);
  fade.addColorStop(0, ColorF(0, 1, 0, 1));
  fade.addColorStop(1, ColorF(0, 1, 0, 0));
  cv.fillStyle(FillStyle.fromLinear(fade));
  cv.fill(rectPath(RectF(100, 100, 100, 40)));
  // below the shape (y 140..150) only the shadow shows
  const sLeft = px(112, 145)[0];
  const sMid = px(160, 145)[0];
  const sRight = px(205, 145)[0];
  assert(sLeft > 200 && near(sMid, 128) && sRight < 20);
  cv.shadow(Shadow.init);

  // invalid shadows are ignored
  Shadow bad = hard;
  bad.blur = -1;
  cv.shadow(bad);
  assert(!cv.shadow().isVisible());

  // 3. blur 8 (sigma 4 px): partial alpha falling off outward
  Shadow soft;
  soft.blur = 8;
  soft.color = ColorF(1, 0, 0, 1);
  r.clearFrame(black);
  cv.shadow(soft);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(100, 80, 80, 60)));
  const edge = px(181, 110);
  assert(edge[0] > 0 && edge[0] < 255 && edge[1] == 0);
  foreach (x; 181 .. 196) {
    assert(px(x, 110)[0] >= px(x + 1, 110)[0]);
  }
  assert(px(181, 110)[0] > px(186, 110)[0]);
  assert(px(196, 110)[0] <= 2);
  assert(isRgb(178, 110, 0, 255, 0));

  // 4. shadow on a stroke
  r.clearFrame(black);
  cv.shadow(hard);
  cv.strokeStyle(FillStyle.solid(ColorF(0, 0, 1, 1)));
  cv.lineWidth(6);
  auto line = new Path2d();
  line.moveTo(PointF(20, 200));
  line.lineTo(PointF(120, 200));
  cv.stroke(line);
  assert(isRgb(60, 200, 0, 0, 255));
  assert(isRgb(60, 210, 255, 0, 0));
  assert(isRgb(60, 190, 0, 0, 0));

  // 5. Canvas clip applies; scissor and viewport are restored
  r.clearFrame(black);
  r.pushClipRect(RectF(0, 0, 200, 200));
  GLint[4] boxBefore;
  glGetIntegerv(GL_SCISSOR_BOX, boxBefore.ptr);
  GLint[4] vpBefore;
  glGetIntegerv(GL_VIEWPORT, vpBefore.ptr);
  cv.save();
  cv.clip(rectPath(RectF(0, 0, 160, 240)));
  cv.shadow(hard);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(140, 50, 40, 40)));
  cv.restore();
  assert(isRgb(155, 95, 255, 0, 0)); // shadow inside the clip
  assert(isRgb(165, 95, 0, 0, 0)); // shadow outside the clip
  assert(isRgb(150, 70, 0, 255, 0));
  GLint[4] boxAfter;
  glGetIntegerv(GL_SCISSOR_BOX, boxAfter.ptr);
  GLint[4] vpAfter;
  glGetIntegerv(GL_VIEWPORT, vpAfter.ptr);
  assert(boxAfter == boxBefore && vpAfter == vpBefore);
  assert(glIsEnabled(GL_SCISSOR_TEST) == GL_TRUE);
  GLint fbo = -1;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fbo);
  assert(fbo == 0);
  r.drawFillRect(RectF(0, 0, 320, 240), ColorF(0, 0, 1, 1));
  r.popClipRect();
  assert(isRgb(5, 5, 0, 0, 255));
  assert(isRgb(210, 210, 0, 0, 0));
  assert(isRgb(250, 100, 0, 0, 0));

  // the shadow is limited by the Renderer scissor too
  r.clearFrame(black);
  r.pushClipRect(RectF(0, 0, 100, 240));
  cv.shadow(hard);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(60, 50, 40, 40)));
  r.popClipRect();
  assert(isRgb(95, 95, 255, 0, 0));
  assert(isRgb(105, 95, 0, 0, 0));

  assert(glGetError() == GL_NO_ERROR);
}

// Canvas.drawImage (transform, clip, src region, tint, shadow, targets)
unittest {
  import glad2.gles2;
  import std.math : PI;
  import yguilib.clibs.sdl3;
  import yguilib.render.image : Image;
  import yguilib.render.render_target : RenderTarget;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_canvas_draw_image");
  win.create();
  scope(exit) win.destroy();
  win.setDisplayScaling(1.0f);
  auto r = win.renderer;
  r.viewport(320, 240);
  auto cv = r.canvas();
  const ColorF black = ColorF(0, 0, 0, 1);
  const ColorF white = ColorF(1, 1, 1, 1);

  // logic (x, y) with y down; GL y = 240 - y
  ubyte[4] px(int x, int y) {
    ubyte[4] p;
    glReadPixels(x, 240 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p.ptr);
    return p;
  }

  bool near(int x, int y, int cr, int cg, int cb, int tol) {
    const p = px(x, y);
    bool ok(int v, int e) {
      return v >= e - tol && v <= e + tol;
    }

    return ok(p[0], cr) && ok(p[1], cg) && ok(p[2], cb);
  }

  bool isRgb(int x, int y, int cr, int cg, int cb) {
    return near(x, y, cr, cg, cb, 0);
  }

  // 80x40 image, left half `left`, right half `right` (RGBA8)
  Image twoColor(ubyte[4] left, ubyte[4] right) {
    auto img = new Image(80, 40);
    foreach (y; 0 .. 40) {
      foreach (x; 0 .. 80) {
        const size_t i = (y * 80 + x) * 4;
        img.pixels[i .. i + 4] = x < 40 ? left : right;
      }
    }
    return img;
  }

  Texture tex = r.createTexture(twoColor([255, 0, 0, 255],
    [0, 0, 255, 255]));
  scope(exit) tex.destroy();
  assert(tex !is null && !tex.premultiplied() && !tex.bottomUp());
  const RectF dest = RectF(20, 20, 80, 40);

  // 1. untransformed: same pixels as Renderer.drawImage
  r.clearFrame(black);
  r.drawImage(tex, dest, white);
  Image expected = r.captureFrame();
  r.clearFrame(black);
  cv.drawImage(tex, dest);
  Image actual = r.captureFrame();
  assert(expected !is null && actual !is null);
  assert(expected.pixels == actual.pixels);
  assert(isRgb(30, 40, 255, 0, 0) && isRgb(90, 40, 0, 0, 255));
  assert(isRgb(10, 40, 0, 0, 0) && isRgb(30, 65, 0, 0, 0));

  // 2. rotate 90 degrees: local (x, y) -> (200 - y, 20 + x)
  r.clearFrame(black);
  cv.save();
  cv.translate(PointF(200, 20));
  cv.rotate(PI / 2);
  cv.drawImage(tex, RectF(0, 0, 80, 40));
  cv.restore();
  assert(isRgb(180, 30, 255, 0, 0) && isRgb(180, 55, 255, 0, 0));
  assert(isRgb(180, 65, 0, 0, 255) && isRgb(165, 95, 0, 0, 255));
  assert(isRgb(205, 40, 0, 0, 0) && isRgb(155, 40, 0, 0, 0));
  assert(isRgb(180, 105, 0, 0, 0));

  // 3. the Canvas clip limits the image
  r.clearFrame(black);
  cv.save();
  auto clipPath = new Path2d();
  clipPath.rect(RectF(0, 0, 40, 240));
  cv.clip(clipPath);
  cv.drawImage(tex, dest);
  cv.restore();
  assert(isRgb(30, 40, 255, 0, 0));
  assert(isRgb(50, 40, 0, 0, 0) && isRgb(90, 40, 0, 0, 0));
  // ... a circle clip too
  r.clearFrame(black);
  cv.save();
  auto circle = new Path2d();
  circle.arc(PointF(60, 40), 15, 0, 2 * PI, false);
  cv.clip(circle);
  cv.drawImage(tex, dest);
  cv.restore();
  assert(isRgb(50, 40, 255, 0, 0) && isRgb(70, 40, 0, 0, 255));
  assert(isRgb(60, 22, 0, 0, 0) && isRgb(30, 40, 0, 0, 0));
  assert(isRgb(90, 40, 0, 0, 0));

  // 4. a src region picks the right half, stretched to dest
  r.clearFrame(black);
  cv.drawImageRegion(tex, RectF(40, 0, 40, 40), dest);
  assert(isRgb(22, 40, 0, 0, 255) && isRgb(98, 40, 0, 0, 255));
  assert(isRgb(60, 40, 0, 0, 255));

  // 5. tint alpha halves the result
  r.clearFrame(black);
  cv.drawImageTinted(tex, dest, ColorF(1, 1, 1, 0.5f));
  assert(near(30, 40, 128, 0, 0, 2) && near(90, 40, 0, 0, 128, 2));
  // invalid input draws nothing
  r.clearFrame(black);
  cv.drawImage(null, dest);
  cv.drawImageTinted(tex, dest, ColorF(1, 1, 1, 0));
  cv.drawImage(tex, RectF(20, 20, 0, 40));
  cv.drawImage(tex, RectF(20, float.nan, 80, 40));
  cv.drawImageRegion(tex, RectF(0, 0, -5, 40), dest);
  assert(isRgb(30, 40, 0, 0, 0) && isRgb(90, 40, 0, 0, 0));

  // 6. hard shadow in the image shape; none under transparent pixels
  Texture half = r.createTexture(twoColor([0, 255, 0, 255],
    [0, 0, 0, 0]));
  scope(exit) half.destroy();
  Shadow hard;
  hard.offset = PointF(10, 10);
  hard.color = ColorF(1, 0, 0, 1);
  r.clearFrame(black);
  cv.shadow(hard);
  cv.drawImage(half, RectF(100, 100, 80, 40));
  assert(isRgb(105, 105, 0, 255, 0) && isRgb(135, 135, 0, 255, 0));
  assert(isRgb(145, 120, 255, 0, 0) && isRgb(120, 145, 255, 0, 0));
  assert(isRgb(160, 130, 0, 0, 0) && isRgb(175, 145, 0, 0, 0));
  assert(isRgb(105, 145, 0, 0, 0));
  // shadow alpha = shadow color alpha * image alpha * tint alpha
  r.clearFrame(black); // also resets the Canvas state
  cv.shadow(hard);
  cv.drawImageTinted(half, RectF(100, 100, 80, 40),
    ColorF(1, 1, 1, 0.5f));
  assert(near(145, 120, 128, 0, 0, 3));
  cv.shadow(Shadow.init);

  // 7. a render target texture is upright with the drawn colors
  RenderTarget rt = r.createRenderTarget(80, 40, false);
  assert(rt !is null);
  scope(exit) rt.destroy();
  // On a failed assert close open targets before destroying them (an
  // assert in destroy() while unwinding loops the test runner forever).
  scope(exit) {
    while (r.inTarget()) {
      r.endTarget();
    }
  }
  r.beginTarget(rt, true);
  r.drawFillRect(RectF(0, 0, 80, 20), ColorF(1, 0, 0, 1));
  r.drawFillRect(RectF(0, 20, 80, 20), ColorF(0, 0, 1, 0.5f));
  r.endTarget();
  r.clearFrame(black);
  cv.drawImage(rt.texture(), RectF(200, 150, 80, 40));
  assert(isRgb(240, 160, 255, 0, 0));
  assert(near(240, 180, 0, 0, 128, 2));
  // ... and through a transform + tint
  r.clearFrame(black);
  cv.save();
  cv.translate(PointF(100, 0));
  cv.drawImageTinted(rt.texture(), RectF(100, 150, 80, 40),
    ColorF(1, 1, 1, 0.5f));
  cv.restore();
  assert(near(240, 160, 128, 0, 0, 2));
  assert(near(240, 180, 0, 0, 64, 2));

  assert(glGetError() == GL_NO_ERROR);
}

// Canvas patterns (repeat modes, transforms, tints, strokes, clips, shadows)
unittest {
  import glad2.gles2;
  import std.math : PI;
  import yguilib.clibs.sdl3;
  import yguilib.render.image : Image;
  import yguilib.render.render_target : RenderTarget;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_canvas_patterns");
  win.create();
  scope(exit) win.destroy();
  win.setDisplayScaling(1.0f);
  auto r = win.renderer;
  r.viewport(320, 240);
  auto cv = r.canvas();
  const ColorF black = ColorF(0, 0, 0, 1);

  // logic (x, y) with y down; GL y = 240 - y
  ubyte[4] px(int x, int y) {
    ubyte[4] p;
    glReadPixels(x, 240 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p.ptr);
    return p;
  }

  bool near(int x, int y, int cr, int cg, int cb, int tol) {
    const p = px(x, y);
    bool ok(int v, int e) {
      return v >= e - tol && v <= e + tol;
    }

    return ok(p[0], cr) && ok(p[1], cg) && ok(p[2], cb);
  }

  bool isRgb(int x, int y, int cr, int cg, int cb) {
    return near(x, y, cr, cg, cb, 0);
  }

  Path2d rectPath(RectF rc) {
    auto p = new Path2d();
    p.rect(rc);
    return p;
  }

  // 20x20 4-quadrant texture: TL red, TR green, BL blue, BR white
  auto quadImg = new Image(20, 20);
  foreach (y; 0 .. 20) {
    foreach (x; 0 .. 20) {
      const size_t i = (y * 20 + x) * 4;
      ubyte[4] c;
      if (y < 10) {
        c = x < 10 ? [255, 0, 0, 255] : [0, 255, 0, 255];
      } else {
        c = x < 10 ? [0, 0, 255, 255] : [255, 255, 255, 255];
      }
      quadImg.pixels[i .. i + 4] = c;
    }
  }
  Texture tex = r.createTexture(quadImg);
  assert(tex !is null);
  scope(exit) tex.destroy();

  auto box = rectPath(RectF(0, 0, 100, 60));

  // 1. repeat: tiles across 100x60 rect
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.repeat)
  ));
  cv.fill(box);
  // tile (0, 0)
  assert(isRgb(5, 5, 255, 0, 0) && isRgb(15, 5, 0, 255, 0));
  assert(isRgb(5, 15, 0, 0, 255) && isRgb(15, 15, 255, 255, 255));
  // tile (1, 0)
  assert(isRgb(25, 5, 255, 0, 0) && isRgb(35, 5, 0, 255, 0));
  assert(isRgb(25, 15, 0, 0, 255) && isRgb(35, 15, 255, 255, 255));
  // tile (0, 1)
  assert(isRgb(5, 25, 255, 0, 0) && isRgb(15, 35, 255, 255, 255));
  // tile (3, 2)
  assert(isRgb(65, 45, 255, 0, 0) && isRgb(75, 45, 0, 255, 0));
  assert(isRgb(65, 55, 0, 0, 255) && isRgb(75, 55, 255, 255, 255));
  // outside rect
  assert(isRgb(120, 30, 0, 0, 0) && isRgb(50, 80, 0, 0, 0));

  // 2. repeatX: tiles horizontally for y in [0, 20), background for y >= 20
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.repeatX)
  ));
  cv.fill(box);
  assert(isRgb(5, 5, 255, 0, 0) && isRgb(25, 5, 255, 0, 0));
  assert(isRgb(75, 15, 255, 255, 255));
  assert(isRgb(5, 25, 0, 0, 0) && isRgb(65, 45, 0, 0, 0));

  // 3. repeatY: tiles vertically for x in [0, 20), background for x >= 20
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.repeatY)
  ));
  cv.fill(box);
  assert(isRgb(5, 5, 255, 0, 0) && isRgb(5, 25, 255, 0, 0));
  assert(isRgb(15, 55, 255, 255, 255));
  assert(isRgb(25, 5, 0, 0, 0) && isRgb(65, 45, 0, 0, 0));

  // 4. noRepeat: draws once in [0, 20) x [0, 20); stencil bits stay clean
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.noRepeat)
  ));
  cv.fill(box);
  assert(isRgb(5, 5, 255, 0, 0) && isRgb(15, 5, 0, 255, 0));
  assert(isRgb(5, 15, 0, 0, 255) && isRgb(15, 15, 255, 255, 255));
  assert(isRgb(25, 5, 0, 0, 0) && isRgb(5, 25, 0, 0, 0));
  assert(isRgb(65, 45, 0, 0, 0));
  // subsequent fill over the whole area works (stencil low bits zeroed)
  cv.fillStyle(FillStyle.solid(ColorF(0, 1, 0, 1)));
  cv.fill(box);
  assert(isRgb(5, 5, 0, 255, 0) && isRgb(25, 5, 0, 255, 0));
  assert(isRgb(65, 45, 0, 255, 0));

  // 5. Pattern.transform: translation, 90-deg rotation, 2x scaling, combined
  r.clearFrame(black);
  Pattern trPat = Pattern.fromTexture(tex, PatternRepeat.repeat);
  trPat.withTransform(Transform2d.translation(PointF(10, 5)));
  cv.fillStyle(FillStyle.fromPattern(trPat));
  cv.fill(box);
  assert(isRgb(15, 10, 255, 0, 0) && isRgb(25, 10, 0, 255, 0));
  assert(isRgb(15, 20, 0, 0, 255) && isRgb(25, 20, 255, 255, 255));

  r.clearFrame(black);
  Pattern rotPat = Pattern.fromTexture(tex, PatternRepeat.repeat);
  rotPat.withTransform(Transform2d.rotation(cast(float)(PI / 2)));
  cv.fillStyle(FillStyle.fromPattern(rotPat));
  cv.fill(box);
  // (u, v) -> pattern (v, -u mod 20)
  assert(isRgb(5, 5, 0, 0, 255) && isRgb(15, 5, 255, 0, 0));
  assert(isRgb(5, 15, 255, 255, 255) && isRgb(15, 15, 0, 255, 0));

  r.clearFrame(black);
  Pattern scPat = Pattern.fromTexture(tex, PatternRepeat.repeat);
  scPat.withTransform(Transform2d.scaling(PointF(2, 2)));
  cv.fillStyle(FillStyle.fromPattern(scPat));
  cv.fill(box);
  assert(isRgb(10, 10, 255, 0, 0) && isRgb(30, 10, 0, 255, 0));
  assert(isRgb(10, 30, 0, 0, 255) && isRgb(30, 30, 255, 255, 255));

  r.clearFrame(black);
  cv.save();
  cv.translate(PointF(40, 20));
  Pattern combPat = Pattern.fromTexture(tex, PatternRepeat.repeat);
  combPat.withTransform(Transform2d.translation(PointF(10, 0)));
  cv.fillStyle(FillStyle.fromPattern(combPat));
  cv.fill(rectPath(RectF(0, 0, 60, 40)));
  cv.restore();
  assert(isRgb(55, 25, 255, 0, 0) && isRgb(65, 25, 0, 255, 0));
  assert(isRgb(45, 25, 0, 255, 0) && isRgb(30, 25, 0, 0, 0));

  // 6. Pattern.tint: half alpha and color tinting
  r.clearFrame(black);
  Pattern halfPat = Pattern.fromTexture(tex, PatternRepeat.repeat);
  halfPat.withTint(ColorF(1, 1, 1, 0.5f));
  cv.fillStyle(FillStyle.fromPattern(halfPat));
  cv.fill(box);
  assert(near(5, 5, 128, 0, 0, 3) && near(15, 15, 128, 128, 128, 3));

  r.clearFrame(black);
  Pattern tintPat = Pattern.fromTexture(tex, PatternRepeat.repeat);
  tintPat.withTint(ColorF(1, 0, 0.5f, 1));
  cv.fillStyle(FillStyle.fromPattern(tintPat));
  cv.fill(box);
  assert(near(15, 15, 255, 0, 128, 3) && near(15, 5, 0, 0, 0, 2));

  // 7. Pattern stroke: thick line, self-overlapping cross, dashed stroke
  r.clearFrame(black);
  cv.strokeStyle(FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.repeat)
  ));
  cv.lineWidth(10);
  auto hline = new Path2d();
  hline.moveTo(PointF(0, 5));
  hline.lineTo(PointF(60, 5));
  cv.stroke(hline);
  assert(isRgb(5, 5, 255, 0, 0) && isRgb(15, 5, 0, 255, 0));
  assert(isRgb(25, 5, 255, 0, 0) && isRgb(35, 5, 0, 255, 0));
  assert(isRgb(5, 20, 0, 0, 0));

  r.clearFrame(black);
  auto cross = new Path2d();
  cross.moveTo(PointF(50, 50));
  cross.lineTo(PointF(200, 200));
  cross.lineTo(PointF(200, 50));
  cross.lineTo(PointF(50, 200));
  cv.strokeStyle(FillStyle.fromPattern(halfPat));
  cv.lineWidth(10);
  cv.stroke(cross);
  // (125, 125) and (85, 85) both fall in TL red (5, 5) mod 20
  assert(near(125, 125, 128, 0, 0, 3));
  assert(near(85, 85, 128, 0, 0, 3));

  r.clearFrame(black);
  cv.strokeStyle(FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.repeat)
  ));
  cv.lineWidth(8);
  cv.lineDash(LineDash([20.0f, 20]));
  auto dline = new Path2d();
  dline.moveTo(PointF(0, 5));
  dline.lineTo(PointF(80, 5));
  cv.stroke(dline);
  assert(isRgb(5, 5, 255, 0, 0) && isRgb(15, 5, 0, 255, 0));
  assert(isRgb(25, 5, 0, 0, 0) && isRgb(35, 5, 0, 0, 0));
  assert(isRgb(45, 5, 255, 0, 0) && isRgb(55, 5, 0, 255, 0));
  cv.lineDash(LineDash.init);
  cv.lineWidth(1);

  // 8. clip() limits pattern fill; save()/restore() preserves styles
  r.clearFrame(black);
  const FillStyle patStyle = FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.repeat)
  );
  cv.save();
  cv.fillStyle(patStyle);
  cv.strokeStyle(patStyle);
  cv.clip(rectPath(RectF(0, 0, 30, 30)));
  cv.fill(box);
  assert(isRgb(5, 5, 255, 0, 0) && isRgb(25, 5, 255, 0, 0));
  assert(isRgb(45, 5, 0, 0, 0) && isRgb(5, 45, 0, 0, 0));
  cv.save();
  cv.fillStyle(FillStyle.solid(ColorF(0, 0, 1, 1)));
  cv.strokeStyle(FillStyle.solid(ColorF(0, 1, 0, 1)));
  cv.restore();
  assert(cv.fillStyle().kind == FillStyle.Kind.pattern);
  assert(cv.fillStyle().pattern.texture is tex);
  assert(cv.strokeStyle().kind == FillStyle.Kind.pattern);
  assert(cv.strokeStyle().pattern.texture is tex);
  cv.restore();
  assert(cv.fillStyle().kind == FillStyle.Kind.color);

  // 9. Pattern shadow: half-transparent texture, noRepeat, tint.a scaling
  auto halfImg = new Image(20, 20);
  foreach (y; 0 .. 20) {
    foreach (x; 0 .. 20) {
      const size_t i = (y * 20 + x) * 4;
      halfImg.pixels[i .. i + 4] =
        x < 10 ? [0, 255, 0, 255] : [0, 0, 0, 0];
    }
  }
  Texture halfTex = r.createTexture(halfImg);
  assert(halfTex !is null);
  scope(exit) halfTex.destroy();

  Shadow hard;
  hard.offset = PointF(10, 10);
  hard.color = ColorF(1, 0, 0, 1);

  r.clearFrame(black);
  cv.shadow(hard);
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(halfTex, PatternRepeat.repeat)
  ));
  cv.fill(rectPath(RectF(20, 20, 40, 20)));
  assert(isRgb(25, 25, 0, 255, 0));
  assert(isRgb(35, 35, 255, 0, 0) && isRgb(35, 45, 255, 0, 0));
  assert(isRgb(45, 45, 0, 0, 0) && isRgb(55, 45, 255, 0, 0));

  r.clearFrame(black);
  cv.shadow(hard);
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(halfTex, PatternRepeat.noRepeat)
  ));
  cv.fill(rectPath(RectF(0, 0, 60, 40)));
  assert(isRgb(5, 5, 0, 255, 0));
  assert(isRgb(15, 15, 255, 0, 0) && isRgb(15, 25, 255, 0, 0));
  assert(isRgb(35, 25, 0, 0, 0));

  r.clearFrame(black);
  cv.shadow(hard);
  Pattern halfAlphaPat = Pattern.fromTexture(halfTex, PatternRepeat.noRepeat);
  halfAlphaPat.withTint(ColorF(1, 1, 1, 0.5f));
  cv.fillStyle(FillStyle.fromPattern(halfAlphaPat));
  cv.fill(rectPath(RectF(0, 0, 60, 40)));
  assert(near(15, 25, 128, 0, 0, 3));
  cv.shadow(Shadow.init);

  // 10. RenderTarget.texture() as a Pattern: upright and tiled cleanly
  RenderTarget rt = r.createRenderTarget(20, 20, false);
  assert(rt !is null);
  scope(exit) rt.destroy();
  scope(exit) {
    while (r.inTarget()) {
      r.endTarget();
    }
  }
  r.beginTarget(rt, true);
  r.drawFillRect(RectF(0, 0, 20, 10), ColorF(1, 0, 0, 1));
  r.drawFillRect(RectF(0, 10, 20, 10), ColorF(0, 0, 1, 0.5f));
  r.endTarget();

  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(rt.texture(), PatternRepeat.repeat)
  ));
  cv.fill(rectPath(RectF(0, 0, 60, 40)));
  assert(isRgb(10, 5, 255, 0, 0) && near(10, 15, 0, 0, 128, 2));
  assert(isRgb(50, 25, 255, 0, 0) && near(50, 35, 0, 0, 128, 2));

  // 11. Invalid patterns draw nothing
  r.clearFrame(black);
  cv.fillStyle(
    FillStyle.fromPattern(Pattern.fromTexture(null, PatternRepeat.repeat))
  );
  cv.fill(box);

  Texture dead = r.createTexture(quadImg);
  assert(dead !is null);
  dead.destroy();
  cv.fillStyle(
    FillStyle.fromPattern(Pattern.fromTexture(dead, PatternRepeat.repeat))
  );
  cv.fill(box);

  Pattern zeroA = Pattern.fromTexture(tex, PatternRepeat.repeat);
  zeroA.withTint(ColorF(1, 1, 1, 0));
  cv.fillStyle(FillStyle.fromPattern(zeroA));
  cv.fill(box);

  Pattern singular = Pattern.fromTexture(tex, PatternRepeat.repeat);
  singular.withTransform(Transform2d.scaling(PointF(0, 1)));
  cv.fillStyle(FillStyle.fromPattern(singular));
  cv.fill(box);

  cv.save();
  cv.scale(PointF(0, 1));
  cv.fillStyle(
    FillStyle.fromPattern(Pattern.fromTexture(tex, PatternRepeat.repeat))
  );
  cv.fill(box);
  cv.restore();

  assert(isRgb(5, 5, 0, 0, 0) && isRgb(15, 15, 0, 0, 0));
  assert(isRgb(50, 30, 0, 0, 0));

  assert(glGetError() == GL_NO_ERROR);
}

// Canvas text state and measureText
unittest {
  import std.math : isClose;
  import yguilib.clibs.sdl3;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_canvas_text_state");
  win.create();
  scope(exit) win.destroy();
  win.setDisplayScaling(1.0f);
  auto r = win.renderer;
  r.viewport(320, 240);
  auto cv = r.canvas();

  assert(cv.fontSpec.ptSize == defaultFontPtSize);
  assert(cv.textAlign == TextAlign.start);
  assert(cv.textBaseline == TextBaseline.alphabetic);
  assert(cv.direction == TextDirection.ltr);

  cv.fontSpec = FontSpec(20, null);
  cv.textAlign = TextAlign.center;
  cv.textBaseline = TextBaseline.middle;
  cv.direction = TextDirection.rtl;
  cv.save();
  cv.fontSpec = FontSpec(30, null);
  cv.textAlign = TextAlign.end;
  cv.textBaseline = TextBaseline.top;
  cv.direction = TextDirection.ltr;
  assert(cv.fontSpec.ptSize == 30);
  cv.restore();
  assert(cv.fontSpec.ptSize == 20);
  assert(cv.textAlign == TextAlign.center);
  assert(cv.textBaseline == TextBaseline.middle);
  assert(cv.direction == TextDirection.rtl);

  // invalid sizes are ignored
  cv.fontSpec = FontSpec(0, null);
  cv.fontSpec = FontSpec(-3, null);
  cv.fontSpec = FontSpec(float.nan, null);
  cv.fontSpec = FontSpec(float.infinity, null);
  assert(cv.fontSpec.ptSize == 20);

  const e = cv.measureText("");
  assert(e.width == 0 && e.fontAscent == 0 && e.fontDescent == 0);
  const m = cv.measureText("Hello");
  assert(m.width > 0 && m.fontAscent > 0 && m.fontDescent >= 0);
  cv.fontSpec = FontSpec(40, null);
  const m2 = cv.measureText("Hello");
  assert(m2.width > m.width && m2.fontAscent > m.fontAscent);
}
