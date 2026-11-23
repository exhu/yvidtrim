module yguilib.render.internal.text_cache;

package(yguilib):

import glad2.gles2;
import std.container.dlist : DList;
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
  DList!TextCacheKey.Range orderRef;
}

package(yguilib):

final class TextCache {
  enum size_t maxCacheEntries = 512;

  this(size_t maxEntries) {
    assert(maxEntries > 0, "maxEntries must be positive");
    this.maxEntries = maxEntries;
  }

  ~this() {
    clear();
  }

  @property size_t length() const {
    return cache.length;
  }

  bool contains(const Font font, string text, int outlinePx = 0) const {
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
    accessOrder.clear();
  }

  TextTexture getOrCreate(Font font, string text, int outlinePx = 0) {
    if (font is null || font.handle is null ||
        font.id == invalidFontId || text.length == 0) {
      return TextTexture();
    }

    const TextCacheKey key = TextCacheKey(
      font.id, font.scaledSize, outlinePx, text
    );
    auto p = key in cache;
    if (p !is null) {
      accessOrder.popFirstOf(p.orderRef);
      accessOrder.insertFront(key);
      p.orderRef = accessOrder[];
      return p.texture;
    }

    if (cache.length >= maxEntries) {
      evictOldest();
    }

    TextTexture tex = createTextTexture(font, text, outlinePx);
    if (tex.isValid()) {
      accessOrder.insertFront(key);
      cache[key] = TextCacheEntry(tex, accessOrder[]);
    }
    return tex;
  }

  /**
   * White-on-transparent bitmap of `text`. With `outlinePx` > 0 the bitmap
   * is the glyph outline ring (hole inside), `outlinePx` larger per side;
   * the shared font's outline is reset to 0 afterwards.
   */
  static TextTexture createTextTexture(
    Font font, string text, int outlinePx = 0
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
    int pitch = yguilib_sdl3_ttf_get_surface_pitch(surf);
    const void* pixels = yguilib_sdl3_ttf_get_surface_pixels(surf);
    if (w <= 0 || h <= 0 || pixels is null) {
      return TextTexture();
    }

    GLuint texId = uploadRgbaTexture(pixels, w, h, pitch);
    return TextTexture(texId, w, h);
  }

  private:
  void evictOldest() {
    import std.algorithm.comparison : max;

    const size_t evictCount = max(1, maxEntries / 4);
    foreach (_; 0 .. evictCount) {
      if (accessOrder.empty) {
        break;
      }
      const TextCacheKey oldestKey = accessOrder.back;
      accessOrder.removeBack();
      if (auto p = oldestKey in cache) {
        p.texture.destroy();
        cache.remove(oldestKey);
      }
    }
  }

  size_t maxEntries = maxCacheEntries;
  TextCacheEntry[TextCacheKey] cache;
  DList!TextCacheKey accessOrder;
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
  foreach (i; 0 .. 8) {
    TextTexture tex = tc.getOrCreate(fontA, "item" ~ i.to!string);
    assert(tex.isValid());
  }
  assert(tc.length == 8);

  // Cache hit on "item0" moves it to front (most recently used)
  TextTexture tex0 = tc.getOrCreate(fontA, "item0");
  assert(tex0.isValid());
  assert(tc.length == 8);

  // Adding 9th item triggers eviction of oldest 25% (8 / 4 = 2 items).
  // "item1" and "item2" were the oldest and should be evicted.
  // "item0" was touched and must still be present.
  TextTexture tex8 = tc.getOrCreate(fontA, "item8");
  assert(tex8.isValid());
  assert(tc.length == 7);
  assert(!tc.contains(fontA, "item1"));
  assert(!tc.contains(fontA, "item2"));
  assert(tc.contains(fontA, "item0"));
  assert(tc.contains(fontA, "item8"));

  // Destroying fontA and allocating fontB produces distinct font IDs
  Font fontB = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData, 12.0f, 1.0f
  );
  scope(exit) fontB.destroy();
  assert(fontB.id != fontA.id);
  assert(!tc.contains(fontB, "item0"));
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

  const fill = tc.getOrCreate(font, "Hi");
  const ring = tc.getOrCreate(font, "Hi", 3);
  assert(fill.isValid() && ring.isValid());
  assert(fill.textureId != ring.textureId);
  assert(tc.length == 2);
  assert(tc.contains(font, "Hi") && tc.contains(font, "Hi", 3));
  assert(!tc.contains(font, "Hi", 2));
  assert(ring.width == fill.width + 6);
  assert(ring.height == fill.height + 6);
  // the shared font is back to its normal outline
  assert(yguilib_sdl3_ttf_get_font_outline(font.handle) == 0);
  const again = tc.getOrCreate(font, "Hi");
  assert(again.textureId == fill.textureId);
  assert(!TextCache.createTextTexture(font, "Hi", -1).isValid());
}
