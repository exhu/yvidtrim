module yguilib.render.internal.text_cache;

package(yguilib):

import glad2.gles2;
import std.container.dlist : DList;
import yguilib.clibs.sdl3_ttf;
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
  string text;
}

struct TextCacheEntry {
  TextTexture texture;
  DList!TextCacheKey.Range orderRef;
}

package(yguilib):

final class TextCache {
  enum size_t maxCacheEntries = 512;

  this(size_t maxEntries = maxCacheEntries) {
    assert(maxEntries > 0, "maxEntries must be positive");
    this.maxEntries = maxEntries;
  }

  ~this() {
    clear();
  }

  @property size_t length() const {
    return cache.length;
  }

  bool contains(const Font font, string text) const {
    if (font is null || font.handle is null ||
        font.id == invalidFontId || text.length == 0) {
      return false;
    }
    const TextCacheKey key = TextCacheKey(font.id, font.scaledSize, text);
    return (key in cache) !is null;
  }

  void clear() {
    foreach (key, ref entry; cache) {
      entry.texture.destroy();
    }
    cache.clear();
    accessOrder.clear();
  }

  TextTexture getOrCreate(Font font, string text) {
    if (font is null || font.handle is null ||
        font.id == invalidFontId || text.length == 0) {
      return TextTexture();
    }

    const TextCacheKey key = TextCacheKey(font.id, font.scaledSize, text);
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

    TextTexture tex = createTextTexture(font, text);
    if (tex.isValid()) {
      accessOrder.insertFront(key);
      cache[key] = TextCacheEntry(tex, accessOrder[]);
    }
    return tex;
  }

  static TextTexture createTextTexture(Font font, string text) {
    if (font is null || font.handle is null || text.length == 0) {
      return TextTexture();
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

    GLuint texId = uploadTextPixels(pixels, w, h, pitch);
    return TextTexture(texId, w, h);
  }

  private:
  static GLuint uploadTextPixels(
    const(void)* pixels,
    int w,
    int h,
    int pitch
  ) {
    GLuint texId;
    glGenTextures(1, &texId);
    glBindTexture(GL_TEXTURE_2D, texId);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    if (pitch != w * 4) {
      glPixelStorei(GL_UNPACK_ROW_LENGTH, pitch / 4);
    }
    glTexImage2D(
      GL_TEXTURE_2D,
      0,
      GL_RGBA,
      w,
      h,
      0,
      GL_RGBA,
      GL_UNSIGNED_BYTE,
      pixels
    );
    if (pitch != w * 4) {
      glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    }
    glBindTexture(GL_TEXTURE_2D, 0);
    return texId;
  }

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

  Font fontA = new Font(cast(const(void)[])defaultTtfFontData, 12.0f);
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
  Font fontB = new Font(cast(const(void)[])defaultTtfFontData, 12.0f);
  scope(exit) fontB.destroy();
  assert(fontB.id != fontA.id);
  assert(!tc.contains(fontB, "item0"));
}
