/**
 * Glyph runs over the shared `GlyphAtlas`: one `TextRun` per (font id,
 * raster size, outline, string), kept in an LRU `TextRunCache` with
 * per-frame eviction protection (see the class doc).
 */
module yguilib.render.internal.text_cache;

package(yguilib):

import glad2.gles2;
import std.array : Appender;
import yguilib.clibs.sdl3_ttf;
import yguilib.render.font : Font, invalidFontId;
import yguilib.render.internal.glyph_atlas : GlyphAtlas, GlyphLookup,
  GlyphSlot;

/**
 * One laid out glyph of a run: its pixel rect `dx, dy, dw, dh` relative
 * to the run origin, and the atlas rect it samples,
 * `(slot.x + srcX, slot.y + srcY, srcW, srcH)`. `slot.w == 0` means the
 * glyph draws nothing (blank or unresolved).
 */
struct RunGlyph {
  short dx;
  short dy;
  short dw;
  short dh;
  uint glyph;
  GlyphSlot slot;
  short srcX;
  short srcY;
  short srcW;
  short srcH;
}

/// Laid out text: pixel size and glyph quads, valid for `atlasGen`.
struct TextRun {
  /// Text area in pixels (includes the outline ring).
  int width;
  int height;
  /// GC array owned by the cache entry.
  RunGlyph[] glyphs;
  /// Atlas generation the slots belong to.
  ulong atlasGen;
}

private:

/// `TextRun.atlasGen` of a run whose slots are incomplete.
enum ulong unresolvedGen = ulong.max;

struct TextCacheKey {
  ulong fontId;
  float ptSize;
  int outlinePx;
  string text;
}

struct TextCacheEntry {
  TextRun run;
  /// `TextRunCache.fTick` of the last hit or of the insert.
  ulong lastUse;
}

struct EvictCandidate {
  ulong lastUse;
  TextCacheKey key;
}

package(yguilib):

/**
 * LRU cache of text runs keyed by font id, size, outline and text, over
 * one `GlyphAtlas` that holds the glyph images.
 *
 * Every hit and insert stamps the entry with an increasing tick, so a
 * hit does not allocate. `beginFrame()` marks the start of a frame
 * (called by `Renderer.clearFrame` outside render targets).
 *
 * A run returned by `runFor` is valid until the next `runFor` call (which
 * may grow or clear the atlas); draw it right away.
 *
 * Eviction policy: when an insert finds `length >= maxEntries`, the
 * oldest `max(1, maxEntries / 4)` entries not used since the last
 * `beginFrame()` are removed. Entries used in the current frame are
 * kept, so a frame drawing more than `maxEntries` strings lets the cache
 * grow instead of thrashing; at the hard cap of `2 * maxEntries` the
 * oldest entries are evicted anyway, even those used in this frame.
 */
final class TextRunCache {
  enum size_t maxCacheEntries = 512;

  /// Atlas sizes: see `GlyphAtlas`; the texture is created on first use.
  this(size_t maxEntries, int atlasInitial, int atlasMax) {
    assert(maxEntries > 0, "maxEntries must be positive");
    this.maxEntries = maxEntries;
    fAtlas = new GlyphAtlas(atlasInitial, atlasMax);
  }

  // No destructor: the atlas texture is freed only by an explicit
  // `clear()` on the main thread with the GL context current.

  @property size_t length() const {
    return cache.length;
  }

  /// The atlas texture (0 until the first glyph is rasterized).
  GLuint atlasTexture() const {
    return fAtlas.texture();
  }

  /// Atlas width and height in pixels.
  int atlasSize() const {
    return fAtlas.size();
  }

  version (unittest) {
    /// Number of cached runs of the font `fontId`.
    size_t countForFont(ulong fontId) const {
      size_t n = 0;
      foreach (key, ref entry; cache) {
        n += key.fontId == fontId ? 1 : 0;
      }
      return n;
    }

    /// The atlas (tests).
    GlyphAtlas atlas() {
      return fAtlas;
    }
  }

  /**
   * Removes every run of the font `fontId` and its atlas keys. Called
   * before that font is destroyed, since its id is never reused.
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
    fAtlas.removeFont(fontId);
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

  /// Removes every run and frees the atlas texture.
  void clear() {
    cache.clear();
    fEvictScratch.clear();
    fAtlas.destroy();
  }

  /**
   * Cached run of `text` with outline `outlinePx` (0 for the glyph fill,
   * else the outline ring `outlinePx` larger per side), laid out on a
   * miss; its glyph slots are re-resolved when the atlas generation
   * changed. Returns null for a null/destroyed font, empty text or a
   * layout failure. The shared font's outline is reset to 0 afterwards.
   */
  const(TextRun)* runFor(Font font, string text, int outlinePx) {
    if (font is null || font.handle is null ||
        font.id == invalidFontId || text.length == 0 || outlinePx < 0) {
      return null;
    }

    const TextCacheKey key = TextCacheKey(
      font.id, font.scaledSize, outlinePx, text
    );
    auto p = key in cache;
    if (p !is null) {
      p.lastUse = ++fTick;
      if (p.run.atlasGen != fAtlas.generation) {
        if (!applyOutline(font, outlinePx)) {
          return null;
        }
        scope(exit) resetOutline(font, outlinePx);
        resolveSlots(font, outlinePx, p.run);
      }
      return &p.run;
    }

    if (!applyOutline(font, outlinePx)) {
      return null;
    }
    scope(exit) resetOutline(font, outlinePx);
    TextRun run;
    if (!layoutRun(font, text, outlinePx, run)) {
      return null;
    }
    resolveSlots(font, outlinePx, run);

    if (cache.length >= maxEntries) {
      evictOldest();
    }
    cache[key] = TextCacheEntry(run, ++fTick);
    return &(key in cache).run;
  }

private:
  static bool applyOutline(Font font, int outlinePx) {
    return outlinePx == 0
      || yguilib_sdl3_ttf_set_font_outline(font.handle, outlinePx) == 0;
  }

  static void resetOutline(Font font, int outlinePx) {
    if (outlinePx > 0) {
      yguilib_sdl3_ttf_set_font_outline(font.handle, 0);
    }
  }

  /**
   * Fills size and glyph rects of `run` (slots left empty). SDL_ttf lays
   * outlined glyphs out `outlinePx` right and below the top-left of the
   * rendered surface, so the rects are shifted back by it.
   */
  bool layoutRun(Font font, string text, int outlinePx, ref TextRun run) {
    if (fQuads.length == 0) {
      fQuads.length = 64;
    }
    int w = 0;
    int h = 0;
    int n = yguilib_sdl3_ttf_layout_text(
      font.handle, text.ptr, text.length, fQuads.ptr,
      cast(int)fQuads.length, &w, &h
    );
    if (n > cast(int)fQuads.length) {
      fQuads.length = n;
      n = yguilib_sdl3_ttf_layout_text(
        font.handle, text.ptr, text.length, fQuads.ptr,
        cast(int)fQuads.length, &w, &h
      );
    }
    if (n <= 0 || n > cast(int)fQuads.length) {
      return false;
    }
    run.width = w;
    run.height = h;
    run.glyphs = new RunGlyph[n];
    foreach (i, ref g; run.glyphs) {
      const q = fQuads[i];
      g.dx = cast(short)(q.dstX - outlinePx);
      g.dy = cast(short)(q.dstY - outlinePx);
      g.dw = cast(short)q.dstW;
      g.dh = cast(short)q.dstH;
      g.glyph = q.glyphIndex;
      g.srcX = cast(short)q.srcX;
      g.srcY = cast(short)q.srcY;
      g.srcW = cast(short)q.srcW;
      g.srcH = cast(short)q.srcH;
    }
    run.atlasGen = unresolvedGen;
    return true;
  }

  /**
   * Resolves the atlas slot of every glyph of `run` (the font outline is
   * already set). The atlas growing or clearing in the middle restarts
   * the loop once; after a second change the stale slots are emptied and
   * the run is marked unresolved, so the next use retries.
   */
  void resolveSlots(Font font, int outlinePx, ref TextRun run) {
    foreach (attempt; 0 .. 2) {
      const ulong gen = fAtlas.generation;
      size_t changedAt = run.glyphs.length;
      foreach (i, ref g; run.glyphs) {
        const GlyphLookup l = fAtlas.slotFor(font, outlinePx, g.glyph);
        if (fAtlas.generation != gen) {
          changedAt = i;
          break;
        }
        g.slot = l.ok ? l.slot : GlyphSlot.init;
      }
      if (changedAt == run.glyphs.length) {
        run.atlasGen = gen;
        return;
      }
      if (attempt == 1) {
        foreach (i, ref g; run.glyphs) {
          g.slot = GlyphSlot.init;
        }
        run.atlasGen = unresolvedGen;
        if (!fLoggedThrash) {
          import std.logger : warningf;

          fLoggedThrash = true;
          warningf("TextRunCache: atlas full, text run not resolved");
        }
      }
    }
  }

  /// Hard cap on `length`, reached only within one frame.
  size_t hardCap() const {
    return 2 * maxEntries;
  }

  /**
   * Removes the oldest `max(1, maxEntries / 4)` entries not used in the
   * current frame. With none and `length` at `hardCap()`, it removes
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
    cache.remove(key);
  }

  size_t maxEntries = maxCacheEntries;
  TextCacheEntry[TextCacheKey] cache;
  GlyphAtlas fAtlas;
  /// Incremented on every hit and insert (see `TextCacheEntry.lastUse`).
  ulong fTick = 0;
  /// First tick of the current frame (set by `beginFrame()`).
  ulong fFrameStartTick = 0;
  /// Reused eviction / removal buffer, so evicting rarely allocates.
  Appender!(EvictCandidate[]) fEvictScratch;
  /// Reused layout output buffer.
  yguilib_sdl3_ttf_GlyphQuad[] fQuads;
  bool fLoggedThrash;
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

  auto tc = new TextRunCache(8, 512, 2048);
  scope(exit) tc.clear();

  // Insert 8 distinct entries (capacity reached)
  tc.beginFrame();
  foreach (i; 0 .. 8) {
    const tex = tc.runFor(fontA, "item" ~ i.to!string, 0);
    assert(tex !is null);
  }
  assert(tc.length == 8);

  // Cache hit on "item0" in a new frame makes it the most recently used
  tc.beginFrame();
  const tex0 = tc.runFor(fontA, "item0", 0);
  assert(tex0 !is null);
  assert(tc.length == 8);

  // Adding 9th item triggers eviction of oldest 25% (8 / 4 = 2 items).
  // "item1" and "item2" were the oldest and should be evicted.
  // "item0" was touched and must still be present.
  const tex8 = tc.runFor(fontA, "item8", 0);
  assert(tex8 !is null);
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

  auto tc = new TextRunCache(8, 512, 2048);
  scope(exit) tc.clear();

  string[] keys;
  foreach (i; 0 .. 40) {
    keys ~= "k" ~ i.to!string;
  }

  // Entries used in the current frame are not evicted: the cache grows.
  tc.beginFrame();
  foreach (i; 0 .. 9) {
    assert(tc.runFor(font, keys[i], 0) !is null);
  }
  assert(tc.length == 9);
  foreach (i; 0 .. 9) {
    assert(tc.contains(font, keys[i], 0));
  }

  // Next frame: only untouched (stale) entries are evicted.
  tc.beginFrame();
  assert(tc.runFor(font, keys[0], 0) !is null);
  assert(tc.runFor(font, keys[1], 0) !is null);
  assert(tc.runFor(font, keys[9], 0) !is null);
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
    assert(tc.runFor(font, keys[i], 0) !is null);
    assert(tc.length <= 16);
  }
  assert(tc.length >= 8);
  assert(tc.contains(font, keys[39], 0));

  // Hits on a cached key do not allocate.
  const string hot = keys[39];
  foreach (_; 0 .. 10) {
    assert(tc.runFor(font, hot, 0) !is null);
  }
  GC.collect();
  const before = GC.stats();
  foreach (_; 0 .. 1000) {
    assert(tc.runFor(font, hot, 0) !is null);
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

  auto tc = new TextRunCache(8, 512, 2048);
  scope(exit) tc.clear();

  const fill = tc.runFor(font, "Hi", 0);
  const ring = tc.runFor(font, "Hi", 3);
  assert(fill !is null && ring !is null);
  assert(fill !is ring);
  assert(tc.length == 2);
  assert(tc.contains(font, "Hi", 0) && tc.contains(font, "Hi", 3));
  assert(!tc.contains(font, "Hi", 2));
  assert(ring.width == fill.width + 6);
  assert(ring.height == fill.height + 6);
  // the shared font is back to its normal outline
  assert(yguilib_sdl3_ttf_get_font_outline(font.handle) == 0);
  assert(tc.runFor(font, "Hi", 0) is fill);
  assert(tc.runFor(font, "Hi", -1) is null);
  assert(tc.runFor(font, "", 0) is null);
  assert(tc.runFor(null, "Hi", 0) is null);
}

// Runs resolve to atlas slots, are re-resolved after an atlas clear and
// removeFont drops runs and atlas keys.
unittest {
  import yguilib.assets : defaultTtfFontData;
  import yguilib.render.internal.gl_test_util : GlTestWindow;

  auto w = GlTestWindow("test_text_cache_atlas");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  Font font = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData, 16.0f, 1.0f
  );
  scope(exit) font.destroy();

  auto tc = new TextRunCache(8, 512, 2048);
  scope(exit) tc.clear();
  assert(tc.atlasTexture() == 0);

  const run = tc.runFor(font, "Ag g", 0);
  assert(run !is null && run.glyphs.length == 3);
  assert(tc.atlasTexture() != 0 && tc.atlasSize() == 512);
  assert(run.atlasGen == tc.atlas.generation);
  assert(run.glyphs[0].slot.w > 0 && run.glyphs[1].slot.w > 0);
  // the repeated glyph shares one slot
  assert(run.glyphs[1].slot == run.glyphs[2].slot);
  assert(tc.atlas.length == 2);

  tc.atlas.clear();
  assert(run.atlasGen != tc.atlas.generation);
  const again = tc.runFor(font, "Ag g", 0);
  assert(again is run);
  assert(again.atlasGen == tc.atlas.generation);
  assert(again.glyphs[0].slot.w > 0);
  assert(yguilib_sdl3_ttf_get_font_outline(font.handle) == 0);

  tc.removeFont(font.id);
  assert(tc.length == 0 && tc.atlas.length == 0);
}
