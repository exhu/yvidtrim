module yguilib.render.font_manager;

import std.math.traits : isFinite;
import yguilib.assets : defaultTtfFontData;
import yguilib.render.font : Font, defaultFontPtSize;

private:

enum FontSourceType {
  memory,
  file,
}

struct FontSource {
  FontSourceType type;
  const(void)[] memoryData;
  string filePath;
}

struct FontKey {
  string faceName;
  int sizeMilli;
}

struct ScaledFontKey {
  string faceName;
  int sizeMilli;
  int scaleEighths;
}

package(yguilib):

/**
 * Manages font typefaces and caches `Font` instances per point size.
 *
 * `FontManager` maintains font face sources (such as embedded TTF font data
 * or registered custom fonts) and lazily instantiates `Font` objects on demand.
 * Cached instances are shared across callers requesting the same font face
 * and point size, avoiding duplicate FreeType handles and rasterizer thrashing.
 *
 * For memory/embedded fonts, underlying raw font data buffers are referenced
 * directly and shared across all sizes without duplication.
 */
final class FontManager {
  ~this() {
    destroy();
  }

  /**
   * Destroys all cached `Font` instances and clears registered font sources.
   */
  void destroy() {
    foreach (font; cache) {
      if (font !is null) {
        font.destroy();
      }
    }
    cache.clear();
    foreach (font; scaledCache) {
      if (font !is null) {
        font.destroy();
      }
    }
    scaledCache.clear();
    registry.clear();
  }

  /**
   * Registers a custom font face from in-memory TTF binary data.
   *
   * @param fontName Unique name identifying the font face.
   * @param fontData In-memory TTF data buffer (must remain valid).
   */
  void registerFontFromMemory(string fontName, const(void)[] fontData) {
    assert(fontName.length > 0, "fontName must not be empty");
    assert(fontData.length > 0, "fontData must not be empty");
    registry[fontName] = FontSource(
      FontSourceType.memory,
      fontData,
      null
    );
  }

  /**
   * Registers a custom font face from a font file path on disk.
   *
   * @param fontName Unique name identifying the font face.
   * @param filePath Path to the TTF font file.
   */
  void registerFontFromFile(string fontName, string filePath) {
    assert(fontName.length > 0, "fontName must not be empty");
    assert(filePath.length > 0, "filePath must not be empty");
    registry[fontName] = FontSource(
      FontSourceType.file,
      null,
      filePath
    );
  }

  /**
   * Checks whether a font face is registered or is the built-in default font.
   *
   * An empty string or `"default"` always resolves to the built-in font face.
   *
   * @param fontName Name of the font face to check.
   * @return true if the font face exists or is default, false otherwise.
   */
  bool hasFont(string fontName) const {
    if (fontName.length == 0 || fontName == "default") {
      return true;
    }
    return (fontName in registry) !is null;
  }

  /**
   * Retrieves a cached `Font` instance for a given size and font face,
   * lazily instantiating it on first request.
   *
   * When `fontName` is empty or `"default"`, the built-in embedded font
   * (`defaultTtfFontData`) is used. If this is the first time the font is
   * requested at this size, it is created lazily and stored in the cache.
   *
   * Non-positive, infinite, or NaN `ptSize` values automatically fall back
   * to `defaultFontPtSize`.
   *
   * @param ptSize Logical point size in user space.
   * @param fontName Registered font name, or null/empty for default font.
   * @param totalScale Raster scaling multiplier (display * units scaling).
   * @return The cached `Font` instance.
   */
  Font getFont(
    float ptSize,
    string fontName,
    float totalScale
  ) {
    const float sanitizedSize =
      (isFinite(ptSize) && ptSize > 0.0f) ? ptSize : defaultFontPtSize;
    const string effectiveFace =
      (fontName.length > 0 && fontName != "default") ? fontName : "";
    const int sizeMilli = cast(int)(sanitizedSize * 1000.0f + 0.5f);

    FontKey key = FontKey(effectiveFace, sizeMilli);
    auto p = key in cache;
    if (p !is null && *p !is null) {
      return *p;
    }

    FontSource source;
    if (effectiveFace.length == 0) {
      source = FontSource(
        FontSourceType.memory,
        cast(const(void)[])defaultTtfFontData,
        null
      );
    } else {
      auto reg = effectiveFace in registry;
      if (reg !is null) {
        source = *reg;
      } else {
        source = FontSource(
          FontSourceType.memory,
          cast(const(void)[])defaultTtfFontData,
          null
        );
      }
    }

    Font font;
    if (source.type == FontSourceType.memory) {
      font = Font.fromMemory(source.memoryData, sanitizedSize, totalScale);
    } else {
      font = Font.fromFile(source.filePath, sanitizedSize, totalScale);
    }

    cache[key] = font;
    return font;
  }

  /**
   * Like `getFont`, but rasterized at `rasterScale` (quantized to 1/8
   * steps and clamped to a sane range) independent of the display scaling.
   * Instances are cached separately and are not touched by `setScaling`.
   * Used by Canvas text so glyphs match the effective drawing scale.
   *
   * @param ptSize Logical point size in user space.
   * @param fontName Registered font name, or null/empty for default font.
   * @param rasterScale Desired raster scale (non-finite or <= 0 gives 1).
   * @return The cached `Font` instance.
   */
  Font getFontAtScale(float ptSize, string fontName, float rasterScale) {
    const float sanitizedSize =
      (isFinite(ptSize) && ptSize > 0.0f) ? ptSize : defaultFontPtSize;
    const string effectiveFace =
      (fontName.length > 0 && fontName != "default") ? fontName : "";
    const int sizeMilli = cast(int)(sanitizedSize * 1000.0f + 0.5f);
    const int eighths = quantizeScaleEighths(rasterScale, sanitizedSize);

    ScaledFontKey key = ScaledFontKey(effectiveFace, sizeMilli, eighths);
    auto p = key in scaledCache;
    if (p !is null && *p !is null) {
      return *p;
    }
    if (scaledCache.length >= maxScaledFonts) {
      foreach (font; scaledCache) {
        if (font !is null) {
          font.destroy();
        }
      }
      scaledCache.clear();
    }

    const float scale = eighths / 8.0f;
    FontSource source = FontSource(
      FontSourceType.memory,
      cast(const(void)[])defaultTtfFontData,
      null
    );
    if (effectiveFace.length > 0) {
      if (auto reg = effectiveFace in registry) {
        source = *reg;
      }
    }
    Font font;
    if (source.type == FontSourceType.memory) {
      font = Font.fromMemory(source.memoryData, sanitizedSize, scale);
    } else {
      font = Font.fromFile(source.filePath, sanitizedSize, scale);
    }
    scaledCache[key] = font;
    return font;
  }

  /**
   * Updates the rasterization scale on all currently cached font instances.
   *
   * Called when display DPI or units zoom changes so that fonts render at
   * native resolution while preserving their logical point sizes.
   *
   * @param totalScale New raster scaling multiplier.
   */
  void setScaling(float totalScale) {
    foreach (font; cache) {
      if (font !is null) {
        font.setScale(totalScale);
      }
    }
  }

private:
  enum size_t maxScaledFonts = 64;

  FontSource[string] registry;
  Font[FontKey] cache;
  Font[ScaledFontKey] scaledCache;
}

/**
 * Raster scale in 1/8 steps, clamped to [1/8, 16] and so that the pixel
 * size `ptSize * scale` stays at most 1024.
 */
package(yguilib) int quantizeScaleEighths(float scale, float ptSize)
  nothrow @safe @nogc pure {
  import std.algorithm.comparison : max, min;
  import std.math : isFinite, round;

  float s = (isFinite(scale) && scale > 0.0f) ? scale : 1.0f;
  s = min(s, 16.0f, 1024.0f / ptSize);
  return max(1, cast(int)round(s * 8.0f));
}

unittest {
  import yguilib.clibs.sdl3;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto fm = new FontManager();
  scope(exit) fm.destroy();

  // Verify default font lookup
  Font f11 = fm.getFont(11.0f, null, 1.0f);
  assert(f11 !is null);
  assert(f11.size == 11.0f);

  // Requesting the exact same font size reuses the cached instance
  Font f11Again = fm.getFont(11.0f, null, 1.0f);
  assert(f11 is f11Again);

  // Requesting a different size returns a distinct Font instance
  Font f24 = fm.getFont(24.0f, null, 1.0f);
  assert(f24 !is null);
  assert(f24.size == 24.0f);
  assert(f24 !is f11);

  // Fallbacks for invalid sizes
  assert(fm.getFont(0.0f, null, 1.0f).size == defaultFontPtSize);
  assert(fm.getFont(-5.0f, null, 1.0f).size == defaultFontPtSize);
  assert(fm.getFont(float.nan, null, 1.0f).size == defaultFontPtSize);
  assert(fm.getFont(float.infinity, null, 1.0f).size == defaultFontPtSize);

  // Scaling update
  fm.setScaling(2.0f);
  assert(f11.scaledSize == 22.0f);
  assert(f24.scaledSize == 48.0f);

  // Scaled fonts: quantized, cached separately, untouched by setScaling
  Font s15 = fm.getFontAtScale(10.0f, null, 1.51f);
  assert(s15.scaledSize == 15.0f);
  assert(fm.getFontAtScale(10.0f, null, 1.49f) is s15);
  assert(fm.getFontAtScale(10.0f, null, 2.0f) !is s15);
  fm.setScaling(3.0f);
  assert(s15.scaledSize == 15.0f);
  assert(quantizeScaleEighths(float.nan, 10.0f) == 8);
  assert(quantizeScaleEighths(0.0f, 10.0f) == 8);
  assert(quantizeScaleEighths(100.0f, 10.0f) == 128);
  assert(quantizeScaleEighths(1e-6f, 10.0f) == 1);
}
