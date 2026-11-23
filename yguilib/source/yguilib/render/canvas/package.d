/** 2d drawing api similar to HTML canvas 2d api or svg. Reduced in features,
    simplified, uses float, int and other efficient types.
    https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial

    A radial gradient with a negative radius, or a negative path radius, draws
    nothing instead of raising an error.

    Square caps on zero-length segments: they stay axis-aligned instead of
    rotating with the path, which shows on diagonal lines.

    Text (`fillText`, `strokeText`, `measureText`) draws glyph bitmaps from
    the `TextCache` as transformed quads, rasterized at the effective scale.
    `strokeText` is an SDL_ttf outline ring: caps, joins and dash are
    ignored. `direction` affects only `start`/`end` alignment.
*/
module yguilib.render.canvas;

import glad2.gles2 : GLuint;
import std.array : Appender;
import yguilib.render : Renderer;
import yguilib.render.canvas.path2d : Path2d;
import yguilib.render.font : Font;
import yguilib.render.internal.text_cache : TextTexture;
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
      drawImageShadow(t.id(), tint.a);
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

  /**
   * Fills `text` at `pos` (HTML `fillText`) with the current font, align,
   * baseline and direction, mapped by the current transform, honoring the
   * Canvas clip and shadow. The glyph bitmap is rasterized at the
   * effective scale (display scaling * transform scale, quantized) and
   * drawn as a transformed textured quad painted with the fill style
   * (solid color, gradient or pattern, using the glyph alpha as a mask).
   * No-op for an uninitialized renderer, empty text, non-finite `pos` or
   * an invisible fill.
   */
  void fillText(string text, PointF pos) {
    drawFilledText(text, pos, float.infinity);
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
    drawFilledText(text, pos, maxWidth);
  }

  /**
   * Strokes the outline of `text` at `pos` (HTML `strokeText`) painted
   * with `strokeStyle` (solid, gradient or pattern), honoring transform,
   * clip and shadow like `fillText`. The outline is an SDL_ttf outline
   * ring bitmap `max(1, round(lineWidth * scale))` px wide (capped at 64),
   * so it extends that far outside the glyph edge. Line cap, join and
   * dash are ignored. Same no-ops as `fillText`.
   */
  void strokeText(string text, PointF pos) {
    drawFilledText(text, pos, float.infinity, true);
  }

  /// Like `strokeText` with the `fillTextWithMaxWidth` squeeze.
  void strokeTextWithMaxWidth(string text, PointF pos, float maxWidth) {
    import std.math : isFinite;

    if (!isFinite(maxWidth) || !(maxWidth > 0)) {
      return;
    }
    drawFilledText(text, pos, maxWidth, true);
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
    private State st;
    private Appender!(State[]) stack;
    private Appender!(ClipEntry[]) clips;
    private Appender!(float[]) clipTris;
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
  void drawImageShadow(GLuint texId, float alpha) {
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
    drawImageShadowMask(texId, alpha, pass.get.box, pass.get.scale);
    endShadowPass(pass.get);
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
    if (!a.ensureSize(b.width, b.height)
      || (blur.sigma > 0 && !t.ensureSize(b.width, b.height))) {
      return res;
    }
    res = ShadowPass(b, scale, blur.sigma, SavedTargetState.capture());
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
   * mask-pixel sigma, limited to what can reach the viewport after the
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
    const float pw = fRenderer.logicWidth() * scale;
    const float ph = fRenderer.logicHeight() * scale;
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
    GLuint texId,
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
      texId, fShadowVerts[], ColorF(1, 1, 1, alpha), TextureMode.alphaMask,
      b.width / scale, b.height / scale
    );
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
    import yguilib.render.internal.pipelines : quadVertices;

    const float[24] local = quadVertices(dest, uv);
    fImageVerts.clear();
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
        xyuv, maskTex, u, fRenderer.logicWidth(), fRenderer.logicHeight()
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
      fRenderer.patternPipelineRef().drawMasked(
        xyuv, maskTex, u, fRenderer.logicWidth(), fRenderer.logicHeight()
      );
      return;
    }
  }

  /// Largest outline ring width (bitmap px) used by `strokeText`.
  enum int maxTextOutlinePx = 64;

  /**
   * Implementation of `fillText` / `strokeText`; `maxWidth` infinity means
   * unlimited.
   */
  void drawFilledText(
    string text, PointF pos, float maxWidth, bool stroke = false
  ) {
    import std.math : abs, isFinite, lrint, sqrt;
    import yguilib.render.internal.pipelines : TextureMode;
    import yguilib.render.internal.stencil_ops : beginClipTest, endStencil;

    const FillStyle paint = stroke ? st.stroke : st.fill;
    if (!fRenderer.isInitialized() || text.length == 0
      || !finitePoint(pos) || !paintVisible(paint)
      || !patternDrawable(paint)) {
      return;
    }
    const float det = abs(st.xf.a * st.xf.d - st.xf.b * st.xf.c);
    if (!isFinite(det) || det < 1e-12f) {
      return;
    }
    const spec = st.fontSpec;
    const float effScale = fRenderer.totalScaling() * sqrt(det);
    Font f = fRenderer.fontAtScale(spec.ptSize, spec.name, effScale);
    if (f is null) {
      return;
    }
    // outline ring width in bitmap pixels (0 for fill)
    int op = 0;
    if (stroke) {
      // SDL_ttf outline is centered on the contour: radius = lineWidth / 2
      const float px = 0.5f * st.lineWidth * effScale;
      op = isFinite(px) ? cast(int)lrint(px) : 1;
      op = op < 1 ? 1 : (op > maxTextOutlinePx ? maxTextOutlinePx : op);
    }
    const TextTexture tex = fRenderer.textTextureFor(f, text, op);
    if (!tex.isValid()) {
      return;
    }
    // bitmap pixels per user unit (the quantized font scale)
    const float q = f.scaledSize / f.size;
    // advance width at the raster scale (what measureText reports, not
    // the bitmap width) and the outline margin, in user units
    const float gw = f.measureText(text).x / q;
    const float margin = op / q;
    const TextMetrics m = TextMetrics(gw, f.ascent / q, abs(f.descent) / q);
    const PointF off = textAnchorOffset(
      m, st.textAlign, st.textBaseline, st.direction
    );
    // maxWidth squeezes x about the anchor
    const float s = gw > maxWidth ? maxWidth / gw : 1.0f;
    const float x0 = pos.x + off.x * s;
    buildImageVertsUv(
      RectF(0, 0, 1, 1),
      RectF(
        x0 - margin * s, pos.y + off.y - margin,
        tex.width / q * s, tex.height / q
      )
    );
    const bool solid = paint.kind == FillStyle.Kind.color;
    if (st.shadow.isVisible()) {
      drawImageShadow(tex.textureId, solid ? paint.color.a : 1.0f);
    }
    beginClipTest(clipActive());
    if (solid) {
      fRenderer.texturePipelineRef().drawTexturedTriangles(
        tex.textureId, fImageVerts[], paint.color, TextureMode.straight,
        fRenderer.logicWidth(), fRenderer.logicHeight()
      );
    } else {
      drawMaskedPaint(fImageVerts[], tex.textureId, paint);
    }
    endStencil();
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
    import yguilib.render.internal.pipelines : TextureMode, TexturedQuad;
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
      a.texture, q, fRenderer.logicWidth(), fRenderer.logicHeight(),
      TextureMode.straight
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
    const float[12] all = quadFromRect(RectF(
      -1, -1, fRenderer.logicWidth() + 2,
      fRenderer.logicHeight() + 2
    ));
    drawVerts(all[], none);
    if (verts.length > 0) {
      const float[12] cover = quadFromRect(boundsOfVerts(verts));
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
