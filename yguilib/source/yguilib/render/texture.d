/**
 * GPU copy of an `Image`, created by `Renderer.createTexture` and drawn
 * with `Renderer.drawImage` / `Renderer.drawImageRegion`.
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
    if (id_ != 0) {
      glDeleteTextures(1, &id_);
      id_ = 0;
    }
    width_ = 0;
    height_ = 0;
  }

package(yguilib):
  /// Uploads `img` (non-null, non-empty). Requires a current GL context.
  this(in Image img) {
    update(img);
  }

  /// GL texture name (0 after `destroy()`).
  GLuint id() const {
    return id_;
  }

private:
  GLuint id_;
  int width_;
  int height_;
}
