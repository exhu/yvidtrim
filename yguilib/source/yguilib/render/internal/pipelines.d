module yguilib.render.internal.pipelines;

package(yguilib):

import glad2.gles2;
import yguilib.render.internal.gl_util;
import yguilib.render.render_types : ColorF, PointF, RectF;

/**
 * Shader pipeline for flat color primitives (triangles, lines, line loops).
 */
struct ColorPipeline {
  GLuint program;
  GLuint vao;
  GLuint vbo;
  GLint uResolutionLoc = -1;
  GLint uColorLoc = -1;

  void initialize() {
    enum string vertexShaderSource =
      import("yguilib/shaders/color.vert.glsl");
    enum string fragmentShaderSource =
      import("yguilib/shaders/color.frag.glsl");

    GLuint vertShader = compileShader(GL_VERTEX_SHADER, vertexShaderSource);
    scope(exit) glDeleteShader(vertShader);

    GLuint fragShader = compileShader(GL_FRAGMENT_SHADER, fragmentShaderSource);
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
  }

  void destroy() {
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
  }

  void drawArrays(
    GLenum mode,
    const(float)[] vertices,
    in ColorF color,
    float vw,
    float vh
  ) {
    setup2DBlendState();
    glUseProgram(program);
    glUniform2f(uResolutionLoc, vw, vh);
    glUniform4f(uColorLoc, color.r, color.g, color.b, color.a);
    uploadAndDrawDynamic(
      mode,
      vao,
      vbo,
      vertices,
      cast(GLsizei)(vertices.length / 2)
    );
  }

  void drawFillRect(in RectF rect, in ColorF color, float vw, float vh) {
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

    drawArrays(GL_TRIANGLES, vertices, color, vw, vh);
  }

  void drawLine(
    in PointF point1,
    in PointF point2,
    in ColorF color,
    float vw,
    float vh
  ) {
    float[4] vertices = [
      point1.x, point1.y,
      point2.x, point2.y,
    ];

    drawArrays(GL_LINES, vertices, color, vw, vh);
  }

  void drawRect(in RectF rect, in ColorF color, float vw, float vh) {
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

    drawArrays(GL_LINE_LOOP, vertices, color, vw, vh);
  }
}

/**
 * Shader pipeline for textured 2D quads.
 */
struct TexturePipeline {
  GLuint program;
  GLuint vao;
  GLuint vbo;
  GLint uResolutionLoc = -1;
  GLint uColorLoc = -1;
  GLint uTextureLoc = -1;

  void initialize() {
    enum string texVertexShaderSource =
      import("yguilib/shaders/texture.vert.glsl");
    enum string texFragmentShaderSource =
      import("yguilib/shaders/texture.frag.glsl");

    GLuint texVert = compileShader(GL_VERTEX_SHADER, texVertexShaderSource);
    scope(exit) glDeleteShader(texVert);

    GLuint texFrag = compileShader(GL_FRAGMENT_SHADER, texFragmentShaderSource);
    scope(exit) glDeleteShader(texFrag);

    program = linkProgram(texVert, texFrag);
    uResolutionLoc = glGetUniformLocation(program, "uResolution\0".ptr);
    uColorLoc = glGetUniformLocation(program, "uColor\0".ptr);
    uTextureLoc = glGetUniformLocation(program, "uTexture\0".ptr);

    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);

    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);

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
  }

  void destroy() {
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
  }

  void drawTexture(
    GLuint texId,
    in RectF destRect,
    in ColorF color,
    float vw,
    float vh
  ) {
    if (texId == 0) {
      return;
    }

    setup2DBlendState();
    glUseProgram(program);
    glUniform2f(uResolutionLoc, vw, vh);
    glUniform4f(uColorLoc, color.r, color.g, color.b, color.a);
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

    uploadAndDrawDynamic(GL_TRIANGLES, vao, vbo, vertices, 6);
    glBindTexture(GL_TEXTURE_2D, 0);
  }
}

/**
 * Shader pipeline for antialiased, outline, and dashed rounded rectangles.
 */
struct RoundRectPipeline {
  GLuint program;
  GLuint vao;
  GLuint vbo;
  GLint uResolutionLoc = -1;
  GLint uColorLoc = -1;
  GLint uHalfSizeLoc = -1;
  GLint uRadiusLoc = -1;
  GLint uLineWidthLoc = -1;
  GLint uDashLenLoc = -1;
  GLint uGapLenLoc = -1;
  GLint uPixelSizeLoc = -1;

  void initialize() {
    enum string rrVertexShaderSource =
      import("yguilib/shaders/roundrect.vert.glsl");
    enum string rrFragmentShaderSource =
      import("yguilib/shaders/roundrect.frag.glsl");

    GLuint rrVert = compileShader(GL_VERTEX_SHADER, rrVertexShaderSource);
    scope(exit) glDeleteShader(rrVert);

    GLuint rrFrag = compileShader(GL_FRAGMENT_SHADER, rrFragmentShaderSource);
    scope(exit) glDeleteShader(rrFrag);

    program = linkProgram(rrVert, rrFrag);
    uResolutionLoc = glGetUniformLocation(program, "uResolution\0".ptr);
    uColorLoc = glGetUniformLocation(program, "uColor\0".ptr);
    uHalfSizeLoc = glGetUniformLocation(program, "uHalfSize\0".ptr);
    uRadiusLoc = glGetUniformLocation(program, "uRadius\0".ptr);
    uLineWidthLoc = glGetUniformLocation(program, "uLineWidth\0".ptr);
    uDashLenLoc = glGetUniformLocation(program, "uDashLen\0".ptr);
    uGapLenLoc = glGetUniformLocation(program, "uGapLen\0".ptr);
    uPixelSizeLoc = glGetUniformLocation(program, "uPixelSize\0".ptr);

    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);

    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);

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
  }

  void destroy() {
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
  }

  void draw(
    in RectF rect,
    float radius,
    float lineWidth,
    float dashLen,
    float gapLen,
    in ColorF color,
    float vw,
    float vh,
    float totalScale
  ) {
    float halfW = rect.width * 0.5f;
    float halfH = rect.height * 0.5f;
    import std.algorithm : min;
    float r = min(radius, min(halfW, halfH));
    if (r < 0.0f) {
      r = 0.0f;
    }

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

    setup2DBlendState();
    glUseProgram(program);
    glUniform2f(uResolutionLoc, vw, vh);
    glUniform4f(uColorLoc, color.r, color.g, color.b, color.a);
    glUniform2f(uHalfSizeLoc, halfW, halfH);
    glUniform1f(uRadiusLoc, r);
    glUniform1f(uLineWidthLoc, lineWidth);
    glUniform1f(uDashLenLoc, dashLen);
    glUniform1f(uGapLenLoc, gapLen);
    glUniform1f(uPixelSizeLoc, px);

    uploadAndDrawDynamic(GL_TRIANGLES, vao, vbo, vertices, 6);
  }
}
