module yguilib.render.font;

import yguilib.clibs.sdl3_ttf;
import yguilib.render.render_types : PointF;
import yguilib.assets : defaultTtfFontData;

package(yguilib) enum float defaultFontPtSize = 16.0 * 96.0 / 72.0;

final class Font {
  /**
   * Loads a font from memory data.
   *
   * Font point sizes (`ptSize`) in user space are unscaled logical points.
   * Scaling (`scale = displayScaling * unitsScaling`) is an internal renderer
   * detail used to rasterize glyphs at native display resolution.
   *
   * @param fontData TTF binary data in memory.
   * @param ptSize Unscaled logical point size in user space.
   * @param scale Rendering scaling factor (defaults to 1.0f).
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
  }

  ~this() {
    destroy();
  }

  void destroy() {
    if (handle !is null) {
      yguilib_sdl3_ttf_close_font(handle);
      handle = null;
    }
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
   * Dynamically updates the unscaled logical point size of the font.
   *
   * Font point units are kept unscaled in user space. The renderer's current
   * scaling factor is reapplied internally to update the raster size in place.
   *
   * @param newPtSize New unscaled point size in logical units.
   * @return true if resized successfully, false otherwise.
   */
  bool setSize(float newPtSize) {
    if (!handle || newPtSize <= 0.0f) {
      return false;
    }
    float targetSize = newPtSize * currentScale;
    if (yguilib_sdl3_ttf_set_font_size(handle, targetSize) == 0) {
      logicalPtSize = newPtSize;
      return true;
    }
    return false;
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
  bool setScale(float newScale) {
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
  private float logicalPtSize;
  private float currentScale = 1.0f;
}
