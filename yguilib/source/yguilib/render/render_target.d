/**
 * GPU offscreen render target: created by `Renderer.createRenderTarget`,
 * drawn into between `Renderer.beginTarget` and `Renderer.endTarget`,
 * then drawn with `Renderer.drawImage(rt.texture(), ...)` or read back
 * with `toImage()`.
 */
module yguilib.render.render_target;

import glad2.gles2;
import yguilib.render.image : Image;
import yguilib.render.texture : BorrowedTextureInfo, Texture;

/**
 * RGBA8 color + depth24-stencil8 framebuffer, optionally multisampled.
 *
 * Without MSAA a single FBO renders straight into the color texture.
 * With MSAA, drawing goes to multisampled renderbuffers that
 * `Renderer.endTarget` resolves into the color texture.
 *
 * The color texture holds premultiplied alpha in GL row order (bottom
 * up); `texture()` is flagged accordingly so drawing it blends right.
 *
 * RAII rule (as for `Texture`): the GL objects are released only by an
 * explicit `destroy()` on the main thread while the GL context is
 * current. There is no destructor because the GC may finalize the
 * object on any thread or after the context is gone.
 */
final class RenderTarget {
  /// Width in pixels (0 when invalid).
  int pixelWidth() const {
    return pixelWidth_;
  }

  /// Height in pixels (0 when invalid).
  int pixelHeight() const {
    return pixelHeight_;
  }

  /// True while the GL objects are allocated and complete.
  bool isValid() const {
    return resolveFbo != 0;
  }

  /// True if drawing is multisampled (resolved at `endTarget`).
  bool isMsaa() const {
    return samples_ >= 2;
  }

  /**
   * Color texture (premultiplied, bottom-up), owned by the target: do
   * not `destroy()` it. A reallocation (resize) or `destroy()`
   * invalidates it and a resize creates a new one, so fetch it again
   * after `Renderer.resizeRenderTarget`. Never null; invalid when the
   * target is invalid. With MSAA it holds the content of the last
   * finished `endTarget`.
   */
  Texture texture() {
    return tex_;
  }

  /**
   * Reads the color texture back as a straight-alpha, top-down RGBA8
   * image (rgb un-premultiplied). Must not be called while the target
   * is being drawn into. Main thread only.
   *
   * Returns: the image, or null if the target is invalid.
   */
  Image toImage() {
    assert(active == 0, "toImage() on an active render target");
    if (!isValid()) {
      return null;
    }
    GLint prevRead = 0;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prevRead);
    auto img = new Image(pixelWidth_, pixelHeight_);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, resolveFbo);
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
    glReadPixels(0, 0, pixelWidth_, pixelHeight_, GL_RGBA,
      GL_UNSIGNED_BYTE, img.pixels.ptr);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, cast(GLuint)prevRead);
    unpremultiply(img.pixels);
    img.flipVertical();
    return img;
  }

  /// Deletes the GL objects. Idempotent. Main thread only.
  void destroy() {
    assert(active == 0, "destroy() on an active render target");
    deleteAttachments();
  }

package(yguilib.render):
  /**
   * Empty target; `samples` >= 2 makes it multisampled. Call
   * `allocate` before use.
   */
  this(int samples) {
    samples_ = samples >= 2 ? samples : 0;
    tex_ = new Texture();
  }

  /// Number of `Renderer.beginTarget` frames using this target (0 or 1).
  int active;

  /**
   * Deletes and recreates the attachments with `pw` x `ph` pixels (both
   * positive) and checks completeness (errors are logged). Content is
   * undefined afterwards.
   *
   * Returns: true on success; on failure the target is invalid.
   */
  bool allocate(int pw, int ph) {
    import yguilib.render.internal.offscreen : AttachmentIds,
      allocateRenderbuffer, allocateTargetTexture, attachAndCheck;

    assert(pw > 0 && ph > 0);
    deleteAttachments();
    glGenFramebuffers(1, &resolveFbo);
    glGenTextures(1, &colorTex);
    allocateTargetTexture(colorTex, pw, ph);
    bool ok;
    if (isMsaa()) {
      ok = attachAndCheck(AttachmentIds(resolveFbo, colorTex, 0, 0),
        "Render target resolve");
      glGenFramebuffers(1, &msaaFbo);
      glGenRenderbuffers(1, &msaaColorRb);
      glGenRenderbuffers(1, &depthStencilRb);
      allocateRenderbuffer(msaaColorRb, GL_RGBA8, samples_, pw, ph);
      allocateRenderbuffer(
        depthStencilRb, GL_DEPTH24_STENCIL8, samples_, pw, ph
      );
      ok = attachAndCheck(
        AttachmentIds(msaaFbo, 0, msaaColorRb, depthStencilRb),
        "Render target MSAA"
      ) && ok;
    } else {
      glGenRenderbuffers(1, &depthStencilRb);
      allocateRenderbuffer(depthStencilRb, GL_DEPTH24_STENCIL8, 0, pw, ph);
      ok = attachAndCheck(
        AttachmentIds(resolveFbo, colorTex, 0, depthStencilRb),
        "Render target"
      );
    }
    if (!ok) {
      deleteAttachments();
      return false;
    }
    pixelWidth_ = pw;
    pixelHeight_ = ph;
    BorrowedTextureInfo info;
    info.id = colorTex;
    info.width = pw;
    info.height = ph;
    info.premultiplied = true;
    info.bottomUp = true;
    tex_ = Texture.borrowedFromInfo(info);
    return true;
  }

  /// GL name of the color texture (0 when invalid).
  GLuint textureId() const {
    return colorTex;
  }

  /// Framebuffer to draw into: the MSAA FBO or the resolve FBO.
  GLuint drawFbo() const {
    return isMsaa() ? msaaFbo : resolveFbo;
  }

  /**
   * Blits the MSAA color into the color texture (scissor off), then
   * restores the read/draw bindings and the scissor. No-op without MSAA.
   */
  void resolve() {
    if (!isMsaa() || !isValid()) {
      return;
    }
    GLint prevRead = 0;
    GLint prevDraw = 0;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prevRead);
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prevDraw);
    const bool scissor = glIsEnabled(GL_SCISSOR_TEST) == GL_TRUE;
    glDisable(GL_SCISSOR_TEST);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, msaaFbo);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, resolveFbo);
    glBlitFramebuffer(0, 0, pixelWidth_, pixelHeight_, 0, 0, pixelWidth_,
      pixelHeight_, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, cast(GLuint)prevRead);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, cast(GLuint)prevDraw);
    if (scissor) {
      glEnable(GL_SCISSOR_TEST);
    }
  }

private:
  /// Deletes every GL object and invalidates `tex_`.
  void deleteAttachments() {
    if (tex_.isValid()) {
      tex_.releaseBorrowed();
    }
    deleteFramebuffer(resolveFbo);
    deleteFramebuffer(msaaFbo);
    if (colorTex != 0) {
      glDeleteTextures(1, &colorTex);
      colorTex = 0;
    }
    deleteRenderbuffer(msaaColorRb);
    deleteRenderbuffer(depthStencilRb);
    pixelWidth_ = 0;
    pixelHeight_ = 0;
  }

  static void deleteFramebuffer(ref GLuint fbo) {
    if (fbo != 0) {
      glDeleteFramebuffers(1, &fbo);
      fbo = 0;
    }
  }

  static void deleteRenderbuffer(ref GLuint rb) {
    if (rb != 0) {
      glDeleteRenderbuffers(1, &rb);
      rb = 0;
    }
  }

  invariant {
    assert(tex_ !is null);
  }

  int pixelWidth_;
  int pixelHeight_;
  /// MSAA sample count (0 = no MSAA).
  const int samples_;
  /// Resolve FBO (the only FBO without MSAA) and its color texture.
  GLuint resolveFbo;
  GLuint colorTex;
  /// Multisampled FBO and color renderbuffer (MSAA only).
  GLuint msaaFbo;
  GLuint msaaColorRb;
  /// Depth24-stencil8 renderbuffer of the draw FBO.
  GLuint depthStencilRb;
  Texture tex_;
}

private:
/**
 * Converts premultiplied RGBA8 `px` to straight alpha in place:
 * rgb = rgb * 255 / a (rounded, clamped to 255) when a > 0.
 */
void unpremultiply(ubyte[] px) nothrow @safe @nogc {
  for (size_t i = 0; i + 3 < px.length; i += 4) {
    const uint a = px[i + 3];
    if (a == 0 || a == 255) {
      continue;
    }
    foreach (k; 0 .. 3) {
      const uint v = (px[i + k] * 255u + a / 2) / a;
      px[i + k] = cast(ubyte)(v > 255 ? 255 : v);
    }
  }
}

// Un-premultiply rounding and clamping (no GL calls).
unittest {
  ubyte[] px = [
    128, 0, 0, 128,  64, 64, 64, 64,  10, 20, 30, 0,
    200, 100, 50, 255,  90, 10, 0, 80,
  ];
  unpremultiply(px);
  assert(px[0 .. 4] == [255, 0, 0, 128]);
  assert(px[4 .. 8] == [255, 255, 255, 64]);
  assert(px[8 .. 12] == [10, 20, 30, 0]);
  assert(px[12 .. 16] == [200, 100, 50, 255]);
  // 90 * 255 / 80 = 286 -> clamped; 10 * 255 / 80 = 31.9 -> 32.
  assert(px[16 .. 20] == [255, 32, 0, 80]);
}

// Render target drawing, read back, state round trip, nesting, MSAA,
// blitting onto the window and resizing (needs a GL window).
unittest {
  import std.math : abs;
  import yguilib.clibs.sdl3;
  import yguilib.render : Renderer;
  import yguilib.render.canvas : FillStyle, Path2d;
  import yguilib.render.internal.clip_stack : ClipStack;
  import yguilib.render.render_types : ColorF, PointF, RectF;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_render_target");
  win.create();
  scope(exit) win.destroy();
  win.setDisplayScaling(1.0f);
  Renderer r = win.renderer;
  r.setViewport(320, 240);

  ubyte[4] windowAt(int x, int y) {
    ubyte[4] p;
    glReadPixels(x, 240 - 1 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p.ptr);
    return p;
  }

  bool near4(in ubyte[] px, int cr, int cg, int cb, int ca) {
    return abs(px[0] - cr) <= 3 && abs(px[1] - cg) <= 3
      && abs(px[2] - cb) <= 3 && abs(px[3] - ca) <= 3;
  }

  const(ubyte)[] imageAt(in Image img, int x, int y) {
    const size_t o = (cast(size_t)y * img.width() + x) * 4;
    return img.pixels[o .. o + 4];
  }

  Path2d rectPath(RectF rc) {
    auto p = new Path2d();
    p.rect(rc);
    return p;
  }

  // 1. Half-alpha red in the top half reads back straight, row 0 = top.
  RenderTarget rt = r.createRenderTarget(40, 30, false);
  assert(rt !is null && rt.isValid() && !rt.isMsaa());
  scope(exit) rt.destroy();
  RenderTarget b = r.createRenderTarget(20, 20, false);
  assert(b !is null);
  scope(exit) b.destroy();
  RenderTarget ms = r.createRenderTarget(40, 30, true);
  assert(ms !is null && ms.isValid());
  scope(exit) ms.destroy();
  // On a failed assert close open targets before destroying them.
  scope(exit) {
    while (r.inTarget()) {
      r.endTarget();
    }
  }
  assert(rt.pixelWidth() == 40 && rt.pixelHeight() == 30);
  assert(rt.texture().premultiplied() && rt.texture().bottomUp());
  assert(rt.texture().width() == 40 && rt.texture().height() == 30);
  assert(!r.inTarget());
  r.beginTarget(rt, true);
  assert(r.inTarget());
  assert(r.getPixelWidth() == 40 && r.getPixelHeight() == 30);
  r.drawFillRect(RectF(0, 0, 40, 15), ColorF(1, 0, 0, 0.5f));
  r.endTarget();
  assert(!r.inTarget());
  Image img = rt.toImage();
  assert(img !is null && img.width() == 40 && img.height() == 30);
  assert(near4(imageAt(img, 5, 5), 255, 0, 0, 128));
  assert(near4(imageAt(img, 35, 14), 255, 0, 0, 128));
  assert(near4(imageAt(img, 5, 25), 0, 0, 0, 0));

  // 2. Viewport, scissor, fbo, clear color and the clip stack restored.
  GLint fboBefore = 0;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fboBefore);
  r.clearFrame(ColorF(0, 0, 0, 1));
  r.pushClipRect(RectF(10, 10, 50, 50));
  r.beginTarget(rt, true);
  assert(glIsEnabled(GL_SCISSOR_TEST) == GL_FALSE);
  // Unclipped inside the target.
  r.drawFillRect(RectF(0, 0, 40, 30), ColorF(0, 1, 0, 1));
  r.endTarget();
  GLint fboAfter = 0;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fboAfter);
  assert(fboAfter == fboBefore);
  GLint[4] vp;
  glGetIntegerv(GL_VIEWPORT, vp.ptr);
  assert(vp == [0, 0, 320, 240]);
  assert(r.getPixelWidth() == 320 && r.getPixelHeight() == 240);
  assert(glIsEnabled(GL_SCISSOR_TEST) == GL_TRUE);
  GLint[4] box;
  glGetIntegerv(GL_SCISSOR_BOX, box.ptr);
  assert(box == ClipStack.scissorBox(RectF(10, 10, 50, 50), 320, 240, 1));
  GLfloat[4] cc;
  glGetFloatv(GL_COLOR_CLEAR_VALUE, cc.ptr);
  assert(cc == [0, 0, 0, 1]);
  r.drawFillRect(RectF(0, 0, 320, 240), ColorF(1, 1, 1, 1));
  assert(near4(windowAt(20, 20), 255, 255, 255, 255));
  assert(near4(windowAt(100, 100), 0, 0, 0, 255));
  r.popClipRect();
  img = rt.toImage();
  assert(near4(imageAt(img, 0, 0), 0, 255, 0, 255));
  assert(near4(imageAt(img, 39, 29), 0, 255, 0, 255));

  // 3. Canvas clip and fill style survive a target pass.
  auto cv = r.canvas();
  const blue = FillStyle.solid(ColorF(0, 0, 1, 1));
  const green = FillStyle.solid(ColorF(0, 1, 0, 1));
  r.clearFrame(ColorF(0, 0, 0, 1));
  cv.save();
  cv.clip(rectPath(RectF(0, 0, 20, 20)));
  cv.fillStyle(blue);
  r.beginTarget(rt, true);
  assert(cv.fillStyle().color == FillStyle.init.color);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(0, 0, 40, 30)));
  r.endTarget();
  assert(cv.fillStyle().color == blue.color);
  cv.fill(rectPath(RectF(0, 0, 320, 240)));
  assert(near4(windowAt(10, 10), 0, 0, 255, 255));
  assert(near4(windowAt(100, 100), 0, 0, 0, 255));
  cv.restore();
  img = rt.toImage();
  assert(near4(imageAt(img, 35, 25), 0, 255, 0, 255));

  // 4. Nested: B's texture drawn into A.
  r.beginTarget(rt, true);
  r.beginTarget(b, true);
  assert(r.getPixelWidth() == 20);
  r.drawFillRect(RectF(0, 0, 20, 10), ColorF(1, 0, 0, 1));
  version (assert) {
    import core.exception : AssertError;
    import std.exception : assertThrown;

    // Feedback loop: drawing an active target's texture.
    assertThrown!AssertError(
      r.drawImage(b.texture(), RectF(0, 0, 5, 5), ColorF(1, 1, 1, 1))
    );
    assertThrown!AssertError(
      r.drawImage(rt.texture(), RectF(0, 0, 5, 5), ColorF(1, 1, 1, 1))
    );
  }
  r.endTarget();
  assert(r.getPixelWidth() == 40 && r.inTarget());
  r.drawImage(b.texture(), RectF(0, 0, 20, 20), ColorF(1, 1, 1, 1));
  r.endTarget();
  img = rt.toImage();
  assert(near4(imageAt(img, 5, 5), 255, 0, 0, 255));
  assert(near4(imageAt(img, 5, 15), 0, 0, 0, 0));
  assert(near4(imageAt(img, 30, 5), 0, 0, 0, 0));

  // 5. MSAA vs plain: same interior, MSAA edge has partial alpha.
  auto tri = new Path2d();
  tri.moveTo(PointF(0, 0));
  tri.lineTo(PointF(40, 0));
  tri.lineTo(PointF(0, 30));
  tri.closePath();
  foreach (t; [rt, ms]) {
    r.beginTarget(t, true);
    cv.fillStyle(FillStyle.solid(ColorF(1, 1, 1, 1)));
    cv.fill(tri);
    r.endTarget();
    img = t.toImage();
    assert(near4(imageAt(img, 3, 3), 255, 255, 255, 255));
    assert(near4(imageAt(img, 36, 26), 0, 0, 0, 0));
  }
  if (ms.isMsaa()) {
    img = ms.toImage();
    bool partial = false;
    foreach (i; 0 .. img.width() * img.height()) {
      const ubyte a = img.pixels[i * 4 + 3];
      partial = partial || (a > 0 && a < 255);
    }
    assert(partial);
  }

  // 6. Blit onto an opaque window: no dark fringe.
  r.beginTarget(rt, true);
  r.drawFillRect(RectF(0, 0, 20, 30), ColorF(1, 1, 1, 0.5f));
  r.drawFillRect(RectF(20, 0, 20, 30), ColorF(1, 0, 0, 0.5f));
  r.endTarget();
  r.clearFrame(ColorF(0, 0, 0, 1));
  r.drawImage(rt.texture(), RectF(100, 100, 40, 30), ColorF(1, 1, 1, 1));
  assert(near4(windowAt(110, 115), 128, 128, 128, 255));
  assert(near4(windowAt(130, 115), 128, 0, 0, 255));
  // A half tint halves the premultiplied color.
  r.clearFrame(ColorF(0, 0, 0, 1));
  r.drawImage(rt.texture(), RectF(100, 100, 40, 30),
    ColorF(1, 1, 1, 0.5f));
  assert(near4(windowAt(110, 115), 64, 64, 64, 255));

  // 7. Resize only on a pixel size change; destroy is idempotent.
  Texture before = rt.texture();
  r.resizeRenderTarget(rt, 39.5f, 29.2f);
  assert(rt.texture() is before && rt.pixelWidth() == 40);
  r.resizeRenderTarget(rt, 64, 48);
  assert(rt.pixelWidth() == 64 && rt.pixelHeight() == 48);
  assert(!before.isValid() && rt.texture().isValid());
  assert(rt.texture().width() == 64);
  r.resizeRenderTarget(rt, float.nan, 10);
  assert(rt.pixelWidth() == 64);
  assert(r.createRenderTarget(0, 10, true) is null);
  assert(r.createRenderTarget(float.infinity, 10, true) is null);
  RenderTarget tiny = r.createRenderTarget(0.1f, 0.1f, false);
  assert(tiny.pixelWidth() == 1 && tiny.pixelHeight() == 1);
  tiny.destroy();
  tiny.destroy();
  assert(!tiny.isValid() && !tiny.texture().isValid());
  assert(tiny.toImage() is null);

  assert(glGetError() == GL_NO_ERROR);
}
