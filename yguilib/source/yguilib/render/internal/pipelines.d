module yguilib.render.internal.pipelines;

package(yguilib):

import glad2.gles2;
import yguilib.render.internal.gl_util;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.internal.assets;

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
    program = buildProgram(colorVertexShaderSource,
      colorFragmentShaderSource);
    uResolutionLoc = glGetUniformLocation(program, "uResolution\0".ptr);
    uColorLoc = glGetUniformLocation(program, "uColor\0".ptr);

    const VertexArrayHandles h = createVec2VertexArray();
    vao = h.vao;
    vbo = h.vbo;
  }

  void destroy() {
    destroyProgramAndBuffers(program, vao, vbo);
  }

  /// Draws with alpha blending (see `setupAlphaBlendState`); stencil state
  /// is left unchanged.
  void drawArrays(
    GLenum mode,
    const(float)[] vertices,
    in ColorF color,
    float vw,
    float vh
  ) {
    setupAlphaBlendState();
    drawArraysWithCurrentState(mode, vertices, color, vw, vh);
  }

  /**
   * Like `drawArrays` but keeps the current blend, cull and depth state
   * (e.g. blending disabled to overwrite pixels in `Canvas.clearRect`).
   */
  void drawArraysWithCurrentState(
    GLenum mode,
    const(float)[] vertices,
    in ColorF color,
    float vw,
    float vh
  ) {
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

  void drawThinLineWithPoints(
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

  void drawLineWithWidth(
    in PointF point1,
    in PointF point2,
    float lineWidth,
    in ColorF color,
    float vw,
    float vh
  ) {
    drawDashedLineWithPoints(
      point1, point2, lineWidth, 0.0f, 0.0f, color, vw, vh
    );
  }

  void drawDashedLineWithPoints(
    in PointF point1,
    in PointF point2,
    float lineWidth,
    float dashLen,
    float gapLen,
    in ColorF color,
    float vw,
    float vh
  ) {
    if (lineWidth <= 0.0f) {
      return;
    }

    import std.math : sqrt;
    const float dx = point2.x - point1.x;
    const float dy = point2.y - point1.y;
    const float dist = sqrt(dx * dx + dy * dy);
    if (dist <= 0.0f) {
      return;
    }

    const float invDist = 1.0f / dist;
    const float ux = dx * invDist;
    const float uy = dy * invDist;
    const float halfWidth = lineWidth * 0.5f;
    const float ox = -uy * halfWidth;
    const float oy = ux * halfWidth;

    if (dashLen <= 0.0f || gapLen <= 0.0f) {
      drawSolidThickLine(point1, point2, ox, oy, color, vw, vh);
      return;
    }
    drawDashedThickLine(
      point1, ux, uy, dist, ox, oy, dashLen, gapLen, color, vw, vh
    );
  }

  void drawRectWithWidth(
    in RectF rect,
    float lineWidth,
    in ColorF color,
    float vw,
    float vh
  ) {
    if (rect.width <= 0.0f || rect.height <= 0.0f || lineWidth <= 0.0f) {
      return;
    }

    import std.algorithm : min;
    float maxLw = min(rect.width, rect.height) * 0.5f;
    float lw = min(lineWidth, maxLw);

    float x0 = rect.x;
    float y0 = rect.y;
    float x1 = rect.x + rect.width;
    float y1 = rect.y + rect.height;
    float xi0 = x0 + lw;
    float yi0 = y0 + lw;
    float xi1 = x1 - lw;
    float yi1 = y1 - lw;

    // 4 non-overlapping strips growing inside rect
    float[48] vertices = [
      // Top strip
      x0, y0,  x1, y0,  x0, yi0,
      x0, yi0, x1, y0,  x1, yi0,

      // Bottom strip
      x0, yi1, x1, yi1, x0, y1,
      x0, y1,  x1, yi1, x1, y1,

      // Left strip
      x0, yi0,  xi0, yi0, x0, yi1,
      x0, yi1,  xi0, yi0, xi0, yi1,

      // Right strip
      xi1, yi0, x1, yi0,  xi1, yi1,
      xi1, yi1, x1, yi0,  x1, yi1,
    ];

    drawArrays(GL_TRIANGLES, vertices, color, vw, vh);
  }

  void drawRectDefaultWidth(
    in RectF rect,
    in ColorF color,
    float vw,
    float vh
  ) {
    drawRectWithWidth(rect, 1.0f, color, vw, vh);
  }

private:
  void drawSolidThickLine(
    in PointF point1,
    in PointF point2,
    float ox,
    float oy,
    in ColorF color,
    float vw,
    float vh
  ) {
    float[12] vertices = [
      point1.x + ox, point1.y + oy,
      point1.x - ox, point1.y - oy,
      point2.x - ox, point2.y - oy,

      point1.x + ox, point1.y + oy,
      point2.x - ox, point2.y - oy,
      point2.x + ox, point2.y + oy,
    ];
    drawArrays(GL_TRIANGLES, vertices, color, vw, vh);
  }

  void drawDashedThickLine(
    in PointF point1,
    float ux,
    float uy,
    float dist,
    float ox,
    float oy,
    float dashLen,
    float gapLen,
    in ColorF color,
    float vw,
    float vh
  ) {
    import std.algorithm : min;
    import std.array : Appender;

    Appender!(float[]) vertices;
    const float period = dashLen + gapLen;
    const size_t estDashes = cast(size_t)(dist / period) + 1;
    vertices.reserve(estDashes * 12);

    float cur = 0.0f;
    while (cur < dist) {
      const float dStart = cur;
      const float dEnd = min(cur + dashLen, dist);
      if (dEnd > dStart) {
        const float sx = point1.x + ux * dStart;
        const float sy = point1.y + uy * dStart;
        const float ex = point1.x + ux * dEnd;
        const float ey = point1.y + uy * dEnd;

        float[12] dashQuad = [
          sx + ox, sy + oy,
          sx - ox, sy - oy,
          ex - ox, ey - oy,

          sx + ox, sy + oy,
          ex - ox, ey - oy,
          ex + ox, ey + oy,
        ];
        vertices.put(dashQuad[]);
      }
      cur += period;
    }

    if (vertices.data.length > 0) {
      drawArrays(GL_TRIANGLES, vertices.data, color, vw, vh);
    }
  }
}

/**
 * How `TexturePipeline` combines the texture with the tint color (matches
 * `uMode` in `texture.frag.glsl`).
 */
enum TextureMode {
  /// Straight-alpha texture: `tex * color`, straight-alpha blending.
  straight = 0,
  /**
   * Premultiplied texture (e.g. a render target): `tex * (color.rgb *
   * color.a, color.a)`, blended with `ONE, ONE_MINUS_SRC_ALPHA`.
   */
  premultiplied = 1,
  /// White with alpha `tex.a * color.a` (shadow masks), straight blending.
  alphaMask = 2,
}

/**
 * Shader pipeline for textured 2D quads and triangles.
 */
struct TexturePipeline {
  GLuint program;
  GLuint vao;
  GLuint vbo;
  GLint uResolutionLoc = -1;
  GLint uColorLoc = -1;
  GLint uTextureLoc = -1;
  GLint uModeLoc = -1;

  void initialize() {
    GLuint texVert = compileShader(GL_VERTEX_SHADER, texVertexShaderSource);
    scope(exit) glDeleteShader(texVert);

    GLuint texFrag = compileShader(GL_FRAGMENT_SHADER, texFragmentShaderSource);
    scope(exit) glDeleteShader(texFrag);

    program = linkProgram(texVert, texFrag);
    uResolutionLoc = glGetUniformLocation(program, "uResolution\0".ptr);
    uColorLoc = glGetUniformLocation(program, "uColor\0".ptr);
    uTextureLoc = glGetUniformLocation(program, "uTexture\0".ptr);
    uModeLoc = glGetUniformLocation(program, "uMode\0".ptr);

    const VertexArrayHandles h = createVec4VertexArray();
    vao = h.vao;
    vbo = h.vbo;
  }

  void destroy() {
    destroyProgramAndBuffers(program, vao, vbo);
  }

  /// Draws a whole straight-alpha texture stretched to `destRect`.
  void drawTexture(
    GLuint texId,
    in RectF destRect,
    in ColorF color,
    float vw,
    float vh
  ) {
    drawTexturedQuad(
      texId, TexturedQuad(destRect, RectF(0, 0, 1, 1), color), vw, vh,
      TextureMode.straight
    );
  }

  /**
   * Draws `q` with the blending for `mode` (see `setupBlendForMode`);
   * stencil state is left unchanged. `texId` 0 draws nothing.
   */
  void drawTexturedQuad(
    GLuint texId,
    in TexturedQuad q,
    float vw,
    float vh,
    TextureMode mode
  ) {
    if (texId == 0) {
      return;
    }
    setupBlendForMode(mode);
    drawTexturedQuadWithCurrentState(texId, q, vw, vh, mode);
  }

  /**
   * Like `drawTexturedQuad` but keeps the current blend, cull and depth
   * state.
   */
  void drawTexturedQuadWithCurrentState(
    GLuint texId,
    in TexturedQuad q,
    float vw,
    float vh,
    TextureMode mode
  ) {
    const float[24] vertices = quadVertices(q.dest, q.uv);
    drawTexturedTrianglesWithCurrentState(
      texId, vertices[], q.color, mode, vw, vh
    );
  }

  /**
   * Draws triangles of interleaved (x, y, u, v) vertices (x, y in logic
   * coordinates) sampling `texId`, combined with `color` per `mode`, with
   * the blending for `mode`; stencil state is left unchanged. `texId` 0
   * or fewer than 3 vertices draw nothing.
   */
  void drawTexturedTriangles(
    GLuint texId,
    const(float)[] xyuv,
    in ColorF color,
    TextureMode mode,
    float vw,
    float vh
  ) {
    if (texId == 0 || xyuv.length < 12) {
      return;
    }
    setupBlendForMode(mode);
    drawTexturedTrianglesWithCurrentState(texId, xyuv, color, mode, vw, vh);
  }

  /**
   * Like `drawTexturedTriangles` but keeps the current blend, cull and
   * depth state (e.g. blending disabled to write a shadow mask).
   */
  void drawTexturedTrianglesWithCurrentState(
    GLuint texId,
    const(float)[] xyuv,
    in ColorF color,
    TextureMode mode,
    float vw,
    float vh
  ) {
    if (texId == 0 || xyuv.length < 12) {
      return;
    }
    glUseProgram(program);
    glUniform2f(uResolutionLoc, vw, vh);
    glUniform4f(uColorLoc, color.r, color.g, color.b, color.a);
    glUniform1i(uTextureLoc, 0);
    glUniform1i(uModeLoc, cast(GLint)mode);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texId);
    uploadAndDrawDynamic(
      GL_TRIANGLES, vao, vbo, xyuv, cast(GLsizei)(xyuv.length / 4)
    );
    glBindTexture(GL_TEXTURE_2D, 0);
  }

  /**
   * Premultiplied mode uses `setupPremultipliedBlendState`, the others
   * `setupAlphaBlendState`.
   */
  static void setupBlendForMode(TextureMode mode) {
    if (mode == TextureMode.premultiplied) {
      setupPremultipliedBlendState();
    } else {
      setupAlphaBlendState();
    }
  }
}

/**
 * Textured quad: `dest` in logic coordinates, `uv` the texture rectangle
 * mapped onto it (top-left of `dest` gets `uv.x, uv.y`; a negative
 * `uv.height` flips vertically), tinted by multiplying with `color`.
 */
struct TexturedQuad {
  RectF dest;
  RectF uv;
  ColorF color;
}

/// Two triangles of interleaved (x, y, u, v) for `dest` mapped to `uv`.
float[24] quadVertices(in RectF dest, in RectF uv) {
  const float x0 = dest.x;
  const float y0 = dest.y;
  const float x1 = dest.x + dest.width;
  const float y1 = dest.y + dest.height;
  const float u0 = uv.x;
  const float v0 = uv.y;
  const float u1 = uv.x + uv.width;
  const float v1 = uv.y + uv.height;
  return [
    x0, y0, u0, v0,
    x1, y0, u1, v0,
    x0, y1, u0, v1,
    x0, y1, u0, v1,
    x1, y0, u1, v0,
    x1, y1, u1, v1,
  ];
}

/**
 * One pass of `BlurPipeline`: blurs the region `(0, 0, width, height)` of
 * `source` (allocated `textureWidth` x `textureHeight`) along one axis
 * into the same region of the bound framebuffer.
 */
struct BlurPass {
  GLuint source;
  int width;
  int height;
  int textureWidth;
  int textureHeight;
  /// false: horizontal, true: vertical.
  bool vertical;
  /// Gaussian standard deviation in pixels (> 0).
  float sigma;
}

/**
 * Separable Gaussian blur of the alpha channel (`blur.frag.glsl`) with the
 * texture vertex layout. Writes white with the blurred alpha.
 */
struct BlurPipeline {
  GLuint program;
  GLuint vao;
  GLuint vbo;
  GLint uResolutionLoc = -1;
  GLint uTextureLoc = -1;
  GLint uDirectionLoc = -1;
  GLint uSigmaLoc = -1;
  GLint uUvMinLoc = -1;
  GLint uUvMaxLoc = -1;

  void initialize() {
    program = buildProgram(texVertexShaderSource, blurFragmentShaderSource);
    uResolutionLoc = glGetUniformLocation(program, "uResolution\0".ptr);
    uTextureLoc = glGetUniformLocation(program, "uTexture\0".ptr);
    uDirectionLoc = glGetUniformLocation(program, "uDirection\0".ptr);
    uSigmaLoc = glGetUniformLocation(program, "uSigma\0".ptr);
    uUvMinLoc = glGetUniformLocation(program, "uUvMin\0".ptr);
    uUvMaxLoc = glGetUniformLocation(program, "uUvMax\0".ptr);

    const VertexArrayHandles h = createVec4VertexArray();
    vao = h.vao;
    vbo = h.vbo;
  }

  void destroy() {
    destroyProgramAndBuffers(program, vao, vbo);
  }

  /**
   * Runs pass `p` with blending disabled (it overwrites the region);
   * the viewport must be `(0, 0, p.width, p.height)`.
   */
  void draw(in BlurPass p) {
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glDisable(GL_BLEND);
    glUseProgram(program);
    const float w = p.width;
    const float h = p.height;
    const float tw = p.textureWidth;
    const float th = p.textureHeight;
    glUniform2f(uResolutionLoc, w, h);
    glUniform1i(uTextureLoc, 0);
    if (p.vertical) {
      glUniform2f(uDirectionLoc, 0, 1.0f / th);
    } else {
      glUniform2f(uDirectionLoc, 1.0f / tw, 0);
    }
    glUniform1f(uSigmaLoc, p.sigma);
    glUniform2f(uUvMinLoc, 0.5f / tw, 0.5f / th);
    glUniform2f(uUvMaxLoc, (w - 0.5f) / tw, (h - 0.5f) / th);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, p.source);
    // GL rows grow upward while logic y grows downward: flip v
    const float[24] vertices = quadVertices(
      RectF(0, 0, w, h), RectF(0, h / th, w / tw, -h / th)
    );
    uploadAndDrawDynamic(GL_TRIANGLES, vao, vbo, vertices, 6);
    glBindTexture(GL_TEXTURE_2D, 0);
    // the next draw re-enables blending via setupAlphaBlendState
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

    const VertexArrayHandles h = createVec4VertexArray();
    vao = h.vao;
    vbo = h.vbo;
  }

  void destroy() {
    destroyProgramAndBuffers(program, vao, vbo);
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

    setupAlphaBlendState();
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

/// Uniform values of `GradientPipeline` (see `paint.frag.glsl`).
struct GradientUniforms {
  /// Max color stops (matches `maxStops` in the shader).
  enum maxStops = 8;

  /// 0 linear (`p0` -> `p1`), 1 radial (`p0`, `r0` -> `p1`, `r1`).
  int kind;
  /// Logic to gradient space as column-major mat3.
  float[9] invXf = [1, 0, 0, 0, 1, 0, 0, 0, 1];
  PointF p0;
  PointF p1;
  float r0 = 0;
  float r1 = 0;
  /// Non-premultiplied rgba per stop.
  float[4 * maxStops] stopColors = 0;
  /// Sorted offsets in [0, 1].
  float[maxStops] stopOffsets = 0;
  int stopCount;
}

/**
 * Shader pipeline for linear and radial gradient paint over vec2
 * triangles in logic coordinates.
 */
struct GradientPipeline {
  GLuint program;
  GLuint vao;
  GLuint vbo;
  GLint uResolutionLoc = -1;
  GLint uKindLoc = -1;
  GLint uInvXfLoc = -1;
  GLint uP0Loc = -1;
  GLint uP1Loc = -1;
  GLint uR0Loc = -1;
  GLint uR1Loc = -1;
  GLint uStopColorsLoc = -1;
  GLint uStopOffsetsLoc = -1;
  GLint uStopCountLoc = -1;

  void initialize() {
    program = buildProgram(paintVertexShaderSource,
      paintFragmentShaderSource);
    uResolutionLoc = glGetUniformLocation(program, "uResolution\0".ptr);
    uKindLoc = glGetUniformLocation(program, "uKind\0".ptr);
    uInvXfLoc = glGetUniformLocation(program, "uInvXf\0".ptr);
    uP0Loc = glGetUniformLocation(program, "uP0\0".ptr);
    uP1Loc = glGetUniformLocation(program, "uP1\0".ptr);
    uR0Loc = glGetUniformLocation(program, "uR0\0".ptr);
    uR1Loc = glGetUniformLocation(program, "uR1\0".ptr);
    uStopColorsLoc = glGetUniformLocation(program, "uStopColors\0".ptr);
    uStopOffsetsLoc = glGetUniformLocation(program, "uStopOffsets\0".ptr);
    uStopCountLoc = glGetUniformLocation(program, "uStopCount\0".ptr);

    const VertexArrayHandles h = createVec2VertexArray();
    vao = h.vao;
    vbo = h.vbo;
  }

  void destroy() {
    destroyProgramAndBuffers(program, vao, vbo);
  }

  /// Draws triangles with alpha blending (see `setupAlphaBlendState`);
  /// stencil state is left unchanged.
  void drawTriangles(
    const(float)[] vertices,
    in GradientUniforms u,
    float vw,
    float vh
  ) {
    setupAlphaBlendState();
    drawTrianglesWithCurrentState(vertices, u, vw, vh);
  }

  /**
   * Like `drawTriangles` but keeps the current blend, cull and depth state
   * (e.g. blending disabled to write paint alpha into a shadow mask).
   */
  void drawTrianglesWithCurrentState(
    const(float)[] vertices,
    in GradientUniforms u,
    float vw,
    float vh
  ) {
    glUseProgram(program);
    glUniform2f(uResolutionLoc, vw, vh);
    glUniform1i(uKindLoc, u.kind);
    glUniformMatrix3fv(uInvXfLoc, 1, GL_FALSE, u.invXf.ptr);
    glUniform2f(uP0Loc, u.p0.x, u.p0.y);
    glUniform2f(uP1Loc, u.p1.x, u.p1.y);
    glUniform1f(uR0Loc, u.r0);
    glUniform1f(uR1Loc, u.r1);
    glUniform4fv(uStopColorsLoc, GradientUniforms.maxStops,
      u.stopColors.ptr);
    glUniform1fv(uStopOffsetsLoc, GradientUniforms.maxStops,
      u.stopOffsets.ptr);
    glUniform1i(uStopCountLoc, u.stopCount);
    uploadAndDrawDynamic(
      GL_TRIANGLES,
      vao,
      vbo,
      vertices,
      cast(GLsizei)(vertices.length / 2)
    );
  }
}
