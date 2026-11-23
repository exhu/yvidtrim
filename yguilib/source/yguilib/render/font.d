/**
 * TTF font handle (SDL_ttf wrapper) with a logical point size and a
 * raster scale.
 *
 * `Font` objects are created and cached by `FontManager`; a font is freed
 * only by an explicit main-thread `destroy()`. Every live font has a unique
 * monotonic `id`, used as the `TextCache` key.
 */
module yguilib.render.font;

import yguilib.clibs.sdl3_ttf;
import yguilib.render.render_types : PointF;
import yguilib.assets : defaultTtfFontData;

final class Font {
  /**
   * Loads a font from memory data.
   *
   * Font point sizes (`ptSize`) in user space are unscaled logical points.
   * Scaling (`scale = displayScaling * unitsScaling`) is an internal renderer
   * detail used to rasterize glyphs at native display resolution.
   *
   * Params:
   *   fontData = TTF binary data in memory.
   *   ptSize = Unscaled logical point size in user space.
   *   scale = Rendering scaling factor (defaults to 1.0f).
   */
  static Font fromMemory(
    const(void)[] fontData,
    float ptSize,
    float scale
  ) {
    assert(fontData.length > 0, "fontData must not be empty");
    assert(ptSize > 0.0f, "ptSize must be positive");
    const float effectiveScale = scale > 0.0f ? scale : 1.0f;
    auto h = yguilib_sdl3_ttf_open_font_from_mem(
      fontData.ptr,
      fontData.length,
      ptSize * effectiveScale
    );
    if (!h) {
      throw new Exception("Failed to load font from memory");
    }
    return new Font(h, ptSize, effectiveScale);
  }

  /**
   * Loads a font from a file path.
   *
   * Font point sizes (`ptSize`) in user space are unscaled logical points.
   * Scaling (`scale = displayScaling * unitsScaling`) is an internal renderer
   * detail used to rasterize glyphs at native display resolution.
   *
   * Params:
   *   filePath = Path to the TTF font file.
   *   ptSize = Unscaled logical point size in user space.
   *   scale = Rendering scaling factor (defaults to 1.0f).
   */
  static Font fromFile(
    string filePath,
    float ptSize,
    float scale
  ) {
    assert(filePath.length > 0, "filePath must not be empty");
    assert(ptSize > 0.0f, "ptSize must be positive");
    const float effectiveScale = scale > 0.0f ? scale : 1.0f;
    import std.string : toStringz;
    auto h = yguilib_sdl3_ttf_open_font(
      filePath.toStringz(),
      ptSize * effectiveScale
    );
    if (!h) {
      throw new Exception("Failed to load font from file: " ~ filePath);
    }
    return new Font(h, ptSize, effectiveScale);
  }

  /**
   * Closes the SDL_ttf handle. There is no destructor: the GC may finalize
   * on any thread or after `TTF_Quit()`, so the handle is freed only by
   * this explicit call on the main thread; an undestroyed font leaks.
   */
  void destroy() {
    if (handle !is null) {
      yguilib_sdl3_ttf_close_font(handle);
      handle = null;
    }
    fId = invalidFontId;
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

package(yguilib):
  /**
   * Gets the unique monotonic identifier of this font instance
   * (`invalidFontId` if destroyed).
   */
  @property ulong id() const {
    return fId;
  }

  /**
   * Dynamically updates the rendering scaling factor of the font.
   *
   * Kept as an internal renderer detail so the font rasterizer matches
   * display and units zoom changes without reallocating font resources.
   *
   * On failure an error is logged and the font keeps its previous size and
   * scale.
   *
   * Params:
   *   newScale = New scaling multiplier (displayScaling * unitsScaling).
   */
  void scale(float newScale) {
    import std.logger : errorf;

    if (!handle) {
      errorf("Font.scale: font already destroyed");
      return;
    }
    const float effectiveScale = newScale > 0.0f ? newScale : 1.0f;
    const float targetSize = logicalPtSize * effectiveScale;
    if (yguilib_sdl3_ttf_set_font_size(handle, targetSize) != 0) {
      errorf(
        "Font.scale(%s) failed: %s",
        targetSize,
        lastError()
      );
      return;
    }
    currentScale = effectiveScale;
  }

  yguilib_sdl3_ttf_Font* handle;

private:
  static string lastError() {
    import std.string : fromStringz;

    return yguilib_sdl3_ttf_get_error().fromStringz().idup;
  }

  this(
    yguilib_sdl3_ttf_Font* handle,
    float ptSize,
    float scale
  ) {
    assert(handle !is null);
    assert(ptSize > 0.0f, "ptSize must be positive");
    this.handle = handle;
    this.logicalPtSize = ptSize;
    this.currentScale = scale > 0.0f ? scale : 1.0f;
    this.fId = ++nextFontId;
  }

  ulong fId = invalidFontId;
  float logicalPtSize;
  float currentScale = 1.0f;
}

package(yguilib):
enum float defaultFontPtSize = 11.0f;
enum ulong invalidFontId = 0;

private:
ulong nextFontId = invalidFontId;

unittest {
  import yguilib.clibs.sdl3;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  Font f1 = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData, 12.0f, 1.0f
  );
  scope(exit) f1.destroy();
  assert(f1.id != invalidFontId);

  Font f2 = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData, 14.0f, 1.0f
  );
  scope(exit) f2.destroy();
  assert(f2.id != invalidFontId);
  assert(f1.id != f2.id);

  f2.destroy();
  assert(f2.id == invalidFontId);
}
