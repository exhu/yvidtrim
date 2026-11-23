module yguilib.render.font_manager;

import std.math.traits : isFinite;
import yguilib.assets : defaultTtfFontData;
import yguilib.render.font : Font, defaultFontPtSize, invalidFontId;

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
  // No destructor: fonts hold SDL_ttf handles and are freed only by an
  // explicit `destroy()` on the main thread (see `texture.d`).

  /**
   * Destroys all cached `Font` instances and clears registered font sources.
   * The `onFontDestroyed` callback runs for every destroyed font.
   */
  void destroy() {
    foreach (font; cache) {
      destroyFont(font);
    }
    cache.clear();
    destroyScaledFonts();
    registry.clear();
  }

  /**
   * Sets the callback run with the id of every cached font right before
   * the manager destroys it (scaled-cache flush, re-registration of its
   * face, `destroy()`). `Renderer` uses it to drop the font's textures
   * from its `TextCache`. Pass null to detach.
   */
  void onFontDestroyed(void delegate(ulong fontId) callback) {
    fOnFontDestroyed = callback;
  }

  /**
   * Registers a custom font face from in-memory TTF binary data.
   *
   * Fonts already cached for `fontName` are destroyed, so later lookups
   * use the new data.
   *
   * @param fontName Unique name identifying the font face.
   * @param fontData In-memory TTF data buffer (must remain valid).
   */
  void registerFontFromMemory(string fontName, const(void)[] fontData) {
    assert(fontName.length > 0, "fontName must not be empty");
    assert(fontData.length > 0, "fontData must not be empty");
    dropFace(fontName);
    registry[fontName] = FontSource(
      FontSourceType.memory,
      fontData,
      null
    );
  }

  /**
   * Registers a custom font face from a font file path on disk.
   *
   * Fonts already cached for `fontName` are destroyed, so later lookups
   * use the new file.
   *
   * @param fontName Unique name identifying the font face.
   * @param filePath Path to the TTF font file.
   */
  void registerFontFromFile(string fontName, string filePath) {
    assert(fontName.length > 0, "fontName must not be empty");
    assert(filePath.length > 0, "filePath must not be empty");
    dropFace(fontName);
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
   * An unregistered `fontName` also uses the default face and shares its
   * cache entries, so registering that name later takes effect.
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
    const float size = sanitizeSize(ptSize);
    const ResolvedFace face = resolveSource(fontName);
    const FontKey key = FontKey(face.name, sizeMilliOf(size));
    auto p = key in cache;
    if (p !is null && *p !is null) {
      return *p;
    }

    Font font = openFont(face.source, size, totalScale);
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
    const float size = sanitizeSize(ptSize);
    const ResolvedFace face = resolveSource(fontName);
    const int eighths = quantizeScaleEighths(rasterScale, size);
    const ScaledFontKey key =
      ScaledFontKey(face.name, sizeMilliOf(size), eighths);
    auto p = key in scaledCache;
    if (p !is null && *p !is null) {
      return *p;
    }
    if (scaledCache.length >= maxScaledFonts) {
      destroyScaledFonts();
    }

    Font font = openFont(face.source, size, eighths / 8.0f);
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

  version (unittest) {
    /// Number of cached fonts (both caches) for the resolved face `name`.
    package(yguilib) size_t countForFace(string name) const {
      size_t n = 0;
      foreach (key, font; cache) {
        n += key.faceName == name ? 1 : 0;
      }
      foreach (key, font; scaledCache) {
        n += key.faceName == name ? 1 : 0;
      }
      return n;
    }

    /// Number of fonts in the scaled cache.
    package(yguilib) size_t scaledCount() const {
      return scaledCache.length;
    }
  }

private:
  enum size_t maxScaledFonts = 64;

  /// Registered face name to look up, and its source.
  static struct ResolvedFace {
    string name;
    FontSource source;
  }

  static float sanitizeSize(float ptSize) {
    return (isFinite(ptSize) && ptSize > 0.0f) ? ptSize : defaultFontPtSize;
  }

  static int sizeMilliOf(float size) {
    return cast(int)(size * 1000.0f + 0.5f);
  }

  /**
   * Maps `fontName` to its registered source. Empty, `"default"` and
   * unregistered names resolve to the built-in face with name `""`.
   */
  ResolvedFace resolveSource(string fontName) const {
    if (fontName.length > 0 && fontName != "default") {
      if (auto reg = fontName in registry) {
        return ResolvedFace(fontName, *reg);
      }
    }
    return ResolvedFace(
      "",
      FontSource(
        FontSourceType.memory,
        cast(const(void)[])defaultTtfFontData,
        null
      )
    );
  }

  /// Opens `source` at the sanitized `ptSize` and raster `scale`.
  static Font openFont(in FontSource source, float ptSize, float scale) {
    const float size = sanitizeSize(ptSize);
    if (source.type == FontSourceType.memory) {
      return Font.fromMemory(source.memoryData, size, scale);
    }
    return Font.fromFile(source.filePath, size, scale);
  }

  /// Notifies `fOnFontDestroyed` with the font's id, then destroys it.
  void destroyFont(Font font) {
    if (font is null) {
      return;
    }
    if (fOnFontDestroyed !is null && font.id != invalidFontId) {
      fOnFontDestroyed(font.id);
    }
    font.destroy();
  }

  void destroyScaledFonts() {
    foreach (font; scaledCache) {
      destroyFont(font);
    }
    scaledCache.clear();
  }

  /// Destroys and removes every cached font of the face `faceName`.
  void dropFace(string faceName) {
    FontKey[] keys;
    foreach (key, font; cache) {
      if (key.faceName == faceName) {
        keys ~= key;
      }
    }
    foreach (key; keys) {
      destroyFont(cache[key]);
      cache.remove(key);
    }
    ScaledFontKey[] scaledKeys;
    foreach (key, font; scaledCache) {
      if (key.faceName == faceName) {
        scaledKeys ~= key;
      }
    }
    foreach (key; scaledKeys) {
      destroyFont(scaledCache[key]);
      scaledCache.remove(key);
    }
  }

  FontSource[string] registry;
  Font[FontKey] cache;
  Font[ScaledFontKey] scaledCache;
  void delegate(ulong fontId) fOnFontDestroyed;
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

// Registration invalidates cached fonts of that face (review 2.2).
unittest {
  import std.algorithm.searching : canFind;
  import yguilib.clibs.sdl3;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto fm = new FontManager();
  scope(exit) fm.destroy();
  ulong[] destroyed;
  fm.onFontDestroyed((ulong id) { destroyed ~= id; });

  // An unregistered name falls back to the default face, cached under "".
  Font before = fm.getFont(12.0f, "Foo", 1.0f);
  assert(before is fm.getFont(12.0f, null, 1.0f));
  Font scaledBefore = fm.getFontAtScale(12.0f, "Foo", 2.0f);
  assert(scaledBefore is fm.getFontAtScale(12.0f, null, 2.0f));
  assert(fm.countForFace("Foo") == 0);
  const ulong beforeId = before.id;

  // After registration "Foo" opens the new source (a missing file throws).
  fm.registerFontFromFile("Foo", "/nonexistent/yguilib-test-foo.ttf");
  assert(destroyed.length == 0);
  bool threw = false;
  try {
    fm.getFont(12.0f, "Foo", 1.0f);
  } catch (Exception e) {
    threw = true;
  }
  assert(threw);
  assert(fm.countForFace("Foo") == 0);

  const(void)[] dataA = (cast(const(ubyte)[])defaultTtfFontData).dup;
  fm.registerFontFromMemory("Foo", dataA);
  Font fooA = fm.getFont(12.0f, "Foo", 1.0f);
  assert(fooA !is before && fooA.id != beforeId);
  assert(fm.getFont(12.0f, "Foo", 1.0f) is fooA);
  Font fooAScaled = fm.getFontAtScale(12.0f, "Foo", 2.0f);
  assert(fooAScaled !is scaledBefore);
  assert(fm.countForFace("Foo") == 2);
  const ulong idA = fooA.id;
  const ulong idAScaled = fooAScaled.id;

  // Re-registering destroys the cached fonts and reports their ids.
  const(void)[] dataB = (cast(const(ubyte)[])defaultTtfFontData).dup;
  fm.registerFontFromMemory("Foo", dataB);
  assert(fooA.id == invalidFontId && fooAScaled.id == invalidFontId);
  assert(destroyed.length == 2);
  assert(destroyed.canFind(idA) && destroyed.canFind(idAScaled));
  assert(fm.countForFace("Foo") == 0);
  Font fooB = fm.getFont(12.0f, "Foo", 1.0f);
  assert(fooB.id != idA && fooB.id != beforeId);
  // The default face is untouched.
  assert(before.id == beforeId);
  assert(fm.getFont(12.0f, null, 1.0f) is before);

  // destroy() reports every remaining font.
  const ulong idB = fooB.id;
  const ulong idScaledBefore = scaledBefore.id;
  destroyed = null;
  fm.destroy();
  assert(destroyed.length == 3);
  assert(destroyed.canFind(beforeId) && destroyed.canFind(idB));
  assert(destroyed.canFind(idScaledBefore));
}
