/**
 * Text bitmaps as GL textures: one texture per (font id, raster size,
 * outline, string), kept in an LRU `TextCache` with per-frame eviction
 * protection (see the class doc).
 */
module yguilib.render.internal.text_cache;

package(yguilib):

import glad2.gles2;
import std.array : Appender;
import yguilib.clibs.sdl3_ttf;
import yguilib.render.internal.gl_util : uploadRgbaTexture;
import yguilib.render.font : Font, invalidFontId;

struct TextTexture {
  GLuint textureId = 0;
  int width = 0;
  int height = 0;

  bool isValid() const {
    return textureId != 0;
  }

  void destroy() {
    if (textureId != 0) {
      glDeleteTextures(1, &textureId);
      textureId = 0;
    }
    width = 0;
    height = 0;
  }
}

private:

struct TextCacheKey {
  ulong fontId;
  float ptSize;
  int outlinePx;
  string text;
}

struct TextCacheEntry {
  TextTexture texture;
  /// `TextCache.fTick` of the last hit or of the insert.
  ulong lastUse;
}

struct EvictCandidate {
  ulong lastUse;
  TextCacheKey key;
}

package(yguilib):

/**
 * LRU cache of text textures keyed by font id, size, outline and text.
 *
 * Every hit and insert stamps the entry with an increasing tick, so a
 * hit does not allocate. `beginFrame()` marks the start of a frame
 * (called by `Renderer.clearFrame` outside render targets).
 *
 * Eviction policy: when an insert finds `length >= maxEntries`, the
 * oldest `max(1, maxEntries / 4)` entries not used since the last
 * `beginFrame()` are destroyed. Entries used in the current frame are
 * kept, so a frame drawing more than `maxEntries` strings lets the cache
 * grow instead of thrashing; at the hard cap of `2 * maxEntries` the
 * oldest entries are evicted anyway, even those used in this frame.
 */
final class TextCache {
  enum size_t maxCacheEntries = 512;

  this(size_t maxEntries) {
    assert(maxEntries > 0, "maxEntries must be positive");
    this.maxEntries = maxEntries;
  }

  // No destructor: textures are freed only by an explicit `clear()` on
  // the main thread with the GL context current (see `texture.d`).

  @property size_t length() const {
    return cache.length;
  }

  version (unittest) {
    /// Number of cached textures rendered with the font `fontId`.
    size_t countForFont(ulong fontId) const {
      size_t n = 0;
      foreach (key, ref entry; cache) {
        n += key.fontId == fontId ? 1 : 0;
      }
      return n;
    }
  }

  /**
   * Destroys and removes every texture rendered with the font `fontId`.
   * Called before that font is destroyed, since its id is never reused.
   */
  void removeFont(ulong fontId) {
    fEvictScratch.clear();
    foreach (key, ref entry; cache) {
      if (key.fontId == fontId) {
        fEvictScratch.put(EvictCandidate(entry.lastUse, key));
      }
    }
    foreach (ref cand; fEvictScratch[]) {
      removeKey(cand.key);
    }
    fEvictScratch.clear();
  }

  /**
   * Marks the start of a frame: entries used from now on are protected
   * from eviction until the next `beginFrame()` (see the class doc).
   */
  void beginFrame() {
    fFrameStartTick = fTick + 1;
  }

  bool contains(const Font font, string text, int outlinePx) const {
    if (font is null || font.handle is null ||
        font.id == invalidFontId || text.length == 0) {
      return false;
    }
    const TextCacheKey key = TextCacheKey(
      font.id, font.scaledSize, outlinePx, text
    );
    return (key in cache) !is null;
  }

  void clear() {
    foreach (key, ref entry; cache) {
      entry.texture.destroy();
    }
    cache.clear();
    fEvictScratch.clear();
  }

  /**
   * Cached texture of `text` (see `createTextTexture`), created on a miss.
   * Returns an invalid texture for a null/destroyed font or empty text.
   */
  TextTexture textureFor(Font font, string text, int outlinePx) {
    if (font is null || font.handle is null ||
        font.id == invalidFontId || text.length == 0) {
      return TextTexture();
    }

    const TextCacheKey key = TextCacheKey(
      font.id, font.scaledSize, outlinePx, text
    );
    auto p = key in cache;
    if (p !is null) {
      p.lastUse = ++fTick;
      return p.texture;
    }

    if (cache.length >= maxEntries) {
      evictOldest();
    }

    TextTexture tex = createTextTexture(font, text, outlinePx);
    if (tex.isValid()) {
      cache[key] = TextCacheEntry(tex, ++fTick);
    }
    return tex;
  }

  /**
   * White-on-transparent bitmap of `text`. With `outlinePx` > 0 the bitmap
   * is the glyph outline ring (hole inside), `outlinePx` larger per side;
   * the shared font's outline is reset to 0 afterwards.
   */
  static TextTexture createTextTexture(
    Font font, string text, int outlinePx
  ) {
    if (font is null || font.handle is null || text.length == 0
      || outlinePx < 0) {
      return TextTexture();
    }
    if (outlinePx > 0 &&
        yguilib_sdl3_ttf_set_font_outline(font.handle, outlinePx) != 0) {
      return TextTexture();
    }
    scope(exit) {
      if (outlinePx > 0) {
        yguilib_sdl3_ttf_set_font_outline(font.handle, 0);
      }
    }

    auto surf = yguilib_sdl3_ttf_render_text_blended(
      font.handle,
      text.ptr,
      text.length,
      255,
      255,
      255,
      255
    );
    if (surf is null) {
      return TextTexture();
    }
    scope(exit) yguilib_sdl3_ttf_destroy_surface(surf);

    int w = 0;
    int h = 0;
    yguilib_sdl3_ttf_get_surface_size(surf, &w, &h);
    const int pitch = yguilib_sdl3_ttf_get_surface_pitch(surf);
    const void* pixels = yguilib_sdl3_ttf_get_surface_pixels(surf);
    if (w <= 0 || h <= 0 || pixels is null) {
      return TextTexture();
    }

    const GLuint texId = uploadRgbaTexture(pixels, w, h, pitch);
    return TextTexture(texId, w, h);
  }

private:
  /// Hard cap on `length`, reached only within one frame.
  size_t hardCap() const {
    return 2 * maxEntries;
  }

  /**
   * Destroys the oldest `max(1, maxEntries / 4)` entries not used in the
   * current frame. With none and `length` at `hardCap()`, it destroys
   * the oldest entries regardless; otherwise the cache grows.
   */
  void evictOldest() {
    import std.algorithm.comparison : max, min;
    import std.algorithm.sorting : sort;

    // At the cap every entry is a candidate; stale entries still sort
    // first, since their ticks are below `fFrameStartTick`.
    const bool atCap = cache.length >= hardCap();
    fEvictScratch.clear();
    foreach (key, ref entry; cache) {
      if (atCap || entry.lastUse < fFrameStartTick) {
        fEvictScratch.put(EvictCandidate(entry.lastUse, key));
      }
    }
    EvictCandidate[] cands = fEvictScratch[];
    sort!((a, b) => a.lastUse < b.lastUse)(cands);
    const size_t evictCount = min(max(1, maxEntries / 4), cands.length);
    foreach (ref cand; cands[0 .. evictCount]) {
      removeKey(cand.key);
    }
    fEvictScratch.clear();
  }

  void removeKey(const TextCacheKey key) {
    if (auto p = key in cache) {
      p.texture.destroy();
      cache.remove(key);
    }
  }

  size_t maxEntries = maxCacheEntries;
  TextCacheEntry[TextCacheKey] cache;
  /// Incremented on every hit and insert (see `TextCacheEntry.lastUse`).
  ulong fTick = 0;
  /// First tick of the current frame (set by `beginFrame()`).
  ulong fFrameStartTick = 0;
  /// Reused eviction / removal buffer, so evicting rarely allocates.
  Appender!(EvictCandidate[]) fEvictScratch;
}

unittest {
  import std.conv : to;
  import yguilib.assets : defaultTtfFontData;
  import yguilib.clibs.sdl3;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(160, 120, "test_text_cache");
  win.create();
  scope(exit) win.destroy();

  Font fontA = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData, 12.0f, 1.0f
  );
  scope(exit) fontA.destroy();

  auto tc = new TextCache(8);
  scope(exit) tc.clear();

  // Insert 8 distinct entries (capacity reached)
  tc.beginFrame();
  foreach (i; 0 .. 8) {
    TextTexture tex = tc.textureFor(fontA, "item" ~ i.to!string, 0);
    assert(tex.isValid());
  }
  assert(tc.length == 8);

  // Cache hit on "item0" in a new frame makes it the most recently used
  tc.beginFrame();
  TextTexture tex0 = tc.textureFor(fontA, "item0", 0);
  assert(tex0.isValid());
  assert(tc.length == 8);

  // Adding 9th item triggers eviction of oldest 25% (8 / 4 = 2 items).
  // "item1" and "item2" were the oldest and should be evicted.
  // "item0" was touched and must still be present.
  TextTexture tex8 = tc.textureFor(fontA, "item8", 0);
  assert(tex8.isValid());
  assert(tc.length == 7);
  assert(!tc.contains(fontA, "item1", 0));
  assert(!tc.contains(fontA, "item2", 0));
  assert(tc.contains(fontA, "item0", 0));
  assert(tc.contains(fontA, "item8", 0));

  // Destroying fontA and allocating fontB produces distinct font IDs
  Font fontB = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData, 12.0f, 1.0f
  );
  scope(exit) fontB.destroy();
  assert(fontB.id != fontA.id);
  assert(!tc.contains(fontB, "item0", 0));
}

// Frame protection, hard cap and allocation-free hits (review 1.1, 2.5).
unittest {
  import core.memory : GC;
  import std.conv : to;
  import yguilib.assets : defaultTtfFontData;
  import yguilib.clibs.sdl3;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(160, 120, "test_text_cache_frames");
  win.create();
  scope(exit) win.destroy();

  Font font = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData, 12.0f, 1.0f
  );
  scope(exit) font.destroy();

  auto tc = new TextCache(8);
  scope(exit) tc.clear();

  string[] keys;
  foreach (i; 0 .. 40) {
    keys ~= "k" ~ i.to!string;
  }

  // Entries used in the current frame are not evicted: the cache grows.
  tc.beginFrame();
  foreach (i; 0 .. 9) {
    assert(tc.textureFor(font, keys[i], 0).isValid());
  }
  assert(tc.length == 9);
  foreach (i; 0 .. 9) {
    assert(tc.contains(font, keys[i], 0));
  }

  // Next frame: only untouched (stale) entries are evicted.
  tc.beginFrame();
  assert(tc.textureFor(font, keys[0], 0).isValid());
  assert(tc.textureFor(font, keys[1], 0).isValid());
  assert(tc.textureFor(font, keys[9], 0).isValid());
  assert(tc.length == 8); // 9 - 2 evicted + 1
  assert(tc.contains(font, keys[0], 0));
  assert(tc.contains(font, keys[1], 0));
  assert(tc.contains(font, keys[9], 0));
  assert(!tc.contains(font, keys[2], 0));
  assert(!tc.contains(font, keys[3], 0));
  foreach (i; 4 .. 9) {
    assert(tc.contains(font, keys[i], 0));
  }

  // Hard cap: one frame with more than 2 * maxEntries strings.
  tc.beginFrame();
  foreach (i; 10 .. 40) {
    assert(tc.textureFor(font, keys[i], 0).isValid());
    assert(tc.length <= 16);
  }
  assert(tc.length >= 8);
  assert(tc.contains(font, keys[39], 0));

  // Hits on a cached key do not allocate.
  const string hot = keys[39];
  foreach (_; 0 .. 10) {
    assert(tc.textureFor(font, hot, 0).isValid());
  }
  GC.collect();
  const before = GC.stats();
  foreach (_; 0 .. 1000) {
    assert(tc.textureFor(font, hot, 0).isValid());
  }
  const after = GC.stats();
  assert(after.allocatedInCurrentThread == before.allocatedInCurrentThread);
  assert(
    after.usedSize + after.freeSize <= before.usedSize + before.freeSize
  );
}

unittest {
  import yguilib.assets : defaultTtfFontData;
  import yguilib.clibs.sdl3;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(160, 120, "test_text_cache_outline");
  win.create();
  scope(exit) win.destroy();

  Font font = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData, 24.0f, 1.0f
  );
  scope(exit) font.destroy();

  auto tc = new TextCache(8);
  scope(exit) tc.clear();

  const fill = tc.textureFor(font, "Hi", 0);
  const ring = tc.textureFor(font, "Hi", 3);
  assert(fill.isValid() && ring.isValid());
  assert(fill.textureId != ring.textureId);
  assert(tc.length == 2);
  assert(tc.contains(font, "Hi", 0) && tc.contains(font, "Hi", 3));
  assert(!tc.contains(font, "Hi", 2));
  assert(ring.width == fill.width + 6);
  assert(ring.height == fill.height + 6);
  // the shared font is back to its normal outline
  assert(yguilib_sdl3_ttf_get_font_outline(font.handle) == 0);
  const again = tc.textureFor(font, "Hi", 0);
  assert(again.textureId == fill.textureId);
  assert(!TextCache.createTextTexture(font, "Hi", -1).isValid());
}
