module yguilib.render;

import glad2.gles2;
import std.algorithm : max, min;
import std.logger;
import std.string : toStringz;
import yguilib.clibs.sdl3_ttf;
import yguilib.events : AppEvent;
public import yguilib.render_types;

enum string defaultTtfFontData =
  import("yguilib/fonts/GoogleSansCode-Regular.ttf");

enum float defaultFontPtSize = 16f;

final class Font {
  this(const(void)[] fontData, float ptSize) {
    assert(fontData.length > 0, "fontData must not be empty");
    assert(ptSize > 0.0f, "ptSize must be positive");
    handle = yguilib_sdl3_ttf_open_font_from_mem(
      fontData.ptr,
      fontData.length,
      ptSize
    );
    if (!handle) {
      throw new Exception("Failed to load font from memory");
    }
    this.ptSize = ptSize;
  }

  this(string filePath, float ptSize) {
    assert(filePath.length > 0, "filePath must not be empty");
    assert(ptSize > 0.0f, "ptSize must be positive");
    handle = yguilib_sdl3_ttf_open_font(filePath.toStringz(), ptSize);
    if (!handle) {
      throw new Exception("Failed to load font from file: " ~ filePath);
    }
    this.ptSize = ptSize;
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

  @property float size() const {
    return ptSize;
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
  private float ptSize;
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
    this.unitsScaling = this.displayScaling;
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
    clipStack.length = 0;
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

  void setUnitsScaling(float scaling) {
    unitsScaling = scaling > 0.0f ? scaling : 1.0f;
  }

  float getUnitsScaling() const {
    return unitsScaling;
  }

  void setDisplayScaling(float scaling) {
    if (scaling != displayScaling) {
      displayScaling = scaling > 0.0f ? scaling : 1.0f;
      // release fonts, they don't match new dpi
      clearTextCache();
      setDefaultFont(null);
    }
  }

  float getDefaultScaling() const {
    return displayScaling;
  }

  float toPixels(float logicUnits) const {
    return logicUnits * unitsScaling;
  }

  float toLogic(float pixels) const {
    return unitsScaling > 0.0f ? (pixels / unitsScaling) : pixels;
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
    float factor = unitsScaling > 0.0f ? (displayScaling / unitsScaling) : 1.0f;
    return PointF(event.x * factor, event.y * factor);
  }

  PointF coordinatesFromEvent(float x, float y) const {
    float factor = unitsScaling > 0.0f ? (displayScaling / unitsScaling) : 1.0f;
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

  void pushClipRect(RectF rect) {
    RectF active;
    if (clipStack.length == 0) {
      active = RectF(0, 0, getLogicWidth(), getLogicHeight());
    } else {
      active = clipStack[$ - 1];
    }
    RectF clipped = intersectRects(active, rect);
    clipStack ~= clipped;
    applyScissor(clipped);
  }

  void popClipRect() {
    if (clipStack.length == 0) {
      return;
    }
    clipStack = clipStack[0 .. $ - 1];
    if (clipStack.length == 0) {
      glDisable(GL_SCISSOR_TEST);
    } else {
      applyScissor(clipStack[$ - 1]);
    }
  }

  void setClipRect(RectF rect) {
    clipStack.length = 0;
    clipStack ~= rect;
    applyScissor(rect);
  }

  void resetClipRect() {
    clipStack.length = 0;
    glDisable(GL_SCISSOR_TEST);
  }

  Font getDefaultFont() {
    if (defaultFont_ is null) {
      defaultFont_ = new Font(cast(const(void)[])defaultTtfFontData, defaultFontPtSize * displayScaling);
      ownsDefaultFont_ = true;
    }
    return defaultFont_;
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
    drawTexture(
      tex.textureId,
      RectF(pos.x, pos.y, cast(float)tex.width, cast(float)tex.height),
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
    TextCacheKey key = TextCacheKey(f.handle, f.size, text);
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
    return f.measureText(text);
  }

  PointF measureText(Font font, string text) {
    return measureText(text, font);
  }

private:
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

  static RectF intersectRects(in RectF a, in RectF b) {
    float x1 = max(a.x, b.x);
    float y1 = max(a.y, b.y);
    float x2 = min(a.x + a.width, b.x + b.width);
    float y2 = min(a.y + a.height, b.y + b.height);
    float w = x2 - x1;
    float h = y2 - y1;
    if (w < 0.0f) {
      w = 0.0f;
    }
    if (h < 0.0f) {
      h = 0.0f;
    }
    return RectF(x1, y1, w, h);
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

  private struct TextCacheKey {
    void* fontHandle;
    float ptSize;
    string text;
  }
  private TextTexture[TextCacheKey] textCache;
  private Font defaultFont_;
  private bool ownsDefaultFont_;

  bool initialized;
  RectF[] clipStack;
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

  // 7. Test coordinatesFromEvent
  // Case A: 200% display scale, Renderer forced to 100% scale (ratio = 2.0)
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
  assert(converted.x == 200.0f);
  assert(converted.y == 100.0f);

  PointF fromFloat = renderer.coordinatesFromEvent(100.0f, 50.0f);
  assert(fromFloat.x == 200.0f);
  assert(fromFloat.y == 100.0f);

  // Case B: 200% display scale, Renderer at 200% scale (ratio = 1.0)
  renderer.setUnitsScaling(2.0f);
  converted = renderer.coordinatesFromEvent(evMotion);
  assert(converted.x == 100.0f);
  assert(converted.y == 50.0f);

  // Case C: 100% display scale, Renderer forced to 200% scale (ratio = 0.5)
  renderer.setDisplayScaling(1.0f);
  renderer.setUnitsScaling(2.0f);
  converted = renderer.coordinatesFromEvent(evMotion);
  assert(converted.x == 50.0f);
  assert(converted.y == 25.0f);

  // 8. Scaled drawing test: unitsScaling = 2.0
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
  renderer.setUnitsScaling(2.0f);
  renderer.clearCanvas(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawText(
    customFont,
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

  assert(glGetError() == GL_NO_ERROR);
}
