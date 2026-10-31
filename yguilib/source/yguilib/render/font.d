module yguilib.render.font;

import yguilib.clibs.sdl3_ttf;
import yguilib.render.render_types : PointF;
import yguilib.assets : defaultTtfFontData;

package(yguilib) enum float defaultFontPtSize = 11.0f;
package(yguilib) enum ulong invalidFontId = 0;

final class Font {
  /**
   * Loads a font from memory data.
   *
   * Font point sizes (`ptSize`) in user space are unscaled logical points.
   * Scaling (`scale = displayScaling * unitsScaling`) is an internal renderer
   * detail used to rasterize glyphs at native display resolution.
   *
   * Params:
   * fontData TTF binary data in memory.
   * ptSize Unscaled logical point size in user space.
   * scale Rendering scaling factor (defaults to 1.0f).
   */
  this(const(void)[] fontData, float ptSize, float scale = 1.0f) {
    assert(fontData.length > 0, "fontData must not be empty");
    assert(ptSize > 0.0f, "ptSize must be positive");
    float effectiveScale = scale > 0.0f ? scale : 1.0f;
    handle = yguilib_sdl3_ttf_open_font_from_mem(
      fontData.ptr,
      fontData.length,
      ptSize * effectiveScale
    );
    if (!handle) {
      throw new Exception("Failed to load font from memory");
    }
    this.logicalPtSize = ptSize;
    this.currentScale = effectiveScale;
    this.id_ = ++nextFontId;
  }

  /**
   * Loads a font from a file path.
   *
   * Font point sizes (`ptSize`) in user space are unscaled logical points.
   * Scaling (`scale = displayScaling * unitsScaling`) is an internal renderer
   * detail used to rasterize glyphs at native display resolution.
   *
   * @param filePath Path to the TTF font file.
   * @param ptSize Unscaled logical point size in user space.
   * @param scale Rendering scaling factor (defaults to 1.0f).
   */
  this(string filePath, float ptSize, float scale = 1.0f) {
    assert(filePath.length > 0, "filePath must not be empty");
    assert(ptSize > 0.0f, "ptSize must be positive");
    float effectiveScale = scale > 0.0f ? scale : 1.0f;
    import std.string : toStringz;
    handle = yguilib_sdl3_ttf_open_font(
      filePath.toStringz(),
      ptSize * effectiveScale
    );
    if (!handle) {
      throw new Exception("Failed to load font from file: " ~ filePath);
    }
    this.logicalPtSize = ptSize;
    this.currentScale = effectiveScale;
    this.id_ = ++nextFontId;
  }

  ~this() {
    destroy();
  }

  void destroy() {
    if (handle !is null) {
      yguilib_sdl3_ttf_close_font(handle);
      handle = null;
    }
    id_ = invalidFontId;
  }

  /**
   * Gets the unique monotonic identifier of this font instance
   * (`invalidFontId` if destroyed).
   */
  package(yguilib) @property ulong id() const {
    return id_;
  }

  /**
   * Gets the unscaled logical point size of the font in user space.
   */
  @property float size() const {
    return logicalPtSize;
  }

  /**
   * Gets the rasterization point size currently applied to the font handle.
   */
  @property float scaledSize() const {
    return logicalPtSize * currentScale;
  }

  /**
   * Dynamically updates the rendering scaling factor of the font.
   *
   * Kept as an internal renderer detail so the font rasterizer matches
   * display and units zoom changes without reallocating font resources.
   *
   * @param newScale New scaling multiplier (displayScaling * unitsScaling).
   * @return true if resized successfully, false otherwise.
   */
  package(yguilib) bool setScale(float newScale) {
    if (!handle) {
      return false;
    }
    float effectiveScale = newScale > 0.0f ? newScale : 1.0f;
    float targetSize = logicalPtSize * effectiveScale;
    if (yguilib_sdl3_ttf_set_font_size(handle, targetSize) == 0) {
      currentScale = effectiveScale;
      return true;
    }
    return false;
  }

  int height() const {
    return handle ? yguilib_sdl3_ttf_get_font_height(handle) : 0;
  }

  int ascent() const {
    return handle ? yguilib_sdl3_ttf_get_font_ascent(handle) : 0;
  }

  int descent() const {
    return handle ? yguilib_sdl3_ttf_get_font_descent(handle) : 0;
  }

  int lineSkip() const {
    return handle ? yguilib_sdl3_ttf_get_font_line_skip(handle) : 0;
  }

  PointF measureText(string text) const {
    if (!handle || text.length == 0) {
      return PointF(0.0f, 0.0f);
    }
    int w = 0;
    int h = 0;
    if (yguilib_sdl3_ttf_get_text_size(
      handle,
      text.ptr,
      text.length,
      &w,
      &h
    ) == 0) {
      return PointF(cast(float)w, cast(float)h);
    }
    return PointF(0.0f, 0.0f);
  }

  package(yguilib) yguilib_sdl3_ttf_Font* handle;

private:
  ulong id_ = invalidFontId;
  float logicalPtSize;
  float currentScale = 1.0f;
}

private ulong nextFontId = invalidFontId;

unittest {
  import yguilib.clibs.sdl3;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  Font f1 = new Font(cast(const(void)[])defaultTtfFontData, 12.0f);
  scope(exit) f1.destroy();
  assert(f1.id != invalidFontId);

  Font f2 = new Font(cast(const(void)[])defaultTtfFontData, 14.0f);
  scope(exit) f2.destroy();
  assert(f2.id != invalidFontId);
  assert(f1.id != f2.id);

  const ulong id2 = f2.id;
  f2.destroy();
  assert(f2.id == invalidFontId);
}
