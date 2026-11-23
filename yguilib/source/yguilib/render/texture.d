/**
 * GPU copy of an `Image`, created by `Renderer.createTexture` and drawn
 * with `Renderer.drawImage` / `Renderer.drawImageRegion`. Also wraps
 * textures owned by others (render targets) as borrowed textures.
 */
module yguilib.render.texture;

import glad2.gles2;
import yguilib.render.image : Image;
import yguilib.render.internal.gl_util : replaceRgbaTextureImage,
  uploadRgbaTexture;

/**
 * RGBA GL texture with linear filtering and clamp-to-edge wrapping.
 *
 * RAII rule: the GL object is released only by an explicit `destroy()`
 * on the main thread while the GL context is current. There is no
 * destructor because the GC may finalize the object on any thread or
 * after the context is gone, where calling GL is invalid; a texture that
 * is never destroyed leaks until its context is destroyed.
 *
 * Image uploads hold straight-alpha, top-down pixels and are owned by the
 * caller. A borrowed texture (`borrowedFromInfo`, e.g. a render target's
 * color texture) may be premultiplied and bottom-up (GL row order); its
 * GL object belongs to the owner, so `update()` and `destroy()` must not
 * be called on it (asserted). The owner calls `releaseBorrowed()` when it
 * deletes or replaces the GL texture.
 */
final class Texture {
  /// Width in pixels (0 after `destroy()`).
  int width() const {
    return width_;
  }

  /// Height in pixels (0 after `destroy()`).
  int height() const {
    return height_;
  }

  /// True until `destroy()` is called.
  bool isValid() const {
    return id_ != 0;
  }

  /**
   * Re-uploads the pixels of `img` (non-null, non-empty); the size may
   * change. Recreates the GL texture if it was destroyed. Main thread only.
   */
  void update(in Image img) {
    assert(!borrowed_, "update() on a borrowed texture");
    assert(img !is null, "img must not be null");
    assert(!img.isEmpty(), "img must not be empty");
    if (id_ == 0) {
      id_ = uploadRgbaTexture(
        img.pixels.ptr, img.width(), img.height(), img.pitch()
      );
    } else {
      replaceRgbaTextureImage(
        id_, img.pixels.ptr, img.width(), img.height(), img.pitch()
      );
    }
    width_ = img.width();
    height_ = img.height();
  }

  /// Deletes the GL texture. Idempotent. Main thread only.
  void destroy() {
    assert(!borrowed_, "destroy() on a borrowed texture");
    if (id_ != 0) {
      glDeleteTextures(1, &id_);
      id_ = 0;
    }
    width_ = 0;
    height_ = 0;
  }

package(yguilib):
  /// Empty texture; fill it with `update()` or use `borrowedFromInfo`.
  this() {
  }

  /**
   * Wraps the GL texture described by `info` without taking ownership
   * (see the class doc). `info.id` must be non-zero.
   */
  static Texture borrowedFromInfo(in BorrowedTextureInfo info) {
    assert(info.id != 0, "borrowed texture id must not be 0");
    auto t = new Texture();
    t.id_ = info.id;
    t.width_ = info.width;
    t.height_ = info.height;
    t.premultiplied_ = info.premultiplied;
    t.bottomUp_ = info.bottomUp;
    t.borrowed_ = true;
    return t;
  }

  /// GL texture name (0 after `destroy()`).
  GLuint id() const {
    return id_;
  }

  /// True if the texels hold premultiplied alpha (false for Image uploads).
  bool premultiplied() const {
    return premultiplied_;
  }

  /// True if the first row is at the bottom (false for Image uploads).
  bool bottomUp() const {
    return bottomUp_;
  }

  /// True if the GL object is owned by someone else (render target).
  bool borrowed() const {
    return borrowed_;
  }

  /**
   * Forgets the borrowed GL texture (the owner deleted or replaced it):
   * the texture becomes invalid with size 0. Only for borrowed textures.
   */
  void releaseBorrowed() {
    assert(borrowed_, "releaseBorrowed() on an owned texture");
    id_ = 0;
    width_ = 0;
    height_ = 0;
  }

private:
  GLuint id_;
  int width_;
  int height_;
  bool premultiplied_;
  bool bottomUp_;
  bool borrowed_;
}

/// GL texture wrapped by `Texture.borrowedFromInfo`.
package(yguilib) struct BorrowedTextureInfo {
  /// GL texture name (non-zero), owned by the caller.
  GLuint id;
  /// Size in pixels.
  int width;
  int height;
  /// Texels hold premultiplied alpha.
  bool premultiplied;
  /// First row at the bottom (GL framebuffer order).
  bool bottomUp;
}

// Flag defaults and the borrowed-texture contract (no GL calls).
unittest {
  auto owned = new Texture();
  assert(!owned.isValid() && owned.width() == 0);
  assert(!owned.premultiplied() && !owned.bottomUp() && !owned.borrowed());

  BorrowedTextureInfo info;
  info.id = 1234; // never passed to GL here
  info.width = 8;
  info.height = 4;
  info.premultiplied = true;
  info.bottomUp = true;
  auto b = Texture.borrowedFromInfo(info);
  assert(b.isValid() && b.id() == 1234);
  assert(b.width() == 8 && b.height() == 4);
  assert(b.premultiplied() && b.bottomUp() && b.borrowed());

  version (assert) {
    import core.exception : AssertError;
    import std.exception : assertThrown;

    assertThrown!AssertError(b.destroy());
    assertThrown!AssertError(b.update(new Image(1, 1)));
    assertThrown!AssertError(owned.releaseBorrowed());
  }
  assert(b.id() == 1234);
  b.releaseBorrowed();
  assert(!b.isValid() && b.width() == 0 && b.height() == 0);
  assert(b.borrowed());
}
