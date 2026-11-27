/**
 * Low-level GL ES helpers for the render pipelines: blend state setup,
 * shader/program creation, `ProgramMesh` (program + streamed vertex
 * array), `uploadAndDrawDynamic` (VBO grown by powers of two, updated
 * with `glBufferSubData`), `ProgramTracker` (current program and the
 * uniform cache epoch), `Vec2UniformCache` and texture upload.
 *
 * New GL code must go through `ProgramTracker.use` and the Renderer's
 * tracked framebuffer/viewport/clear-color setters, and must not touch a
 * pipeline VBO directly, or the debug `Renderer.targetState()` check
 * fails.
 */
module yguilib.render.internal.gl_util;

package(yguilib):

import glad2.gles2;
import yguilib.internal.memstats : telemetryTextureAlloc,
  telemetryTextureFree;

/**
 * Configures common 2D blending state: alpha blending enabled,
 * depth test and face culling disabled.
 *
 * Color uses straight-alpha "over" (`SRC_ALPHA, ONE_MINUS_SRC_ALPHA`)
 * and alpha uses `ONE, ONE_MINUS_SRC_ALPHA`, so the destination alpha
 * accumulates correctly: drawing onto a target cleared to transparent
 * leaves a correct premultiplied result (alpha `a`, not `a * a`).
 * Opaque destinations are unaffected.
 */
void setupAlphaBlendState() {
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);
  glEnable(GL_BLEND);
  glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE,
    GL_ONE_MINUS_SRC_ALPHA);
}

/**
 * Like `setupAlphaBlendState` but for premultiplied-alpha sources
 * (`ONE, ONE_MINUS_SRC_ALPHA` for color and alpha), e.g. render target
 * textures.
 */
void setupPremultipliedBlendState() {
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);
  glEnable(GL_BLEND);
  glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
}

/**
 * Compiles a GLSL shader object from source string.
 */
GLuint compileShader(GLenum type, string source) {
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
    import std.logger : errorf;
    errorf("Shader compile error: %s", log);
    throw new Exception("Shader compile failed: " ~ log);
  }
  return shader;
}

/**
 * Links vertex and fragment shaders into a shader program.
 */
GLuint linkProgram(GLuint vertShader, GLuint fragShader) {
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
    import std.logger : errorf;
    errorf("Program link error: %s", log);
    throw new Exception("Program link failed: " ~ log);
  }
  return prog;
}

/**
 * Uploads dynamic vertex data to the VBO of `va` and issues a draw call.
 * The data goes in with `glBufferSubData` when it fits `va.capacity`;
 * otherwise the buffer is first reallocated (`GL_DYNAMIC_DRAW`) to the
 * next power of two bytes. The VAO and VBO of `va` stay bound afterwards
 * (every draw binds its own VAO; nothing relies on VAO 0).
 */
void uploadAndDrawDynamic(
  GLenum mode,
  ref VertexArrayHandles va,
  const(float)[] vertices,
  GLsizei count
) {
  const size_t bytes = vertices.length * float.sizeof;
  if (bytes == 0) {
    return;
  }
  glBindVertexArray(va.vao);
  glBindBuffer(GL_ARRAY_BUFFER, va.vbo);
  if (bytes > va.capacity) {
    const size_t cap = vboCapacityFor(bytes);
    glBufferData(GL_ARRAY_BUFFER, cast(GLsizeiptr)cap, null,
      GL_DYNAMIC_DRAW);
    va.capacity = cap;
  } else {
    // Orphan so in-flight draws do not stall the upload.
    glBufferData(GL_ARRAY_BUFFER, cast(GLsizeiptr)va.capacity, null,
      GL_DYNAMIC_DRAW);
  }
  glBufferSubData(GL_ARRAY_BUFFER, 0, cast(GLsizeiptr)bytes, vertices.ptr);
  glDrawArrays(mode, 0, count);
}

/**
 * VBO size for `bytes` of data: the next power of two, at least
 * `minVboCapacity`.
 */
size_t vboCapacityFor(size_t bytes) nothrow @safe @nogc pure {
  size_t cap = minVboCapacity;
  while (cap < bytes) {
    cap *= 2;
  }
  return cap;
}

/// Smallest VBO allocation of `uploadAndDrawDynamic` in bytes.
enum size_t minVboCapacity = 256;

/// Maximum quads per indexed draw (16-bit indices allow up to 16383).
enum size_t maxIndexedQuads = 2048;

/// Writes two triangles per quad (`indices.length / 6` quads) into `indices`.
void fillQuadIndices(ushort[] indices) nothrow @safe @nogc pure {
  assert(indices.length % 6 == 0);
  assert(indices.length / 6 <= 16383);
  foreach (q; 0 .. indices.length / 6) {
    const ushort b = cast(ushort)(q * 4);
    const size_t base = q * 6;
    indices[base + 0] = b;
    indices[base + 1] = cast(ushort)(b + 1);
    indices[base + 2] = cast(ushort)(b + 2);
    indices[base + 3] = cast(ushort)(b + 2);
    indices[base + 4] = cast(ushort)(b + 1);
    indices[base + 5] = cast(ushort)(b + 3);
  }
}


/// VAO with a dynamic VBO and a static quad EBO built on first draw.
struct IndexedQuadArray {
  GLuint vao;
  GLuint vbo;
  GLuint ebo;
  size_t vboCapacity;
  size_t eboQuadCapacity;
}

/**
 * Creates a VAO for interleaved `TextVertex` data (vec2 position at 0,
 * vec2 texCoord at 1, normalized ubyte[4] color at 2) with an attached EBO.
 * Leaves no VAO or buffer bound.
 */
IndexedQuadArray createTextQuadArray() {
  IndexedQuadArray h;
  glGenVertexArrays(1, &h.vao);
  glBindVertexArray(h.vao);

  glGenBuffers(1, &h.vbo);
  glBindBuffer(GL_ARRAY_BUFFER, h.vbo);

  glGenBuffers(1, &h.ebo);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, h.ebo);

  const GLsizei stride = 5 * float.sizeof;
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, stride, null);

  glEnableVertexAttribArray(1);
  glVertexAttribPointer(
    1, 2, GL_FLOAT, GL_FALSE, stride, cast(const(void)*)(2 * float.sizeof)
  );

  glEnableVertexAttribArray(2);
  glVertexAttribPointer(
    2, 4, GL_UNSIGNED_BYTE, GL_TRUE, stride,
    cast(const(void)*)(4 * float.sizeof)
  );

  glBindVertexArray(0);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
  return h;
}

/**
 * Uploads `vertexBytes` to `qa.vbo` and draws `quadCount` indexed quads
 * (growing the VBO and regenerating the EBO when needed).
 */
void uploadAndDrawIndexedQuads(
  ref IndexedQuadArray qa,
  const(void)[] vertexBytes,
  size_t quadCount
) {
  if (quadCount == 0 || vertexBytes.length == 0) {
    return;
  }
  assert(quadCount <= maxIndexedQuads);

  glBindVertexArray(qa.vao);
  glBindBuffer(GL_ARRAY_BUFFER, qa.vbo);
  if (vertexBytes.length > qa.vboCapacity) {
    const size_t cap = vboCapacityFor(vertexBytes.length);
    glBufferData(
      GL_ARRAY_BUFFER, cast(GLsizeiptr)cap, null, GL_DYNAMIC_DRAW
    );
    qa.vboCapacity = cap;
  } else {
    // Orphan so in-flight draws of earlier flushes do not stall the upload.
    glBufferData(
      GL_ARRAY_BUFFER, cast(GLsizeiptr)qa.vboCapacity, null, GL_DYNAMIC_DRAW
    );
  }
  glBufferSubData(
    GL_ARRAY_BUFFER, 0, cast(GLsizeiptr)vertexBytes.length, vertexBytes.ptr
  );

  if (qa.eboQuadCapacity == 0) {
    // Built once at full capacity from a temporary malloc buffer.
    import core.exception : onOutOfMemoryError;
    import core.stdc.stdlib : free, malloc;

    enum size_t count = maxIndexedQuads * 6;
    ushort* ptr = cast(ushort*)malloc(count * ushort.sizeof);
    if (ptr is null) {
      onOutOfMemoryError();
    }
    scope(exit) free(ptr);
    auto indices = ptr[0 .. count];
    fillQuadIndices(indices);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, qa.ebo);
    glBufferData(
      GL_ELEMENT_ARRAY_BUFFER,
      cast(GLsizeiptr)(count * ushort.sizeof),
      indices.ptr,
      GL_STATIC_DRAW
    );
    qa.eboQuadCapacity = maxIndexedQuads;
  }

  glDrawElements(
    GL_TRIANGLES, cast(GLsizei)(quadCount * 6), GL_UNSIGNED_SHORT, null
  );
}

/// Deletes the non-zero buffers and VAO of `qa` and resets it.
void destroyIndexedQuadArray(ref IndexedQuadArray qa) {
  if (qa.ebo != 0) {
    glDeleteBuffers(1, &qa.ebo);
  }
  if (qa.vbo != 0) {
    glDeleteBuffers(1, &qa.vbo);
  }
  if (qa.vao != 0) {
    glDeleteVertexArrays(1, &qa.vao);
  }
  qa = IndexedQuadArray.init;
}

unittest {
  assert(vboCapacityFor(1) == 256);
  assert(vboCapacityFor(256) == 256);
  assert(vboCapacityFor(257) == 512);
  assert(vboCapacityFor(5000) == 8192);
}

unittest {
  ushort[12] idx;
  fillQuadIndices(idx[]);
  assert(idx == [0, 1, 2, 2, 1, 3, 4, 5, 6, 6, 5, 7]);
  static assert(maxIndexedQuads * 4 <= ushort.max + 1);
}

/**
 * Current GL program of one context, so redundant `glUseProgram` calls
 * are skipped. `epoch()` changes on every `invalidate()`; the uniform
 * caches (`Vec2UniformCache`, `GradientLocs`) re-upload after a change.
 * Owned by `Renderer`; the pipelines keep a pointer to it.
 */
struct ProgramTracker {
  /// Binds `program` unless it is already current.
  void use(GLuint program) {
    if (program != fCurrent) {
      glUseProgram(program);
      fCurrent = program;
    }
  }

  /**
   * Forgets the current program and starts a new epoch, so the next
   * `use` binds again and the cached uniforms are uploaded again (on
   * viewport, target and scaling changes, and after any direct
   * `glUseProgram`).
   */
  void invalidate() {
    fCurrent = 0;
    if (++fEpoch == 0) {
      fEpoch = 1;
    }
  }

  /// Uniform cache epoch (never 0, so `.init` caches are stale).
  uint epoch() const {
    return fEpoch;
  }

  /// The program bound by the last `use` (0 when unknown).
  GLuint current() const {
    return fCurrent;
  }

private:
  GLuint fCurrent;
  uint fEpoch = 1;
}

/**
 * Last value uploaded to one vec2 uniform of one program (e.g.
 * `uResolution`); `upload` skips the GL call when the value and the
 * `ProgramTracker` epoch are unchanged. The program must be current.
 */
struct Vec2UniformCache {
  void upload(GLint loc, float x, float y, uint epoch) {
    if (epoch == fEpoch && x == fX && y == fY) {
      return;
    }
    glUniform2f(loc, x, y);
    fX = x;
    fY = y;
    fEpoch = epoch;
  }

private:
  float fX = float.nan;
  float fY = float.nan;
  uint fEpoch;
}

/**
 * Compiles `vertSource` and `fragSource` and links them into a program;
 * the shader objects are deleted afterwards.
 */
GLuint buildProgram(string vertSource, string fragSource) {
  GLuint vertShader = compileShader(GL_VERTEX_SHADER, vertSource);
  scope(exit) glDeleteShader(vertShader);

  GLuint fragShader = compileShader(GL_FRAGMENT_SHADER, fragSource);
  scope(exit) glDeleteShader(fragShader);

  return linkProgram(vertShader, fragShader);
}

/// VAO and its dynamic VBO.
struct VertexArrayHandles {
  GLuint vao;
  GLuint vbo;
  /// Allocated VBO size in bytes (0 before the first upload).
  size_t capacity;
}

/**
 * Creates a VAO with one VBO holding tightly packed vec2 positions at
 * attribute location 0. Leaves no VAO or buffer bound.
 */
VertexArrayHandles createVec2VertexArray() {
  VertexArrayHandles h;
  glGenVertexArrays(1, &h.vao);
  glBindVertexArray(h.vao);

  glGenBuffers(1, &h.vbo);
  glBindBuffer(GL_ARRAY_BUFFER, h.vbo);

  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * float.sizeof, null);

  glBindVertexArray(0);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  return h;
}

/**
 * Creates a VAO with one VBO holding interleaved vec2 position
 * (location 0) and vec2 texture/local coordinate (location 1). Leaves no
 * VAO or buffer bound.
 */
VertexArrayHandles createVec4VertexArray() {
  VertexArrayHandles h;
  glGenVertexArrays(1, &h.vao);
  glBindVertexArray(h.vao);

  glGenBuffers(1, &h.vbo);
  glBindBuffer(GL_ARRAY_BUFFER, h.vbo);

  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * float.sizeof, null);

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
  return h;
}

/**
 * A shader program and the VAO/VBO (with its streaming capacity) it draws
 * from: the trio every pipeline owns.
 */
struct ProgramMesh {
  GLuint program;
  VertexArrayHandles va;

  /// Builds the program (`buildProgram`) with a vec2 vertex array.
  static ProgramMesh vec2(string vertSource, string fragSource) {
    return ProgramMesh(
      buildProgram(vertSource, fragSource), createVec2VertexArray()
    );
  }

  /// Builds the program (`buildProgram`) with a vec4 vertex array.
  static ProgramMesh vec4(string vertSource, string fragSource) {
    return ProgramMesh(
      buildProgram(vertSource, fragSource), createVec4VertexArray()
    );
  }

  /// Location of uniform `name` (a NUL-terminated literal) in `program`.
  GLint uniform(string name) const {
    assert(name.length > 0 && name[$ - 1] == '\0');
    return glGetUniformLocation(program, name.ptr);
  }

  /// Deletes the non-zero objects and zeroes the handles.
  void destroy() {
    destroyProgramAndBuffers(program, va);
  }
}

/// Deletes the non-zero objects and zeroes the handles in place.
void destroyProgramAndBuffers(ref GLuint program,
  ref VertexArrayHandles va) {
  if (va.vbo != 0) {
    glDeleteBuffers(1, &va.vbo);
  }
  if (va.vao != 0) {
    glDeleteVertexArrays(1, &va.vao);
  }
  va = VertexArrayHandles.init;
  if (program != 0) {
    glDeleteProgram(program);
    program = 0;
  }
}

/**
 * Creates a GL_RGBA texture from RGBA8 `pixels` (`w` x `h`, rows `pitch`
 * bytes apart, first row at the top) with linear filtering and
 * clamp-to-edge wrapping. Resets `GL_UNPACK_ROW_LENGTH` to 0 and leaves no
 * texture bound. Returns the texture id.
 */
GLuint uploadRgbaTexture(const(void)* pixels, int w, int h, int pitch) {
  GLuint texId;
  glGenTextures(1, &texId);
  glBindTexture(GL_TEXTURE_2D, texId);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  replaceRgbaTextureImage(texId, pixels, w, h, pitch);
  return texId;
}

/**
 * Replaces the level-0 image of texture `texId` with RGBA8 `pixels`
 * (`w` x `h`, rows `pitch` bytes apart, first row at the top); the size
 * may change. Resets `GL_UNPACK_ROW_LENGTH` to 0 and leaves no texture
 * bound.
 */
void replaceRgbaTextureImage(
  GLuint texId,
  const(void)* pixels,
  int w,
  int h,
  int pitch
) {
  assert(pitch >= w * 4 && pitch % 4 == 0);
  glBindTexture(GL_TEXTURE_2D, texId);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, pitch != w * 4 ? pitch / 4 : 0);
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
  telemetryTextureAlloc(texId, w, h);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  glBindTexture(GL_TEXTURE_2D, 0);
}

/// Largest texture width/height the GL context supports.
int maxTextureSize() {
  GLint n = 0;
  glGetIntegerv(GL_MAX_TEXTURE_SIZE, &n);
  return n;
}

/**
 * Creates a zero-filled (transparent black) `size` x `size` RGBA8 texture
 * with linear filtering and clamp-to-edge wrapping. Leaves no texture
 * bound. Returns the texture id.
 */
GLuint allocRgbaTexture(int size) {
  import core.exception : onOutOfMemoryError;
  import core.stdc.stdlib : calloc, free;

  assert(size > 0);
  const size_t pixelCount = cast(size_t)size * cast(size_t)size;
  void* zeros = calloc(pixelCount, 4);
  if (zeros is null) {
    onOutOfMemoryError();
  }
  scope(exit) free(zeros);

  GLuint texId;
  glGenTextures(1, &texId);
  glBindTexture(GL_TEXTURE_2D, texId);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  glTexImage2D(
    GL_TEXTURE_2D, 0, GL_RGBA, size, size, 0,
    GL_RGBA, GL_UNSIGNED_BYTE, zeros
  );
  telemetryTextureAlloc(texId, size, size);
  glBindTexture(GL_TEXTURE_2D, 0);
  return texId;
}

/// A sub-rectangle upload: RGBA8 `pixels` (rows `pitch` bytes apart).
struct RgbaSubImage {
  int x;
  int y;
  int w;
  int h;
  const(void)* pixels;
  int pitch;
}

/**
 * Writes `img` into the level-0 image of texture `texId` at (`img.x`,
 * `img.y`) with `glTexSubImage2D`. Resets `GL_UNPACK_ROW_LENGTH` to 0 and
 * leaves no texture bound.
 */
void uploadRgbaSubImage(GLuint texId, const ref RgbaSubImage img) {
  assert(img.pitch >= img.w * 4 && img.pitch % 4 == 0);
  glBindTexture(GL_TEXTURE_2D, texId);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  const int rowLen = img.pitch != img.w * 4 ? img.pitch / 4 : 0;
  glPixelStorei(GL_UNPACK_ROW_LENGTH, rowLen);
  glTexSubImage2D(
    GL_TEXTURE_2D, 0, img.x, img.y, img.w, img.h,
    GL_RGBA, GL_UNSIGNED_BYTE, img.pixels
  );
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  glBindTexture(GL_TEXTURE_2D, 0);
}

/**
 * Deletes texture `texId` and records it in the memory telemetry. All
 * owned textures must be deleted through this helper.
 */
void deleteTexture(GLuint texId) {
  telemetryTextureFree(texId);
  glDeleteTextures(1, &texId);
}
