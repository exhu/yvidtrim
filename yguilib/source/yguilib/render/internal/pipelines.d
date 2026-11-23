module yguilib.render.internal.pipelines;

package(yguilib):

import glad2.gles2;
import std.array : Appender;
import yguilib.render.internal.gl_util;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.render.texture : Texture;
import yguilib.internal.assets;

/**
 * Shader pipeline for flat color primitives (triangles, lines, line loops).
 */
struct ColorPipeline {
  ProgramMesh mesh;
  GLint uResolutionLoc = -1;
  GLint uColorLoc = -1;

  /// `programs` (the renderer's program tracker) must outlive the pipeline.
  void initialize(ProgramTracker* programs) {
    assert(programs !is null);
    fPrograms = programs;
    mesh = ProgramMesh.vec2(colorVertexShaderSource,
      colorFragmentShaderSource);
    uResolutionLoc = mesh.uniform("uResolution\0");
    uColorLoc = mesh.uniform("uColor\0");
  }

  void destroy() {
    mesh.destroy();
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
    fPrograms.use(mesh.program);
    fResolution.upload(uResolutionLoc, vw, vh, fPrograms.epoch());
    glUniform4f(uColorLoc, color.r, color.g, color.b, color.a);
    uploadAndDrawDynamic(
      mode,
      mesh.va,
      vertices,
      cast(GLsizei)(vertices.length / 2)
    );
  }

  void drawFillRect(in RectF rect, in ColorF color, float vw, float vh) {
    const float[12] vertices = rectTriangles(rect);
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

    fDashScratch.clear();
    const float period = dashLen + gapLen;
    const size_t estDashes = cast(size_t)(dist / period) + 1;
    fDashScratch.reserve(estDashes * 12);

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
        fDashScratch.put(dashQuad[]);
      }
      cur += period;
    }

    if (fDashScratch[].length > 0) {
      drawArrays(GL_TRIANGLES, fDashScratch[], color, vw, vh);
    }
  }

  /// Reused vertex buffer of `drawDashedThickLine` (cleared per call).
  Appender!(float[]) fDashScratch;
  ProgramTracker* fPrograms;
  Vec2UniformCache fResolution;
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
  ProgramMesh mesh;
  GLint uResolutionLoc = -1;
  GLint uColorLoc = -1;
  GLint uTextureLoc = -1;
  GLint uModeLoc = -1;

  /// `programs` (the renderer's program tracker) must outlive the pipeline.
  void initialize(ProgramTracker* programs) {
    assert(programs !is null);
    fPrograms = programs;
    mesh = ProgramMesh.vec4(texVertexShaderSource, texFragmentShaderSource);
    uResolutionLoc = mesh.uniform("uResolution\0");
    uColorLoc = mesh.uniform("uColor\0");
    uTextureLoc = mesh.uniform("uTexture\0");
    uModeLoc = mesh.uniform("uMode\0");
  }

  void destroy() {
    mesh.destroy();
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
    fPrograms.use(mesh.program);
    fResolution.upload(uResolutionLoc, vw, vh, fPrograms.epoch());
    glUniform4f(uColorLoc, color.r, color.g, color.b, color.a);
    glUniform1i(uTextureLoc, 0);
    glUniform1i(uModeLoc, cast(GLint)mode);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texId);
    uploadAndDrawDynamic(
      GL_TRIANGLES, mesh.va, xyuv, cast(GLsizei)(xyuv.length / 4)
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

private:
  ProgramTracker* fPrograms;
  Vec2UniformCache fResolution;
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

/// Two vec2 triangles covering `r` (same corner order as `quadVertices`).
float[12] rectTriangles(in RectF r) nothrow @safe @nogc pure {
  const float x0 = r.x;
  const float y0 = r.y;
  const float x1 = r.x + r.width;
  const float y1 = r.y + r.height;
  return [x0, y0, x1, y0, x0, y1, x0, y1, x1, y0, x1, y1];
}

/// `TextureMode` sampling texture `t` as an image (not as a mask).
TextureMode textureModeFor(const Texture t) {
  assert(t !is null);
  return t.premultiplied() ? TextureMode.premultiplied : TextureMode.straight;
}

/**
 * Logic size of the bound viewport and the total scaling (logic units to
 * pixels) that a draw needs.
 */
struct Viewport {
  float vw;
  float vh;
  float scale;
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
  ProgramMesh mesh;
  GLint uResolutionLoc = -1;
  GLint uTextureLoc = -1;
  GLint uDirectionLoc = -1;
  GLint uSigmaLoc = -1;
  GLint uUvMinLoc = -1;
  GLint uUvMaxLoc = -1;

  /// `programs` (the renderer's program tracker) must outlive the pipeline.
  void initialize(ProgramTracker* programs) {
    assert(programs !is null);
    fPrograms = programs;
    mesh = ProgramMesh.vec4(texVertexShaderSource, blurFragmentShaderSource);
    uResolutionLoc = mesh.uniform("uResolution\0");
    uTextureLoc = mesh.uniform("uTexture\0");
    uDirectionLoc = mesh.uniform("uDirection\0");
    uSigmaLoc = mesh.uniform("uSigma\0");
    uUvMinLoc = mesh.uniform("uUvMin\0");
    uUvMaxLoc = mesh.uniform("uUvMax\0");
  }

  void destroy() {
    mesh.destroy();
  }

  /**
   * Runs pass `p` with blending disabled (it overwrites the region);
   * the viewport must be `(0, 0, p.width, p.height)`.
   */
  void draw(in BlurPass p) {
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glDisable(GL_BLEND);
    fPrograms.use(mesh.program);
    const float w = p.width;
    const float h = p.height;
    const float tw = p.textureWidth;
    const float th = p.textureHeight;
    fResolution.upload(uResolutionLoc, w, h, fPrograms.epoch());
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
    uploadAndDrawDynamic(GL_TRIANGLES, mesh.va, vertices, 6);
    glBindTexture(GL_TEXTURE_2D, 0);
    // the next draw re-enables blending via setupAlphaBlendState
  }

private:
  ProgramTracker* fPrograms;
  Vec2UniformCache fResolution;
}

/**
 * Shader pipeline for antialiased, outline, and dashed rounded rectangles.
 */
struct RoundRectPipeline {
  ProgramMesh mesh;
  GLint uResolutionLoc = -1;
  GLint uColorLoc = -1;
  GLint uHalfSizeLoc = -1;
  GLint uRadiusLoc = -1;
  GLint uLineWidthLoc = -1;
  GLint uDashLenLoc = -1;
  GLint uGapLenLoc = -1;
  GLint uPixelSizeLoc = -1;

  /// `programs` (the renderer's program tracker) must outlive the pipeline.
  void initialize(ProgramTracker* programs) {
    assert(programs !is null);
    fPrograms = programs;
    mesh = ProgramMesh.vec4(rrVertexShaderSource, rrFragmentShaderSource);
    uResolutionLoc = mesh.uniform("uResolution\0");
    uColorLoc = mesh.uniform("uColor\0");
    uHalfSizeLoc = mesh.uniform("uHalfSize\0");
    uRadiusLoc = mesh.uniform("uRadius\0");
    uLineWidthLoc = mesh.uniform("uLineWidth\0");
    uDashLenLoc = mesh.uniform("uDashLen\0");
    uGapLenLoc = mesh.uniform("uGapLen\0");
    uPixelSizeLoc = mesh.uniform("uPixelSize\0");
  }

  void destroy() {
    mesh.destroy();
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
    fPrograms.use(mesh.program);
    fResolution.upload(uResolutionLoc, vw, vh, fPrograms.epoch());
    glUniform4f(uColorLoc, color.r, color.g, color.b, color.a);
    glUniform2f(uHalfSizeLoc, halfW, halfH);
    glUniform1f(uRadiusLoc, r);
    glUniform1f(uLineWidthLoc, lineWidth);
    glUniform1f(uDashLenLoc, dashLen);
    glUniform1f(uGapLenLoc, gapLen);
    glUniform1f(uPixelSizeLoc, px);

    uploadAndDrawDynamic(GL_TRIANGLES, mesh.va, vertices, 6);
  }

private:
  ProgramTracker* fPrograms;
  Vec2UniformCache fResolution;
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
 * Uniform locations of one `GradientPipeline` program and the last
 * uploaded resolution and color stops (see `set`).
 */
struct GradientLocs {
  GLint uResolution = -1;
  GLint uKind = -1;
  GLint uInvXf = -1;
  GLint uP0 = -1;
  GLint uP1 = -1;
  GLint uR0 = -1;
  GLint uR1 = -1;
  GLint uStopColors = -1;
  GLint uStopOffsets = -1;
  GLint uStopCount = -1;
  GLint uMask = -1;

  static GradientLocs query(GLuint program) {
    GradientLocs l;
    l.uResolution = glGetUniformLocation(program, "uResolution\0".ptr);
    l.uKind = glGetUniformLocation(program, "uKind\0".ptr);
    l.uInvXf = glGetUniformLocation(program, "uInvXf\0".ptr);
    l.uP0 = glGetUniformLocation(program, "uP0\0".ptr);
    l.uP1 = glGetUniformLocation(program, "uP1\0".ptr);
    l.uR0 = glGetUniformLocation(program, "uR0\0".ptr);
    l.uR1 = glGetUniformLocation(program, "uR1\0".ptr);
    l.uStopColors = glGetUniformLocation(program, "uStopColors\0".ptr);
    l.uStopOffsets = glGetUniformLocation(program, "uStopOffsets\0".ptr);
    l.uStopCount = glGetUniformLocation(program, "uStopCount\0".ptr);
    l.uMask = glGetUniformLocation(program, "uMask\0".ptr);
    return l;
  }

  /**
   * Uploads `u` and the resolution to the current program (the one these
   * locations belong to). The resolution and the stops (colors, offsets,
   * count) are skipped when equal to the last upload in the same
   * `ProgramTracker` `epoch`.
   */
  void set(in GradientUniforms u, float vw, float vh, uint epoch) {
    fResolution.upload(uResolution, vw, vh, epoch);
    glUniform1i(uKind, u.kind);
    glUniformMatrix3fv(uInvXf, 1, GL_FALSE, u.invXf.ptr);
    glUniform2f(uP0, u.p0.x, u.p0.y);
    glUniform2f(uP1, u.p1.x, u.p1.y);
    glUniform1f(uR0, u.r0);
    glUniform1f(uR1, u.r1);
    if (epoch == fStopsEpoch && u.stopCount == fStopCount
      && u.stopColors == fStopColors && u.stopOffsets == fStopOffsets) {
      return;
    }
    glUniform4fv(uStopColors, GradientUniforms.maxStops, u.stopColors.ptr);
    glUniform1fv(uStopOffsets, GradientUniforms.maxStops,
      u.stopOffsets.ptr);
    glUniform1i(uStopCount, u.stopCount);
    fStopColors = u.stopColors;
    fStopOffsets = u.stopOffsets;
    fStopCount = u.stopCount;
    fStopsEpoch = epoch;
  }

  version (unittest) {
    /// Epoch of the last stop upload (0: none yet); tests of the cache.
    uint stopsEpoch() const {
      return fStopsEpoch;
    }
  }

private:
  Vec2UniformCache fResolution;
  /// Copy of the last uploaded stops (NaN initially: never equal).
  float[4 * GradientUniforms.maxStops] fStopColors;
  float[GradientUniforms.maxStops] fStopOffsets;
  int fStopCount;
  uint fStopsEpoch;
}

/**
 * Shader pipeline for linear and radial gradient paint over vec2
 * triangles in logic coordinates. A second program variant modulates the
 * alpha by a mask texture over (x, y, u, v) vertices (`drawMasked`).
 */
struct GradientPipeline {
  ProgramMesh mesh;
  GradientLocs locs;
  ProgramMesh maskMesh;
  GradientLocs maskLocs;

  /// `programs` (the renderer's program tracker) must outlive the pipeline.
  void initialize(ProgramTracker* programs) {
    assert(programs !is null);
    fPrograms = programs;
    mesh = ProgramMesh.vec2(paintVertexShaderSource,
      paintFragmentShaderSource);
    locs = GradientLocs.query(mesh.program);

    maskMesh = ProgramMesh.vec4(paintMaskVertexShaderSource,
      withMaskDefine!paintFragmentShaderSource);
    maskLocs = GradientLocs.query(maskMesh.program);
  }

  void destroy() {
    mesh.destroy();
    maskMesh.destroy();
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
    fPrograms.use(mesh.program);
    locs.set(u, vw, vh, fPrograms.epoch());
    uploadAndDrawDynamic(
      GL_TRIANGLES,
      mesh.va,
      vertices,
      cast(GLsizei)(vertices.length / 2)
    );
  }

  /**
   * Draws (x, y, u, v) triangles with alpha blending; the paint alpha is
   * multiplied by the alpha of `maskTexId` at (u, v). Stencil state is
   * left unchanged. `maskTexId` 0 or fewer than 3 vertices draw nothing.
   */
  void drawMasked(
    const(float)[] xyuv,
    GLuint maskTexId,
    in GradientUniforms u,
    float vw,
    float vh
  ) {
    if (maskTexId == 0 || xyuv.length < 12) {
      return;
    }
    setupAlphaBlendState();
    fPrograms.use(maskMesh.program);
    maskLocs.set(u, vw, vh, fPrograms.epoch());
    glUniform1i(maskLocs.uMask, 0);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, maskTexId);
    uploadAndDrawDynamic(
      GL_TRIANGLES, maskMesh.va, xyuv, cast(GLsizei)(xyuv.length / 4)
    );
    glBindTexture(GL_TEXTURE_2D, 0);
  }

private:
  ProgramTracker* fPrograms;
}

/// Uniform values of `PatternPipeline` (see `pattern.frag.glsl`).
struct PatternUniforms {
  GLuint textureId;
  /// Logic to normalized tile UV (top-left [0, 1]) as column-major mat3.
  float[9] invXf = [1, 0, 0, 0, 1, 0, 0, 0, 1];
  /// Straight-alpha tint color.
  ColorF tint = ColorF(1, 1, 1, 1);
  /// Repeat mask: bit 0 = repeat X, bit 1 = repeat Y (0..3).
  int repeat;
  TextureMode mode = TextureMode.straight;
  /// True for GL bottom-up render target textures.
  bool bottomUp;
}

/**
 * Uniform locations of one `PatternPipeline` program and its last
 * uploaded resolution (see `set`). `uMask` is -1 for the unmasked
 * program.
 */
struct PatternLocs {
  GLint uResolution = -1;
  GLint uTexture = -1;
  GLint uInvXf = -1;
  GLint uTint = -1;
  GLint uRepeat = -1;
  GLint uMode = -1;
  GLint uBottomUp = -1;
  GLint uMask = -1;

  static PatternLocs query(GLuint program) {
    PatternLocs l;
    l.uResolution = glGetUniformLocation(program, "uResolution\0".ptr);
    l.uTexture = glGetUniformLocation(program, "uTexture\0".ptr);
    l.uInvXf = glGetUniformLocation(program, "uInvXf\0".ptr);
    l.uTint = glGetUniformLocation(program, "uTint\0".ptr);
    l.uRepeat = glGetUniformLocation(program, "uRepeat\0".ptr);
    l.uMode = glGetUniformLocation(program, "uMode\0".ptr);
    l.uBottomUp = glGetUniformLocation(program, "uBottomUp\0".ptr);
    l.uMask = glGetUniformLocation(program, "uMask\0".ptr);
    return l;
  }

  /**
   * Uploads `u` (pattern texture on unit 0) and the resolution to the
   * current program (the one these locations belong to); the resolution
   * is skipped when unchanged in the same `ProgramTracker` `epoch`.
   */
  void set(in PatternUniforms u, float vw, float vh, uint epoch) {
    fResolution.upload(uResolution, vw, vh, epoch);
    glUniform1i(uTexture, 0);
    glUniformMatrix3fv(uInvXf, 1, GL_FALSE, u.invXf.ptr);
    glUniform4f(uTint, u.tint.r, u.tint.g, u.tint.b, u.tint.a);
    glUniform1i(uRepeat, u.repeat & 3);
    glUniform1i(uMode, cast(GLint)u.mode);
    glUniform1i(uBottomUp, u.bottomUp ? 1 : 0);
  }

private:
  Vec2UniformCache fResolution;
}

/**
 * Shader pipeline for image pattern paint over vec2 triangles in logic
 * coordinates.
 */
struct PatternPipeline {
  ProgramMesh mesh;
  PatternLocs locs;
  ProgramMesh maskMesh;
  PatternLocs maskLocs;
  GLuint[4] samplers;

  /// `programs` (the renderer's program tracker) must outlive the pipeline.
  void initialize(ProgramTracker* programs) {
    assert(programs !is null);
    fPrograms = programs;
    mesh = ProgramMesh.vec2(
      paintVertexShaderSource, patternFragmentShaderSource
    );
    locs = PatternLocs.query(mesh.program);
    maskMesh = ProgramMesh.vec4(
      paintMaskVertexShaderSource,
      withMaskDefine!patternFragmentShaderSource
    );
    maskLocs = PatternLocs.query(maskMesh.program);

    glGenSamplers(4, samplers.ptr);
    foreach (i; 0 .. 4) {
      glSamplerParameteri(samplers[i], GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      glSamplerParameteri(samplers[i], GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      const GLint wrapS = (i & 1) ? GL_REPEAT : GL_CLAMP_TO_EDGE;
      const GLint wrapT = (i & 2) ? GL_REPEAT : GL_CLAMP_TO_EDGE;
      glSamplerParameteri(samplers[i], GL_TEXTURE_WRAP_S, wrapS);
      glSamplerParameteri(samplers[i], GL_TEXTURE_WRAP_T, wrapT);
    }
  }

  void destroy() {
    if (samplers[0] != 0) {
      glDeleteSamplers(4, samplers.ptr);
      samplers = 0;
    }
    mesh.destroy();
    maskMesh.destroy();
  }

  /**
   * Draws (x, y, u, v) triangles with the blending for `u.mode`; the paint
   * is multiplied by the alpha of `maskTexId` at (u, v) (texture unit 1).
   * Stencil state is left unchanged. `u.textureId` or `maskTexId` 0 or
   * fewer than 3 vertices draw nothing.
   */
  void drawMasked(
    const(float)[] xyuv,
    GLuint maskTexId,
    in PatternUniforms u,
    float vw,
    float vh
  ) {
    if (u.textureId == 0 || maskTexId == 0 || xyuv.length < 12) {
      return;
    }
    TexturePipeline.setupBlendForMode(u.mode);
    fPrograms.use(maskMesh.program);
    maskLocs.set(u, vw, vh, fPrograms.epoch());
    glUniform1i(maskLocs.uMask, 1);

    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, maskTexId);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, u.textureId);
    glBindSampler(0, samplers[u.repeat & 3]);
    uploadAndDrawDynamic(
      GL_TRIANGLES, maskMesh.va, xyuv, cast(GLsizei)(xyuv.length / 4)
    );
    glBindSampler(0, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, 0);
    glActiveTexture(GL_TEXTURE0);
  }

  /// Draws triangles with the blending for `u.mode`; stencil state is left
  /// unchanged. `u.textureId` 0 or fewer than 3 vertices draw nothing.
  void drawTriangles(
    const(float)[] vertices,
    in PatternUniforms u,
    float vw,
    float vh
  ) {
    if (u.textureId == 0 || vertices.length < 6) {
      return;
    }
    TexturePipeline.setupBlendForMode(u.mode);
    drawTrianglesWithCurrentState(vertices, u, vw, vh);
  }

  /**
   * Like `drawTriangles` but keeps the current blend, cull and depth state
   * (e.g. blending disabled to write paint alpha into a shadow mask).
   */
  void drawTrianglesWithCurrentState(
    const(float)[] vertices,
    in PatternUniforms u,
    float vw,
    float vh
  ) {
    if (u.textureId == 0 || vertices.length < 6) {
      return;
    }
    fPrograms.use(mesh.program);
    locs.set(u, vw, vh, fPrograms.epoch());

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, u.textureId);
    glBindSampler(0, samplers[u.repeat & 3]);
    uploadAndDrawDynamic(
      GL_TRIANGLES,
      mesh.va,
      vertices,
      cast(GLsizei)(vertices.length / 2)
    );
    glBindSampler(0, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
  }

private:
  ProgramTracker* fPrograms;
}
