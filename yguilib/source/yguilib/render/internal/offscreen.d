/**
 * Offscreen render targets (RGBA8 texture + depth24-stencil8 FBO) and
 * the GL target state saved around offscreen passes (Canvas shadows).
 */
module yguilib.render.internal.offscreen;

package(yguilib):

import glad2.gles2;

/**
 * FBO with an RGBA8 color texture (linear filtering, clamp to edge) and a
 * depth24-stencil8 renderbuffer. It only grows: `ensureSize` reallocates
 * to the maximum size requested so far. Passes draw into the region
 * `(0, 0, w, h)` of the texture. Not multisampled.
 */
struct OffscreenTarget {
  GLuint fbo;
  GLuint texture;
  GLuint depthStencil;
  /// Allocated texture size in pixels (0 before the first `ensureSize`).
  int width;
  int height;

  /// Grows the attachments to hold at least `w` x `h` pixels.
  void ensureSize(int w, int h) {
    if (w <= width && h <= height && fbo != 0) {
      return;
    }
    const int nw = w > width ? w : width;
    const int nh = h > height ? h : height;
    if (fbo == 0) {
      glGenFramebuffers(1, &fbo);
      glGenTextures(1, &texture);
      glGenRenderbuffers(1, &depthStencil);
    }
    allocateTargetTexture(texture, nw, nh);
    allocateRenderbuffer(depthStencil, GL_DEPTH24_STENCIL8, 0, nw, nh);
    attachAndCheck(AttachmentIds(fbo, texture, 0, depthStencil),
      "Offscreen");
    width = nw;
    height = nh;
  }

  /**
   * Binds the FBO with viewport and scissor `(0, 0, w, h)`; `w` x `h`
   * must fit the allocated size. Clears that region (color to
   * transparent, stencil to 0) when `clear` is true.
   */
  void bindRegion(int w, int h, bool clear) {
    assert(fbo != 0 && w <= width && h <= height);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glViewport(0, 0, w, h);
    glEnable(GL_SCISSOR_TEST);
    glScissor(0, 0, w, h);
    if (clear) {
      glClearColor(0, 0, 0, 0);
      glStencilMask(0xFF);
      glClearStencil(0);
      glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
    }
  }

  /// Deletes the GL objects; the target can be reused afterwards.
  void destroy() {
    if (fbo != 0) {
      glDeleteFramebuffers(1, &fbo);
      glDeleteTextures(1, &texture);
      glDeleteRenderbuffers(1, &depthStencil);
    }
    fbo = 0;
    texture = 0;
    depthStencil = 0;
    width = 0;
    height = 0;
  }
}

/**
 * Framebuffer binding, viewport, scissor (enabled and box) and clear
 * color captured before an offscreen pass and restored after it.
 */
struct SavedTargetState {
  GLint framebuffer;
  GLint[4] viewport;
  GLint[4] scissorBox;
  bool scissorEnabled;
  GLfloat[4] clearColor;

  /// Reads the current state.
  static SavedTargetState capture() {
    SavedTargetState s;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &s.framebuffer);
    glGetIntegerv(GL_VIEWPORT, s.viewport.ptr);
    glGetIntegerv(GL_SCISSOR_BOX, s.scissorBox.ptr);
    s.scissorEnabled = glIsEnabled(GL_SCISSOR_TEST) == GL_TRUE;
    glGetFloatv(GL_COLOR_CLEAR_VALUE, s.clearColor.ptr);
    return s;
  }

  /// Rebinds the framebuffer and restores viewport, scissor, clear color.
  void restore() const {
    glBindFramebuffer(GL_FRAMEBUFFER, cast(GLuint)framebuffer);
    glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
    glScissor(scissorBox[0], scissorBox[1], scissorBox[2], scissorBox[3]);
    if (scissorEnabled) {
      glEnable(GL_SCISSOR_TEST);
    } else {
      glDisable(GL_SCISSOR_TEST);
    }
    glClearColor(clearColor[0], clearColor[1], clearColor[2],
      clearColor[3]);
  }
}

/**
 * (Re)allocates the storage of texture `tex` as `w` x `h` RGBA8 with
 * linear filtering and clamp-to-edge wrapping, content undefined.
 */
void allocateTargetTexture(GLuint tex, int w, int h) {
  glBindTexture(GL_TEXTURE_2D, tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA,
    GL_UNSIGNED_BYTE, null);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glBindTexture(GL_TEXTURE_2D, 0);
}

/**
 * (Re)allocates renderbuffer `rb` as `w` x `h` of `format`; multisampled
 * with `samples` samples when `samples` >= 2.
 */
void allocateRenderbuffer(GLuint rb, GLenum format, int samples, int w,
  int h) {
  glBindRenderbuffer(GL_RENDERBUFFER, rb);
  if (samples >= 2) {
    glRenderbufferStorageMultisample(GL_RENDERBUFFER, samples, format, w,
      h);
  } else {
    glRenderbufferStorage(GL_RENDERBUFFER, format, w, h);
  }
  glBindRenderbuffer(GL_RENDERBUFFER, 0);
}

/**
 * Framebuffer attachments for `attachAndCheck`: the color attachment is
 * `colorTexture` when non-zero, else `colorRenderbuffer`; a zero
 * `depthStencil` attaches no depth-stencil buffer.
 */
struct AttachmentIds {
  GLuint fbo;
  GLuint colorTexture;
  GLuint colorRenderbuffer;
  GLuint depthStencil;
}

/**
 * Attaches `ids` to `ids.fbo` and checks completeness, keeping the
 * current framebuffer binding. Logs an error prefixed with `what` when
 * incomplete. Returns: true if the framebuffer is complete.
 */
bool attachAndCheck(in AttachmentIds ids, string what) {
  GLint prevFbo = 0;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prevFbo);
  glBindFramebuffer(GL_FRAMEBUFFER, ids.fbo);
  if (ids.colorTexture != 0) {
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
      GL_TEXTURE_2D, ids.colorTexture, 0);
  } else {
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
      GL_RENDERBUFFER, ids.colorRenderbuffer);
  }
  if (ids.depthStencil != 0) {
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
      GL_RENDERBUFFER, ids.depthStencil);
  }
  const GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  glBindFramebuffer(GL_FRAMEBUFFER, cast(GLuint)prevFbo);
  if (status != GL_FRAMEBUFFER_COMPLETE) {
    import std.logger : errorf;

    errorf("%s framebuffer incomplete: 0x%x", what, status);
    return false;
  }
  return true;
}
