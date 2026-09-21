module yguilib.render.internal.gl_util;

package(yguilib):

import glad2.gles2;

/**
 * Configures common 2D blending state: alpha blending enabled,
 * depth test and face culling disabled.
 */
void setup2DBlendState() {
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
