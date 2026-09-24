module yguilib.render;

import glad2.gles2;
import std.algorithm : max, min;
import yguilib.events : AppEvent;
import yguilib.render.internal.clip_stack : ClipStack;
import yguilib.render.font : Font, defaultFontPtSize;
import yguilib.render.internal.pipelines : ColorPipeline, RoundRectPipeline,
  TexturePipeline;
import yguilib.render.internal.text_cache : TextCache, TextTexture;
import yguilib.render.render_types;
import yguilib.assets : defaultTtfFontData;

final class Renderer {
  this(int width = 0, int height = 0, float displayScaling = 1.0f) {
    viewportPixelWidth = width;
    viewportPixelHeight = height;
    this.displayScaling = displayScaling > 0.0f ? displayScaling : 1.0f;
    this.unitsScaling = 1.0f;
    initialize();
  }

  private void initialize() {
    if (initialized) {
      return;
    }

    colorPipeline.initialize();
    texPipeline.initialize();
    rrPipeline.initialize();
    textCache = new TextCache();

    initialized = true;
  }

  void destroy() {
    if (!initialized) {
      return;
    }

    clearTextCache();
    if (ownsDefaultFont_ && defaultFont_ !is null) {
      defaultFont_.destroy();
      defaultFont_ = null;
    }
    rrPipeline.destroy();
    texPipeline.destroy();
    colorPipeline.destroy();
    clipStack.clear();
    initialized = false;
  }

  ~this() {
    destroy();
  }

  void setViewport(int pixelWidth, int pixelHeight) {
    viewportPixelWidth = pixelWidth;
    viewportPixelHeight = pixelHeight;
    glViewport(0, 0, pixelWidth, pixelHeight);
  }

  /**
   * Sets the additional scaling factor above displayScaling (e.g. to support
   * zooming in/out UI for user preferences). Defaults to 1.0.
   */
  void setUnitsScaling(float scaling) {
    float newScale = scaling > 0.0f ? scaling : 1.0f;
    if (newScale != unitsScaling) {
      unitsScaling = newScale;
      onScalingChanged();
    }
  }

  /**
   * Gets the additional scaling factor above displayScaling (defaults to 1.0).
   */
  float getUnitsScaling() const {
    return unitsScaling;
  }

  void setDisplayScaling(float scaling) {
    float newScale = scaling > 0.0f ? scaling : 1.0f;
    if (newScale != displayScaling) {
      displayScaling = newScale;
      onScalingChanged();
    }
  }

  float getDisplayScaling() const {
    return displayScaling;
  }

  alias getDefaultScaling = getDisplayScaling;

  /**
   * Gets the combined scaling factor (displayScaling * unitsScaling).
   */
  float getTotalScaling() const {
    return displayScaling * unitsScaling;
  }

  float toPixels(float logicUnits) const {
    return logicUnits * (displayScaling * unitsScaling);
  }

  float toLogic(float pixels) const {
    float totalScale = displayScaling * unitsScaling;
    return totalScale > 0.0f ? (pixels / totalScale) : pixels;
  }

  PointF toPixels(in PointF logicPoint) const {
    return PointF(toPixels(logicPoint.x), toPixels(logicPoint.y));
  }

  PointF toLogic(in PointF pixelPoint) const {
    return PointF(toLogic(pixelPoint.x), toLogic(pixelPoint.y));
  }

  RectF toPixels(in RectF logicRect) const {
    return RectF(
      toPixels(logicRect.x),
      toPixels(logicRect.y),
      toPixels(logicRect.width),
      toPixels(logicRect.height)
    );
  }

  RectF toLogic(in RectF pixelRect) const {
    return RectF(
      toLogic(pixelRect.x),
      toLogic(pixelRect.y),
      toLogic(pixelRect.width),
      toLogic(pixelRect.height)
    );
  }

  alias logicToPixels = toPixels;
  alias pixelsToLogic = toLogic;

  int getPixelWidth() const {
    return viewportPixelWidth;
  }

  int getPixelHeight() const {
    return viewportPixelHeight;
  }

  float getLogicWidth() const {
    return toLogic(cast(float)viewportPixelWidth);
  }

  float getLogicHeight() const {
    return toLogic(cast(float)viewportPixelHeight);
  }

  int getViewportWidth() const {
    return cast(int)getLogicWidth();
  }

  int getViewportHeight() const {
    return cast(int)getLogicHeight();
  }

  bool isOnScreen(in RectF rect) const {
    return isOnScreen(rect, getLogicWidth(), getLogicHeight());
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
  static bool isOnScreen(in RectF rect, float vw, float vh) {
    return rect.width > 0.0f && rect.height > 0.0f
      && rect.x < vw && rect.y < vh
      && (rect.x + rect.width) > 0.0f
      && (rect.y + rect.height) > 0.0f;
  }

  PointF coordinatesFromEvent(in AppEvent event) const {
    return coordinatesFromEvent(event.x, event.y);
  }

  PointF coordinatesFromEvent(float x, float y) const {
    float factor = unitsScaling > 0.0f ? (1.0f / unitsScaling) : 1.0f;
    return PointF(x * factor, y * factor);
  }

  PointF coordinatesFromEvent(in PointF point) const {
    return coordinatesFromEvent(point.x, point.y);
  }

  void clearCanvas(ColorF color) {
    glClearColor(color.r, color.g, color.b, color.a);
    glClear(GL_COLOR_BUFFER_BIT);
  }

  void drawFillRect(RectF rect, ColorF color) {
    if (!initialized) {
      return;
    }
    colorPipeline.drawFillRect(
      rect,
      color,
      getLogicWidth(),
      getLogicHeight()
    );
  }

  void drawLine(PointF point1, PointF point2, ColorF color) {
    if (!initialized) {
      return;
    }
    colorPipeline.drawLine(
      point1,
      point2,
      color,
      getLogicWidth(),
      getLogicHeight()
    );
  }

  void drawRect(RectF rect, ColorF color) {
    if (!initialized) {
      return;
    }
    colorPipeline.drawRect(
      rect,
      color,
      getLogicWidth(),
      getLogicHeight()
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
      getLogicWidth(),
      getLogicHeight(),
      getTotalScaling()
    );
  }

  /**
   * Draws a rounded rectangle outline with configurable line width
   * and anti-aliased corners.
   *
   * @param rect Bounding rectangle in logic-space units.
   * @param radius Corner radius (clamped to half the smallest dimension).
   * @param lineWidth Outline thickness in logic-space units.
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
      getLogicWidth(),
      getLogicHeight(),
      getTotalScaling()
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
      getLogicWidth(),
      getLogicHeight(),
      getTotalScaling()
    );
  }

  void pushClipRect(RectF rect) {
    clipStack.push(
      rect,
      getLogicWidth(),
      getLogicHeight(),
      viewportPixelWidth,
      viewportPixelHeight,
      getTotalScaling()
    );
  }

  void popClipRect() {
    clipStack.pop(
      viewportPixelWidth,
      viewportPixelHeight,
      getTotalScaling()
    );
  }

  void setClipRect(RectF rect) {
    clipStack.set(
      rect,
      viewportPixelWidth,
      viewportPixelHeight,
      getTotalScaling()
    );
  }

  void resetClipRect() {
    clipStack.reset();
  }

  Font getDefaultFont() {
    if (defaultFont_ is null) {
      defaultFont_ = new Font(
        cast(const(void)[])defaultTtfFontData,
        defaultFontPtSize,
        getTotalScaling()
      );
      ownsDefaultFont_ = true;
    }
    return defaultFont_;
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
  Font createFont(const(void)[] fontData, float ptSize) {
    return new Font(fontData, ptSize, getTotalScaling());
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
  Font createFont(string filePath, float ptSize) {
    return new Font(filePath, ptSize, getTotalScaling());
  }

  void setDefaultFont(Font font) {
    if (ownsDefaultFont_ && defaultFont_ !is null) {
      defaultFont_.destroy();
    }
    defaultFont_ = font;
    ownsDefaultFont_ = false;
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
      getLogicWidth(),
      getLogicHeight()
    );
  }

  void drawText(
    string text,
    PointF pos,
    ColorF color = ColorF(1.0f, 1.0f, 1.0f, 1.0f),
    Font font = null
  ) {
    Font f = font !is null ? font : getDefaultFont();
    if (f is null || text.length == 0 || textCache is null) {
      return;
    }

    TextTexture tex = textCache.getOrCreate(f, text);
    if (tex.isValid()) {
      drawTextTexture(tex, pos, color);
    }
  }

  void drawText(
    Font font,
    string text,
    PointF pos,
    ColorF color = ColorF(1.0f, 1.0f, 1.0f, 1.0f)
  ) {
    drawText(text, pos, color, font);
  }

  PointF measureText(string text, Font font = null) {
    Font f = font !is null ? font : getDefaultFont();
    if (f is null || text.length == 0) {
      return PointF(0.0f, 0.0f);
    }
    return toLogic(f.measureText(text));
  }

  PointF measureText(Font font, string text) {
    return measureText(text, font);
  }

private:
  TextTexture createTextTexture(Font font, string text) {
    if (!initialized) {
      return TextTexture();
    }
    return TextCache.createTextTexture(font, text);
  }

  void drawTextTexture(
    in TextTexture tex,
    PointF pos,
    ColorF color = ColorF(1.0f, 1.0f, 1.0f, 1.0f)
  ) {
    if (!tex.isValid()) {
      return;
    }
    import std.math : round;

    float screenX = round(toPixels(pos.x));
    float screenY = round(toPixels(pos.y));
    float screenW = cast(float)tex.width;
    float screenH = cast(float)tex.height;

    float logicX0 = toLogic(screenX);
    float logicY0 = toLogic(screenY);
    float logicX1 = toLogic(screenX + screenW);
    float logicY1 = toLogic(screenY + screenH);

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

  void onScalingChanged() {
    float totalScale = getTotalScaling();
    if (ownsDefaultFont_ && defaultFont_ !is null) {
      defaultFont_.setScale(totalScale);
    } else {
      setDefaultFont(null);
    }
    clearTextCache();
  }

  int viewportPixelWidth;
  int viewportPixelHeight;
  float displayScaling = 1.0f;
  float unitsScaling = 1.0f;

  ColorPipeline colorPipeline;
  TexturePipeline texPipeline;
  RoundRectPipeline rrPipeline;
  ClipStack clipStack;
  TextCache textCache;

  private Font defaultFont_;
  private bool ownsDefaultFont_;
  bool initialized;
}

// Verifies isOnScreen viewport culling helper.
unittest {
  const float vw = 640.0f;
  const float vh = 480.0f;

  // Fully inside
  assert(Renderer.isOnScreen(RectF(10, 10, 100, 100), vw, vh));

  // Intersecting edges
  assert(Renderer.isOnScreen(RectF(-50, 10, 100, 100), vw, vh));
  assert(Renderer.isOnScreen(RectF(10, -50, 100, 100), vw, vh));
  assert(Renderer.isOnScreen(RectF(600, 10, 100, 100), vw, vh));
  assert(Renderer.isOnScreen(RectF(10, 450, 100, 100), vw, vh));

  // Fully outside
  assert(!Renderer.isOnScreen(RectF(-150, 10, 100, 100), vw, vh));
  assert(!Renderer.isOnScreen(RectF(10, -150, 100, 100), vw, vh));
  assert(!Renderer.isOnScreen(RectF(700, 10, 100, 100), vw, vh));
  assert(!Renderer.isOnScreen(RectF(10, 500, 100, 100), vw, vh));

  // Zero or negative size
  assert(!Renderer.isOnScreen(RectF(10, 10, 0, 100), vw, vh));
  assert(!Renderer.isOnScreen(RectF(10, 10, 100, 0), vw, vh));
  assert(!Renderer.isOnScreen(RectF(10, 10, -10, 100), vw, vh));
}

unittest {
  import yguilib.clibs.sdl3;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_renderer");
  win.create();
  scope(exit) win.destroy();

  auto renderer = new Renderer(320, 240);
  scope(exit) renderer.destroy();

  assert(renderer.getViewportWidth() == 320);
  assert(renderer.getViewportHeight() == 240);
  assert(renderer.isOnScreen(RectF(10, 10, 100, 100)));
  assert(!renderer.isOnScreen(RectF(700, 10, 100, 100)));

  // 1. Clear canvas red
  renderer.clearCanvas(ColorF(1.0f, 0.0f, 0.0f, 1.0f));
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
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawFillRect(
    RectF(0, 0, 320, 240),
    ColorF(1.0f, 1.0f, 1.0f, 0.5f)
  );
  glReadPixels(160, 120, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] >= 126 && pixel[0] <= 129);
  assert(pixel[1] >= 126 && pixel[1] <= 129);
  assert(pixel[2] >= 126 && pixel[2] <= 129);

  // 4. Clipping rectangle
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
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
  renderer.drawLine(
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
  assert(renderer.getDefaultScaling() == 1.0f);
  assert(renderer.getDisplayScaling() == 1.0f);
  assert(renderer.getUnitsScaling() == 1.0f);
  assert(renderer.toPixels(10.0f) == 10.0f);
  assert(renderer.toLogic(10.0f) == 10.0f);

  renderer.setUnitsScaling(2.0f);
  assert(renderer.getUnitsScaling() == 2.0f);
  assert(renderer.toPixels(10.0f) == 20.0f);
  assert(renderer.toLogic(20.0f) == 10.0f);
  assert(renderer.logicToPixels(15.0f) == 30.0f);
  assert(renderer.pixelsToLogic(30.0f) == 15.0f);

  PointF lp = PointF(10.0f, 20.0f);
  PointF pp = renderer.toPixels(lp);
  assert(pp.x == 20.0f && pp.y == 40.0f);
  PointF backLp = renderer.toLogic(pp);
  assert(backLp.x == 10.0f && backLp.y == 20.0f);

  RectF lr = RectF(5.0f, 10.0f, 50.0f, 60.0f);
  RectF pr = renderer.toPixels(lr);
  assert(
    pr.x == 10.0f && pr.y == 20.0f &&
    pr.width == 100.0f && pr.height == 120.0f
  );
  RectF backLr = renderer.toLogic(pr);
  assert(
    backLr.x == 5.0f && backLr.y == 10.0f &&
    backLr.width == 50.0f && backLr.height == 60.0f
  );

  assert(renderer.getPixelWidth() == 320);
  assert(renderer.getPixelHeight() == 240);
  assert(renderer.getViewportWidth() == 160);
  assert(renderer.getViewportHeight() == 120);

  // Combined scaling: displayScaling = 2.0f, unitsScaling = 1.5f
  // (effective scale = 3.0f)
  renderer.setDisplayScaling(2.0f);
  renderer.setUnitsScaling(1.5f);
  assert(renderer.getDisplayScaling() == 2.0f);
  assert(renderer.getUnitsScaling() == 1.5f);
  assert(renderer.toPixels(10.0f) == 30.0f);
  assert(renderer.toLogic(30.0f) == 10.0f);
  assert(renderer.getViewportWidth() == 106);
  assert(renderer.getViewportHeight() == 80);

  // 7. Test coordinatesFromEvent
  // Case A: 200% display scale, zoom = 1.0 (1:1 window points to logic)
  renderer.setDisplayScaling(2.0f);
  renderer.setUnitsScaling(1.0f);
  assert(renderer.getDefaultScaling() == 2.0f);
  assert(renderer.getUnitsScaling() == 1.0f);

  AppEvent evMotion = AppEvent(AppEvent.Kind.mouseMotion);
  evMotion.windowId = win.id;
  evMotion.x = 100.0f;
  evMotion.y = 50.0f;
  PointF converted = renderer.coordinatesFromEvent(evMotion);
  assert(converted.x == 100.0f);
  assert(converted.y == 50.0f);

  PointF fromFloat = renderer.coordinatesFromEvent(100.0f, 50.0f);
  assert(fromFloat.x == 100.0f);
  assert(fromFloat.y == 50.0f);

  // Case B: 200% display scale, zoom = 2.0 (logic coords halved)
  renderer.setUnitsScaling(2.0f);
  converted = renderer.coordinatesFromEvent(evMotion);
  assert(converted.x == 50.0f);
  assert(converted.y == 25.0f);

  // Case C: 100% display scale, zoom = 0.5 (logic coords doubled)
  renderer.setDisplayScaling(1.0f);
  renderer.setUnitsScaling(0.5f);
  converted = renderer.coordinatesFromEvent(evMotion);
  assert(converted.x == 200.0f);
  assert(converted.y == 100.0f);

  // 8. Scaled drawing test: unitsScaling = 2.0
  renderer.setDisplayScaling(1.0f);
  renderer.setUnitsScaling(2.0f);
  // Drawing rect (0, 0, 160, 120) logic units covers all 320x240 pixels.
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
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
  renderer.setUnitsScaling(1.0f);
  renderer.setDisplayScaling(1.0f);

  Font customFont = new Font(
    cast(const(void)[])defaultTtfFontData,
    16.0f
  );
  scope(exit) customFont.destroy();

  assert(customFont.size == 16.0f);
  assert(customFont.height > 0);
  assert(customFont.ascent > 0);
  assert(customFont.lineSkip > 0);

  PointF mEmpty = renderer.measureText("", customFont);
  assert(mEmpty.x == 0.0f && mEmpty.y == 0.0f);

  PointF mShort = renderer.measureText("Hi", customFont);
  assert(mShort.x > 0.0f && mShort.y > 0.0f);

  PointF mLong = renderer.measureText("Hello World!", customFont);
  assert(mLong.x > mShort.x);

  PointF mFirst = renderer.measureText(customFont, "Hi");
  assert(mFirst.x == mShort.x && mFirst.y == mShort.y);

  // Render text blended in white on black background
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawText(
    "ABC",
    PointF(20.0f, 30.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f),
    customFont
  );

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
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawText(
    customFont,
    "ABC",
    PointF(20.0f, 30.0f),
    ColorF(0.0f, 1.0f, 0.0f, 1.0f)
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
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawText(
    "DefaultFont",
    PointF(10.0f, 10.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f)
  );
  assert(renderer.getDefaultFont() !is null);
  assert(renderer.getDefaultFont().height > 0);

  // Text clipped outside clip rect
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.pushClipRect(RectF(0.0f, 0.0f, 10.0f, 10.0f));
  renderer.drawText(
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
  renderer.setDisplayScaling(1.0f);
  renderer.setUnitsScaling(2.0f);
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawText(
    "ABC",
    PointF(10.0f, 10.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f)
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
  renderer.setUnitsScaling(1.0f);

  // Scaled text drawing test: displayScaling = 1.5
  renderer.setDisplayScaling(1.5f);
  renderer.setUnitsScaling(1.0f);
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawText(
    "ABC",
    PointF(35.0f, 45.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f)
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
  renderer.setDisplayScaling(1.0f);

  // In-place dynamic resizing & unscaled user-space size tests
  Font defaultF = renderer.getDefaultFont();
  assert(defaultF !is null);
  assert(defaultF.size == defaultFontPtSize);
  assert(defaultF.scaledSize == defaultFontPtSize);
  int initialH = defaultF.height;

  // Scale display: defaultFont instance is preserved and resized in place
  renderer.setDisplayScaling(2.0f);
  assert(renderer.getDefaultFont() is defaultF);
  assert(defaultF.size == defaultFontPtSize);
  assert(defaultF.scaledSize == defaultFontPtSize * 2.0f);
  assert(defaultF.height > initialH);

  // Scale units: defaultFont instance is preserved and resized in place
  renderer.setUnitsScaling(1.5f);
  assert(renderer.getDefaultFont() is defaultF);
  assert(defaultF.size == defaultFontPtSize);
  assert(defaultF.scaledSize == defaultFontPtSize * 3.0f);

  renderer.setDisplayScaling(1.0f);
  renderer.setUnitsScaling(1.0f);
  assert(defaultF.size == defaultFontPtSize);
  assert(defaultF.scaledSize == defaultFontPtSize);

  // Factory createFont automatically applies renderer's current scaling
  renderer.setDisplayScaling(2.0f);
  Font factoryFont = renderer.createFont(
    cast(const(void)[])defaultTtfFontData,
    14.0f
  );
  scope(exit) factoryFont.destroy();
  assert(factoryFont.size == 14.0f);
  assert(factoryFont.scaledSize == 28.0f);
  assert(factoryFont.height > 0);

  // In-place setSize updates unscaled size and re-applies current scale
  assert(factoryFont.setSize(20.0f));
  assert(factoryFont.size == 20.0f);
  assert(factoryFont.scaledSize == 40.0f);

  // In-place setScale updates raster size while preserving unscaled size
  assert(factoryFont.setScale(1.0f));
  assert(factoryFont.size == 20.0f);
  assert(factoryFont.scaledSize == 20.0f);

  renderer.setDisplayScaling(1.0f);
  renderer.setUnitsScaling(1.0f);

  assert(glGetError() == GL_NO_ERROR);

  // 10. Rounded rectangle drawing tests (fill, outline, dashed, clamping,
  // scaling)
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));

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
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
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
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
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
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawFillRoundRect(
    RectF(10.0f, 10.0f, 40.0f, 40.0f),
    100.0f, // excess radius clamped to 20
    ColorF(1.0f, 0.0f, 0.0f, 1.0f)
  );
  // Center (30, 30) -> GL y = 210 should be red
  glReadPixels(30, 210, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 255 && pixel[1] == 0 && pixel[2] == 0 && pixel[3] == 255);

  // Test units scaling with rounded rect
  renderer.setUnitsScaling(2.0f);
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  // Logic (10, 10, 50, 50) maps to screen (20, 20, 100, 100)
  renderer.drawFillRoundRect(
    RectF(10.0f, 10.0f, 50.0f, 50.0f),
    5.0f,
    ColorF(0.0f, 1.0f, 1.0f, 1.0f)
  );
  // Screen center of rect is (70, 70) -> GL y = 240 - 70 = 170
  glReadPixels(70, 170, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[1] == 255 && pixel[2] == 255);
  renderer.setUnitsScaling(1.0f);

  assert(glGetError() == GL_NO_ERROR);
}
