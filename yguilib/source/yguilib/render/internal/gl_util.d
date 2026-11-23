module yguilib.render.internal.gl_util;

package(yguilib):

import glad2.gles2;

/**
 * Configures common 2D blending state: alpha blending enabled,
 * depth test and face culling disabled.
 */
void setupAlphaBlendState() {
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
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
 * Uploads dynamic vertex data to VBO and issues a draw call.
 */
void uploadAndDrawDynamic(
  GLenum mode,
  GLuint vao,
  GLuint vbo,
  const(float)[] vertices,
  GLsizei count
) {
  glBindVertexArray(vao);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glBufferData(
    GL_ARRAY_BUFFER,
    cast(GLsizeiptr)(vertices.length * float.sizeof),
    vertices.ptr,
    GL_DYNAMIC_DRAW
  );
  glDrawArrays(mode, 0, count);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindVertexArray(0);
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

/// Deletes the non-zero objects and zeroes the handles in place.
void destroyProgramAndBuffers(ref GLuint program, ref GLuint vao,
  ref GLuint vbo) {
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
