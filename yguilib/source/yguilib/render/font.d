/**
 * TTF font handle (SDL_ttf wrapper) with a logical point size and a
 * raster scale.
 *
 * `Font` objects are created and cached by `FontManager`; a font is freed
 * only by an explicit main-thread `destroy()`. Every live font has a unique
 * monotonic `id`, used as the text run cache key.
 */
module yguilib.render.font;

import std.math.traits : isFinite;
import yguilib.clibs.sdl3_ttf;
import yguilib.render.render_types : PointF;

final class Font {
  /**
   * Loads a font from memory data.
   *
   * Font point sizes (`ptSize`) in user space are unscaled logical points.
   * Scaling (`scale = displayScaling * unitsScaling`) is an internal renderer
   * detail used to rasterize glyphs at native display resolution.
   *
   * For GC-allocated slices, `Font` retains a reference until `destroy()`.
   * Non-GC buffers (such as C/malloc memory) must remain valid until
   * `destroy()`.
   *
   * Params:
   *   fontData = TTF binary data in memory.
   *   ptSize = Unscaled logical point size in user space.
   *   scale = Rendering scaling factor (<= 0 or non-finite falls back to 1.0f).
   */
  static Font fromMemory(
    const(void)[] fontData,
    float ptSize,
    float scale
  ) {
    assert(fontData.length > 0, "fontData must not be empty");
    assert(
      isFinite(ptSize) && ptSize > 0.0f,
      "ptSize must be finite and positive"
    );
    const float effectiveScale =
      (isFinite(scale) && scale > 0.0f) ? scale : 1.0f;
    auto h = yguilib_sdl3_ttf_open_font_from_mem(
      fontData.ptr,
      fontData.length,
      ptSize * effectiveScale
    );
    if (!h) {
      throw new Exception("Failed to load font from memory: " ~ lastError());
    }
    auto font = new Font(h, ptSize, effectiveScale);
    font.fMemoryData = fontData;
    return font;
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
   *   scale = Rendering scaling factor (<= 0 or non-finite falls back to 1.0f).
   */
  static Font fromFile(
    string filePath,
    float ptSize,
    float scale
  ) {
    assert(filePath.length > 0, "filePath must not be empty");
    assert(
      isFinite(ptSize) && ptSize > 0.0f,
      "ptSize must be finite and positive"
    );
    const float effectiveScale =
      (isFinite(scale) && scale > 0.0f) ? scale : 1.0f;
    import std.string : toStringz;
    auto h = yguilib_sdl3_ttf_open_font(
      filePath.toStringz(),
      ptSize * effectiveScale
    );
    if (!h) {
      throw new Exception(
        "Failed to load font from file: " ~ filePath ~ ": " ~ lastError()
      );
    }
    return new Font(h, ptSize, effectiveScale);
  }

  /**
   * Closes the SDL_ttf handle. There is no destructor: the GC may finalize
   * on any thread or after `TTF_Quit()`, so the handle is freed only by
   * this explicit call on the main thread; an undestroyed font leaks.
   */
  void destroy() {
    if (fHandle !is null) {
      yguilib_sdl3_ttf_close_font(fHandle);
      fHandle = null;
    }
    fMemoryData = null;
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

  /// Total font height in raster pixels at `scaledSize`.
  int height() const {
    return fHandle ? yguilib_sdl3_ttf_get_font_height(fHandle) : 0;
  }

  /// Font ascent above baseline in raster pixels at `scaledSize`.
  int ascent() const {
    return fHandle ? yguilib_sdl3_ttf_get_font_ascent(fHandle) : 0;
  }

  /// Font descent below baseline in raster pixels at `scaledSize`.
  int descent() const {
    return fHandle ? yguilib_sdl3_ttf_get_font_descent(fHandle) : 0;
  }

  /// Recommended line spacing in raster pixels at `scaledSize`.
  int lineSkip() const {
    return fHandle ? yguilib_sdl3_ttf_get_font_line_skip(fHandle) : 0;
  }

  /// Measures `text` in raster pixels at `scaledSize`.
  PointF measureText(string text) const {
    if (!fHandle || text.length == 0) {
      return PointF(0.0f, 0.0f);
    }
    int w = 0;
    int h = 0;
    if (yguilib_sdl3_ttf_get_text_size(
      fHandle,
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

    if (!fHandle) {
      errorf("Font.scale: font already destroyed");
      return;
    }
    const float effectiveScale =
      (isFinite(newScale) && newScale > 0.0f) ? newScale : 1.0f;
    const float targetSize = logicalPtSize * effectiveScale;
    if (yguilib_sdl3_ttf_set_font_size(fHandle, targetSize) != 0) {
      errorf(
        "Font.scale(%s) failed: %s",
        targetSize,
        lastError()
      );
      return;
    }
    currentScale = effectiveScale;
  }

  /// Underlying SDL_ttf font handle (null when destroyed).
  @property inout(yguilib_sdl3_ttf_Font)* handle()
    inout nothrow @safe @nogc pure {
    return fHandle;
  }

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
    assert(
      isFinite(ptSize) && ptSize > 0.0f,
      "ptSize must be finite and positive"
    );
    this.fHandle = handle;
    this.logicalPtSize = ptSize;
    this.currentScale = (isFinite(scale) && scale > 0.0f) ? scale : 1.0f;
    this.fId = ++nextFontId;
  }

  yguilib_sdl3_ttf_Font* fHandle;
  const(void)[] fMemoryData;
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
  import std.file : remove, tempDir, write;
  import std.path : buildPath;
  import std.process : thisProcessID;
  import std.conv : to;
  import yguilib.assets : defaultTtfFontData;
  import yguilib.clibs.sdl3;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  Font f1 = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData, 12.0f, 1.0f
  );
  scope(exit) f1.destroy();
  assert(f1.id != invalidFontId);
  assert(f1.size == 12.0f);
  assert(f1.scaledSize == 12.0f);

  // Metrics and measureText at 1x scale.
  assert(f1.height() > 0);
  assert(f1.ascent() > 0);
  assert(f1.lineSkip() > 0);
  assert(f1.descent() <= 0 || f1.descent() > 0);
  const PointF m1 = f1.measureText("Hello");
  assert(m1.x > 0.0f && m1.y > 0.0f);
  assert(f1.measureText("") == PointF(0.0f, 0.0f));

  // scale() updates scaledSize and falls back to 1.0f for non-finite/<=0.
  f1.scale(2.0f);
  assert(f1.scaledSize == 24.0f);
  const PointF m2 = f1.measureText("Hello");
  assert(m2.x > m1.x && m2.y > m1.y);
  foreach (const float bad; [0.0f, -1.0f, float.nan, float.infinity]) {
    f1.scale(bad);
    assert(f1.scaledSize == 12.0f);
  }

  // Non-finite / <= 0 scale in fromMemory falls back to 1.0f.
  Font fBadScale = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData, 10.0f, float.infinity
  );
  scope(exit) fBadScale.destroy();
  assert(fBadScale.scaledSize == 10.0f);

  // fromFile succeeds for a valid TTF file and throws with error on missing.
  const string tmpPath = buildPath(
    tempDir(),
    "yguilib-font-test-" ~ thisProcessID().to!string ~ ".ttf"
  );
  write(tmpPath, defaultTtfFontData);
  scope(exit) remove(tmpPath);
  Font fFile = Font.fromFile(tmpPath, 16.0f, 1.5f);
  scope(exit) fFile.destroy();
  assert(fFile.id != invalidFontId);
  assert(fFile.scaledSize == 24.0f);
  assert(fFile.height() > 0);

  bool threw = false;
  try {
    Font.fromFile("/nonexistent/yguilib-missing-font.ttf", 12.0f, 1.0f);
  } catch (Exception e) {
    threw = e.msg.length > 0;
  }
  assert(threw);

  Font f2 = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData, 14.0f, 1.0f
  );
  scope(exit) f2.destroy();
  assert(f2.id != invalidFontId);
  assert(f1.id != f2.id);

  f2.destroy();
  assert(f2.id == invalidFontId);
  assert(f2.handle is null);
  assert(f2.height() == 0);
  assert(f2.ascent() == 0);
  assert(f2.descent() == 0);
  assert(f2.lineSkip() == 0);
  assert(f2.measureText("Hello") == PointF(0.0f, 0.0f));
}
