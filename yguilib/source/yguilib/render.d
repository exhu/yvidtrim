module yguilib.render;

import glad2.gles2;
import std.algorithm : max, min;
import std.logger;
import std.string : toStringz;
import yguilib.events : AppEvent;
public import yguilib.render_types;

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

    initialized = true;
  }

  void destroy() {
    if (!initialized) {
      return;
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
    displayScaling = scaling > 0.0f ? scaling : 1.0f;
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
}
