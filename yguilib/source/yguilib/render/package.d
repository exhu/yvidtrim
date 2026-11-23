module yguilib.render;

import glad2.gles2;
import yguilib.events : AppEvent;
import yguilib.render.internal.clip_stack : ClipStack;
import yguilib.render.font : Font, defaultFontPtSize;
import yguilib.render.font_manager : FontManager;
import yguilib.render.image : Image;
import yguilib.render.internal.offscreen : OffscreenTarget,
  SavedTargetState;
import yguilib.render.internal.pipelines : BlurPipeline, ColorPipeline,
  GradientPipeline, PatternPipeline, RoundRectPipeline, TextureMode,
  TexturePipeline, TexturedQuad;
import yguilib.render.internal.text_cache : TextCache, TextTexture;
import yguilib.render.render_types;
import yguilib.render.render_target : RenderTarget;
import yguilib.render.texture : Texture;
import yguilib.assets : defaultTtfFontData;
import yguilib.render.canvas : Canvas;

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
    initialize();
  }

  Canvas canvas() {
    return fCanvas;
  }

  void destroy() {
    if (!initialized) {
      return;
    }

    clearTextCache();
    if (fontManager !is null) {
      fontManager.destroy();
      fontManager = null;
    }
    if (fOwnsDefaultFont && fDefaultFont !is null) {
      fDefaultFont.destroy();
      fDefaultFont = null;
    }
    foreach (ref t; offscreenTargets) {
      t.destroy();
    }
    // User render targets are caller owned: only forget the stack.
    foreach (ref f; targetFrames) {
      f.target.active--;
    }
    targetFrames = null;
    blurPipeline.destroy();
    patternPipeline.destroy();
    gradientPipeline.destroy();
    rrPipeline.destroy();
    texPipeline.destroy();
    colorPipeline.destroy();
    clipStack.clear();
    initialized = false;
  }

  ~this() {
    destroy();
  }

  void viewport(int pixelWidth, int pixelHeight) {
    viewportPixelWidth = pixelWidth;
    viewportPixelHeight = pixelHeight;
    glViewport(0, 0, pixelWidth, pixelHeight);
  }

  /**
   * Sets the additional scaling factor above displayScaling (e.g. to support
   * zooming in/out UI for user preferences). Defaults to 1.0.
   */
  void unitsScaling(float scaling) {
    float newScale = scaling > 0.0f ? scaling : 1.0f;
    if (newScale != fUnitsScaling) {
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
    float newScale = scaling > 0.0f ? scaling : 1.0f;
    if (newScale != fDisplayScaling) {
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

  PointF coordinatesFromEvent(in AppEvent event) const {
    return coordinatesFromCoords(event.mouse.x, event.mouse.y);
  }

  PointF coordinatesFromCoords(float x, float y) const {
    const float factor = fUnitsScaling > 0.0f ? (1.0f / fUnitsScaling) : 1.0f;
    return PointF(x * factor, y * factor);
  }

  PointF coordinatesFromPoint(in PointF point) const {
    return coordinatesFromCoords(point.x, point.y);
  }

  /**
   * Starts a frame: clears color to `color` and the stencil to 0 (both
   * honor the active scissor clip) and resets the Canvas state.
   * Inside `beginTarget` it clears the target; `color` is stored as-is,
   * so it should be premultiplied (target textures are premultiplied).
   */
  void clearFrame(ColorF color) {
    glClearColor(color.r, color.g, color.b, color.a);
    glStencilMask(0xFF);
    glClearStencil(0);
    glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
    if (fCanvas !is null) {
      fCanvas.resetFrame();
    }
  }

  void drawFillRect(RectF rect, ColorF color) {
    if (!initialized) {
      return;
    }
    colorPipeline.drawFillRect(
      rect,
      color,
      logicWidth(),
      logicHeight()
    );
  }

  /**
   * Draws a 1-pixel line connecting two points.
   *
   * @param point1 Start point in logic-space units.
   * @param point2 End point in logic-space units.
   * @param color Line color.
   */
  void drawThinLineWithPoints(PointF point1, PointF point2, ColorF color) {
    if (!initialized) {
      return;
    }
    colorPipeline.drawThinLineWithPoints(
      point1,
      point2,
      color,
      logicWidth(),
      logicHeight()
    );
  }

  /**
   * Draws a line with configurable thickness.
   *
   * @param point1 Start point in logic-space units.
   * @param point2 End point in logic-space units.
   * @param lineWidth Line thickness in logic-space units.
   * @param color Line color.
   */
  void drawLineWithPoints(
    PointF point1,
    PointF point2,
    float lineWidth,
    ColorF color
  ) {
    drawLineDashed(point1, point2, lineWidth, 0.0f, 0.0f, color);
  }

  /**
   * Draws a dashed line with configurable thickness and dash pattern.
   *
   * @param point1 Start point in logic-space units.
   * @param point2 End point in logic-space units.
   * @param lineWidth Line thickness in logic-space units.
   * @param dashLen Length of each visible dash segment.
   * @param gapLen Length of each gap between dashes.
   * @param color Line color.
   */
  void drawLineDashed(
    PointF point1,
    PointF point2,
    float lineWidth,
    float dashLen,
    float gapLen,
    ColorF color
  ) {
    if (!initialized) {
      return;
    }
    colorPipeline.drawDashedLineWithPoints(
      point1,
      point2,
      lineWidth,
      dashLen,
      gapLen,
      color,
      logicWidth(),
      logicHeight()
    );
  }

  /**
   * Draws a rectangle outline with configurable line width.
   *
   * @param rect Bounding rectangle in logic-space units.
   * @param lineWidth Outline thickness in logic-space units.
   * lineWidth grows inside, i.e. rect is always outer boundary.
   * @param color Outline color.
   */
  void drawRectWithWidth(RectF rect, float lineWidth, ColorF color) {
    if (!initialized) {
      return;
    }
    colorPipeline.drawRectWithWidth(
      rect,
      lineWidth,
      color,
      logicWidth(),
      logicHeight()
    );
  }

  /**
   * Draws a rectangle outline with default line width (1.0).
   *
   * @param rect Bounding rectangle in logic-space units.
   * @param color Outline color.
   */
  void drawRect(RectF rect, ColorF color) {
    drawRectWithWidth(rect, 1.0f, color);
  }

  /**
   * Draws a dashed rectangle outline with configurable line
   * width and dash pattern.
   *
   * @param rect Bounding rectangle in logic-space units.
   * @param lineWidth Outline thickness in logic-space units.
   * lineWidth grows inside, i.e. rect is always outer boundary.
   * @param dashLen Length of each visible dash segment.
   * @param gapLen Length of each gap between dashes.
   * @param color Outline color.
   */
  void drawRectDashed(
    RectF rect,
    float lineWidth,
    float dashLen,
    float gapLen,
    ColorF color
  ) {
    if (!initialized) {
      return;
    }
    rrPipeline.draw(
      rect,
      0.0f,
      lineWidth,
      dashLen,
      gapLen,
      color,
      logicWidth(),
      logicHeight(),
      totalScaling()
    );
  }

  /**
   * Draws a filled rounded rectangle with anti-aliased corners.
   *
   * @param rect Bounding rectangle in logic-space units.
   * @param radius Corner radius (clamped to half the smallest dimension).
   * @param color Fill color.
   */
  void drawFillRoundRect(RectF rect, float radius, ColorF color) {
    if (!initialized) {
      return;
    }
    rrPipeline.draw(
      rect,
      radius,
      0.0f,
      0.0f,
      0.0f,
      color,
      logicWidth(),
      logicHeight(),
      totalScaling()
    );
  }

  /**
   * Draws a rounded rectangle outline with configurable line width
   * and anti-aliased corners.
   *
   * @param rect Bounding rectangle in logic-space units.
   * @param radius Corner radius (clamped to half the smallest dimension).
   * @param lineWidth Outline thickness in logic-space units.
   * lineWidth grows inside, i.e. rect is always outer boundary.
   * @param color Outline color.
   */
  void drawRoundRect(
    RectF rect,
    float radius,
    float lineWidth,
    ColorF color
  ) {
    if (!initialized) {
      return;
    }
    rrPipeline.draw(
      rect,
      radius,
      lineWidth,
      0.0f,
      0.0f,
      color,
      logicWidth(),
      logicHeight(),
      totalScaling()
    );
  }

  /**
   * Draws a dashed rounded rectangle outline with configurable line
   * width and dash pattern.
   *
   * @param rect Bounding rectangle in logic-space units.
   * @param radius Corner radius (clamped to half the smallest dimension).
   * @param lineWidth Outline thickness in logic-space units.
   * @param dashLen Length of each visible dash segment.
   * @param gapLen Length of each gap between dashes.
   * @param color Outline color.
   */
  void drawRoundRectDashed(
    RectF rect,
    float radius,
    float lineWidth,
    float dashLen,
    float gapLen,
    ColorF color
  ) {
    if (!initialized) {
      return;
    }
    rrPipeline.draw(
      rect,
      radius,
      lineWidth,
      dashLen,
      gapLen,
      color,
      logicWidth(),
      logicHeight(),
      totalScaling()
    );
  }

  void pushClipRect(RectF rect) {
    clipStack.push(
      rect,
      logicWidth(),
      logicHeight(),
      viewportPixelWidth,
      viewportPixelHeight,
      totalScaling()
    );
  }

  void popClipRect() {
    clipStack.pop(
      viewportPixelWidth,
      viewportPixelHeight,
      totalScaling()
    );
  }

  void clipRect(RectF rect) {
    clipStack.set(
      rect,
      viewportPixelWidth,
      viewportPixelHeight,
      totalScaling()
    );
  }

  void resetClipRect() {
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
   * @param ptSize Logical point size in user space (defaults to 11.0f).
   * @param fontName Registered font name, or null/empty for default font.
   * @return A cached Font instance, or null if FontManager is not initialized.
   */
  Font font(float ptSize, string fontName) {
    if (fontManager !is null) {
      return fontManager.getFont(ptSize, fontName, totalScaling());
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
   * @return The default Font instance.
   */
  Font defaultFont() {
    if (fDefaultFont !is null) {
      return fDefaultFont;
    }
    return font(defaultFontPtSize, null);
  }

  /**
   * Registers a custom font face from in-memory TTF binary data.
   *
   * Registered fonts can subsequently be resolved by name in font,
   * measureText, and drawText.
   *
   * @param fontName Unique name identifying the font face.
   * @param fontData In-memory TTF data buffer.
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
   * @param fontName Unique name identifying the font face.
   * @param filePath Path to the TTF font file.
   */
  void registerFontFromFile(string fontName, string filePath) {
    if (fontManager !is null) {
      fontManager.registerFontFromFile(fontName, filePath);
    }
  }

  /**
   * Checks whether a font face is registered or is the built-in default font.
   *
   * @param fontName Name of the font face to check.
   * @return true if the font face exists or is default, false otherwise.
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
   * @param fontData TTF binary data in memory.
   * @param ptSize Unscaled logical point size in user space.
   * @return A newly allocated Font instance.
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
   * @param filePath Path to the TTF font file.
   * @param ptSize Unscaled logical point size in user space.
   * @return A newly allocated Font instance.
   */
  Font createFontFromFile(string filePath, float ptSize) {
    return Font.fromFile(filePath, ptSize, totalScaling());
  }

  void defaultFont(Font font) {
    if (fOwnsDefaultFont && fDefaultFont !is null) {
      fDefaultFont.destroy();
    }
    fDefaultFont = font;
    fOwnsDefaultFont = false;
  }

  void clearTextCache() {
    if (textCache !is null) {
      textCache.clear();
    }
  }

  void drawTexture(GLuint texId, RectF destRect, ColorF color) {
    if (!initialized) {
      return;
    }
    texPipeline.drawTexture(
      texId,
      destRect,
      color,
      logicWidth(),
      logicHeight()
    );
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
    assert(!isActiveTargetTexture(t),
      "drawing the texture of an active render target (feedback loop)");
    const TextureMode mode = t.premultiplied()
      ? TextureMode.premultiplied : TextureMode.straight;
    texPipeline.drawTexturedQuad(
      t.id(),
      TexturedQuad(dest, textureUv(t, srcPx), tint),
      logicWidth(),
      logicHeight(),
      mode
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
    if (!initialized || !isValidTargetSize(logicW, logicH)) {
      return null;
    }
    const int pw = targetPixelsFromLogic(logicW);
    const int ph = targetPixelsFromLogic(logicH);
    const int samples = msaa ? targetSampleCount() : 0;
    auto rt = new RenderTarget(samples);
    if (rt.allocate(pw, ph)) {
      return rt;
    }
    if (samples == 0) {
      return null;
    }
    rt = new RenderTarget(0);
    return rt.allocate(pw, ph) ? rt : null;
  }

  /**
   * Resizes `rt` to `logicW` x `logicH` logic units (pixels as in
   * `createRenderTarget`). Reallocates only if the pixel size changes or
   * `rt` is invalid (e.g. destroyed); the content is undefined after a
   * reallocation and `rt.texture()` returns a new texture. A size that
   * is not finite and positive is ignored. `rt` must not be active.
   */
  void resizeRenderTarget(RenderTarget rt, float logicW, float logicH) {
    assert(rt !is null);
    assert(rt.active == 0, "resizeRenderTarget() on an active target");
    if (!initialized || !isValidTargetSize(logicW, logicH)) {
      return;
    }
    const int pw = targetPixelsFromLogic(logicW);
    const int ph = targetPixelsFromLogic(logicH);
    if (rt.isValid() && rt.pixelWidth() == pw && rt.pixelHeight() == ph) {
      return;
    }
    rt.allocate(pw, ph);
  }

  /**
   * Redirects all Renderer and Canvas drawing into `rt` (valid, not
   * already active) until the matching `endTarget()`. Targets nest. The
   * viewport becomes the target size, the clip stack and Canvas state
   * start empty (both restored by `endTarget`), the scissor is off.
   * With `clear` the color is cleared to transparent and stencil to 0.
   */
  void beginTarget(RenderTarget rt, bool clear) {
    assert(rt !is null && rt.isValid());
    assert(rt.active == 0, "render target is already active");
    TargetFrame f;
    f.target = rt;
    f.saved = SavedTargetState.capture();
    f.pixelWidth = viewportPixelWidth;
    f.pixelHeight = viewportPixelHeight;
    f.clips = clipStack;
    clipStack = ClipStack.init;
    if (fCanvas !is null) {
      f.canvasState = fCanvas.saveFrameState();
      fCanvas.resetFrame();
    }
    targetFrames ~= f;
    rt.active++;

    viewportPixelWidth = rt.pixelWidth();
    viewportPixelHeight = rt.pixelHeight();
    glBindFramebuffer(GL_FRAMEBUFFER, rt.drawFbo());
    glViewport(0, 0, viewportPixelWidth, viewportPixelHeight);
    glDisable(GL_SCISSOR_TEST);
    if (clear) {
      glClearColor(0, 0, 0, 0);
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
    assert(targetFrames.length > 0, "endTarget() without beginTarget()");
    TargetFrame f = targetFrames[$ - 1];
    targetFrames = targetFrames[0 .. $ - 1];
    targetFrames.assumeSafeAppend();
    f.target.resolve();
    f.target.active--;

    f.saved.restore();
    viewportPixelWidth = f.pixelWidth;
    viewportPixelHeight = f.pixelHeight;
    clipStack = f.clips;
    clipStack.reapply(
      viewportPixelWidth, viewportPixelHeight, totalScaling()
    );
    if (fCanvas !is null) {
      fCanvas.restoreFrameState(f.canvasState);
    }
  }

  /// True between `beginTarget` and its matching `endTarget`.
  bool inTarget() const {
    return targetFrames.length > 0;
  }

  /**
   * Draws text at a specified position using a font instance or the default
   * font.
   *
   * If font is null, the managed default font (created lazily on demand)
   * is used. Text rasterization is cached in OpenGL textures via TextCache.
   *
   * @param text Text string to render.
   * @param pos Top-left position in logical coordinates.
   * @param color Text color (defaults to opaque white).
   * @param font Optional font instance (defaults to null for default font).
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

    TextTexture tex = textCache.getOrCreate(f, text);
    if (tex.isValid()) {
      drawTextTexture(tex, pos, color);
    }
  }

  /**
   * Draws text at a specified position resolving the font by size and name.
   *
   * The font instance is retrieved or lazily created on demand via font.
   *
   * @param text Text string to render.
   * @param pos Top-left position in logical coordinates.
   * @param color Text color.
   * @param ptSize Logical point size in user space.
   * @param fontName Registered font name, or null/empty for default font.
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
   * @param text Text string to measure.
   * @param font Optional font instance (null uses default font).
   * @return Dimensions of the measured text in logical units.
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
   * @param text Text string to measure.
   * @param ptSize Logical point size in user space.
   * @param fontName Registered font name, or null/empty for default font.
   * @return Dimensions of the measured text in logical units.
   */
  PointF measureTextWithFontName(
    string text,
    float ptSize,
    string fontName
  ) {
    Font f = font(ptSize, fontName);
    return measureTextWithFont(text, f);
  }

package(yguilib.render):
  /**
   * Font resolved by size and name rasterized at `rasterScale` (quantized
   * to 1/8 steps, see `FontManager.getFontAtScale`); null when not
   * initialized. Used by `Canvas` text.
   */
  Font fontAtScale(float ptSize, string fontName, float rasterScale) {
    if (fontManager is null) {
      return null;
    }
    return fontManager.getFontAtScale(ptSize, fontName, rasterScale);
  }

  /// Cached white-on-transparent bitmap of `text` (invalid when none).
  TextTexture textTextureFor(Font f, string text, int outlinePx = 0) {
    if (textCache is null) {
      return TextTexture();
    }
    return textCache.getOrCreate(f, text, outlinePx);
  }

  /// Shared flat color pipeline (used by `Canvas`).
  ref ColorPipeline colorPipelineRef() return {
    return colorPipeline;
  }

  /// Shared gradient paint pipeline (used by `Canvas`).
  ref GradientPipeline gradientPipelineRef() return {
    return gradientPipeline;
  }

  /// Shared image pattern paint pipeline (used by `Canvas`).
  ref PatternPipeline patternPipelineRef() return {
    return patternPipeline;
  }

  /// Shared textured quad pipeline (Canvas shadow composite).
  ref TexturePipeline texturePipelineRef() return {
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

  /**
   * True if `t` is the texture of a target on the `beginTarget` stack
   * (drawing it would be a feedback loop).
   */
  bool isActiveTargetTexture(in Texture t) const {
    if (t is null || !t.isValid()) {
      return false;
    }
    foreach (ref f; targetFrames) {
      if (f.target.textureId() == t.id()) {
        return true;
      }
    }
    return false;
  }

private:
  void initialize() {
    if (initialized) {
      return;
    }

    colorPipeline.initialize();
    texPipeline.initialize();
    rrPipeline.initialize();
    gradientPipeline.initialize();
    patternPipeline.initialize();
    blurPipeline.initialize();
    textCache = new TextCache(TextCache.maxCacheEntries);
    fontManager = new FontManager();
    fCanvas = new Canvas(this);

    initialized = true;
  }

  TextTexture createTextTexture(Font font, string text) {
    if (!initialized) {
      return TextTexture();
    }
    return TextCache.createTextTexture(font, text);
  }

  void drawTextTexture(
    in TextTexture tex,
    PointF pos,
    ColorF color
  ) {
    if (!tex.isValid()) {
      return;
    }
    import std.math : round;

    const float screenX = round(pixelsFromLogicFloat(pos.x));
    const float screenY = round(pixelsFromLogicFloat(pos.y));
    const float screenW = cast(float)tex.width;
    const float screenH = cast(float)tex.height;

    const float logicX0 = logicFromPixelsFloat(screenX);
    const float logicY0 = logicFromPixelsFloat(screenY);
    const float logicX1 = logicFromPixelsFloat(screenX + screenW);
    const float logicY1 = logicFromPixelsFloat(screenY + screenH);

    drawTexture(
      tex.textureId,
      RectF(
        logicX0,
        logicY0,
        logicX1 - logicX0,
        logicY1 - logicY0
      ),
      color
    );
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

  static bool isValidTargetSize(float logicW, float logicH) {
    import std.math : isFinite;

    return isFinite(logicW) && isFinite(logicH)
      && logicW > 0.0f && logicH > 0.0f;
  }

  /// Target pixels for `logic` units: max(1, ceil(logic * scaling)).
  int targetPixelsFromLogic(float logic) const {
    import std.math : ceil;

    const float px = ceil(logic * totalScaling());
    return px < 1.0f ? 1 : cast(int)px;
  }

  /// min(4, GL_MAX_SAMPLES), or 0 when fewer than 2 are supported.
  static int targetSampleCount() {
    GLint maxSamples = 0;
    glGetIntegerv(GL_MAX_SAMPLES, &maxSamples);
    const int n = maxSamples < 4 ? maxSamples : 4;
    return n >= 2 ? n : 0;
  }

  void onScalingChanged() {
    float totalScale = totalScaling();
    if (fontManager !is null) {
      fontManager.setScaling(totalScale);
    }
    if (fOwnsDefaultFont && fDefaultFont !is null) {
      fDefaultFont.setScale(totalScale);
    } else if (fDefaultFont !is null) {
      defaultFont(null);
    }
    clearTextCache();
  }

  int viewportPixelWidth;
  int viewportPixelHeight;
  float fDisplayScaling = 1.0f;
  float fUnitsScaling = 1.0f;

  ColorPipeline colorPipeline;
  TexturePipeline texPipeline;
  RoundRectPipeline rrPipeline;
  GradientPipeline gradientPipeline;
  PatternPipeline patternPipeline;
  BlurPipeline blurPipeline;
  OffscreenTarget[2] offscreenTargets;
  ClipStack clipStack;
  /// `beginTarget` stack (innermost last).
  TargetFrame[] targetFrames;
  TextCache textCache;
  FontManager fontManager;
  Font fDefaultFont;
  bool fOwnsDefaultFont;
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

unittest {
  import yguilib.render.internal.gl_test_util : GlTestWindow;

  auto w = GlTestWindow("test_renderer");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto win = w.window();

  auto renderer = w.renderer();
  assert(renderer !is null);

  assert(renderer.viewportWidth() == 320);
  assert(renderer.viewportHeight() == 240);
  assert(renderer.isOnScreen(RectF(10, 10, 100, 100)));
  assert(!renderer.isOnScreen(RectF(700, 10, 100, 100)));

  // 1. Clear canvas red
  renderer.clearFrame(ColorF(1.0f, 0.0f, 0.0f, 1.0f));
  ubyte[4] pixel;
  // Center pixel (160, 120)
  glReadPixels(160, 120, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 255 && pixel[1] == 0 && pixel[2] == 0 && pixel[3] == 255);

  // 2. Draw filled rect green at (10, 10, 30, 30)
  renderer.drawFillRect(RectF(10, 10, 30, 30), ColorF(0.0f, 1.0f, 0.0f, 1.0f));
  // Inside rect: screen (20, 20) -> GL y = 240 - 20 = 220
  glReadPixels(20, 220, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0 && pixel[1] == 255 && pixel[2] == 0 && pixel[3] == 255);
  // Outside rect: screen (100, 100) -> GL y = 240 - 100 = 140
  glReadPixels(100, 140, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 255 && pixel[1] == 0 && pixel[2] == 0 && pixel[3] == 255);

  // 3. Alpha blending: draw 50% white over black canvas
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawFillRect(
    RectF(0, 0, 320, 240),
    ColorF(1.0f, 1.0f, 1.0f, 0.5f)
  );
  glReadPixels(160, 120, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] >= 126 && pixel[0] <= 129);
  assert(pixel[1] >= 126 && pixel[1] <= 129);
  assert(pixel[2] >= 126 && pixel[2] <= 129);

  // 4. Clipping rectangle
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.pushClipRect(RectF(50, 50, 50, 50));
  renderer.drawFillRect(
    RectF(0, 0, 320, 240),
    ColorF(0.0f, 0.0f, 1.0f, 1.0f)
  );
  renderer.popClipRect();

  // Inside clip rect: screen (60, 60) -> GL y = 240 - 60 = 180 (blue)
  glReadPixels(60, 180, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 255 && pixel[3] == 255);
  // Outside clip rect: screen (10, 10) -> GL y = 240 - 10 = 230 (black)
  glReadPixels(10, 230, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0 && pixel[3] == 255);

  // 5. Draw line and outline rect
  renderer.drawThinLineWithPoints(
    PointF(0.0f, 0.0f),
    PointF(319.0f, 239.0f),
    ColorF(1.0f, 1.0f, 0.0f, 1.0f)
  );
  renderer.drawRect(
    RectF(150, 100, 40, 40),
    ColorF(0.0f, 1.0f, 1.0f, 1.0f)
  );

  assert(glGetError() == GL_NO_ERROR);

  // 6. Test units scaling and pixel conversions
  assert(renderer.defaultScaling() == 1.0f);
  assert(renderer.displayScaling() == 1.0f);
  assert(renderer.unitsScaling() == 1.0f);
  assert(renderer.pixelsFromLogicFloat(10.0f) == 10.0f);
  assert(renderer.logicFromPixelsFloat(10.0f) == 10.0f);

  renderer.unitsScaling(2.0f);
  assert(renderer.unitsScaling() == 2.0f);
  assert(renderer.pixelsFromLogicFloat(10.0f) == 20.0f);
  assert(renderer.logicFromPixelsFloat(20.0f) == 10.0f);
  assert(renderer.pixelsFromLogicFloat(15.0f) == 30.0f);
  assert(renderer.logicFromPixelsFloat(30.0f) == 15.0f);

  PointF lp = PointF(10.0f, 20.0f);
  PointF pp = renderer.pixelsFromLogicPoint(lp);
  assert(pp.x == 20.0f && pp.y == 40.0f);
  PointF backLp = renderer.logicFromPixelsPoint(pp);
  assert(backLp.x == 10.0f && backLp.y == 20.0f);

  RectF lr = RectF(5.0f, 10.0f, 50.0f, 60.0f);
  RectF pr = renderer.pixelsFromLogicRect(lr);
  assert(
    pr.x == 10.0f && pr.y == 20.0f &&
    pr.width == 100.0f && pr.height == 120.0f
  );
  RectF backLr = renderer.logicFromPixelsRect(pr);
  assert(
    backLr.x == 5.0f && backLr.y == 10.0f &&
    backLr.width == 50.0f && backLr.height == 60.0f
  );

  assert(renderer.pixelWidth() == 320);
  assert(renderer.pixelHeight() == 240);
  assert(renderer.viewportWidth() == 160);
  assert(renderer.viewportHeight() == 120);

  // Combined scaling: displayScaling = 2.0f, unitsScaling = 1.5f
  // (effective scale = 3.0f)
  renderer.displayScaling(2.0f);
  renderer.unitsScaling(1.5f);
  assert(renderer.displayScaling() == 2.0f);
  assert(renderer.unitsScaling() == 1.5f);
  assert(renderer.pixelsFromLogicFloat(10.0f) == 30.0f);
  assert(renderer.logicFromPixelsFloat(30.0f) == 10.0f);
  assert(renderer.viewportWidth() == 106);
  assert(renderer.viewportHeight() == 80);

  // 7. Test coordinatesFromEvent
  // Case A: 200% display scale, zoom = 1.0 (1:1 window points to logic)
  renderer.displayScaling(2.0f);
  renderer.unitsScaling(1.0f);
  assert(renderer.defaultScaling() == 2.0f);
  assert(renderer.unitsScaling() == 1.0f);

  AppEvent evMotion = AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(win.id, 100.0f, 50.0f)
  );
  PointF converted = renderer.coordinatesFromEvent(evMotion);
  assert(converted.x == 100.0f);
  assert(converted.y == 50.0f);

  PointF fromFloat = renderer.coordinatesFromCoords(100.0f, 50.0f);
  assert(fromFloat.x == 100.0f);
  assert(fromFloat.y == 50.0f);

  // Case B: 200% display scale, zoom = 2.0 (logic coords halved)
  renderer.unitsScaling(2.0f);
  converted = renderer.coordinatesFromEvent(evMotion);
  assert(converted.x == 50.0f);
  assert(converted.y == 25.0f);

  // Case C: 100% display scale, zoom = 0.5 (logic coords doubled)
  renderer.displayScaling(1.0f);
  renderer.unitsScaling(0.5f);
  converted = renderer.coordinatesFromEvent(evMotion);
  assert(converted.x == 200.0f);
  assert(converted.y == 100.0f);

  // 8. Scaled drawing test: unitsScaling = 2.0
  renderer.displayScaling(1.0f);
  renderer.unitsScaling(2.0f);
  // Drawing rect (0, 0, 160, 120) logic units covers all 320x240 pixels.
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawFillRect(
    RectF(0.0f, 0.0f, 160.0f, 120.0f),
    ColorF(0.0f, 1.0f, 0.0f, 1.0f)
  );
  // Center pixel (160, 120) should be green
  glReadPixels(160, 120, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0 && pixel[1] == 255 && pixel[2] == 0 && pixel[3] == 255);
  // Near top-right corner pixel (318, 238) should be green
  glReadPixels(318, 238, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0 && pixel[1] == 255 && pixel[2] == 0 && pixel[3] == 255);

  // 9. Font loading, metrics, text measurement, and rendering tests
  renderer.unitsScaling(1.0f);
  renderer.displayScaling(1.0f);

  Font customFont = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData,
    16.0f,
    1.0f
  );
  scope(exit) customFont.destroy();

  assert(customFont.size == 16.0f);
  assert(customFont.height > 0);
  assert(customFont.ascent > 0);
  assert(customFont.lineSkip > 0);

  PointF mEmpty = renderer.measureTextWithFont("", customFont);
  assert(mEmpty.x == 0.0f && mEmpty.y == 0.0f);

  PointF mShort = renderer.measureTextWithFont("Hi", customFont);
  assert(mShort.x > 0.0f && mShort.y > 0.0f);

  PointF mLong = renderer.measureTextWithFont("Hello World!", customFont);
  assert(mLong.x > mShort.x);

  PointF mBySize = renderer.measureTextWithFontName("Hi", 16.0f, null);
  assert(mBySize.x == mShort.x && mBySize.y == mShort.y);

  // Render text blended in white on black background
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawTextWithFont(
    "ABC",
    PointF(20.0f, 30.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f),
    customFont
  );

  import std.algorithm : min;

  int litCount = 0;
  int checkW = min(cast(int)mLong.x, 50);
  int checkH = min(customFont.height, 30);
  foreach (x; 20 .. 20 + checkW) {
    foreach (y; 30 .. 30 + checkH) {
      glReadPixels(x, 240 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
      if (pixel[0] > 100 && pixel[1] > 100 && pixel[2] > 100) {
        litCount++;
      }
    }
  }
  assert(litCount > 0);

  // Render text in green color
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawTextWithFont(
    "ABC",
    PointF(20.0f, 30.0f),
    ColorF(0.0f, 1.0f, 0.0f, 1.0f),
    customFont
  );
  litCount = 0;
  foreach (x; 20 .. 20 + checkW) {
    foreach (y; 30 .. 30 + checkH) {
      glReadPixels(x, 240 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
      if (pixel[1] > 100 && pixel[0] == 0 && pixel[2] == 0) {
        litCount++;
      }
    }
  }
  assert(litCount > 0);

  // Render using default font (embedded defaultTtfFontData)
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawTextWithFont(
    "DefaultFont",
    PointF(10.0f, 10.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f),
    null
  );
  assert(renderer.defaultFont() !is null);
  assert(renderer.defaultFont().height > 0);

  // Text clipped outside clip rect
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.pushClipRect(RectF(0.0f, 0.0f, 10.0f, 10.0f));
  renderer.drawTextWithFont(
    "Clipped",
    PointF(50.0f, 50.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f),
    customFont
  );
  renderer.popClipRect();

  // (50..80, 50..70) should have stayed black because it was clipped
  foreach (x; 50 .. 80) {
    foreach (y; 50 .. 70) {
      glReadPixels(x, 240 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
      assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);
    }
  }

  // Scaled text drawing test: unitsScaling = 2.0
  renderer.displayScaling(1.0f);
  renderer.unitsScaling(2.0f);
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawTextWithFont(
    "ABC",
    PointF(10.0f, 10.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f),
    null
  );
  litCount = 0;
  foreach (x; 20 .. 80) {
    foreach (y; 20 .. 60) {
      glReadPixels(x, 240 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
      if (pixel[0] > 100 && pixel[1] > 100 && pixel[2] > 100) {
        litCount++;
      }
    }
  }
  assert(litCount > 0);
  renderer.unitsScaling(1.0f);

  // Scaled text drawing test: displayScaling = 1.5
  renderer.displayScaling(1.5f);
  renderer.unitsScaling(1.0f);
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawTextWithFont(
    "ABC",
    PointF(35.0f, 45.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f),
    null
  );
  litCount = 0;
  // 35 * 1.5 = 52.5 -> snapped to 53
  // 45 * 1.5 = 67.5 -> snapped to 68
  foreach (x; 53 .. 120) {
    foreach (y; 68 .. 100) {
      glReadPixels(x, 240 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
      if (pixel[0] > 100 && pixel[1] > 100 && pixel[2] > 100) {
        litCount++;
      }
    }
  }
  assert(litCount > 0);
  renderer.displayScaling(1.0f);

  // In-place dynamic resizing & unscaled user-space size tests
  Font defaultF = renderer.defaultFont();
  assert(defaultF !is null);
  assert(defaultF.size == defaultFontPtSize);
  assert(defaultF.scaledSize == defaultFontPtSize);
  int initialH = defaultF.height;

  // Scale display: defaultFont instance is preserved and resized in place
  renderer.displayScaling(2.0f);
  assert(renderer.defaultFont() is defaultF);
  assert(defaultF.size == defaultFontPtSize);
  assert(defaultF.scaledSize == defaultFontPtSize * 2.0f);
  assert(defaultF.height > initialH);

  // Scale units: defaultFont instance is preserved and resized in place
  renderer.unitsScaling(1.5f);
  assert(renderer.defaultFont() is defaultF);
  assert(defaultF.size == defaultFontPtSize);
  assert(defaultF.scaledSize == defaultFontPtSize * 3.0f);

  renderer.displayScaling(1.0f);
  renderer.unitsScaling(1.0f);
  assert(defaultF.size == defaultFontPtSize);
  assert(defaultF.scaledSize == defaultFontPtSize);

  // Factory createFont automatically applies renderer's current scaling
  renderer.displayScaling(2.0f);
  Font factoryFont = renderer.createFontFromMemory(
    cast(const(void)[])defaultTtfFontData,
    14.0f
  );
  scope(exit) factoryFont.destroy();
  assert(factoryFont.size == 14.0f);
  assert(factoryFont.scaledSize == 28.0f);
  assert(factoryFont.height > 0);

  // In-place setScale updates raster size while preserving unscaled size
  assert(factoryFont.setScale(1.0f));
  assert(factoryFont.size == 14.0f);
  assert(factoryFont.scaledSize == 14.0f);

  // Managed fonts via font: distinct instances per size, cached on reuse
  Font f14 = renderer.font(14.0f, null);
  Font f20 = renderer.font(20.0f, null);
  assert(f14 !is null);
  assert(f20 !is null);
  assert(f14.size == 14.0f);
  assert(f20.size == 20.0f);
  assert(renderer.font(14.0f, null) is f14);
  assert(renderer.font(20.0f, null) is f20);
  assert(f14 !is f20);

  renderer.displayScaling(1.0f);
  renderer.unitsScaling(1.0f);

  assert(glGetError() == GL_NO_ERROR);

  // 10. Rounded rectangle drawing tests (fill, outline, dashed, clamping,
  // scaling)
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));

  // Test fill mode: draw green filled round rect at (20, 20, 60, 40)
  // with radius 10
  renderer.drawFillRoundRect(
    RectF(20.0f, 20.0f, 60.0f, 40.0f),
    10.0f,
    ColorF(0.0f, 1.0f, 0.0f, 1.0f)
  );
  // Center pixel (50, 40) -> GL y = 240 - 40 = 200 should be green
  glReadPixels(50, 200, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0 && pixel[1] == 255 && pixel[2] == 0 && pixel[3] == 255);
  // Outside corner pixel (21, 21) -> GL y = 240 - 21 = 219 should be black
  // (clipped by corner radius)
  glReadPixels(21, 219, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);
  // Far outside pixel (5, 5) -> GL y = 235 should be black
  glReadPixels(5, 235, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);

  // Test outline mode: draw blue outline at (100, 100, 80, 60), radius 8,
  // line width 4
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawRoundRect(
    RectF(100.0f, 100.0f, 80.0f, 60.0f),
    8.0f,
    4.0f,
    ColorF(0.0f, 0.0f, 1.0f, 1.0f)
  );
  // Center of outline rect (140, 130) -> GL y = 240 - 130 = 110 should be
  // hollow (black)
  glReadPixels(140, 110, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);
  // On top edge border: (140, 101) -> GL y = 240 - 101 = 139 should be blue
  glReadPixels(140, 139, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[2] > 100);

  // Test dashed mode: draw dashed round rect, verify border has colored pixels
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawRoundRectDashed(
    RectF(50.0f, 50.0f, 100.0f, 60.0f),
    10.0f,
    3.0f,
    8.0f,
    6.0f,
    ColorF(1.0f, 1.0f, 0.0f, 1.0f)
  );
  // Center (100, 80) -> GL y = 160 should be hollow (black)
  glReadPixels(100, 160, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);
  // Along top edge, some pixels should be yellow
  int yellowPixels = 0;
  foreach (x; 60 .. 140) {
    glReadPixels(x, 240 - 51, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
    if (pixel[0] > 100 && pixel[1] > 100) {
      yellowPixels++;
    }
  }
  assert(yellowPixels > 0);

  // Test radius clamping: radius larger than half dimensions does not crash
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawFillRoundRect(
    RectF(10.0f, 10.0f, 40.0f, 40.0f),
    100.0f, // excess radius clamped to 20
    ColorF(1.0f, 0.0f, 0.0f, 1.0f)
  );
  // Center (30, 30) -> GL y = 210 should be red
  glReadPixels(30, 210, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 255 && pixel[1] == 0 && pixel[2] == 0 && pixel[3] == 255);

  // Test units scaling with rounded rect
  renderer.unitsScaling(2.0f);
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  // Logic (10, 10, 50, 50) maps to screen (20, 20, 100, 100)
  renderer.drawFillRoundRect(
    RectF(10.0f, 10.0f, 50.0f, 50.0f),
    5.0f,
    ColorF(0.0f, 1.0f, 1.0f, 1.0f)
  );
  // Screen center of rect is (70, 70) -> GL y = 240 - 70 = 170
  glReadPixels(70, 170, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[1] == 255 && pixel[2] == 255);
  renderer.unitsScaling(1.0f);

  // 11. drawRect with lineWidth, drawRectDashed, and small drawRoundRectDashed
  // A. drawRectWithWidth with lineWidth = 4 growing inside
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawRectWithWidth(
    RectF(100.0f, 50.0f, 60.0f, 40.0f),
    4.0f,
    ColorF(0.0f, 1.0f, 0.0f, 1.0f)
  );
  // Outside rect (99, 50) -> black
  glReadPixels(99, 240 - 50, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[1] == 0);
  // Outside rect (161, 50) -> black
  glReadPixels(161, 240 - 50, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[1] == 0);
  // Top-left border inside rect: (101, 51) -> green
  glReadPixels(101, 240 - 51, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[1] == 255);
  // Center of rect (130, 70) -> hollow (black)
  glReadPixels(130, 240 - 70, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[1] == 0);

  // B. drawRectDashed: rect at (50, 50, 100, 60), lw = 3,
  // dashLen = 8, gapLen = 6
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawRectDashed(
    RectF(50.0f, 50.0f, 100.0f, 60.0f),
    3.0f,
    8.0f,
    6.0f,
    ColorF(1.0f, 1.0f, 0.0f, 1.0f)
  );
  // Center (100, 80) -> hollow (black)
  glReadPixels(100, 240 - 80, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);
  // Outside rect (48, 50) -> black
  glReadPixels(48, 240 - 50, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);
  // Top edge border has dashes and gaps
  int dashedYellow = 0;
  int dashedBlack = 0;
  foreach (x; 60 .. 140) {
    glReadPixels(x, 240 - 51, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
    if (pixel[0] > 100 && pixel[1] > 100) {
      dashedYellow++;
    } else if (pixel[0] == 0 && pixel[1] == 0) {
      dashedBlack++;
    }
  }
  assert(dashedYellow > 0 && dashedBlack > 0);

  // C. Small drawRoundRectDashed: (20, 20, 30, 20), radius 4, lw 2,
  // dash 4, gap 3
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawRoundRectDashed(
    RectF(20.0f, 20.0f, 30.0f, 20.0f),
    4.0f,
    2.0f,
    4.0f,
    3.0f,
    ColorF(0.0f, 0.0f, 1.0f, 1.0f)
  );
  // Center (35, 30) -> hollow (black)
  glReadPixels(35, 240 - 30, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[2] == 0);
  // Blue pixels present on the small rect border
  int smallBlue = 0;
  foreach (x; 20 .. 50) {
    glReadPixels(x, 240 - 21, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
    if (pixel[2] > 100) {
      smallBlue++;
    }
  }
  assert(smallBlue > 0);

  // 12. drawLine* variants: thick solid line and dashed line
  // A. Solid thick line: horizontal from (50, 100) to (150, 100), width = 6
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawLineWithPoints(
    PointF(50.0f, 100.0f),
    PointF(150.0f, 100.0f),
    6.0f,
    ColorF(1.0f, 0.0f, 0.0f, 1.0f)
  );
  // Center of line (100, 100) -> red
  glReadPixels(100, 240 - 100, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 255 && pixel[1] == 0 && pixel[2] == 0);
  // Inside thickness: (100, 98) and (100, 102) -> red
  glReadPixels(100, 240 - 98, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 255);
  glReadPixels(100, 240 - 102, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 255);
  // Outside thickness: (100, 95) and (100, 105) -> black
  glReadPixels(100, 240 - 95, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0);
  glReadPixels(100, 240 - 105, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0);
  // Beyond endpoints: (45, 100) and (155, 100) -> black
  glReadPixels(45, 240 - 100, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0);
  glReadPixels(155, 240 - 100, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0);

  // B. Dashed line: (50, 150) to (200, 150), width = 4, dash = 10, gap = 10
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawLineDashed(
    PointF(50.0f, 150.0f),
    PointF(200.0f, 150.0f),
    4.0f,
    10.0f,
    10.0f,
    ColorF(0.0f, 1.0f, 0.0f, 1.0f)
  );
  // First dash: (55, 150) -> green
  glReadPixels(55, 240 - 150, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[1] == 255);
  // First gap: (65, 150) -> black
  glReadPixels(65, 240 - 150, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[1] == 0);
  // Second dash: (75, 150) -> green
  glReadPixels(75, 240 - 150, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[1] == 255);

  // C. drawLineDashed alias
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawLineDashed(
    PointF(50.0f, 150.0f),
    PointF(200.0f, 150.0f),
    4.0f,
    10.0f,
    10.0f,
    ColorF(0.0f, 0.0f, 1.0f, 1.0f)
  );
  glReadPixels(55, 240 - 150, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[2] == 255);
  glReadPixels(65, 240 - 150, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[2] == 0);

  // D. Degenerate and zero/negative width edge cases
  renderer.drawLineWithPoints(
    PointF(10, 10), PointF(10, 10), 5.0f, ColorF(1, 1, 1, 1)
  );
  renderer.drawLineWithPoints(
    PointF(10, 10), PointF(50, 50), 0.0f, ColorF(1, 1, 1, 1)
  );
  renderer.drawLineWithPoints(
    PointF(10, 10), PointF(50, 50), -2.0f, ColorF(1, 1, 1, 1)
  );

  assert(glGetError() == GL_NO_ERROR);
}

// Verifies createTexture, drawImage, drawImageRegion, tint and update.
unittest {
  import yguilib.render.internal.gl_test_util : GlTestWindow, nearPixel,
    readAt;

  auto w = GlTestWindow("test_renderer_image");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  auto renderer = w.renderer();

  // 2x2: red, green / blue, white (top-down rows).
  auto img = new Image(2, 2);
  img.pixels[] = [
    255, 0, 0, 255,  0, 255, 0, 255,
    0, 0, 255, 255,  255, 255, 255, 255,
  ];

  assert(renderer.createTexture(null) is null);
  assert(renderer.createTexture(new Image(0, 0)) is null);
  Texture tex = renderer.createTexture(img);
  assert(tex !is null && tex.isValid());
  scope(exit) tex.destroy();
  assert(tex.width() == 2 && tex.height() == 2);

  bool near(ubyte[4] px, int r, int g, int b) {
    // Linear filtering bleeds a few levels from neighboring texels.
    return nearPixel(px, r, g, b, 8);
  }

  const ColorF opaque = ColorF(1, 1, 1, 1);

  // 1. Whole image: colors and orientation at quadrant centers.
  renderer.clearFrame(ColorF(0, 0, 0, 1));
  renderer.drawImage(tex, RectF(0, 0, 100, 100), opaque);
  assert(near(readAt(25, 25), 255, 0, 0));
  assert(near(readAt(75, 25), 0, 255, 0));
  assert(near(readAt(25, 75), 0, 0, 255));
  assert(near(readAt(75, 75), 255, 255, 255));
  // Outside dest stays black.
  assert(near(readAt(150, 150), 0, 0, 0));

  // 2. Source sub-rect: only the blue texel.
  renderer.clearFrame(ColorF(0, 0, 0, 1));
  renderer.drawImageRegion(
    tex, RectF(0, 0, 100, 100), RectF(0, 1, 1, 1), opaque
  );
  assert(near(readAt(50, 50), 0, 0, 255));
  assert(near(readAt(10, 90), 0, 0, 255));

  // 3. 50% alpha tint over black.
  renderer.clearFrame(ColorF(0, 0, 0, 1));
  renderer.drawImage(tex, RectF(0, 0, 100, 100), ColorF(1, 1, 1, 0.5f));
  assert(near(readAt(25, 25), 128, 0, 0));
  assert(near(readAt(75, 75), 128, 128, 128));

  // 4. update() re-uploads and resizes.
  auto green = new Image(1, 1);
  green.pixels[] = [0, 255, 0, 255];
  tex.update(green);
  assert(tex.width() == 1 && tex.height() == 1);
  renderer.clearFrame(ColorF(0, 0, 0, 1));
  renderer.drawImage(tex, RectF(0, 0, 100, 100), opaque);
  assert(near(readAt(25, 25), 0, 255, 0));
  assert(near(readAt(75, 75), 0, 255, 0));

  // 5. Null and destroyed textures are no-ops; destroy is idempotent.
  renderer.clearFrame(ColorF(0, 0, 0, 1));
  renderer.drawImage(null, RectF(0, 0, 100, 100), opaque);
  tex.destroy();
  tex.destroy();
  assert(!tex.isValid() && tex.width() == 0);
  renderer.drawImage(tex, RectF(0, 0, 100, 100), opaque);
  assert(near(readAt(50, 50), 0, 0, 0));

  assert(glGetError() == GL_NO_ERROR);
}

// Verifies the blend on a transparent target (alpha a, not a * a) and
// that premultiplied + bottom-up textures draw like straight ones.
unittest {
  import yguilib.render.internal.gl_test_util : GlTestWindow,
    nearPixelRgba, readAt;
  import yguilib.render.internal.gl_util : uploadRgbaTexture;
  import yguilib.render.internal.offscreen : SavedTargetState;
  import yguilib.render.texture : BorrowedTextureInfo;

  auto w = GlTestWindow("test_renderer_blend_premultiplied");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  auto renderer = w.renderer();

  bool near4(ubyte[4] px, int r, int g, int b, int a) {
    return nearPixelRgba(px, r, g, b, a, 3);
  }

  // Offscreen RGBA target cleared to transparent.
  OffscreenTarget fb;
  fb.ensureSize(320, 240);
  scope(exit) fb.destroy();
  const SavedTargetState saved = SavedTargetState.capture();
  fb.bindRegion(320, 240, true);

  // 1. Semi-transparent over transparent: premultiplied (128, 0, 0, 128).
  renderer.drawFillRect(RectF(0, 0, 50, 50), ColorF(1, 0, 0, 0.5f));
  assert(near4(readAt(25, 25), 128, 0, 0, 128));
  // Opaque results are unchanged.
  renderer.drawFillRect(RectF(60, 0, 50, 50), ColorF(0, 1, 0, 1));
  assert(near4(readAt(85, 25), 0, 255, 0, 255));
  renderer.drawFillRect(RectF(60, 0, 50, 50), ColorF(1, 0, 0, 0.5f));
  assert(near4(readAt(85, 25), 128, 128, 0, 255));
  assert(near4(readAt(200, 200), 0, 0, 0, 0));

  // 2. Straight top-down image and its premultiplied bottom-up twin.
  // 2x2: red a=128, green / blue, white a=64 (top-down rows).
  auto img = new Image(2, 2);
  img.pixels[] = [
    255, 0, 0, 128,  0, 255, 0, 255,
    0, 0, 255, 255,  255, 255, 255, 64,
  ];
  Texture straight = renderer.createTexture(img);
  scope(exit) straight.destroy();
  assert(!straight.premultiplied() && !straight.bottomUp());
  assert(!straight.borrowed());

  // Bottom row first, rgb multiplied by alpha.
  ubyte[16] pre = [
    0, 0, 255, 255,  64, 64, 64, 64,
    128, 0, 0, 128,  0, 255, 0, 255,
  ];
  BorrowedTextureInfo info;
  info.id = uploadRgbaTexture(pre.ptr, 2, 2, 8);
  info.width = 2;
  info.height = 2;
  info.premultiplied = true;
  info.bottomUp = true;
  scope(exit) glDeleteTextures(1, &info.id);
  Texture borrowed = Texture.borrowedFromInfo(info);
  scope(exit) borrowed.releaseBorrowed();

  // uv of a bottom-up texture is flipped.
  const RectF uvAll = Renderer.textureUv(borrowed, RectF(0, 0, 2, 2));
  assert(uvAll == RectF(0, 1, 1, -1));
  const RectF uvPlain = Renderer.textureUv(straight, RectF(0, 1, 1, 1));
  assert(uvPlain == RectF(0, 0.5f, 0.5f, 0.5f));

  const int[2][4] centers = [[25, 25], [75, 25], [25, 75], [75, 75]];
  void compareAt(ColorF tint, ColorF clear) {
    renderer.clearFrame(clear);
    renderer.drawImage(straight, RectF(0, 0, 100, 100), tint);
    renderer.drawImage(borrowed, RectF(100, 0, 100, 100), tint);
    foreach (c; centers) {
      const ubyte[4] a = readAt(c[0], c[1]);
      const ubyte[4] b = readAt(c[0] + 100, c[1]);
      assert(near4(b, a[0], a[1], a[2], a[3]));
    }
  }

  const ColorF opaque = ColorF(1, 1, 1, 1);
  const ColorF halfTint = ColorF(1, 0.5f, 1, 0.5f);
  compareAt(opaque, ColorF(0, 0, 0, 0));
  compareAt(halfTint, ColorF(0, 0, 0, 0));
  // Over transparent the straight red texel gives premultiplied alpha.
  compareAt(opaque, ColorF(0, 0, 0, 0));
  assert(near4(readAt(25, 25), 128, 0, 0, 128));
  compareAt(opaque, ColorF(0.2f, 0.4f, 0.6f, 1));
  compareAt(halfTint, ColorF(0.2f, 0.4f, 0.6f, 1));

  // 3. Region of a bottom-up texture uses top-left source pixels: blue.
  renderer.clearFrame(ColorF(0, 0, 0, 1));
  renderer.drawImageRegion(
    borrowed, RectF(0, 0, 100, 100), RectF(0, 1, 1, 1), opaque
  );
  assert(near4(readAt(50, 50), 0, 0, 255, 255));

  saved.restore();
  assert(glGetError() == GL_NO_ERROR);
}

// Verifies readPixels/captureFrame orientation, clamping and empty rects.
unittest {
  import yguilib.render.internal.gl_test_util : GlTestWindow;

  auto w = GlTestWindow("test_renderer_read_pixels");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  auto renderer = w.renderer();

  renderer.clearFrame(ColorF(0, 0, 0, 1));
  renderer.drawFillRect(RectF(0, 0, 10, 10), ColorF(1, 0, 0, 1));

  Image frame = renderer.captureFrame();
  assert(frame !is null);
  assert(frame.width() == 320 && frame.height() == 240);
  // Top-left pixel is red: rows are top-down.
  assert(frame.pixels[0 .. 4] == [255, 0, 0, 255]);
  // Bottom-right pixel is black.
  const size_t last = frame.pixels.length - 4;
  assert(frame.pixels[last .. last + 4] == [0, 0, 0, 255]);

  // Sub-rect straddling the red square's corner, clamped at the origin.
  Image part = renderer.readPixels(-5, -5, 20, 20);
  assert(part !is null);
  assert(part.width() == 15 && part.height() == 15);
  assert(part.pixels[0 .. 4] == [255, 0, 0, 255]);
  const size_t offs = cast(size_t)(12 * part.width() + 12) * 4;
  assert(part.pixels[offs .. offs + 4] == [0, 0, 0, 255]);

  // Rect at the bottom-right edge is clamped to the viewport.
  Image edge = renderer.readPixels(310, 230, 50, 50);
  assert(edge !is null);
  assert(edge.width() == 10 && edge.height() == 10);

  // Empty or fully outside rects give null.
  assert(renderer.readPixels(0, 0, 0, 10) is null);
  assert(renderer.readPixels(400, 0, 10, 10) is null);
  assert(renderer.readPixels(0, -20, 10, 10) is null);

  assert(glGetError() == GL_NO_ERROR);
}
