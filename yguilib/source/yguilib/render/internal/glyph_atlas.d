/**
 * Glyph atlas: glyph images rasterized on demand into one growing RGBA8
 * GL texture, packed with a shelf packer.
 *
 * A slot holds the whole glyph image (white RGB, coverage in alpha, see the
 * tests) as returned by `yguilib_sdl3_ttf_render_glyph`, so a layout quad
 * `q` (`yguilib_sdl3_ttf_GlyphQuad`) samples the atlas rect
 * `(slot.x + q.srcX, slot.y + q.srcY, q.srcW, q.srcH)`.
 *
 * Slots are valid only for the `generation()` they were returned in: when
 * the atlas grows or is cleared every slot is dropped and the generation
 * is bumped, so callers holding slots must compare generations.
 */
module yguilib.render.internal.glyph_atlas;

package(yguilib):

import glad2.gles2;
import yguilib.clibs.sdl3_ttf;
import yguilib.render.font : Font, invalidFontId;
import yguilib.render.internal.gl_util;

/// Identifies one rasterized glyph image.
struct GlyphKey {
  ulong fontId;
  float ptSize;
  int outlinePx;
  uint glyph;
}

/// Pixel rectangle of a glyph image in the atlas; `w == 0` means empty.
struct GlyphSlot {
  short x;
  short y;
  short w;
  short h;
}

/// Result of a slot request; `slot` is meaningful only when `ok`.
struct GlyphLookup {
  bool ok;
  GlyphSlot slot;
}

/// Pure shelf packer (no GL); every rect keeps a 1 px gutter on all sides.
struct ShelfPacker {
  /// Empties the packer and sets the page to `size` x `size` pixels.
  void reset(int size) {
    fSize = size;
    fCursorX = 0;
    fShelfY = 0;
    fShelfH = 0;
  }

  /// Packs `w` x `h` with a 1 px gutter on every side; `ok` is false if full.
  GlyphLookup pack(int w, int h) {
    const int pw = w + 2;
    const int ph = h + 2;
    if (pw > fSize) {
      return GlyphLookup(false, GlyphSlot.init);
    }
    const bool wrap = fCursorX + pw > fSize;
    const int x = wrap ? 0 : fCursorX;
    const int y = wrap ? fShelfY + fShelfH : fShelfY;
    if (y + ph > fSize) {
      return GlyphLookup(false, GlyphSlot.init);
    }
    fShelfH = wrap ? ph : (ph > fShelfH ? ph : fShelfH);
    fShelfY = y;
    fCursorX = x + pw;
    return GlyphLookup(
      true,
      GlyphSlot(cast(short)(x + 1), cast(short)(y + 1),
        cast(short)w, cast(short)h)
    );
  }

private:
  int fSize;
  int fCursorX;
  int fShelfY;
  int fShelfH;
}

/**
 * Atlas texture plus key -> slot map. The texture is created lazily on
 * the first `slotFor`, so an atlas can be constructed without GL. There is
 * no destructor: call `destroy()` on the main thread.
 */
final class GlyphAtlas {
  /// `maxSize` is typically `min(4096, maxTextureSize())`.
  this(int initialSize, int maxSize) {
    assert(initialSize > 0 && maxSize >= initialSize);
    fSize = initialSize;
    fMaxSize = maxSize;
    fPacker.reset(initialSize);
  }

  /// The atlas texture; 0 until the first `slotFor`.
  GLuint texture() const {
    return fTexture;
  }

  /// Current texture width and height in pixels.
  int size() const {
    return fSize;
  }

  /// Bumped whenever the texture is reallocated or cleared.
  ulong generation() const {
    return fGeneration;
  }

  /// Number of stored keys.
  size_t length() const {
    return fSlots.length;
  }

  /**
   * Slot of glyph `glyph` of `f`, rasterizing it on a miss. The caller has
   * already set the font outline to `outlinePx`. An empty glyph (space)
   * returns ok with `slot.w == 0`. May grow or clear the atlas (bumping
   * `generation()`), which invalidates earlier slots.
   */
  GlyphLookup slotFor(Font f, int outlinePx, uint glyph) {
    assert(f.id != invalidFontId, "font is destroyed");
    const key = GlyphKey(f.id, f.scaledSize, outlinePx, glyph);
    if (auto hit = key in fSlots) {
      return GlyphLookup(true, *hit);
    }
    return rasterize(f, key);
  }

  /// Drops the keys of font `fontId`; the space is reclaimed on clear.
  void removeFont(ulong fontId) {
    GlyphKey[] doomed;
    foreach (key, ref slot; fSlots) {
      if (key.fontId == fontId) {
        doomed ~= key;
      }
    }
    foreach (ref key; doomed) {
      fSlots.remove(key);
    }
  }

  /// Drops all keys, zeroes the texture and bumps `generation()`.
  void clear() {
    fSlots.clear();
    fPacker.reset(fSize);
    fGeneration++;
    if (fTexture != 0) {
      glDeleteTextures(1, &fTexture);
      fTexture = allocRgbaTexture(fSize);
    }
  }

  /// Frees the texture (main thread only).
  void destroy() {
    if (fTexture != 0) {
      glDeleteTextures(1, &fTexture);
      fTexture = 0;
    }
    fSlots.clear();
  }

private:
  GlyphLookup rasterize(Font f, const ref GlyphKey key) {
    import std.logger : errorf;

    auto surf = yguilib_sdl3_ttf_render_glyph(f.handle, key.glyph);
    if (surf is null) {
      // SDL_ttf has no image for blank glyphs (space); store them empty.
      fSlots[key] = GlyphSlot.init;
      return GlyphLookup(true, GlyphSlot.init);
    }
    scope(exit) yguilib_sdl3_ttf_destroy_surface(surf);
    int w = 0;
    int h = 0;
    yguilib_sdl3_ttf_get_surface_size(surf, &w, &h);
    if (w <= 0 || h <= 0) {
      fSlots[key] = GlyphSlot.init;
      return GlyphLookup(true, GlyphSlot.init);
    }
    if (w + 2 > fMaxSize || h + 2 > fMaxSize) {
      errorf("GlyphAtlas: glyph %sx%s exceeds max atlas %s", w, h, fMaxSize);
      return GlyphLookup(false, GlyphSlot.init);
    }
    if (fTexture == 0) {
      fTexture = allocRgbaTexture(fSize);
    }
    auto place = fPacker.pack(w, h);
    if (!place.ok) {
      makeRoom();
      place = fPacker.pack(w, h);
      if (!place.ok) {
        errorf("GlyphAtlas: glyph %sx%s does not fit", w, h);
        return GlyphLookup(false, GlyphSlot.init);
      }
    }
    const RgbaSubImage img = {
      place.slot.x, place.slot.y, w, h,
      yguilib_sdl3_ttf_get_surface_pixels(surf),
      yguilib_sdl3_ttf_get_surface_pitch(surf)
    };
    uploadRgbaSubImage(fTexture, img);
    fSlots[key] = place.slot;
    return place;
  }

  /// Doubles the texture when below the max size, else clears in place.
  void makeRoom() {
    if (fSize < fMaxSize) {
      const int grown = fSize * 2 < fMaxSize ? fSize * 2 : fMaxSize;
      fSize = grown;
    }
    clear();
  }

  GlyphSlot[GlyphKey] fSlots;
  ShelfPacker fPacker;
  GLuint fTexture;
  int fSize;
  int fMaxSize;
  ulong fGeneration;
}

version (unittest) {
  import yguilib.assets : defaultTtfFontData;
  import yguilib.render.internal.gl_test_util;

  /// Glyph index of the first quad laid out for `text` (non-empty glyph).
  uint glyphOf(Font f, string text) {
    yguilib_sdl3_ttf_GlyphQuad[8] quads;
    int w, h;
    const n = yguilib_sdl3_ttf_layout_text(
      f.handle, text.ptr, text.length, quads.ptr, 8, &w, &h
    );
    assert(n >= 1);
    return quads[0].glyphIndex;
  }

  /// Reads atlas pixels (x, y, w, h) through a temporary FBO; y is down.
  ubyte[] readAtlas(GLuint tex, int x, int y, int w, int h) {
    GLint prev;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev);
    GLuint fbo;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(
      GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0
    );
    assert(
      glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
    );
    auto buf = new ubyte[w * h * 4];
    glReadPixels(x, y, w, h, GL_RGBA, GL_UNSIGNED_BYTE, buf.ptr);
    glBindFramebuffer(GL_FRAMEBUFFER, prev);
    glDeleteFramebuffers(1, &fbo);
    return buf;
  }

  bool overlaps(GlyphSlot a, GlyphSlot b, int gutter) {
    return a.x - gutter < b.x + b.w + gutter
      && b.x - gutter < a.x + a.w + gutter
      && a.y - gutter < b.y + b.h + gutter
      && b.y - gutter < a.y + a.h + gutter;
  }
}

unittest {
  ShelfPacker p;
  p.reset(64);
  GlyphSlot[] slots;
  auto a = p.pack(10, 10);
  auto b = p.pack(10, 20);
  assert(a.ok && b.ok);
  // Side by side on the first shelf, each with a 1 px gutter.
  assert(a.slot == GlyphSlot(1, 1, 10, 10));
  assert(b.slot == GlyphSlot(13, 1, 10, 20));
  // Wide rect wraps to a new shelf below the tallest (22 px) one.
  auto c = p.pack(50, 5);
  assert(c.ok && c.slot.x == 1 && c.slot.y == 23);
  slots = [a.slot, b.slot, c.slot];
  foreach (i; 0 .. 40) {
    auto r = p.pack(7, 9);
    if (!r.ok) {
      break;
    }
    slots ~= r.slot;
  }
  foreach (i, s; slots) {
    assert(s.x >= 1 && s.y >= 1 && s.x + s.w <= 63 && s.y + s.h <= 63);
    foreach (j; i + 1 .. slots.length) {
      assert(!overlaps(s, slots[j], 0));
    }
  }
  // Full: nothing more fits, and oversize rects never fit.
  while (p.pack(7, 9).ok) {}
  assert(!p.pack(7, 9).ok);
  assert(!p.pack(63, 1).ok);
  // Reset empties it.
  p.reset(64);
  assert(p.pack(62, 62).ok);
  assert(!p.pack(1, 1).ok);
  p.reset(64);
  assert(p.pack(10, 10).slot == GlyphSlot(1, 1, 10, 10));
}

unittest {
  // Gutter: neighbours on a shelf and across shelves are >= 1 px apart.
  ShelfPacker p;
  p.reset(32);
  GlyphSlot[] slots;
  while (true) {
    auto r = p.pack(5, 5);
    if (!r.ok) {
      break;
    }
    slots ~= r.slot;
  }
  assert(slots.length > 4);
  foreach (i, s; slots) {
    foreach (j; i + 1 .. slots.length) {
      const gap = s.x + s.w < slots[j].x || slots[j].x + slots[j].w < s.x
        || s.y + s.h < slots[j].y || slots[j].y + slots[j].h < s.y;
      assert(gap);
    }
  }
}

unittest {
  import core.memory : GC;

  auto w = GlTestWindow("test_glyph_atlas");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  Font font = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData, 16.0f, 1.0f
  );
  scope(exit) font.destroy();

  auto atlas = new GlyphAtlas(256, 256);
  scope(exit) atlas.destroy();
  assert(atlas.texture() == 0);

  const gA = glyphOf(font, "A");

  const first = atlas.slotFor(font, 0, gA);
  assert(first.ok && first.slot.w > 0 && first.slot.h > 0);
  assert(atlas.texture() != 0);
  const again = atlas.slotFor(font, 0, gA);
  assert(again.ok && again.slot == first.slot);
  assert(atlas.length == 1);

  // Blank or unknown glyph indices never fail (stored empty or sized).
  foreach (g; 0 .. 40) {
    assert(atlas.slotFor(font, 0, g).ok);
  }

  // Pixels were uploaded: white RGB, coverage in alpha.
  const s = first.slot;
  const px = readAtlas(atlas.texture(), s.x, s.y, s.w, s.h);
  int lit = 0;
  foreach (i; 0 .. s.w * s.h) {
    const p = px[i * 4 .. i * 4 + 4];
    if (p[3] > 0) {
      lit++;
      assert(p[0] == 255 && p[1] == 255 && p[2] == 255);
    }
  }
  assert(lit > 0);
  // The gutter around the slot stays transparent.
  const gut = readAtlas(atlas.texture(), s.x - 1, s.y - 1, 1, 1);
  assert(gut[3] == 0);

  // Hits do not allocate.
  foreach (_; 0 .. 10) {
    assert(atlas.slotFor(font, 0, gA).ok);
  }
  GC.collect();
  const before = GC.stats();
  foreach (_; 0 .. 1000) {
    assert(atlas.slotFor(font, 0, gA).ok);
  }
  const after = GC.stats();
  assert(after.allocatedInCurrentThread == before.allocatedInCurrentThread);
  assert(
    after.usedSize + after.freeSize <= before.usedSize + before.freeSize
  );
}

unittest {
  auto w = GlTestWindow("test_glyph_atlas_grow");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  Font font = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData, 32.0f, 1.0f
  );
  scope(exit) font.destroy();

  auto atlas = new GlyphAtlas(64, 128);
  scope(exit) atlas.destroy();

  enum string text = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
  yguilib_sdl3_ttf_GlyphQuad[64] quads;
  int tw, th;
  const n = yguilib_sdl3_ttf_layout_text(
    font.handle, text.ptr, text.length, quads.ptr, 64, &tw, &th
  );
  assert(n == text.length);

  assert(atlas.slotFor(font, 0, quads[0].glyphIndex).ok);
  const gen0 = atlas.generation();
  assert(atlas.size() == 64);
  ulong gen = gen0;
  bool grew = false;
  bool cleared = false;
  foreach (round; 0 .. 3) {
    foreach (ref q; quads[0 .. n]) {
      assert(atlas.slotFor(font, 0, q.glyphIndex).ok);
      if (atlas.generation() != gen) {
        if (atlas.size() == 128 && !grew) {
          grew = true;
        } else if (grew) {
          cleared = true;
        }
        gen = atlas.generation();
      }
    }
  }
  assert(grew && cleared);
  assert(atlas.size() == 128);
  assert(atlas.generation() >= gen0 + 2);
}

unittest {
  auto w = GlTestWindow("test_glyph_atlas_remove");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  Font f1 = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData, 16.0f, 1.0f
  );
  scope(exit) f1.destroy();
  Font f2 = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData, 20.0f, 1.0f
  );
  scope(exit) f2.destroy();

  auto atlas = new GlyphAtlas(256, 256);
  scope(exit) atlas.destroy();

  const g1 = glyphOf(f1, "A");
  const g2 = glyphOf(f1, "B");
  const s1 = atlas.slotFor(f1, 0, g1);
  atlas.slotFor(f1, 0, g2);
  const s2 = atlas.slotFor(f2, 0, g1);
  assert(atlas.length == 3);
  assert(s1.ok && s2.ok && s1.slot != s2.slot);

  atlas.removeFont(f1.id);
  assert(atlas.length == 1);
  assert(atlas.slotFor(f2, 0, g1).slot == s2.slot);
  assert(atlas.length == 1);
  atlas.slotFor(f1, 0, g1);
  assert(atlas.length == 2);
}
