/**
 * Hardware 2D renderer over GL ES (`Renderer`), owned by `Window`.
 *
 * Draws flat, rounded, dashed, textured and text primitives in logic
 * units (pixels = logic * `totalScaling()`), keeps the scissor clip
 * stack, offscreen render targets (`beginTarget`/`endTarget`), the font
 * manager, the text texture cache and the shared pipelines used by
 * `Canvas`. The framebuffer, viewport, clear color, scissor and current
 * program are tracked, never queried from GL (debug builds check).
 */
module yguilib.render;

import glad2.gles2;
import yguilib.events : AppEvent;
import yguilib.render.internal.clip_stack : ClipStack;
import yguilib.render.font : Font, defaultFontPtSize;
import yguilib.render.font_manager : FontManager;
import yguilib.render.image : Image;
import yguilib.render.internal.offscreen : OffscreenTarget,
  SavedTargetState;
import yguilib.render.internal.gl_util : ProgramTracker, maxTextureSize;
import yguilib.render.internal.pipelines : BlurPipeline, ColorPipeline,
  GradientPipeline, PatternPipeline, RoundRectPipeline, RoundRectShape,
  TextPipeline, TextVertex, TextureMode, TexturePipeline, TexturedQuad,
  packTextColor,
  ThickLine, Viewport, textureModeFor;
import yguilib.render.internal.text_batch : TextBatch;
import yguilib.render.internal.text_cache : TextRun, TextRunCache;
import yguilib.render.render_types;
import yguilib.render.render_target : RenderTarget;
import yguilib.render.texture : Texture;
import yguilib.assets : defaultTtfFontData;
import yguilib.render.canvas : Canvas;

version (unittest) {
  import yguilib.render.internal.text_batch : TextBatchStats;
}

/// Managed by Window class. Lower level 2d api.
final class Renderer {
  this(int width, int height, float displayScaling) {
    viewportPixelWidth = width;
    viewportPixelHeight = height;
    fDisplayScaling = displayScaling > 0.0f ? displayScaling : 1.0f;
    fUnitsScaling = 1.0f;
    if (width > 0 && height > 0) {
      glViewport(0, 0, width, height);
    }
    // the only read of the target state: from here on it is tracked
    const SavedTargetState s = SavedTargetState.capture();
    fFramebuffer = cast(GLuint)s.framebuffer;
    fViewport = s.viewport;
    fClearColor = s.clearColor;
    if (s.scissorEnabled) {
      glDisable(GL_SCISSOR_TEST);
    }
    initialize();
  }

  Canvas canvas() {
    return fCanvas;
  }

  /**
   * Frees every GL and SDL_ttf object the renderer owns. Called by
   * `Window.destroy()` on the main thread with the context current; there
   * is no destructor (see `texture.d`).
   *
   * Order: the text cache is cleared first, then the font manager's
   * `onFontDestroyed` callback is detached (the cache is already empty)
   * and the managed fonts are destroyed, then the owned default font,
   * offscreen targets and pipelines.
   */
  void destroy() {
    if (!initialized) {
      return;
    }

    if (textCache !is null) {
      textCache.onBeforeAtlasReset(null);
    }
    fTextBatch.releaseMemory();
    clearTextCache();
    textCache = null;
    if (fontManager !is null) {
      fontManager.onFontDestroyed(null);
      fontManager.destroy();
      fontManager = null;
    }
    foreach (ref t; offscreenTargets) {
      t.destroy();
    }
    // User render targets are caller owned: only forget the stack.
    foreach (ref f; targetFrames[0 .. fTargetDepth]) {
      f.target.active--;
    }
    targetFrames = null;
    fTargetDepth = 0;
    blurPipeline.destroy();
    patternPipeline.destroy();
    gradientPipeline.destroy();
    rrPipeline.destroy();
    texPipeline.destroy();
    textPipeline.destroy();
    colorPipeline.destroy();
    clipStack.clear();
    initialized = false;
  }

  /**
   * Submits any queued batched text quads to the GPU.
   *
   * Callers issuing direct raw GL calls (such as `glReadPixels` or
   * `glFinish`) after text draws must call `flush()` first.
   */
  void flush() {
    if (!initialized) {
      return;
    }
    fTextBatch.flush(textPipeline, logicViewport());
  }

  void viewport(int pixelWidth, int pixelHeight) {
    assert(!inTarget(), "viewport() called while a render target is active");
    flush();
    viewportPixelWidth = pixelWidth;
    viewportPixelHeight = pixelHeight;
    glViewport(0, 0, pixelWidth, pixelHeight);
    fViewport = [0, 0, pixelWidth, pixelHeight];
    fPrograms.invalidate();
    if (initialized && !clipStack.isEmpty()) {
      clipStack.reapply(
        viewportPixelWidth, viewportPixelHeight, totalScaling()
      );
    }
  }

  /**
   * Sets the additional scaling factor above displayScaling (e.g. to support
   * zooming in/out UI for user preferences). Defaults to 1.0.
   */
  void unitsScaling(float scaling) {
    const float newScale = scaling > 0.0f ? scaling : 1.0f;
    if (newScale != fUnitsScaling) {
      flush();
      fUnitsScaling = newScale;
      onScalingChanged();
    }
  }

  /**
   * Gets the additional scaling factor above displayScaling (defaults to 1.0).
   */
  float unitsScaling() const {
    return fUnitsScaling;
  }

  void displayScaling(float scaling) {
    const float newScale = scaling > 0.0f ? scaling : 1.0f;
    if (newScale != fDisplayScaling) {
      flush();
      fDisplayScaling = newScale;
      onScalingChanged();
    }
  }

  float displayScaling() const {
    return fDisplayScaling;
  }

  alias defaultScaling = displayScaling;

  /**
   * Gets the combined scaling factor (displayScaling * unitsScaling).
   */
  float totalScaling() const {
    return fDisplayScaling * fUnitsScaling;
  }

  float pixelsFromLogicFloat(float logicUnits) const {
    return logicUnits * (fDisplayScaling * fUnitsScaling);
  }

  float logicFromPixelsFloat(float pixels) const {
    const float totalScale = fDisplayScaling * fUnitsScaling;
    return totalScale > 0.0f ? (pixels / totalScale) : pixels;
  }

  PointF pixelsFromLogicPoint(in PointF logicPoint) const {
    return PointF(
      pixelsFromLogicFloat(logicPoint.x),
      pixelsFromLogicFloat(logicPoint.y)
    );
  }

  PointF logicFromPixelsPoint(in PointF pixelPoint) const {
    return PointF(
      logicFromPixelsFloat(pixelPoint.x),
      logicFromPixelsFloat(pixelPoint.y)
    );
  }

  RectF pixelsFromLogicRect(in RectF logicRect) const {
    return RectF(
      pixelsFromLogicFloat(logicRect.x),
      pixelsFromLogicFloat(logicRect.y),
      pixelsFromLogicFloat(logicRect.width),
      pixelsFromLogicFloat(logicRect.height)
    );
  }

  RectF logicFromPixelsRect(in RectF pixelRect) const {
    return RectF(
      logicFromPixelsFloat(pixelRect.x),
      logicFromPixelsFloat(pixelRect.y),
      logicFromPixelsFloat(pixelRect.width),
      logicFromPixelsFloat(pixelRect.height)
    );
  }

  int pixelWidth() const {
    return viewportPixelWidth;
  }

  int pixelHeight() const {
    return viewportPixelHeight;
  }

  float logicWidth() const {
    return logicFromPixelsFloat(cast(float)viewportPixelWidth);
  }

  float logicHeight() const {
    return logicFromPixelsFloat(cast(float)viewportPixelHeight);
  }

  int viewportWidth() const {
    return cast(int)logicWidth();
  }

  int viewportHeight() const {
    return cast(int)logicHeight();
  }

  bool isOnScreen(in RectF rect) const {
    return isOnScreenWithViewport(rect, logicWidth(), logicHeight());
  }

  /**
   * Tests whether a rectangle intersects the logical screen viewport.
   *
   * Params:
   *   rect = Rectangle in logical coordinates.
   *   vw = Viewport width in logical units.
   *   vh = Viewport height in logical units.
   * Returns: true if rectangle has positive size and intersects the viewport.
   */
  static bool isOnScreenWithViewport(in RectF rect, float vw, float vh) {
    return rect.width > 0.0f && rect.height > 0.0f
      && rect.x < vw && rect.y < vh
      && (rect.x + rect.width) > 0.0f
      && (rect.y + rect.height) > 0.0f;
  }

  /// Converts mouse coordinates in `event` (window points) to logic units.
  PointF coordinatesFromEvent(in AppEvent event) const {
    return coordinatesFromCoords(event.mouse.x, event.mouse.y);
  }

  /// Converts (`x`, `y`) in window points to logic units.
  PointF coordinatesFromCoords(float x, float y) const {
    const float factor = fUnitsScaling > 0.0f ? (1.0f / fUnitsScaling) : 1.0f;
    return PointF(x * factor, y * factor);
  }

  /// Converts `point` in window points to logic units.
  PointF coordinatesFromPoint(in PointF point) const {
    return coordinatesFromCoords(point.x, point.y);
  }

  /**
   * Starts a frame: clears color to `color` and the stencil to 0 (both
   * honor the active scissor clip) and resets the Canvas state.
   * Inside `beginTarget` it clears the target; `color` is stored as-is,
   * so it should be premultiplied (target textures are premultiplied).
   * Outside render targets it also starts a new text cache frame
   * (`TextRunCache.beginFrame`), protecting this frame's strings.
   */
  void clearFrame(ColorF color) {
    if (!initialized) {
      return;
    }
    flush();
    clearColor(color);
    glStencilMask(0xFF);
    glClearStencil(0);
    glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
    if (fCanvas !is null) {
      fCanvas.resetFrame();
    }
    if (textCache !is null && !inTarget()) {
      textCache.beginFrame();
    }
  }

  void drawFillRect(RectF rect, ColorF color) {
    if (!initialized) {
      return;
    }
    flush();
    colorPipeline.drawFillRect(rect, color, logicViewport());
  }

  /**
   * Draws a 1-pixel line connecting two points.
   *
   * Params:
   *   point1 = Start point in logic-space units.
   *   point2 = End point in logic-space units.
   *   color = Line color.
   */
  void drawThinLineWithPoints(PointF point1, PointF point2, ColorF color) {
    if (!initialized) {
      return;
    }
    flush();
    colorPipeline.drawThinLineWithPoints(
      point1, point2, color, logicViewport()
    );
  }

  /**
   * Draws a line with configurable thickness.
   *
   * Params:
   *   point1 = Start point in logic-space units.
   *   point2 = End point in logic-space units.
   *   lineWidth = Line thickness in logic-space units.
   *   color = Line color.
   */
  void drawLineWithPoints(
    PointF point1,
    PointF point2,
    float lineWidth,
    ColorF color
  ) {
    drawLineDashed(point1, point2, lineWidth, DashPattern.init, color);
  }

  /**
   * Draws a dashed line with configurable thickness and dash pattern.
   *
   * Params:
   *   point1 = Start point in logic-space units.
   *   point2 = End point in logic-space units.
   *   lineWidth = Line thickness in logic-space units.
   *   dash = Dash and gap lengths (`DashPattern.init` draws solid).
   *   color = Line color.
   */
  void drawLineDashed(
    PointF point1,
    PointF point2,
    float lineWidth,
    DashPattern dash,
    ColorF color
  ) {
    if (!initialized) {
      return;
    }
    flush();
    colorPipeline.drawDashedLine(
      ThickLine(point1, point2, lineWidth), dash, color, logicViewport()
    );
  }

  /**
   * Draws a rectangle outline with configurable line width.
   *
   * Params:
   *   rect = Bounding rectangle in logic-space units.
   *   lineWidth = Outline thickness in logic-space units; it grows
   *     inside, i.e. rect is always the outer boundary.
   *   color = Outline color.
   */
  void drawRectWithWidth(RectF rect, float lineWidth, ColorF color) {
    if (!initialized) {
      return;
    }
    flush();
    colorPipeline.drawRectWithWidth(rect, lineWidth, color, logicViewport());
  }

  /**
   * Draws a rectangle outline with default line width (1.0).
   *
   * Params:
   *   rect = Bounding rectangle in logic-space units.
   *   color = Outline color.
   */
  void drawRect(RectF rect, ColorF color) {
    drawRectWithWidth(rect, 1.0f, color);
  }

  /**
   * Draws a dashed rectangle outline with configurable line
   * width and dash pattern.
   *
   * Params:
   *   rect = Bounding rectangle in logic-space units.
   *   lineWidth = Outline thickness in logic-space units; it grows
   *     inside, i.e. rect is always the outer boundary.
   *   dash = Dash and gap lengths (`DashPattern.init` draws solid).
   *   color = Outline color.
   */
  void drawRectDashed(
    RectF rect,
    float lineWidth,
    DashPattern dash,
    ColorF color
  ) {
    drawRoundRectDashed(rect, 0.0f, lineWidth, dash, color);
  }

  /**
   * Draws a filled rounded rectangle with anti-aliased corners.
   *
   * Params:
   *   rect = Bounding rectangle in logic-space units.
   *   radius = Corner radius (clamped to half the smallest dimension).
   *   color = Fill color.
   */
  void drawFillRoundRect(RectF rect, float radius, ColorF color) {
    drawRoundRectDashed(rect, radius, 0.0f, DashPattern.init, color);
  }

  /**
   * Draws a rounded rectangle outline with configurable line width
   * and anti-aliased corners.
   *
   * Params:
   *   rect = Bounding rectangle in logic-space units.
   *   radius = Corner radius (clamped to half the smallest dimension).
   *   lineWidth = Outline thickness in logic-space units; it grows
   *     inside, i.e. rect is always the outer boundary.
   *   color = Outline color.
   */
  void drawRoundRect(
    RectF rect,
    float radius,
    float lineWidth,
    ColorF color
  ) {
    drawRoundRectDashed(rect, radius, lineWidth, DashPattern.init, color);
  }

  /**
   * Draws a dashed rounded rectangle outline with configurable line
   * width and dash pattern.
   *
   * Params:
   *   rect = Bounding rectangle in logic-space units.
   *   radius = Corner radius (clamped to half the smallest dimension).
   *   lineWidth = Outline thickness in logic-space units (0 fills).
   *   dash = Dash and gap lengths (`DashPattern.init` draws solid).
   *   color = Outline color.
   */
  void drawRoundRectDashed(
    RectF rect,
    float radius,
    float lineWidth,
    DashPattern dash,
    ColorF color
  ) {
    if (!initialized) {
      return;
    }
    flush();
    rrPipeline.draw(
      RoundRectShape(rect, radius, lineWidth, dash), color, logicViewport()
    );
  }

  void pushClipRect(RectF rect) {
    const float scale = totalScaling();
    if (clipStack.wouldPushChangeScissor(
        rect, viewportPixelWidth, viewportPixelHeight, scale)) {
      flush();
    }
    clipStack.push(
      rect,
      viewportPixelWidth,
      viewportPixelHeight,
      scale
    );
  }

  void popClipRect() {
    const float scale = totalScaling();
    if (clipStack.wouldPopChangeScissor(
        viewportPixelWidth, viewportPixelHeight, scale)) {
      flush();
    }
    clipStack.pop(
      viewportPixelWidth,
      viewportPixelHeight,
      scale
    );
  }

  void clipRect(RectF rect) {
    const float scale = totalScaling();
    if (clipStack.wouldSetChangeScissor(
        rect, viewportPixelWidth, viewportPixelHeight, scale)) {
      flush();
    }
    clipStack.set(
      rect,
      viewportPixelWidth,
      viewportPixelHeight,
      scale
    );
  }

  void resetClipRect() {
    if (clipStack.wouldResetChangeScissor()) {
      flush();
    }
    clipStack.reset();
  }

  /**
   * Retrieves a managed font instance for a given size and font face.
   *
   * Font instances are managed and cached by FontManager. When fontName is
   * null, empty, or "default", the built-in default font (defaultTtfFontData)
   * is used. The default font is created lazily on demand upon the very first
   * call to font, defaultFont, measureText, or drawText for a given size.
   *
   * If ptSize is non-positive, NaN, or infinity, it automatically falls back
   * to defaultFontPtSize.
   *
   * Params:
   *   ptSize = Logical point size in user space (defaults to 11.0f).
   *   fontName = Registered font name, or null/empty for default font.
   * Returns: A cached Font instance, or null if FontManager is not
   *   initialized.
   */
  Font font(float ptSize, string fontName) {
    if (fontManager !is null) {
      return fontManager.fontWithSize(ptSize, fontName, totalScaling());
    }
    return null;
  }

  /**
   * Gets the default font at defaultFontPtSize (11.0f).
   *
   * If no custom font was explicitly assigned via defaultFont, this
   * retrieves the managed default font instance via font(defaultFontPtSize).
   * The default font is created lazily on demand on first request.
   *
   * Returns: The default Font instance.
   */
  Font defaultFont() {
    if (fDefaultFont !is null) {
      return fDefaultFont;
    }
    return font(defaultFontPtSize, null);
  }

  /**
   * Assigns the default font (null restores the managed one). The font
   * stays caller owned; on a display or units scaling change the renderer
   * resizes it in place (`Font.scale`) to the new total scaling.
   */
  void defaultFont(Font font) {
    fDefaultFont = font;
  }

  /**
   * Registers a custom font face from in-memory TTF binary data.
   *
   * Registered fonts can subsequently be resolved by name in font,
   * measureText, and drawText.
   *
   * Params:
   *   fontName = Unique name identifying the font face.
   *   fontData = In-memory TTF data buffer.
   */
  void registerFontFromMemory(string fontName, const(void)[] fontData) {
    if (fontManager !is null) {
      fontManager.registerFontFromMemory(fontName, fontData);
    }
  }

  /**
   * Registers a custom font face from a font file path on disk.
   *
   * Registered fonts can subsequently be resolved by name in font,
   * measureText, and drawText.
   *
   * Params:
   *   fontName = Unique name identifying the font face.
   *   filePath = Path to the TTF font file.
   */
  void registerFontFromFile(string fontName, string filePath) {
    if (fontManager !is null) {
      fontManager.registerFontFromFile(fontName, filePath);
    }
  }

  /**
   * Checks whether a font face is registered or is the built-in default font.
   *
   * Params:
   *   fontName = Name of the font face to check.
   * Returns: true if the font face exists or is default, false otherwise.
   */
  bool hasFont(string fontName) const {
    return fontManager !is null ? fontManager.hasFont(fontName) : false;
  }

  /**
   * Creates a font from memory data scaled to the renderer's current display
   * and units resolution.
   *
   * Font point sizes (`ptSize`) in user space are unscaled logical points.
   * Scaling is automatically applied by the renderer as an internal detail.
   *
   * Params:
   *   fontData = TTF binary data in memory.
   *   ptSize = Unscaled logical point size in user space.
   * Returns: A newly allocated Font instance.
   */
  Font createFontFromMemory(const(void)[] fontData, float ptSize) {
    return Font.fromMemory(fontData, ptSize, totalScaling());
  }

  /**
   * Creates a font from a file path scaled to the renderer's current display
   * and units resolution.
   *
   * Font point sizes (`ptSize`) in user space are unscaled logical points.
   * Scaling is automatically applied by the renderer as an internal detail.
   *
   * Params:
   *   filePath = Path to the TTF font file.
   *   ptSize = Unscaled logical point size in user space.
   * Returns: A newly allocated Font instance.
   */
  Font createFontFromFile(string filePath, float ptSize) {
    return Font.fromFile(filePath, ptSize, totalScaling());
  }

  void clearTextCache() {
    flush();
    if (textCache !is null) {
      textCache.clear();
    }
  }

  /**
   * Uploads `img` into a new GPU texture. The caller owns the result and
   * must call `Texture.destroy()` on the main thread.
   *
   * Returns: the texture, or null if the renderer is not initialized or
   * `img` is null (allowed) or empty.
   */
  Texture createTexture(in Image img) {
    if (!initialized || img is null || img.isEmpty()) {
      return null;
    }
    auto t = new Texture();
    t.update(img);
    return t;
  }

  /**
   * Draws the whole texture `t` stretched to `dest` (logic coordinates),
   * multiplied by `tint` (straight alpha). A null `t` is a no-op.
   * Premultiplied and bottom-up textures (render targets) are handled.
   */
  void drawImage(Texture t, RectF dest, ColorF tint) {
    if (t is null) {
      return;
    }
    drawImageRegion(
      t, dest, RectF(0, 0, t.width(), t.height()), tint
    );
  }

  /**
   * Draws the `srcPx` region (texture pixels, top-left origin) of texture
   * `t` stretched to `dest` (logic coordinates), multiplied by `tint`
   * (straight alpha, also for premultiplied textures). Bottom-up textures
   * are flipped so the region shows upright.
   * A null or destroyed `t` is a no-op.
   */
  void drawImageRegion(Texture t, RectF dest, RectF srcPx, ColorF tint) {
    if (!initialized || t is null || !t.isValid()) {
      return;
    }
    version (assert) {
      assert(!isActiveTargetTexture(t),
        "drawing the texture of an active render target (feedback loop)");
    }
    flush();
    texPipeline.drawTexturedQuad(
      t.id(),
      TexturedQuad(dest, textureUv(t, srcPx), tint),
      logicViewport(),
      textureModeFor(t)
    );
  }

  /**
   * Reads back the `w` x `h` pixel rect at `x`, `y` (pixels, top-left
   * origin) from the currently bound framebuffer. The rect is clamped to
   * the viewport. Call it after rendering and before the buffer swap.
   *
   * Returns: an RGBA8 top-down image, or null if the renderer is not
   * initialized or the clamped rect is empty.
   */
  Image readPixels(int x, int y, int w, int h) {
    import std.algorithm.comparison : max, min;

    if (!initialized) {
      return null;
    }
    flush();
    const int pw = viewportPixelWidth;
    const int ph = viewportPixelHeight;
    const int x0 = max(x, 0);
    const int y0 = max(y, 0);
    const int x1 = min(x + w, pw);
    const int y1 = min(y + h, ph);
    if (x1 <= x0 || y1 <= y0) {
      return null;
    }
    const int cw = x1 - x0;
    const int ch = y1 - y0;
    auto img = new Image(cw, ch);
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
    glReadPixels(
      x0, ph - y0 - ch, cw, ch, GL_RGBA, GL_UNSIGNED_BYTE, img.pixels.ptr
    );
    img.flipVertical();
    return img;
  }

  /**
   * Reads back the whole viewport from the currently bound framebuffer
   * (see `readPixels`). Call it after rendering and before the swap.
   *
   * Returns: the frame image, or null if the renderer is not initialized
   * or the viewport is empty.
   */
  Image captureFrame() {
    return readPixels(0, 0, viewportPixelWidth, viewportPixelHeight);
  }

  /**
   * Creates an offscreen render target of `logicW` x `logicH` logic
   * units: `max(1, ceil(logic * totalScaling()))` pixels. With `msaa`
   * it uses min(4, GL_MAX_SAMPLES) samples, falling back to no MSAA when
   * fewer than 2 are supported or the MSAA framebuffer is incomplete.
   * The caller owns the result and must call `RenderTarget.destroy()` on
   * the main thread.
   *
   * Returns: the target, or null if the renderer is not initialized, the
   * size is not finite and positive, or the framebuffer is incomplete.
   */
  RenderTarget createRenderTarget(float logicW, float logicH, bool msaa) {
    if (!initialized) {
      return null;
    }
    const int pw = targetPixelsFromLogic(logicW);
    const int ph = targetPixelsFromLogic(logicH);
    if (pw <= 0 || ph <= 0) {
      return null;
    }
    const int samples = msaa ? targetSampleCount() : 0;
    auto rt = new RenderTarget(samples);
    if (rt.allocate(pw, ph, fFramebuffer)) {
      return rt;
    }
    if (samples == 0) {
      return null;
    }
    rt = new RenderTarget(0);
    return rt.allocate(pw, ph, fFramebuffer) ? rt : null;
  }

  /**
   * Resizes `rt` to `logicW` x `logicH` logic units (pixels as in
   * `createRenderTarget`). Reallocates only if the pixel size changes or
   * `rt` is invalid (e.g. destroyed); the content is undefined after a
   * reallocation and `rt.texture()` returns a new texture. A size that
   * is not finite and positive, or exceeds the GL limit, is ignored.
   * `rt` must not be active.
   *
   * Returns: true if `rt` is valid at the requested size, false on invalid
   * size or allocation failure.
   */
  bool resizeRenderTarget(RenderTarget rt, float logicW, float logicH) {
    assert(rt !is null);
    assert(rt.active == 0, "resizeRenderTarget() on an active target");
    if (!initialized) {
      return false;
    }
    const int pw = targetPixelsFromLogic(logicW);
    const int ph = targetPixelsFromLogic(logicH);
    if (pw <= 0 || ph <= 0) {
      return false;
    }
    if (rt.isValid() && rt.pixelWidth() == pw && rt.pixelHeight() == ph) {
      return true;
    }
    return rt.allocate(pw, ph, fFramebuffer);
  }

  /**
   * Redirects all Renderer and Canvas drawing into `rt` (valid, not
   * already active) until the matching `endTarget()`. Targets nest. The
   * viewport becomes the target size, the clip stack and Canvas state
   * start empty (both restored by `endTarget`), the scissor is off.
   * With `clear` the color is cleared to transparent and stencil to 0.
   */
  void beginTarget(RenderTarget rt, bool clear) {
    assert(initialized, "beginTarget() on uninitialized Renderer");
    assert(rt !is null && rt.isValid());
    import std.algorithm.mutation : swap;

    assert(rt.active == 0, "render target is already active");
    flush();
    // one reusable slot per depth: its buffers are swapped, not copied
    if (fTargetDepth == targetFrames.length) {
      targetFrames ~= TargetFrame.init;
    }
    TargetFrame* f = &targetFrames[fTargetDepth];
    f.target = rt;
    f.saved = targetState();
    f.pixelWidth = viewportPixelWidth;
    f.pixelHeight = viewportPixelHeight;
    debug assert(!clipStack.sharesStorage(f.clips),
      "TargetFrame aliases the clip stack");
    swap(clipStack, f.clips);
    clipStack.clear();
    if (fCanvas !is null) {
      fCanvas.saveFrameState(f.canvasState);
      fCanvas.resetFrame();
    }
    ++fTargetDepth;
    rt.active++;

    viewportPixelWidth = rt.pixelWidth();
    viewportPixelHeight = rt.pixelHeight();
    fFramebuffer = rt.drawFbo();
    fViewport = [0, 0, viewportPixelWidth, viewportPixelHeight];
    fPrograms.invalidate();
    glBindFramebuffer(GL_FRAMEBUFFER, fFramebuffer);
    glViewport(0, 0, viewportPixelWidth, viewportPixelHeight);
    glDisable(GL_SCISSOR_TEST);
    if (clear) {
      clearColor(ColorF(0, 0, 0, 0));
      glStencilMask(0xFF);
      glClearStencil(0);
      glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
    }
  }

  /**
   * Finishes the innermost `beginTarget`: resolves MSAA into the target
   * texture and restores the framebuffer, viewport, scissor, clear
   * color, clip stack and Canvas state. A `beginTarget` must be open.
   */
  void endTarget() {
    import std.algorithm.mutation : swap;

    assert(fTargetDepth > 0, "endTarget() without beginTarget()");
    flush();
    --fTargetDepth;
    TargetFrame* f = &targetFrames[fTargetDepth];
    const bool resolved = f.target.resolve(
      cast(GLuint)f.saved.framebuffer, !clipStack.isEmpty()
    );
    f.target.active--;
    f.target = null;

    fFramebuffer = cast(GLuint)f.saved.framebuffer;
    if (!resolved) {
      glBindFramebuffer(GL_FRAMEBUFFER, fFramebuffer);
    }
    fViewport = f.saved.viewport;
    glViewport(fViewport[0], fViewport[1], fViewport[2], fViewport[3]);
    fClearColor = f.saved.clearColor;
    glClearColor(
      fClearColor[0], fClearColor[1], fClearColor[2], fClearColor[3]
    );
    fPrograms.invalidate();
    viewportPixelWidth = f.pixelWidth;
    viewportPixelHeight = f.pixelHeight;
    debug assert(!clipStack.sharesStorage(f.clips),
      "TargetFrame aliases the clip stack");
    swap(clipStack, f.clips);
    // the slot keeps the target's (cleared) buffer for the next pass
    f.clips.clear();
    clipStack.reapply(
      viewportPixelWidth, viewportPixelHeight, totalScaling()
    );
    if (fCanvas !is null) {
      fCanvas.restoreFrameState(f.canvasState);
    }
  }

  /// True between `beginTarget` and its matching `endTarget`.
  bool inTarget() const {
    return fTargetDepth > 0;
  }

  /**
   * Draws text at a specified position using a font instance or the default
   * font.
   *
   * If font is null, the managed default font (created lazily on demand)
   * is used. Glyph runs are cached via TextRunCache over one glyph atlas.
   *
   * Params:
   *   text = Text string to render.
   *   pos = Top-left position in logical coordinates.
   *   color = Text color (defaults to opaque white).
   *   font = Optional font instance (null for the default font).
   */
  void drawTextWithFont(
    string text,
    PointF pos,
    ColorF color,
    Font font
  ) {
    Font f = font !is null ? font : defaultFont();
    if (f is null || text.length == 0 || textCache is null) {
      return;
    }

    drawTextRun(textCache.runFor(f, text, 0), pos, color);
  }

  /**
   * Draws text at a specified position resolving the font by size and name.
   *
   * The font instance is retrieved or lazily created on demand via font.
   *
   * Params:
   *   text = Text string to render.
   *   pos = Top-left position in logical coordinates.
   *   color = Text color.
   *   ptSize = Logical point size in user space.
   *   fontName = Registered font name, or null/empty for default font.
   */
  void drawTextWithFontName(
    string text,
    PointF pos,
    ColorF color,
    float ptSize,
    string fontName
  ) {
    Font f = font(ptSize, fontName);
    drawTextWithFont(text, pos, color, f);
  }

  /**
   * Measures text bounding dimensions in logical coordinates.
   *
   * If font is null, the managed default font (created lazily on demand)
   * is used. Returned dimensions are scaled to user logical units.
   *
   * Params:
   *   text = Text string to measure.
   *   font = Optional font instance (null uses default font).
   * Returns: Dimensions of the measured text in logical units.
   */
  PointF measureTextWithFont(string text, Font font) {
    Font f = font !is null ? font : defaultFont();
    if (f is null || text.length == 0) {
      return PointF(0.0f, 0.0f);
    }
    return logicFromPixelsPoint(f.measureText(text));
  }

  /**
   * Measures text bounding dimensions resolving the font by size and name.
   *
   * The font instance is retrieved or lazily created on demand via font.
   * Returned dimensions are scaled to user logical units.
   *
   * Params:
   *   text = Text string to measure.
   *   ptSize = Logical point size in user space.
   *   fontName = Registered font name, or null/empty for default font.
   * Returns: Dimensions of the measured text in logical units.
   */
  PointF measureTextWithFontName(
    string text,
    float ptSize,
    string fontName
  ) {
    Font f = font(ptSize, fontName);
    return measureTextWithFont(text, f);
  }

package(yguilib):
  /**
   * Sets the GL clear color and tracks it (saved and restored around
   * render target and shadow passes without GL queries). All clear color
   * changes on this renderer's context must go through it. Values are
   * clamped to [0, 1] as GL does.
   */
  void clearColor(ColorF color) {
    import std.algorithm.comparison : clamp;

    fClearColor = [clamp(color.r, 0.0f, 1.0f), clamp(color.g, 0.0f, 1.0f),
      clamp(color.b, 0.0f, 1.0f), clamp(color.a, 0.0f, 1.0f)];
    glClearColor(fClearColor[0], fClearColor[1], fClearColor[2],
      fClearColor[3]);
  }

  version (unittest) {
    TextBatchStats textBatchStats() const {
      return fTextBatch.stats();
    }

    void resetTextBatchStats() {
      fTextBatch.resetStats();
    }
  }

package(yguilib.render):
  /// Tracked GL framebuffer currently bound for rendering.
  GLuint currentFramebuffer() const {
    return fFramebuffer;
  }

  void drawTexture(GLuint texId, RectF destRect, ColorF color) {
    if (!initialized) {
      return;
    }
    flush();
    // a whole straight-alpha texture stretched to destRect
    texPipeline.drawTexturedQuad(
      texId, TexturedQuad(destRect, RectF(0, 0, 1, 1), color),
      logicViewport(), TextureMode.straight
    );
  }

  version (unittest) {
    FontManager fontManagerRef() {
      return fontManager;
    }

    TextRunCache textCacheRef() {
      return textCache;
    }

    int maxTargetSizeForTest() {
      return maxTargetSize();
    }
  }

  /**
   * The current framebuffer, viewport, scissor and clear color from the
   * tracked state (no GL queries; debug builds check it against GL). The
   * scissor is enabled exactly while the clip stack is not empty.
   */
  SavedTargetState targetState() const {
    SavedTargetState s;
    s.framebuffer = cast(GLint)fFramebuffer;
    s.viewport = fViewport;
    s.scissorEnabled = !clipStack.isEmpty();
    s.scissorBox = clipStack.appliedBox();
    s.clearColor = fClearColor;
    debug assert(s.sameStateAs(SavedTargetState.capture()),
      "tracked GL target state differs from GL");
    return s;
  }

  /**
   * Clears the GL pixel box `box` (`[x, y, w, h]`, bottom-left origin) of
   * the bound framebuffer to transparent black, color only, within the
   * clip stack scissor. The scissor and the clear color are restored.
   */
  void clearPixelBox(in int[4] box) {
    flush();
    glClearColor(0, 0, 0, 0);
    clipStack.clearBox(box, GL_COLOR_BUFFER_BIT);
    glClearColor(fClearColor[0], fClearColor[1], fClearColor[2],
      fClearColor[3]);
  }

  /// Appends a glyph quad to the shared text batch, flushing on state change.
  void queueTextQuad(GLuint texId, bool stencilClip, in TextVertex[4] quad) {
    if (!initialized || texId == 0) {
      return;
    }
    if (fTextBatch.needsFlushFor(texId, stencilClip)) {
      flush();
    }
    fTextBatch.pushQuad(texId, stencilClip, quad);
  }

  /// Logic viewport size and total scaling for the pipeline draws.
  Viewport logicViewport() const {
    return Viewport(logicWidth(), logicHeight(), totalScaling());
  }

  /// True while a clip rect is pushed (the GL scissor test is on).
  bool scissorEnabled() const {
    return !clipStack.isEmpty();
  }

  /**
   * Visible area in logic units: the innermost clip rect intersected with
   * the viewport, or the whole viewport without a clip rect.
   */
  RectF scissorLogicRect() const {
    const RectF vp = RectF(0, 0, logicWidth(), logicHeight());
    if (clipStack.isEmpty()) {
      return vp;
    }
    return intersectRects(vp, clipStack.top());
  }

  /// Renderer program tracker (tests of the uniform caches).
  ref ProgramTracker programTrackerRef() return {
    return fPrograms;
  }

  /**
   * Font resolved by size and name rasterized at `rasterScale` (quantized
   * to 1/8 steps, see `FontManager.fontAtScale`); null when not
   * initialized. Used by `Canvas` text.
   */
  Font fontAtScale(float ptSize, string fontName, float rasterScale) {
    if (fontManager is null) {
      return null;
    }
    return fontManager.fontAtScale(ptSize, fontName, rasterScale);
  }

  /**
   * Cached glyph run of `text` (null when none), valid until the next
   * `textRunFor` call; its slots sample `glyphAtlasTexture()`.
   */
  const(TextRun)* textRunFor(Font f, string text, int outlinePx) {
    if (textCache is null) {
      return null;
    }
    return textCache.runFor(f, text, outlinePx);
  }

  /// The glyph atlas texture (0 before the first glyph).
  GLuint glyphAtlasTexture() const {
    return textCache is null ? 0 : textCache.atlasTexture();
  }

  /// Glyph atlas width and height in pixels (0 before initialization).
  int glyphAtlasSize() const {
    return textCache is null ? 0 : textCache.atlasSize();
  }

  /// Shared flat color pipeline (used by `Canvas`).
  ref ColorPipeline colorPipelineRef() return {
    flush();
    return colorPipeline;
  }

  /// Shared gradient paint pipeline (used by `Canvas`).
  ref GradientPipeline gradientPipelineRef() return {
    flush();
    return gradientPipeline;
  }

  /// Shared image pattern paint pipeline (used by `Canvas`).
  ref PatternPipeline patternPipelineRef() return {
    flush();
    return patternPipeline;
  }

  /// Shared textured quad pipeline (Canvas shadow composite).
  ref TexturePipeline texturePipelineRef() return {
    flush();
    return texPipeline;
  }

  /**
   * Normalized uv rect of the `srcPx` region (texture pixels, top-left
   * origin as displayed) of `t` (valid, non-empty), such that the
   * top-left of a quad gets `uv.x, uv.y`. For bottom-up textures (GL
   * rows grow upward) v is flipped: `uv.y` is the top edge measured from
   * the bottom and `uv.height` is negative.
   */
  static RectF textureUv(in Texture t, in RectF srcPx) {
    assert(t !is null && t.width() > 0 && t.height() > 0);
    const float tw = cast(float)t.width();
    const float th = cast(float)t.height();
    const RectF uv = RectF(
      srcPx.x / tw, srcPx.y / th, srcPx.width / tw, srcPx.height / th
    );
    if (!t.bottomUp()) {
      return uv;
    }
    return RectF(uv.x, 1.0f - uv.y, uv.width, -uv.height);
  }

  /// Shared separable blur pipeline (Canvas shadows).
  ref BlurPipeline blurPipelineRef() return {
    flush();
    return blurPipeline;
  }

  /**
   * Ping-pong offscreen target `index` (0 or 1) used by Canvas shadows;
   * allocated on first `ensureSize`, destroyed in `destroy()`.
   */
  ref OffscreenTarget offscreenTargetRef(size_t index) return {
    return offscreenTargets[index];
  }

  /// True between successful initialization and `destroy()`.
  bool isInitialized() const {
    return initialized;
  }

  version (assert) {
    /**
     * True if `t` is the texture of a target on the `beginTarget` stack
     * (drawing it would be a feedback loop). Only for asserts: callers
     * wrap it in `version (assert)`, so release builds skip the walk.
     */
    bool isActiveTargetTexture(in Texture t) const {
      if (t is null || !t.isValid()) {
        return false;
      }
      foreach (ref f; targetFrames[0 .. fTargetDepth]) {
        if (f.target.textureId() == t.id()) {
          return true;
        }
      }
      return false;
    }
  }

private:
  void initialize() {
    if (initialized) {
      return;
    }

    colorPipeline.initialize(&fPrograms);
    texPipeline.initialize(&fPrograms);
    textPipeline.initialize(&fPrograms);
    rrPipeline.initialize(&fPrograms);
    gradientPipeline.initialize(&fPrograms);
    patternPipeline.initialize(&fPrograms);
    blurPipeline.initialize(&fPrograms);
    import std.algorithm.comparison : min;

    textCache = new TextRunCache(
      TextRunCache.maxCacheEntries, 512, min(4096, maxTextureSize())
    );
    textCache.onBeforeAtlasReset(&flush);
    fontManager = new FontManager();
    fontManager.onFontDestroyed(&onFontDestroyed);
    fCanvas = new Canvas(this);
    fMaxTargetSize = queryMaxTargetSize();
    fMaxSamples = queryMaxSamples();

    initialized = true;
  }

  /// Drops the text runs of a font the font manager is destroying.
  void onFontDestroyed(ulong fontId) {
    flush();
    if (textCache !is null) {
      textCache.removeFont(fontId);
    }
  }

  /// Draws `run` (null allowed) at `pos` as batched glyph quads.
  void drawTextRun(const(TextRun)* run, PointF pos, ColorF color) {
    if (run is null || !initialized) {
      return;
    }
    const GLuint atlasTex = glyphAtlasTexture();
    const int atlasSz = glyphAtlasSize();
    if (atlasTex == 0 || atlasSz <= 0) {
      return;
    }
    import std.math : round;

    const float screenX = round(pixelsFromLogicFloat(pos.x));
    const float screenY = round(pixelsFromLogicFloat(pos.y));
    const float invAtlas = 1.0f / atlasSz;
    const float scale = totalScaling();
    const float invScale = scale > 0.0f ? 1.0f / scale : 1.0f;
    const ubyte[4] packed = packTextColor(color);
    if (fTextBatch.needsFlushFor(atlasTex, false)
        || fTextBatch.remaining() < run.glyphs.length) {
      flush();
    }
    fTextBatch.beginRun(atlasTex, false);
    foreach (ref g; run.glyphs) {
      if (g.slot.w <= 0) {
        continue;
      }
      if (fTextBatch.remaining() == 0) {
        flush();
        fTextBatch.beginRun(atlasTex, false);
      }
      const float x0 = (screenX + g.dx) * invScale;
      const float y0 = (screenY + g.dy) * invScale;
      const float x1 = (screenX + g.dx + g.dw) * invScale;
      const float y1 = (screenY + g.dy + g.dh) * invScale;
      const float u0 = (g.slot.x + g.srcX) * invAtlas;
      const float v0 = (g.slot.y + g.srcY) * invAtlas;
      const float u1 = (g.slot.x + g.srcX + g.srcW) * invAtlas;
      const float v1 = (g.slot.y + g.srcY + g.srcH) * invAtlas;
      const TextVertex[4] quad = [
        TextVertex(x0, y0, u0, v0, packed),
        TextVertex(x1, y0, u1, v0, packed),
        TextVertex(x0, y1, u0, v1, packed),
        TextVertex(x1, y1, u1, v1, packed),
      ];
      fTextBatch.appendQuad(quad);
    }
  }

  /// State saved by `beginTarget` and restored by `endTarget`.
  struct TargetFrame {
    RenderTarget target;
    SavedTargetState saved;
    int pixelWidth;
    int pixelHeight;
    ClipStack clips;
    Canvas.FrameState canvasState;
  }

  /// Largest render-target dimension supported by the GL context.
  int maxTargetSize() {
    if (fMaxTargetSize <= 0) {
      fMaxTargetSize = queryMaxTargetSize();
    }
    return fMaxTargetSize;
  }

  static int queryMaxTargetSize() {
    GLint maxTex = 0;
    GLint maxRb = 0;
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTex);
    glGetIntegerv(GL_MAX_RENDERBUFFER_SIZE, &maxRb);
    const int m = maxTex < maxRb ? maxTex : maxRb;
    return m > 0 ? m : int.max;
  }

  static int queryMaxSamples() {
    GLint n = 0;
    glGetIntegerv(GL_MAX_SAMPLES, &n);
    return n >= 0 ? n : 0;
  }

  /**
   * Target pixels for `logic` units: max(1, ceil(logic * scaling)), or
   * 0 when `logic` is non-finite, non-positive, or exceeds `maxTargetSize`.
   */
  int targetPixelsFromLogic(float logic) {
    import std.math : ceil, isFinite;

    if (!isFinite(logic) || logic <= 0.0f) {
      return 0;
    }
    const double px = ceil(cast(double)logic * cast(double)totalScaling());
    const int limit = maxTargetSize();
    if (!isFinite(px) || px > cast(double)limit) {
      return 0;
    }
    return px < 1.0 ? 1 : cast(int)px;
  }

  /// min(4, GL_MAX_SAMPLES), or 0 when fewer than 2 are supported.
  int targetSampleCount() {
    if (fMaxSamples < 0) {
      fMaxSamples = queryMaxSamples();
    }
    const int n = fMaxSamples < 4 ? fMaxSamples : 4;
    return n >= 2 ? n : 0;
  }

  /**
   * Rescales the managed fonts and the default font (owned or user
   * assigned, resized in place like the managed ones), drops the text
   * cache and re-applies the clip stack scissor, whose rects are in logic
   * units. The scissor is only touched while a clip rect is pushed (that
   * is mid-frame, with this renderer's context current).
   */
  void onScalingChanged() {
    flush();
    const float totalScale = totalScaling();
    if (fontManager !is null) {
      fontManager.scaling(totalScale);
    }
    if (fDefaultFont !is null) {
      // a user font has no known source to re-create it from: resize the
      // handle in place, as FontManager.scaling does
      fDefaultFont.scale(totalScale);
    }
    clearTextCache();
    fPrograms.invalidate();
    if (initialized && !clipStack.isEmpty()) {
      clipStack.reapply(
        viewportPixelWidth, viewportPixelHeight, totalScale
      );
    }
  }

  int viewportPixelWidth;
  int viewportPixelHeight;
  float fDisplayScaling = 1.0f;
  float fUnitsScaling = 1.0f;

  ColorPipeline colorPipeline;
  TexturePipeline texPipeline;
  TextPipeline textPipeline;
  RoundRectPipeline rrPipeline;
  GradientPipeline gradientPipeline;
  PatternPipeline patternPipeline;
  BlurPipeline blurPipeline;
  /// Current program; the pipelines hold a pointer to it.
  ProgramTracker fPrograms;
  /**
   * Tracked target state (set by the renderer, never read back from GL):
   * bound framebuffer, viewport and clear color. The scissor state is
   * owned by `clipStack` (see `targetState`).
   */
  GLuint fFramebuffer;
  GLint[4] fViewport;
  GLfloat[4] fClearColor;
  OffscreenTarget[2] offscreenTargets;
  ClipStack clipStack;
  /**
   * `beginTarget` slots indexed by depth (innermost last); the first
   * `fTargetDepth` are active, the rest are kept for reuse. Grown on
   * demand; never copy a slot (its buffers would be shared).
   */
  TargetFrame[] targetFrames;
  size_t fTargetDepth;
  TextRunCache textCache;
  TextBatch fTextBatch;
  FontManager fontManager;
  Font fDefaultFont;
  int fMaxTargetSize;
  int fMaxSamples = -1;
  bool initialized;
  Canvas fCanvas;
}

// Verifies isOnScreen viewport culling helper.
unittest {
  const float vw = 640.0f;
  const float vh = 480.0f;

  // Fully inside
  assert(Renderer.isOnScreenWithViewport(RectF(10, 10, 100, 100), vw, vh));

  // Intersecting edges
  assert(Renderer.isOnScreenWithViewport(RectF(-50, 10, 100, 100), vw, vh));
  assert(Renderer.isOnScreenWithViewport(RectF(10, -50, 100, 100), vw, vh));
  assert(Renderer.isOnScreenWithViewport(RectF(600, 10, 100, 100), vw, vh));
  assert(Renderer.isOnScreenWithViewport(RectF(10, 450, 100, 100), vw, vh));

  // Fully outside
  assert(!Renderer.isOnScreenWithViewport(RectF(-150, 10, 100, 100), vw, vh));
  assert(!Renderer.isOnScreenWithViewport(RectF(10, -150, 100, 100), vw, vh));
  assert(!Renderer.isOnScreenWithViewport(RectF(700, 10, 100, 100), vw, vh));
  assert(!Renderer.isOnScreenWithViewport(RectF(10, 500, 100, 100), vw, vh));

  // Zero or negative size
  assert(!Renderer.isOnScreenWithViewport(RectF(10, 10, 0, 100), vw, vh));
  assert(!Renderer.isOnScreenWithViewport(RectF(10, 10, 100, 0), vw, vh));
  assert(!Renderer.isOnScreenWithViewport(RectF(10, 10, -10, 100), vw, vh));
}
