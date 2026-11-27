/** 2d drawing api similar to HTML canvas 2d api or svg. Reduced in features,
    simplified, uses float, int and other efficient types.
    https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial

    A radial gradient with a negative radius, or a negative path radius, draws
    nothing instead of raising an error.

    Square caps on zero-length segments: they stay axis-aligned instead of
    rotating with the path, which shows on diagonal lines.

    Text (`fillText`, `strokeText`, `measureText`) draws per-glyph quads from
    the shared glyph atlas (`TextRunCache` runs), rasterized at the effective
    scale.
    `strokeText` is an SDL_ttf outline ring: caps, joins and dash are
    ignored. `direction` affects only `start`/`end` alignment.
*/
module yguilib.render.canvas;

import glad2.gles2 : GLuint;
import std.array : Appender;
import yguilib.render : Renderer;
import yguilib.render.canvas.path2d : Path2d;
import yguilib.render.font : Font;
import yguilib.render.internal.text_cache : RunGlyph, TextRun;
import yguilib.render.canvas.types;
import yguilib.render.internal.offscreen : SavedTargetState;
import yguilib.render.internal.path_flatten : Contours;
import yguilib.render.internal.pipelines : GradientUniforms, PatternUniforms,
  TextVertex, TextureMode, Viewport, packTextColor, rectTriangles,
  textureModeFor;
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
 *
 * Do not replicate standalone path functions, like `ctx.arc` or
 * `ctx.beginPath`: the user is expected to use `Path2d` to draw paths.
 */
final class Canvas {
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
   * black, honoring the Canvas clip and the scissor. Without a Canvas
   * clip and with a translate/scale transform this is a scissored
   * `glClear` of the pixels whose centers are inside the rect (the
   * pixels the stencil fill would cover). That clear is not antialiased:
   * on a multisampled framebuffer a fractional edge is cut at the pixel
   * centers instead of partially covering the edge pixels (rotation,
   * skew or a Canvas clip use the antialiased stencil path).
   */
  void clearRect(RectF rect) {
    if (fRenderer.isInitialized() && !clipActive()) {
      const box = clearBoxOf(rect);
      if (!box.isNull) {
        version (unittest) {
          ++fPathStats.scissorClears;
        }
        fRenderer.clearPixelBox(box.get);
        return;
      }
    }
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

  /**
   * Stores a copy of `dash` (already normalized by
   * `LineDash.fromSegments`); does not allocate.
   */
  void lineDash(in LineDash dash) {
    st.dash = dash;
  }

  /// A copy of the current dash; does not allocate.
  LineDash lineDash() const {
    return st.dash;
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

    if (isFinitePoint(s.offset) && isFinite(s.blur) && s.blur >= 0) {
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
    p.dash = st.dash;
    p.dashOffset = st.dashOffset;
    p.tolerance = tol;
    // stroke straight into fVerts (the shadow pass reads it) and map it
    // to device space in place: no second copy of the geometry
    fVerts.clear();
    strokeContours(fContours, p, fVerts, fDashContours);
    transformInPlace(fVerts[], st.xf);
    if (fVerts[].length == 0) {
      return;
    }
    if (st.shadow.isVisible()) {
      drawShadow(ShadowShape.stroke, FillRule.nonZero, st.stroke);
    }
    fRenderer.flush();
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
    import yguilib.render.internal.stencil_ops : beginClipTest, endStencil;

    if (!fRenderer.isInitialized() || t is null || !t.isValid()
      || !rectDrawable(srcPx) || !rectDrawable(dest) || !(tint.a > 0)) {
      return;
    }
    version (assert) {
      assert(!fRenderer.isActiveTargetTexture(t),
        "drawing the texture of an active render target (feedback loop)");
    }
    buildImageVerts(t, srcPx, dest);
    if (st.shadow.isVisible()) {
      drawImageShadow(t.id(), tint.a);
    }
    fRenderer.flush();
    beginClipTest(clipActive());
    fRenderer.texturePipelineRef().drawTexturedTriangles(
      t.id(), fImageVerts[], tint, textureModeFor(t),
      fRenderer.logicViewport()
    );
    endStencil();
  }

  // push state
  void save() {
    // clips are shared by prefix (see `fClips`): no copy needed
    fStack.put(st);
  }

  // pop state
  void restore() {
    const size_t n = fStack[].length;
    if (n == 0) {
      return;
    }
    st = fStack[][n - 1];
    fStack.shrinkTo(n - 1);
    assert(st.clipCount <= fClips[].length);
    if (st.clipCount < fClips[].length) {
      fClipTris.shrinkTo(fClips[][st.clipCount].triStart);
      fClips.shrinkTo(st.clipCount);
      rebuildClip();
    }
  }

  void translate(PointF offset) {
    if (isFinitePoint(offset)) {
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
    if (isFinitePoint(factor)) {
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
    import yguilib.render.internal.path_flatten : flattenPath;

    assert(path !is null);
    assert(st.clipCount == fClips[].length);
    // the fan is stored flattened with today's tolerance, so a clip keeps
    // the tolerance (display scaling) from when it was created
    flattenPath(path, tolerance(st.xf), fContours);
    const size_t start = fClipTris[].length;
    appendFan(st.xf, fClipTris);
    const ClipEntry e = ClipEntry(
      start, fClipTris[].length - start, st.clipRule
    );
    const bool first = st.clipCount == 0;
    fClips.put(e);
    ++st.clipCount;
    if (!fRenderer.isInitialized()) {
      return;
    }
    fRenderer.flush();
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
   * Measures `text` with the current font in user units. The font is
   * rasterized at the current effective scale (display scaling * transform
   * scale, quantized), so the advance is the one `fillText` lays out.
   * Returns zeros when the renderer is uninitialized or `text` is empty.
   */
  TextMetrics measureText(string text) {
    if (!fRenderer.isInitialized() || text.length == 0) {
      return TextMetrics.init;
    }
    // one font lookup for the width and the metrics
    Font f = textFont();
    if (f is null) {
      return TextMetrics.init;
    }
    return textMetricsOf(f, text);
  }

  /**
   * Fills `text` at `pos` (HTML `fillText`) with the current font, align,
   * baseline and direction, mapped by the current transform, honoring the
   * Canvas clip and shadow. The glyphs are rasterized at the
   * effective scale (display scaling * transform scale, quantized) and
   * drawn as transformed atlas quads painted with the fill style
   * (solid color, gradient or pattern, using the glyph alpha as a mask).
   * No-op for an uninitialized renderer, empty text, non-finite `pos` or
   * an invisible fill.
   */
  void fillText(string text, PointF pos) {
    drawTextBitmap(text, pos, float.infinity, 0);
  }

  /**
   * Like `fillText`, but text wider than `maxWidth` (user units) is
   * squeezed horizontally about `pos` to fit. No-op when `maxWidth` is
   * not finite or <= 0.
   */
  void fillTextWithMaxWidth(string text, PointF pos, float maxWidth) {
    import std.math : isFinite;

    if (!isFinite(maxWidth) || !(maxWidth > 0)) {
      return;
    }
    drawTextBitmap(text, pos, maxWidth, 0);
  }

  /**
   * Strokes the outline of `text` at `pos` (HTML `strokeText`) painted
   * with `strokeStyle` (solid, gradient or pattern), honoring transform,
   * clip and shadow like `fillText`. The outline is an SDL_ttf outline
   * ring `max(1, round(lineWidth * scale))` px wide (capped at 64),
   * so it extends that far outside the glyph edge. Line cap, join and
   * dash are ignored. Same no-ops as `fillText`.
   */
  void strokeText(string text, PointF pos) {
    drawTextBitmap(text, pos, float.infinity, strokeOutlinePx());
  }

  /// Like `strokeText` with the `fillTextWithMaxWidth` squeeze.
  void strokeTextWithMaxWidth(string text, PointF pos, float maxWidth) {
    import std.math : isFinite;

    if (!isFinite(maxWidth) || !(maxWidth > 0)) {
      return;
    }
    drawTextBitmap(text, pos, maxWidth, strokeOutlinePx());
  }

package(yguilib):
  version (unittest) {
    /// Counts of the fill / clear paths taken (tests of the fast paths).
    struct PathStats {
      /// `fill` drawn directly as a convex fan (no stencil).
      size_t convexFills;
      /// Fills (and clears) drawn by stencil-then-cover.
      size_t stencilFills;
      /// `clearRect` done as a scissored `glClear`.
      size_t scissorClears;
    }

    PathStats pathStats() const {
      return fPathStats;
    }
  }

package(yguilib.render):
  /// Resets to the default state with an empty save stack (new frame).
  void resetFrame() {
    st = State.init;
    fStack.clear();
    fClips.clear();
    fClipTris.clear();
  }

  /**
   * Drawing state, save stack and clips kept across a render target pass.
   * A reusable slot (`Renderer` keeps one per target depth): the buffers
   * are swapped with the Canvas, never copied, so a slot must not be
   * copied while it holds buffers (the copy would share them).
   */
  struct FrameState {
  private:
    State st;
    Appender!(State[]) stack;
    Appender!(ClipEntry[]) clips;
    Appender!(float[]) clipTris;
  }

  /**
   * Moves the current state, save stack and clips into `slot` and leaves
   * the Canvas with the slot's former (cleared) buffers. Nothing is
   * copied (`Renderer.beginTarget` calls `resetFrame()` afterwards).
   */
  void saveFrameState(ref FrameState slot) {
    import std.algorithm.mutation : swap;

    debug assertDistinct(slot);
    slot.st = st;
    swap(fStack, slot.stack);
    swap(fClips, slot.clips);
    swap(fClipTris, slot.clipTris);
    fStack.clear();
    fClips.clear();
    fClipTris.clear();
  }

  /**
   * Restores a state saved by `saveFrameState` into `slot`, swapping the
   * buffers back (the slot keeps the target pass buffers, cleared, for
   * reuse). The clip bit is not rebuilt: it still lives in the stencil of
   * the restored framebuffer.
   */
  void restoreFrameState(ref FrameState slot) {
    import std.algorithm.mutation : swap;

    debug assertDistinct(slot);
    st = slot.st;
    swap(fStack, slot.stack);
    swap(fClips, slot.clips);
    swap(fClipTris, slot.clipTris);
    slot.st = State.init;
    slot.stack.clear();
    slot.clips.clear();
    slot.clipTris.clear();
    assert(st.clipCount == fClips[].length);
  }

  /// Asserts that `slot` shares no buffer with the Canvas.
  void assertDistinct(ref FrameState slot) {
    assert(!sameStorage(fStack, slot.stack), "FrameState aliases fStack");
    assert(!sameStorage(fClips, slot.clips), "FrameState aliases fClips");
    assert(!sameStorage(fClipTris, slot.clipTris),
      "FrameState aliases fClipTris");
  }

  /**
   * True when `a` and `b` (both allocated) use the same storage, as Appender
   * copies do.
   */
  static bool sameStorage(T)(ref Appender!(T[]) a, ref Appender!(T[]) b) {
    return a[].ptr !is null && a[].ptr is b[].ptr;
  }

private:
  /**
   * One `clip()` call, replayed to rebuild the clip bit on `restore()`:
   * its fan triangles (already flattened and transformed to logic
   * coordinates) are the floats `fClipTris[triStart .. triStart +
   * triCount]`.
   */
  struct ClipEntry {
    size_t triStart;
    size_t triCount;
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
    /// Number of `fClips` entries active in this state (see `clip()`).
    size_t clipCount;
    Shadow shadow;
    FontSpec fontSpec;
    TextAlign textAlign = TextAlign.start;
    TextBaseline textBaseline = TextBaseline.alphabetic;
    TextDirection direction = TextDirection.ltr;
  }

  // 1176 bytes before `FillStyle` became a tagged union (review 1.9)
  static assert(State.sizeof < 1176 * 6 / 10);

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
  /**
   * Clips of the current state (`st.clipCount` entries) and their fan
   * triangles. Invariant: the list is append-only between `save()` and
   * `restore()`, so every saved state's clips are a prefix of it and a
   * state needs only its `clipCount`; `restore()` truncates.
   */
  Appender!(ClipEntry[]) fClips;
  /// Float (x, y) fan triangles of all `fClips` entries, in order.
  Appender!(float[]) fClipTris;
  /// Reused scratch buffers (no per-call GC churn).
  Contours fContours;
  /// Dashed sub-contours of `fContours` (see `strokeContours`).
  Contours fDashContours;
  Appender!(float[]) fVerts;
  Appender!(float[]) fShadowVerts;
  /// (x, y, u, v) triangles of the last `drawImageRegionTinted`.
  Appender!(float[]) fImageVerts;
  Path2d fRectPath;
  version (unittest) {
    PathStats fPathStats;
  }

  bool clipActive() const {
    return st.clipCount > 0;
  }

  bool canDraw(const Path2d path) const {
    return fRenderer.isInitialized() && !path.isEmpty();
  }

  float tolerance(in Transform2d xf) const {
    import yguilib.render.internal.path_flatten : flattenTolerance;

    return flattenTolerance(fRenderer.totalScaling(), xf);
  }

  /// True when `r` is finite with a positive width and height.
  static bool rectDrawable(in RectF r) {
    return isFiniteRect(r) && r.width > 0 && r.height > 0;
  }

  /**
   * GL pixel box (`[x, y, w, h]`, bottom-left origin) of the pixels whose
   * centers lie inside `rect` mapped by the current transform, clamped to
   * the viewport. Null when the transform rotates or skews or the result
   * is not finite (`clearRect` then uses the stencil path).
   */
  auto clearBoxOf(in RectF rect) const {
    import std.algorithm : max, min;
    import std.math : ceil, isFinite;
    import std.typecons : Nullable;

    Nullable!(int[4]) res;
    const Transform2d m = st.xf;
    if (m.b != 0 || m.c != 0 || !isFiniteRect(rect)) {
      return res;
    }
    const float s = fRenderer.totalScaling();
    const float ax = (m.a * rect.x + m.e) * s;
    const float bx = (m.a * (rect.x + rect.width) + m.e) * s;
    const float ay = (m.d * rect.y + m.f) * s;
    const float by = (m.d * (rect.y + rect.height) + m.f) * s;
    if (!isFinite(ax) || !isFinite(bx) || !isFinite(ay) || !isFinite(by)) {
      return res;
    }
    const float pw = fRenderer.pixelWidth();
    const float ph = fRenderer.pixelHeight();
    // pixel i is covered when its center i + 0.5 is in [lo, hi)
    const float left = min(max(ceil(min(ax, bx) - 0.5f), 0.0f), pw);
    const float right = min(max(ceil(max(ax, bx) - 0.5f), left), pw);
    const float top = min(max(ceil(min(ay, by) - 0.5f), 0.0f), ph);
    const float bottom = min(max(ceil(max(ay, by) - 0.5f), top), ph);
    const int[4] box = [cast(int)left, cast(int)(ph - bottom),
      cast(int)(right - left), cast(int)(bottom - top)];
    res = box;
    return res;
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
        && s.pattern.tint.a > 0 && s.pattern.transform.isInvertible();
    }
  }

  /// False when `s` is a pattern whose combined transform is singular.
  bool patternDrawable(in FillStyle s) const {
    if (s.kind != FillStyle.Kind.pattern) {
      return true;
    }
    return (st.xf * s.pattern.transform).isInvertible();
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
  ) nothrow @safe @nogc {
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
      const size_t base = i * 4;
      u.stopColors[base + 0] = stop.color.r;
      u.stopColors[base + 1] = stop.color.g;
      u.stopColors[base + 2] = stop.color.b;
      u.stopColors[base + 3] = stop.color.a;
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
   * `patternUniforms` of pattern style `s` under the current transform:
   * logic coordinates map to pattern space by the inverse of `st.xf *
   * s.pattern.transform`, with `extra` applied first (the shadow mask
   * origin shift, or identity). Asserts that the pattern is not the
   * texture of an active render target (feedback loop).
   */
  PatternUniforms patternUniformsFor(
    in FillStyle s,
    in Transform2d extra,
    TextureMode mode
  ) {
    version (assert) {
      assert(!fRenderer.isActiveTargetTexture(s.pattern.texture),
        "drawing the texture of an active render target (feedback loop)");
    }
    const Transform2d logicToPat =
      (st.xf * s.pattern.transform).inverse() * extra;
    return patternUniforms(s.pattern, logicToPat, mode);
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
        verts, u, fRenderer.logicViewport()
      );
      return;
    case FillStyle.Kind.pattern:
      const PatternUniforms u = patternUniformsFor(
        style, Transform2d.identity(), textureModeFor(style.pattern.texture)
      );
      fRenderer.patternPipelineRef().drawTriangles(
        verts, u, fRenderer.logicViewport()
      );
      return;
    }
  }

  /**
   * Stencil-then-cover fill of `path`. With `blend` false the cover pass
   * overwrites pixels with the solid color of `style` (used by
   * `clearRect`); with `blend` true an invisible `style` draws nothing.
   * A blended fill of a single convex contour without a Canvas clip
   * draws its fan triangles directly: they cover each pixel once, and
   * `nonZero` and `evenOdd` agree on it.
   */
  void fillWithRule(
    Path2d path,
    FillRule rule,
    in FillStyle style,
    bool blend
  ) {
    import glad2.gles2 : GL_BLEND, GL_TRIANGLES, glDisable;
    import yguilib.render.internal.path_flatten : flattenPath,
      isSingleConvex;
    import yguilib.render.internal.stencil_ops : beginClipTest,
      beginCover, beginWinding, endStencil;

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
    fRenderer.flush();
    if (blend && !clipActive() && isSingleConvex(fContours)) {
      version (unittest) {
        ++fPathStats.convexFills;
      }
      beginClipTest(false);
      drawPaint(fVerts[], style);
      return;
    }
    version (unittest) {
      ++fPathStats.stencilFills;
    }
    const float[12] cover = rectTriangles(boundsOfVerts(fVerts[]));
    beginWinding(rule);
    drawVerts(fVerts[], ColorF(0, 0, 0, 0));
    beginCover(rule, clipActive());
    if (blend) {
      drawPaint(cover[], style);
    } else {
      glDisable(GL_BLEND);
      fRenderer.colorPipelineRef().drawArraysWithCurrentState(
        GL_TRIANGLES, cover[], style.color, fRenderer.logicViewport()
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
  void drawImageShadow(GLuint texId, float alpha) {
    const pass = beginImageShadowPass();
    if (pass.isNull) {
      return;
    }
    drawImageShadowMask(texId, alpha, pass.get.box, pass.get.scale);
    endShadowPass(pass.get);
  }

  /**
   * Shadow of the `fImageVerts` glyph quads masked by `atlasTex` and
   * painted with `paint` (solid color alpha or gradient/pattern alpha).
   */
  void drawTextShadow(GLuint atlasTex, in FillStyle paint) {
    const pass = beginImageShadowPass();
    if (pass.isNull) {
      return;
    }
    const PixelBox b = pass.get.box;
    const float scale = pass.get.scale;
    if (paint.kind == FillStyle.Kind.color) {
      drawImageShadowMask(atlasTex, paint.color.a, b, scale);
    } else {
      drawMaskedShadowMask(atlasTex, paint, b, scale);
    }
    endShadowPass(pass.get);
  }

  /// Copies `fImageVerts` xy into `fVerts` and begins a shadow pass.
  auto beginImageShadowPass() {
    const(float)[] xyuv = fImageVerts[];
    fVerts.clear();
    for (size_t i = 0; i + 3 < xyuv.length; i += 4) {
      fVerts.put(xyuv[i]);
      fVerts.put(xyuv[i + 1]);
    }
    return beginShadowPass();
  }

  /**
   * Offscreen shadow pass in progress (see `beginShadowPass`). `box` is
   * in mask pixels, `scale` is mask pixels per logic unit (the total
   * scaling over the downsample factor) and `sigma` is in mask pixels.
   */
  struct ShadowPass {
    PixelBox box;
    float scale;
    float sigma;
    SavedTargetState saved;
  }

  /**
   * Saves the target state and binds the cleared region of offscreen
   * target 0 for the shadow box of `fVerts`, at the (possibly reduced)
   * mask resolution of `shadowBlurFromSigmaPx`. Null (nothing bound, the
   * caller draws the shape without a shadow) when the box is empty or the
   * offscreen targets cannot hold it.
   */
  auto beginShadowPass() {
    import std.typecons : Nullable;
    import yguilib.render.canvas.types : ShadowBlur, shadowBlurFromSigmaPx;
    import yguilib.render.internal.offscreen : OffscreenTarget;

    const float total = fRenderer.totalScaling();
    const ShadowBlur blur =
      shadowBlurFromSigmaPx(st.shadow.blur * 0.5f * total);
    const float scale = total / blur.downsample;
    const box = shadowBox(blur.sigma, scale);
    Nullable!ShadowPass res;
    if (box.isNull) {
      return res;
    }
    const PixelBox b = box.get;
    OffscreenTarget* a = &fRenderer.offscreenTargetRef(0);
    OffscreenTarget* t = &fRenderer.offscreenTargetRef(1);
    const GLuint curFbo = fRenderer.currentFramebuffer();
    if (!a.ensureSize(b.width, b.height, curFbo)
      || (blur.sigma > 0 && !t.ensureSize(b.width, b.height, curFbo))) {
      return res;
    }
    fRenderer.flush();
    res = ShadowPass(b, scale, blur.sigma, fRenderer.targetState());
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
   * Box of the shadow pass in mask pixels (`scale` per logic unit):
   * `fVerts` bounds padded by 3 sigma (+1), `sigma` being the clamped
   * mask-pixel sigma, limited to what can reach the visible area (the
   * viewport and the Renderer scissor clip, `scissorLogicRect`) after
   * the offset. The limit is padded too, so the blur near the visible
   * edges still reads every mask pixel it needs. Null when empty or when
   * nothing is visible.
   */
  auto shadowBox(float sigma, float scale) {
    import std.algorithm : max, min;
    import std.math : ceil, floor;
    import std.typecons : Nullable;

    Nullable!PixelBox res;
    const RectF vis = fRenderer.scissorLogicRect();
    if (!(vis.width > 0) || !(vis.height > 0)) {
      return res;
    }
    const RectF r = boundsOfVerts(fVerts[]);
    const float pad = ceil(3 * sigma) + 1;
    const float offX = st.shadow.offset.x * scale;
    const float offY = st.shadow.offset.y * scale;
    const float vx0 = vis.x * scale - offX;
    const float vy0 = vis.y * scale - offY;
    const float vx1 = (vis.x + vis.width) * scale - offX;
    const float vy1 = (vis.y + vis.height) * scale - offY;
    const float rx0 = r.x * scale;
    const float ry0 = r.y * scale;
    const float rx1 = (r.x + r.width) * scale;
    const float ry1 = (r.y + r.height) * scale;
    if (rx0 - pad >= vx1 || rx1 + pad <= vx0
      || ry0 - pad >= vy1 || ry1 + pad <= vy0) {
      return res;
    }
    const float x0 = max(floor(rx0), floor(vx0)) - pad;
    const float y0 = max(floor(ry0), floor(vy0)) - pad;
    const float x1 = min(ceil(rx1), ceil(vx1)) + pad;
    const float y1 = min(ceil(ry1), ceil(vy1)) + pad;
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
    const Viewport mask = maskViewport(b, scale);
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
        mask);
      beginCover(rule, false);
      const float[12] cover = rectTriangles(RectF(0, 0, mask.vw, mask.vh));
      drawMaskPaint(cover[], style, PointF(ox, oy), mask);
      endStencil();
      break;
    case ShadowShape.stroke:
      // no blending: overlapping triangles rewrite the same alpha
      drawMaskPaint(fShadowVerts[], style, PointF(ox, oy), mask);
      break;
    }
  }

  /// Logic viewport of shadow pass box `b` (`scale` mask px per unit).
  static Viewport maskViewport(in PixelBox b, float scale) {
    return Viewport(b.width / scale, b.height / scale, scale);
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
    in Viewport mask
  ) {
    import glad2.gles2 : GL_BLEND, GL_TRIANGLES, glDisable;

    glDisable(GL_BLEND);
    // the next draw re-enables blending via setupAlphaBlendState
    final switch (style.kind) {
    case FillStyle.Kind.color:
      fRenderer.colorPipelineRef().drawArraysWithCurrentState(
        GL_TRIANGLES, verts, ColorF(1, 1, 1, style.color.a), mask
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
        verts, u, mask
      );
      return;
    case FillStyle.Kind.pattern:
      const PatternUniforms u = patternUniformsFor(
        style, Transform2d.translation(origin), TextureMode.alphaMask
      );
      fRenderer.patternPipelineRef().drawTrianglesWithCurrentState(
        verts, u, mask
      );
      return;
    }
  }

  /// Shifts `fImageVerts` to the origin of box `b` into `fShadowVerts`.
  void fillShadowVertsFromImageVerts(in PixelBox b, float scale) {
    const float ox = b.x / scale;
    const float oy = b.y / scale;
    const(float)[] xyuv = fImageVerts[];
    fShadowVerts.clear();
    for (size_t i = 0; i + 3 < xyuv.length; i += 4) {
      const float[4] v = [xyuv[i] - ox, xyuv[i + 1] - oy, xyuv[i + 2],
        xyuv[i + 3]];
      fShadowVerts.put(v[]);
    }
  }

  /**
   * Draws the `fImageVerts` triangles shifted to the origin of box `b`
   * into the bound offscreen region with `GL_MAX` blending so overlapping
   * glyph quads do not erase neighbor masks or double-darken alpha,
   * writing the texture alpha * `alpha` (`TextureMode.alphaMask`).
   */
  void drawImageShadowMask(
    GLuint texId,
    float alpha,
    in PixelBox b,
    float scale
  ) {
    import glad2.gles2 : GL_BLEND, GL_FUNC_ADD, GL_MAX, glBlendEquation,
      glEnable;

    fillShadowVertsFromImageVerts(b, scale);
    glEnable(GL_BLEND);
    glBlendEquation(GL_MAX);
    fRenderer.texturePipelineRef().drawTexturedTrianglesWithCurrentState(
      texId, fShadowVerts[], ColorF(1, 1, 1, alpha), TextureMode.alphaMask,
      maskViewport(b, scale)
    );
    glBlendEquation(GL_FUNC_ADD);
  }

  /**
   * Draws `fImageVerts` shifted to the origin of box `b` using a
   * glyph-masked gradient/pattern pass into the bound offscreen region
   * with `GL_MAX` blending so stop/pattern alphas control shadow opacity.
   */
  void drawMaskedShadowMask(
    GLuint maskTex,
    in FillStyle style,
    in PixelBox b,
    float scale
  ) {
    import glad2.gles2 : GL_FUNC_ADD, GL_MAX, glBlendEquation;

    fillShadowVertsFromImageVerts(b, scale);
    const PointF origin = PointF(b.x / scale, b.y / scale);
    const Viewport mask = maskViewport(b, scale);
    glBlendEquation(GL_MAX);
    final switch (style.kind) {
    case FillStyle.Kind.color:
      assert(false);
    case FillStyle.Kind.linearGradient:
    case FillStyle.Kind.radialGradient:
      const Transform2d inv =
        st.xf.inverse() * Transform2d.translation(origin);
      GradientUniforms u = gradientUniforms(style, inv);
      // the composite tints the mask RGB too: keep only the stop alphas
      foreach (i; 0 .. u.stopCount) {
        u.stopColors[i * 4 .. i * 4 + 3] = 1.0f;
      }
      fRenderer.gradientPipelineRef().drawMasked(
        fShadowVerts[], maskTex, u, mask
      );
      break;
    case FillStyle.Kind.pattern:
      const PatternUniforms u = patternUniformsFor(
        style, Transform2d.translation(origin), TextureMode.alphaMask
      );
      fRenderer.patternPipelineRef().drawMasked(
        fShadowVerts[], maskTex, u, mask
      );
      break;
    }
    glBlendEquation(GL_FUNC_ADD);
  }

  /**
   * `fImageVerts` = two (x, y, u, v) triangles of `dest` transformed by
   * the current transform, sampling `srcPx` of `t`.
   */
  void buildImageVerts(Texture t, in RectF srcPx, in RectF dest) {
    buildImageVertsUv(Renderer.textureUv(t, srcPx), dest);
  }

  /// Like `buildImageVerts` with an explicit normalized `uv` rect.
  void buildImageVertsUv(in RectF uv, in RectF dest) {
    fImageVerts.clear();
    appendImageVerts(uv, dest);
  }

  /// Appends the transformed quad of `buildImageVertsUv` to `fImageVerts`.
  void appendImageVerts(in RectF uv, in RectF dest) {
    import yguilib.render.internal.pipelines : quadVertices;

    const float[24] local = quadVertices(dest, uv);
    for (size_t i = 0; i < local.length; i += 4) {
      const PointF p = st.xf.apply(PointF(local[i], local[i + 1]));
      const float[4] v = [p.x, p.y, local[i + 2], local[i + 3]];
      fImageVerts.put(v[]);
    }
  }

  /**
   * Draws (x, y, u, v) logic-space triangles painted with gradient or
   * pattern `style`, its alpha multiplied by the alpha of texture `maskTex`
   * (same uniforms as `drawPaint`). The stencil state must already be set.
   */
  void drawMaskedPaint(
    const(float)[] xyuv,
    GLuint maskTex,
    in FillStyle style
  ) {
    final switch (style.kind) {
    case FillStyle.Kind.color:
      return;
    case FillStyle.Kind.linearGradient:
    case FillStyle.Kind.radialGradient:
      const GradientUniforms u = gradientUniforms(style, st.xf.inverse());
      fRenderer.gradientPipelineRef().drawMasked(
        xyuv, maskTex, u, fRenderer.logicViewport()
      );
      return;
    case FillStyle.Kind.pattern:
      const PatternUniforms u = patternUniformsFor(
        style, Transform2d.identity(), textureModeFor(style.pattern.texture)
      );
      fRenderer.patternPipelineRef().drawMasked(
        xyuv, maskTex, u, fRenderer.logicViewport()
      );
      return;
    }
  }

  /// Largest outline ring width (bitmap px) used by `strokeText`.
  enum int maxTextOutlinePx = 64;

  /**
   * Text raster scale: display scaling times the transform scale
   * (`sqrt(|det|)`), before the font manager quantizes it.
   */
  float textRasterScale() const {
    import std.math : abs, sqrt;

    return fRenderer.totalScaling() * sqrt(abs(st.xf.determinant()));
  }

  /**
   * Current font rasterized at `textRasterScale` (display scaling alone
   * for a degenerate transform); null when it cannot be opened.
   */
  Font textFont() {
    const spec = st.fontSpec;
    const float s = textRasterScale();
    return fRenderer.fontAtScale(
      spec.ptSize, spec.name, s > 0 ? s : fRenderer.totalScaling()
    );
  }

  /**
   * Advance width, ascent and descent of `text` in font `f` (from
   * `textFont`), in user units.
   */
  TextMetrics textMetricsOf(Font f, string text) const {
    import std.math : abs;

    // bitmap pixels per user unit (the quantized font scale)
    const float q = f.scaledSize / f.size;
    return TextMetrics(
      f.measureText(text).x / q, f.ascent / q, abs(f.descent) / q
    );
  }

  /**
   * Outline ring width (bitmap px) of `strokeText`: `lineWidth / 2` at
   * the text raster scale, rounded, clamped to [1, `maxTextOutlinePx`].
   */
  int strokeOutlinePx() const {
    import std.math : isFinite, lrint;

    // SDL_ttf outline is centered on the contour: radius = lineWidth / 2
    const float px = 0.5f * st.lineWidth * textRasterScale();
    const int op = isFinite(px) ? cast(int)lrint(px) : 1;
    return op < 1 ? 1 : (op > maxTextOutlinePx ? maxTextOutlinePx : op);
  }

  /// Placement metrics and atlas scale shared by Canvas text draw paths.
  struct TextPlacement {
    float q;
    float ox;
    float oy;
    float sx;
    float invAtlas;
  }

  /// Computes anchor, squeeze, and atlas scale for `text` in font `f`.
  TextPlacement computeTextPlacement(
    Font f,
    string text,
    int outlinePx,
    PointF pos,
    float maxWidth
  ) const {
    const float q = f.scaledSize / f.size;
    const TextMetrics m = textMetricsOf(f, text);
    const PointF off = textAnchorOffset(
      m, st.textAlign, st.textBaseline, st.direction
    );
    // maxWidth squeezes x about the anchor
    const float sx = m.width > maxWidth ? maxWidth / m.width : 1.0f;
    const float margin = outlinePx / q;
    return TextPlacement(
      q,
      pos.x + off.x * sx - margin * sx,
      pos.y + off.y - margin,
      sx,
      1.0f / fRenderer.glyphAtlasSize()
    );
  }

  /// Local logic rect and normalized atlas UV rect of one laid-out glyph.
  struct GlyphQuadRect {
    RectF dest;
    RectF uv;
  }

  /// Computes the local quad rect and atlas UV rect for `g` under `p`.
  static GlyphQuadRect glyphQuadRect(
    in RunGlyph g,
    in TextPlacement p
  ) nothrow @safe @nogc {
    return GlyphQuadRect(
      RectF(
        p.ox + g.dx / p.q * p.sx,
        p.oy + g.dy / p.q,
        g.dw / p.q * p.sx,
        g.dh / p.q
      ),
      RectF(
        (g.slot.x + g.srcX) * p.invAtlas,
        (g.slot.y + g.srcY) * p.invAtlas,
        g.srcW * p.invAtlas,
        g.srcH * p.invAtlas
      )
    );
  }

  /**
   * Queues transformed glyph quads of `run` painted with solid `color`
   * into the renderer's shared text batch.
   */
  void queueTransformedTextRun(
    GLuint atlasTex,
    in TextRun run,
    in TextPlacement p,
    in ColorF color
  ) {
    const bool stencil = clipActive();
    const ubyte[4] packed = packTextColor(color);
    foreach (ref g; run.glyphs) {
      if (g.slot.w <= 0) {
        continue;
      }
      const GlyphQuadRect r = glyphQuadRect(g, p);
      const float gx0 = r.dest.x;
      const float gy0 = r.dest.y;
      const float gx1 = gx0 + r.dest.width;
      const float gy1 = gy0 + r.dest.height;
      const PointF p0 = st.xf.apply(PointF(gx0, gy0));
      const PointF p1 = st.xf.apply(PointF(gx1, gy0));
      const PointF p2 = st.xf.apply(PointF(gx0, gy1));
      const PointF p3 = st.xf.apply(PointF(gx1, gy1));
      const float u0 = r.uv.x;
      const float v0 = r.uv.y;
      const float u1 = u0 + r.uv.width;
      const float v1 = v0 + r.uv.height;
      const TextVertex[4] quad = [
        TextVertex(p0.x, p0.y, u0, v0, packed),
        TextVertex(p1.x, p1.y, u1, v0, packed),
        TextVertex(p2.x, p2.y, u0, v1, packed),
        TextVertex(p3.x, p3.y, u1, v1, packed),
      ];
      fRenderer.queueTextQuad(atlasTex, stencil, quad);
    }
  }

  /**
   * Implementation of `fillText` / `strokeText`: draws the glyph quads of
   * `text` (glyph fill for `outlinePx` 0, otherwise the outline ring of
   * that width, painted with the stroke style); `maxWidth` infinity means
   * unlimited.
   */
  void drawTextBitmap(
    string text, PointF pos, float maxWidth, int outlinePx
  ) {
    import yguilib.render.internal.stencil_ops : beginClipTest, endStencil;

    assert(outlinePx >= 0);
    const FillStyle paint = outlinePx > 0 ? st.stroke : st.fill;
    if (!fRenderer.isInitialized() || text.length == 0
      || !isFinitePoint(pos) || !paintVisible(paint)
      || !patternDrawable(paint) || !st.xf.isInvertible()) {
      return;
    }
    Font f = textFont();
    if (f is null) {
      return;
    }
    const TextRun* run = fRenderer.textRunFor(f, text, outlinePx);
    if (run is null) {
      return;
    }
    const GLuint atlasTex = fRenderer.glyphAtlasTexture();
    const int atlasSz = fRenderer.glyphAtlasSize();
    if (atlasTex == 0 || atlasSz <= 0) {
      return;
    }
    const TextPlacement p = computeTextPlacement(
      f, text, outlinePx, pos, maxWidth
    );
    const bool solid = paint.kind == FillStyle.Kind.color;
    if (solid && !st.shadow.isVisible()) {
      queueTransformedTextRun(atlasTex, *run, p, paint.color);
      return;
    }
    buildTextVerts(*run, p);
    if (fImageVerts[].length == 0) {
      return;
    }
    if (st.shadow.isVisible()) {
      drawTextShadow(atlasTex, paint);
    }
    if (solid) {
      queueTransformedTextRun(atlasTex, *run, p, paint.color);
    } else {
      fRenderer.flush();
      beginClipTest(clipActive());
      drawMaskedPaint(fImageVerts[], atlasTex, paint);
      endStencil();
    }
  }

  /**
   * `fImageVerts` = the glyph quads of `run` placed via `p`, used for
   * shadows and gradient/pattern masked text.
   */
  void buildTextVerts(in TextRun run, in TextPlacement p) {
    fImageVerts.clear();
    foreach (ref g; run.glyphs) {
      if (g.slot.w <= 0) {
        continue;
      }
      const GlyphQuadRect r = glyphQuadRect(g, p);
      appendImageVerts(r.uv, r.dest);
    }
  }

  /**
   * Blurs region `b` of target 0 horizontally into 1, vertically back.
   * Both targets were sized by `beginShadowPass`.
   */
  void blurShadow(in PixelBox b, float sigma) {
    import yguilib.render.internal.offscreen : OffscreenTarget;
    import yguilib.render.internal.pipelines : BlurPass;

    OffscreenTarget* a = &fRenderer.offscreenTargetRef(0);
    OffscreenTarget* t = &fRenderer.offscreenTargetRef(1);
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

  /**
   * Draws region `b` of target 0 tinted at `b` + offset (logic units),
   * upscaled with linear filtering when the mask is downsampled. The quad
   * is inset by half a mask pixel (whose alpha is 0: the box is padded)
   * so filtering never reads texels outside the region.
   */
  void compositeShadow(in PixelBox b, float scale) {
    import yguilib.render.internal.offscreen : OffscreenTarget;
    import yguilib.render.internal.pipelines : TexturedQuad;
    import yguilib.render.internal.stencil_ops : beginClipTest, endStencil;

    const OffscreenTarget* a = &fRenderer.offscreenTargetRef(0);
    const float tw = a.width;
    const float th = a.height;
    const float w = b.width - 1.0f;
    const float h = b.height - 1.0f;
    TexturedQuad q;
    q.dest = RectF(
      (b.x + 0.5f) / scale + st.shadow.offset.x,
      (b.y + 0.5f) / scale + st.shadow.offset.y,
      w / scale, h / scale
    );
    // GL rows grow upward while logic y grows downward: flip v
    q.uv = RectF(0.5f / tw, (b.height - 0.5f) / th, w / tw, -h / th);
    q.color = st.shadow.color;
    beginClipTest(clipActive());
    fRenderer.texturePipelineRef().drawTexturedQuad(
      a.texture, q, fRenderer.logicViewport(), TextureMode.straight
    );
    endStencil();
  }

  /**
   * Intersects the clip bit with clip entry `e` (scissor must be off),
   * drawing its stored triangles (no flattening).
   */
  void applyClip(in ClipEntry e) {
    import yguilib.render.internal.stencil_ops : beginClipIntersect,
      beginResetLow, beginWinding, endStencil;

    const(float)[] verts =
      fClipTris[][e.triStart .. e.triStart + e.triCount];
    const ColorF none = ColorF(0, 0, 0, 0);
    beginWinding(e.rule);
    drawVerts(verts, none);
    beginClipIntersect(e.rule);
    const float[12] all = rectTriangles(RectF(
      -1, -1, fRenderer.logicWidth() + 2,
      fRenderer.logicHeight() + 2
    ));
    drawVerts(all[], none);
    if (verts.length > 0) {
      const float[12] cover = rectTriangles(boundsOfVerts(verts));
      beginResetLow();
      drawVerts(cover[], none);
    }
    endStencil();
  }

  /// Rebuilds the clip bit from `fClips` after `restore()`.
  void rebuildClip() {
    if (!fRenderer.isInitialized()) {
      return;
    }
    fRenderer.flush();
    const bool scissor = disableScissor();
    clearClipBit(st.clipCount > 0);
    foreach (ref e; fClips[]) {
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
  bool disableScissor() {
    import glad2.gles2 : GL_SCISSOR_TEST, glDisable;

    // tracked by the Renderer (no glIsEnabled query)
    const bool was = fRenderer.scissorEnabled();
    if (was) {
      glDisable(GL_SCISSOR_TEST);
    }
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
      GL_TRIANGLES, verts, color, fRenderer.logicViewport()
    );
  }

  /// Fan triangles of every `fContours` contour, transformed into `fVerts`.
  void buildFan(in Transform2d xf) {
    fVerts.clear();
    appendFan(xf, fVerts);
  }

  /// Appends the `fContours` fan triangles, transformed by `xf`, to `dst`.
  void appendFan(in Transform2d xf, ref Appender!(float[]) dst) {
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
        dst.put(tri[]);
        prev = cur;
      }
    }
  }

  /// Transforms the `verts` (x, y pairs) by `xf` in place.
  static void transformInPlace(float[] verts, in Transform2d xf) {
    if (xf.isIdentity()) {
      return;
    }
    for (size_t i = 0; i + 1 < verts.length; i += 2) {
      const PointF p = xf.apply(PointF(verts[i], verts[i + 1]));
      verts[i] = p.x;
      verts[i + 1] = p.y;
    }
  }

  /// Bounds of `verts` grown by 1 unit so the cover hits edge samples.
  static RectF boundsOfVerts(const(float)[] verts) {
    const RectF b = boundsOfXy(verts);
    return RectF(b.x - 1, b.y - 1, b.width + 2, b.height + 2);
  }
}
