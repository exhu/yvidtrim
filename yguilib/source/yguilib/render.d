module yguilib.render;

import glad2.gles2;
import std.algorithm : max, min;
import std.array : Appender;
import std.logger;
import std.string : toStringz;
import yguilib.clibs.sdl3_ttf;
import yguilib.events : AppEvent;
public import yguilib.render_types;

enum string defaultTtfFontData =
  import("yguilib/fonts/GoogleSansCode-Regular.ttf");

enum float defaultFontPtSize = 16.0 * 96.0/72.0;

final class Font {
  /**
   * Loads a font from memory data.
   *
   * Font point sizes (`ptSize`) in user space are unscaled logical points.
   * Scaling (`scale = displayScaling * unitsScaling`) is an internal renderer
   * detail used to rasterize glyphs at native display resolution.
   *
   * @param fontData TTF binary data in memory.
   * @param ptSize Unscaled logical point size in user space.
   * @param scale Rendering scaling factor (defaults to 1.0f).
   */
  this(const(void)[] fontData, float ptSize, float scale = 1.0f) {
    assert(fontData.length > 0, "fontData must not be empty");
    assert(ptSize > 0.0f, "ptSize must be positive");
    float effectiveScale = scale > 0.0f ? scale : 1.0f;
    handle = yguilib_sdl3_ttf_open_font_from_mem(
      fontData.ptr,
      fontData.length,
      ptSize * effectiveScale
    );
    if (!handle) {
      throw new Exception("Failed to load font from memory");
    }
    this.logicalPtSize = ptSize;
    this.currentScale = effectiveScale;
  }

  /**
   * Loads a font from a file path.
   *
   * Font point sizes (`ptSize`) in user space are unscaled logical points.
   * Scaling (`scale = displayScaling * unitsScaling`) is an internal renderer
   * detail used to rasterize glyphs at native display resolution.
   *
   * @param filePath Path to the TTF font file.
   * @param ptSize Unscaled logical point size in user space.
   * @param scale Rendering scaling factor (defaults to 1.0f).
   */
  this(string filePath, float ptSize, float scale = 1.0f) {
    assert(filePath.length > 0, "filePath must not be empty");
    assert(ptSize > 0.0f, "ptSize must be positive");
    float effectiveScale = scale > 0.0f ? scale : 1.0f;
    handle = yguilib_sdl3_ttf_open_font(
      filePath.toStringz(),
      ptSize * effectiveScale
    );
    if (!handle) {
      throw new Exception("Failed to load font from file: " ~ filePath);
    }
    this.logicalPtSize = ptSize;
    this.currentScale = effectiveScale;
  }

  ~this() {
    destroy();
  }

  void destroy() {
    if (handle !is null) {
      yguilib_sdl3_ttf_close_font(handle);
      handle = null;
    }
  }

  /**
   * Gets the unscaled logical point size of the font in user space.
   */
  @property float size() const {
    return logicalPtSize;
  }

  /**
   * Gets the rasterization point size currently applied to the font handle.
   */
  @property float scaledSize() const {
    return logicalPtSize * currentScale;
  }

  /**
   * Dynamically updates the unscaled logical point size of the font.
   *
   * Font point units are kept unscaled in user space. The renderer's current
   * scaling factor is reapplied internally to update the raster size in place.
   *
   * @param newPtSize New unscaled point size in logical units.
   * @return true if resized successfully, false otherwise.
   */
  bool setSize(float newPtSize) {
    if (!handle || newPtSize <= 0.0f) {
      return false;
    }
    float targetSize = newPtSize * currentScale;
    if (yguilib_sdl3_ttf_set_font_size(handle, targetSize) == 0) {
      logicalPtSize = newPtSize;
      return true;
    }
    return false;
  }

  /**
   * Dynamically updates the rendering scaling factor of the font.
   *
   * Kept as an internal renderer detail so the font rasterizer matches
   * display and units zoom changes without reallocating font resources.
   *
   * @param newScale New scaling multiplier (displayScaling * unitsScaling).
   * @return true if resized successfully, false otherwise.
   */
  bool setScale(float newScale) {
    if (!handle) {
      return false;
    }
    float effectiveScale = newScale > 0.0f ? newScale : 1.0f;
    float targetSize = logicalPtSize * effectiveScale;
    if (yguilib_sdl3_ttf_set_font_size(handle, targetSize) == 0) {
      currentScale = effectiveScale;
      return true;
    }
    return false;
  }

  int height() const {
    return handle ? yguilib_sdl3_ttf_get_font_height(handle) : 0;
  }

  int ascent() const {
    return handle ? yguilib_sdl3_ttf_get_font_ascent(handle) : 0;
  }

  int descent() const {
    return handle ? yguilib_sdl3_ttf_get_font_descent(handle) : 0;
  }

  int lineSkip() const {
    return handle ? yguilib_sdl3_ttf_get_font_line_skip(handle) : 0;
  }

  PointF measureText(string text) const {
    if (!handle || text.length == 0) {
      return PointF(0.0f, 0.0f);
    }
    int w = 0;
    int h = 0;
    if (yguilib_sdl3_ttf_get_text_size(
      handle,
      text.ptr,
      text.length,
      &w,
      &h
    ) == 0) {
      return PointF(cast(float)w, cast(float)h);
    }
    return PointF(0.0f, 0.0f);
  }

  package yguilib_sdl3_ttf_Font* handle;
  private float logicalPtSize;
  private float currentScale = 1.0f;
}

struct TextTexture {
  GLuint textureId = 0;
  int width = 0;
  int height = 0;

  bool isValid() const {
    return textureId != 0;
  }

  void destroy() {
    if (textureId != 0) {
      glDeleteTextures(1, &textureId);
      textureId = 0;
    }
    width = 0;
    height = 0;
  }
}

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

    enum string vertexShaderSource =
      import("yguilib/shaders/color.vert.glsl");
    enum string fragmentShaderSource =
      import("yguilib/shaders/color.frag.glsl");

    GLuint vertShader = compileShader(
      GL_VERTEX_SHADER,
      vertexShaderSource
    );
    scope(exit) glDeleteShader(vertShader);

    GLuint fragShader = compileShader(
      GL_FRAGMENT_SHADER,
      fragmentShaderSource
    );
    scope(exit) glDeleteShader(fragShader);

    program = linkProgram(vertShader, fragShader);
    uResolutionLoc = glGetUniformLocation(program, "uResolution\0".ptr);
    uColorLoc = glGetUniformLocation(program, "uColor\0".ptr);

    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);

    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);

    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * float.sizeof, null);

    glBindVertexArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);

    enum string texVertexShaderSource =
      import("yguilib/shaders/texture.vert.glsl");
    enum string texFragmentShaderSource =
      import("yguilib/shaders/texture.frag.glsl");

    GLuint texVert = compileShader(
      GL_VERTEX_SHADER,
      texVertexShaderSource
    );
    scope(exit) glDeleteShader(texVert);

    GLuint texFrag = compileShader(
      GL_FRAGMENT_SHADER,
      texFragmentShaderSource
    );
    scope(exit) glDeleteShader(texFrag);

    texProgram = linkProgram(texVert, texFrag);
    uTexResolutionLoc =
      glGetUniformLocation(texProgram, "uResolution\0".ptr);
    uTexColorLoc = glGetUniformLocation(texProgram, "uColor\0".ptr);
    uTextureLoc = glGetUniformLocation(texProgram, "uTexture\0".ptr);

    glGenVertexArrays(1, &texVao);
    glBindVertexArray(texVao);

    glGenBuffers(1, &texVbo);
    glBindBuffer(GL_ARRAY_BUFFER, texVbo);

    glEnableVertexAttribArray(0);
    glVertexAttribPointer(
      0,
      2,
      GL_FLOAT,
      GL_FALSE,
      4 * float.sizeof,
      null
    );

    glEnableVertexAttribArray(1);
    glVertexAttribPointer(
      1,
      2,
      GL_FLOAT,
      GL_FALSE,
      4 * float.sizeof,
      cast(const(void)*)(2 * float.sizeof)
    );

    glBindVertexArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);

    enum string rrVertexShaderSource =
      import("yguilib/shaders/roundrect.vert.glsl");
    enum string rrFragmentShaderSource =
      import("yguilib/shaders/roundrect.frag.glsl");

    GLuint rrVert = compileShader(
      GL_VERTEX_SHADER,
      rrVertexShaderSource
    );
    scope(exit) glDeleteShader(rrVert);

    GLuint rrFrag = compileShader(
      GL_FRAGMENT_SHADER,
      rrFragmentShaderSource
    );
    scope(exit) glDeleteShader(rrFrag);

    rrProgram = linkProgram(rrVert, rrFrag);
    uRrResolutionLoc =
      glGetUniformLocation(rrProgram, "uResolution\0".ptr);
    uRrColorLoc = glGetUniformLocation(rrProgram, "uColor\0".ptr);
    uRrHalfSizeLoc = glGetUniformLocation(rrProgram, "uHalfSize\0".ptr);
    uRrRadiusLoc = glGetUniformLocation(rrProgram, "uRadius\0".ptr);
    uRrLineWidthLoc = glGetUniformLocation(rrProgram, "uLineWidth\0".ptr);
    uRrDashLenLoc = glGetUniformLocation(rrProgram, "uDashLen\0".ptr);
    uRrGapLenLoc = glGetUniformLocation(rrProgram, "uGapLen\0".ptr);
    uRrPixelSizeLoc = glGetUniformLocation(rrProgram, "uPixelSize\0".ptr);

    glGenVertexArrays(1, &rrVao);
    glBindVertexArray(rrVao);

    glGenBuffers(1, &rrVbo);
    glBindBuffer(GL_ARRAY_BUFFER, rrVbo);

    glEnableVertexAttribArray(0);
    glVertexAttribPointer(
      0,
      2,
      GL_FLOAT,
      GL_FALSE,
      4 * float.sizeof,
      null
    );

    glEnableVertexAttribArray(1);
    glVertexAttribPointer(
      1,
      2,
      GL_FLOAT,
      GL_FALSE,
      4 * float.sizeof,
      cast(const(void)*)(2 * float.sizeof)
    );

    glBindVertexArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);

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
    if (rrVbo != 0) {
      glDeleteBuffers(1, &rrVbo);
      rrVbo = 0;
    }
    if (rrVao != 0) {
      glDeleteVertexArrays(1, &rrVao);
      rrVao = 0;
    }
    if (rrProgram != 0) {
      glDeleteProgram(rrProgram);
      rrProgram = 0;
    }
    if (texVbo != 0) {
      glDeleteBuffers(1, &texVbo);
      texVbo = 0;
    }
    if (texVao != 0) {
      glDeleteVertexArrays(1, &texVao);
      texVao = 0;
    }
    if (texProgram != 0) {
      glDeleteProgram(texProgram);
      texProgram = 0;
    }
    if (vbo != 0) {
      glDeleteBuffers(1, &vbo);
      vbo = 0;
    }
    if (vao != 0) {
      glDeleteVertexArrays(1, &vao);
      vao = 0;
    }
    if (program != 0) {
      glDeleteProgram(program);
      program = 0;
    }
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
      float totalScale = getTotalScaling();
      if (ownsDefaultFont_ && defaultFont_ !is null) {
        defaultFont_.setScale(totalScale);
      } else {
        setDefaultFont(null);
      }
      clearTextCache();
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
      float totalScale = getTotalScaling();
      if (ownsDefaultFont_ && defaultFont_ !is null) {
        defaultFont_.setScale(totalScale);
      } else {
        setDefaultFont(null);
      }
      clearTextCache();
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
    float x0 = rect.x;
    float y0 = rect.y;
    float x1 = rect.x + rect.width;
    float y1 = rect.y + rect.height;

    float[12] vertices = [
      x0, y0,
      x1, y0,
      x0, y1,
      x0, y1,
      x1, y0,
      x1, y1,
    ];

    drawArrays(GL_TRIANGLES, vertices, color);
  }

  void drawLine(PointF point1, PointF point2, ColorF color) {
    float[4] vertices = [
      point1.x, point1.y,
      point2.x, point2.y,
    ];

    drawArrays(GL_LINES, vertices, color);
  }

  void drawRect(RectF rect, ColorF color) {
    float x0 = rect.x;
    float y0 = rect.y;
    float x1 = rect.x + rect.width;
    float y1 = rect.y + rect.height;

    float[8] vertices = [
      x0, y0,
      x1, y0,
      x1, y1,
      x0, y1,
    ];

    drawArrays(GL_LINE_LOOP, vertices, color);
  }

  /**
   * Draws a filled rounded rectangle with anti-aliased corners.
   *
   * @param rect Bounding rectangle in logic-space units.
   * @param radius Corner radius (clamped to half the smallest dimension).
   * @param color Fill color.
   */
  void drawFillRoundRect(RectF rect, float radius, ColorF color) {
    drawRoundRectImpl(rect, radius, 0.0f, 0.0f, 0.0f, color);
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
    drawRoundRectImpl(rect, radius, lineWidth, 0.0f, 0.0f, color);
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
    drawRoundRectImpl(rect, radius, lineWidth, dashLen, gapLen, color);
  }

  void pushClipRect(RectF rect) {
    const auto stackData = clipStack[];
    RectF active;
    if (stackData.length == 0) {
      active = RectF(0, 0, getLogicWidth(), getLogicHeight());
    } else {
      active = stackData[$ - 1];
    }
    RectF clipped = intersectRects(active, rect);
    clipStack ~= clipped;
    applyScissor(clipped);
  }

  void popClipRect() {
    auto stackData = clipStack[];
    if (stackData.length == 0) {
      return;
    }
    clipStack.shrinkTo(stackData.length - 1);
    stackData = clipStack[];
    if (stackData.length == 0) {
      glDisable(GL_SCISSOR_TEST);
    } else {
      applyScissor(stackData[$ - 1]);
    }
  }

  void setClipRect(RectF rect) {
    clipStack.clear();
    clipStack ~= rect;
    applyScissor(rect);
  }

  void resetClipRect() {
    clipStack.clear();
    glDisable(GL_SCISSOR_TEST);
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
    foreach (key, tex; textCache) {
      tex.destroy();
    }
    textCache.clear();
  }

  TextTexture createTextTexture(Font font, string text) {
    if (!initialized || font is null || font.handle is null || text.length == 0)
    {
      return TextTexture();
    }

    auto surf = yguilib_sdl3_ttf_render_text_blended(
      font.handle,
      text.ptr,
      text.length,
      255,
      255,
      255,
      255
    );
    if (surf is null) {
      return TextTexture();
    }
    scope(exit) yguilib_sdl3_ttf_destroy_surface(surf);

    int w = 0;
    int h = 0;
    yguilib_sdl3_ttf_get_surface_size(surf, &w, &h);
    int pitch = yguilib_sdl3_ttf_get_surface_pitch(surf);
    const void* pixels = yguilib_sdl3_ttf_get_surface_pixels(surf);
    if (w <= 0 || h <= 0 || pixels is null) {
      return TextTexture();
    }

    GLuint texId;
    glGenTextures(1, &texId);
    glBindTexture(GL_TEXTURE_2D, texId);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    if (pitch != w * 4) {
      glPixelStorei(GL_UNPACK_ROW_LENGTH, pitch / 4);
    }
    glTexImage2D(
      GL_TEXTURE_2D,
      0,
      GL_RGBA,
      w,
      h,
      0,
      GL_RGBA,
      GL_UNSIGNED_BYTE,
      pixels
    );
    if (pitch != w * 4) {
      glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    }
    glBindTexture(GL_TEXTURE_2D, 0);

    return TextTexture(texId, w, h);
  }

  void drawTexture(GLuint texId, RectF destRect, ColorF color) {
    if (!initialized || texId == 0) {
      return;
    }

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glUseProgram(texProgram);
    glUniform2f(
      uTexResolutionLoc,
      getLogicWidth(),
      getLogicHeight()
    );
    glUniform4f(uTexColorLoc, color.r, color.g, color.b, color.a);
    glUniform1i(uTextureLoc, 0);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texId);

    float x0 = destRect.x;
    float y0 = destRect.y;
    float x1 = destRect.x + destRect.width;
    float y1 = destRect.y + destRect.height;

    float[24] vertices = [
      x0, y0, 0.0f, 0.0f,
      x1, y0, 1.0f, 0.0f,
      x0, y1, 0.0f, 1.0f,
      x0, y1, 0.0f, 1.0f,
      x1, y0, 1.0f, 0.0f,
      x1, y1, 1.0f, 1.0f,
    ];

    glBindVertexArray(texVao);
    glBindBuffer(GL_ARRAY_BUFFER, texVbo);
    glBufferData(
      GL_ARRAY_BUFFER,
      cast(GLsizeiptr)(vertices.length * float.sizeof),
      vertices.ptr,
      GL_DYNAMIC_DRAW
    );

    glDrawArrays(GL_TRIANGLES, 0, 6);

    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArray(0);
    glBindTexture(GL_TEXTURE_2D, 0);
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

  void drawText(
    string text,
    PointF pos,
    ColorF color = ColorF(1.0f, 1.0f, 1.0f, 1.0f),
    Font font = null
  ) {
    Font f = font !is null ? font : getDefaultFont();
    if (f is null || f.handle is null || text.length == 0) {
      return;
    }

    // TODO move text cache data and functions to its own separate struct/class
    TextCacheKey key = TextCacheKey(f.handle, f.scaledSize, text);
    auto p = key in textCache;
    TextTexture tex;
    if (p !is null) {
      tex = *p;
    } else {
      if (textCache.length >= 512) {
        clearTextCache();
      }
      tex = createTextTexture(f, text);
      if (tex.isValid()) {
        textCache[key] = tex;
      }
    }

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
  private void drawRoundRectImpl(
    RectF rect,
    float radius,
    float lineWidth,
    float dashLen,
    float gapLen,
    in ColorF color
  ) {
    import std.algorithm : min;
    if (!initialized) {
      return;
    }

    float halfW = rect.width * 0.5f;
    float halfH = rect.height * 0.5f;
    float r = min(radius, min(halfW, halfH));
    if (r < 0.0f) {
      r = 0.0f;
    }

    // Expand the quad slightly for AA margin
    float totalScale = getTotalScaling();
    float px = totalScale > 0.0f ? (1.0f / totalScale) : 1.0f;
    float margin = px * 2.0f;

    float cx = rect.x + halfW;
    float cy = rect.y + halfH;

    float qx0 = cx - halfW - margin;
    float qy0 = cy - halfH - margin;
    float qx1 = cx + halfW + margin;
    float qy1 = cy + halfH + margin;

    float lx0 = -(halfW + margin);
    float ly0 = -(halfH + margin);
    float lx1 = halfW + margin;
    float ly1 = halfH + margin;

    float[24] vertices = [
      qx0, qy0, lx0, ly0,
      qx1, qy0, lx1, ly0,
      qx0, qy1, lx0, ly1,
      qx0, qy1, lx0, ly1,
      qx1, qy0, lx1, ly0,
      qx1, qy1, lx1, ly1,
    ];

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glUseProgram(rrProgram);
    glUniform2f(
      uRrResolutionLoc,
      getLogicWidth(),
      getLogicHeight()
    );
    glUniform4f(
      uRrColorLoc,
      color.r,
      color.g,
      color.b,
      color.a
    );
    glUniform2f(uRrHalfSizeLoc, halfW, halfH);
    glUniform1f(uRrRadiusLoc, r);
    glUniform1f(uRrLineWidthLoc, lineWidth);
    glUniform1f(uRrDashLenLoc, dashLen);
    glUniform1f(uRrGapLenLoc, gapLen);
    glUniform1f(uRrPixelSizeLoc, px);

    glBindVertexArray(rrVao);
    glBindBuffer(GL_ARRAY_BUFFER, rrVbo);
    glBufferData(
      GL_ARRAY_BUFFER,
      cast(GLsizeiptr)(vertices.length * float.sizeof),
      vertices.ptr,
      GL_DYNAMIC_DRAW
    );
    glDrawArrays(GL_TRIANGLES, 0, 6);

    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArray(0);
  }

  void drawArrays(GLenum mode, const(float)[] vertices, in ColorF color) {
    if (!initialized) {
      return;
    }

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glUseProgram(program);
    glUniform2f(
      uResolutionLoc,
      getLogicWidth(),
      getLogicHeight()
    );
    glUniform4f(uColorLoc, color.r, color.g, color.b, color.a);

    glBindVertexArray(vao);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(
      GL_ARRAY_BUFFER,
      cast(GLsizeiptr)(vertices.length * float.sizeof),
      vertices.ptr,
      GL_DYNAMIC_DRAW
    );

    glDrawArrays(mode, 0, cast(GLsizei)(vertices.length / 2));

    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArray(0);
  }

  void applyScissor(in RectF rect) {
    RectF pixelRect = toPixels(rect);
    float clampedX = max(0.0f, pixelRect.x);
    float clampedY = max(0.0f, pixelRect.y);
    float clampedRight = min(
      cast(float)viewportPixelWidth,
      pixelRect.x + pixelRect.width
    );
    float clampedBottom = min(
      cast(float)viewportPixelHeight,
      pixelRect.y + pixelRect.height
    );

    float w = clampedRight - clampedX;
    float h = clampedBottom - clampedY;
    if (w < 0.0f) {
      w = 0.0f;
    }
    if (h < 0.0f) {
      h = 0.0f;
    }

    int glX = cast(int)clampedX;
    int glY = cast(int)(viewportPixelHeight - (clampedY + h));
    int glW = cast(int)w;
    int glH = cast(int)h;

    glEnable(GL_SCISSOR_TEST);
    glScissor(glX, glY, glW, glH);
  }

  static GLuint compileShader(GLenum type, string source) {
    GLuint shader = glCreateShader(type);
    if (shader == 0) {
      throw new Exception("Failed to create shader object");
    }

    const(char)* srcPtr = source.ptr;
    GLint srcLen = cast(GLint)source.length;
    glShaderSource(shader, 1, &srcPtr, &srcLen);
    glCompileShader(shader);

    GLint compiled = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (!compiled) {
      GLint logLength = 0;
      glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength);
      string log;
      if (logLength > 0) {
        char[] buf = new char[logLength];
        GLsizei written = 0;
        glGetShaderInfoLog(shader, logLength, &written, buf.ptr);
        log = buf[0 .. written].idup;
      }
      glDeleteShader(shader);
      errorf("Shader compile error: %s", log);
      throw new Exception("Shader compile failed: " ~ log);
    }
    return shader;
  }

  static GLuint linkProgram(GLuint vertShader, GLuint fragShader) {
    GLuint prog = glCreateProgram();
    if (prog == 0) {
      throw new Exception("Failed to create shader program");
    }

    glAttachShader(prog, vertShader);
    glAttachShader(prog, fragShader);
    glLinkProgram(prog);

    GLint linked = 0;
    glGetProgramiv(prog, GL_LINK_STATUS, &linked);
    if (!linked) {
      GLint logLength = 0;
      glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
      string log;
      if (logLength > 0) {
        char[] buf = new char[logLength];
        GLsizei written = 0;
        glGetProgramInfoLog(prog, logLength, &written, buf.ptr);
        log = buf[0 .. written].idup;
      }
      glDeleteProgram(prog);
      errorf("Program link error: %s", log);
      throw new Exception("Program link failed: " ~ log);
    }
    return prog;
  }

  int viewportPixelWidth;
  int viewportPixelHeight;
  float displayScaling = 1.0f;
  float unitsScaling = 1.0f;
  GLuint program;
  GLuint vao;
  GLuint vbo;
  GLint uResolutionLoc = -1;
  GLint uColorLoc = -1;

  GLuint texProgram;
  GLuint texVao;
  GLuint texVbo;
  GLint uTexResolutionLoc = -1;
  GLint uTexColorLoc = -1;
  GLint uTextureLoc = -1;

  GLuint rrProgram;
  GLuint rrVao;
  GLuint rrVbo;
  GLint uRrResolutionLoc = -1;
  GLint uRrColorLoc = -1;
  GLint uRrHalfSizeLoc = -1;
  GLint uRrRadiusLoc = -1;
  GLint uRrLineWidthLoc = -1;
  GLint uRrDashLenLoc = -1;
  GLint uRrGapLenLoc = -1;
  GLint uRrPixelSizeLoc = -1;

  private struct TextCacheKey {
    void* fontHandle;
    float ptSize;
    string text;
  }
  private TextTexture[TextCacheKey] textCache;
  private Font defaultFont_;
  private bool ownsDefaultFont_;

  bool initialized;
  Appender!(RectF[]) clipStack;
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

  AppEvent evMotion = AppEvent(
    AppEvent.Kind.mouseMotion,
    win.id,
    0,
    0,
    null,
    100.0f,
    50.0f
  );
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

  // 10. Rounded rectangle drawing tests (fill, outline, dashed, clamping, scaling)
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));

  // Test fill mode: draw green filled round rect at (20, 20, 60, 40) with radius 10
  renderer.drawFillRoundRect(
    RectF(20.0f, 20.0f, 60.0f, 40.0f),
    10.0f,
    ColorF(0.0f, 1.0f, 0.0f, 1.0f)
  );
  // Center pixel (50, 40) -> GL y = 240 - 40 = 200 should be green
  glReadPixels(50, 200, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0 && pixel[1] == 255 && pixel[2] == 0 && pixel[3] == 255);
  // Outside corner pixel (21, 21) -> GL y = 240 - 21 = 219 should be black (clipped by corner radius)
  glReadPixels(21, 219, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);
  // Far outside pixel (5, 5) -> GL y = 235 should be black
  glReadPixels(5, 235, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.ptr);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);

  // Test outline mode: draw blue outline at (100, 100, 80, 60), radius 8, line width 4
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawRoundRect(
    RectF(100.0f, 100.0f, 80.0f, 60.0f),
    8.0f,
    4.0f,
    ColorF(0.0f, 0.0f, 1.0f, 1.0f)
  );
  // Center of outline rect (140, 130) -> GL y = 240 - 130 = 110 should be hollow (black)
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
