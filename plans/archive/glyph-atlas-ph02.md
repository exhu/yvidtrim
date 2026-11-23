# Glyph atlas ph02: GlyphAtlas module

Overview: `plans/glyph-atlas.md`. Read `AGENTS.md` and `codestyle.md`
first. Depends on ph01 (`yguilib_sdl3_ttf_render_glyph` binding in
`yguilib/source/yguilib/clibs/sdl3_ttf.d`).

## Goal

A new module `yguilib/source/yguilib/render/internal/glyph_atlas.d`
that rasterizes glyphs on demand into one growing RGBA8 GL texture. It
is not wired into the renderer yet (ph03 does that).

## Types

```d
package(yguilib):

struct GlyphKey { ulong fontId; float ptSize; int outlinePx; uint glyph; }
struct GlyphSlot { short x, y, w, h; }   // px in the atlas; w==0: empty
struct GlyphLookup { bool ok; GlyphSlot slot; }  // no `out` params

/// Pure shelf packer (no GL), unit-testable.
struct ShelfPacker {
  void reset(int size);
  /// Packs w x h with a 1 px gutter on every side; ok == false if full.
  GlyphLookup pack(int w, int h);
}

final class GlyphAtlas {
  this(int initialSize, int maxSize);   // e.g. 512, min(4096, GL max)
  GLuint texture() const;  int size() const;  ulong generation() const;
  GlyphLookup slotFor(Font f, int outlinePx, uint glyph);
  void removeFont(ulong fontId);   // drops keys; space reclaimed later
  void clear();                    // keys + packer; bumps generation
  void destroy();                  // frees the texture (main thread)
}
```
Adjust the names to the codestyle (fields use the `f` prefix, no
get/set prefixes, no default parameter values, const by default).

## Behaviour

- `slotFor` on a hit is an AA lookup with no allocation. On a miss,
  rasterize with `yguilib_sdl3_ttf_render_glyph(f.handle, glyph)`
  (the caller has already set the font outline to `outlinePx`). Pack
  the glyph, upload it with `glTexSubImage2D`, store it and return it.
  A zero-size glyph (e.g. space) is stored as an empty slot with ok ==
  true and w == 0.
- The key uses `f.id` and `f.scaledSize`. Add an assert that the font
  is live.
- Packer full: if `size < maxSize`, allocate a new texture at twice the
  size (zero-filled), delete the old one, clear the keys and reset the
  packer. Otherwise clear in place: zero the texture with one
  `glTexSubImage2D` of zeros or a reallocation, then clear the keys and
  the packer. Both bump `generation`. Then retry the pack once. A glyph
  that does not fit an empty max-size page is skipped, an error is
  logged with `std.logger`, and ok == false is returned.
- The texture is created lazily on the first `slotFor`, so a GlyphAtlas
  can be constructed without GL (useful for headless tests that never
  draw text).
- No destructor. Textures are freed only by `destroy()` on the main
  thread (the rule documented in `render/texture.d`).
- `maxSize`: the caller passes `min(4096, GL_MAX_TEXTURE_SIZE)`. Add a
  helper in `gl_util.d` to query it.

## gl_util.d additions (`render/internal/gl_util.d`)

- `GLuint allocRgbaTexture(int size)`: RGBA8, zero-filled, LINEAR
  min/mag filters, CLAMP_TO_EDGE. Mirror `uploadRgbaTexture` (~line
  359).
- `void uploadRgbaSubImage(GLuint tex, int x, int y, int w, int h,
  const(void)* pixels, int pitch)`: reuse the `GL_UNPACK_ROW_LENGTH`
  handling of `replaceRgbaTextureImage` (~line 378), reset the row
  length to 0 and leave no texture bound. Use a parameter struct if
  there are more than 5 parameters (codestyle), e.g.
  `RgbaSubImage { int x, y, w, h; const(void)* pixels; int pitch; }`.
- `int maxTextureSize()`.

## Tests (in glyph_atlas.d unittest blocks)

- ShelfPacker, no GL: packs side by side and wraps to a new shelf;
  rects never overlap including the 1 px gutters; reports full; reset
  empties it.
- GL (use the window fixture in `render/internal/gl_test_util.d`, and
  follow the AGENTS.md scope(exit) cleanup rules):
  - The same key returns the same slot. 1000 hits do not allocate
    (same GC.stats pattern as the `text_cache.d` tests).
  - Glyph pixels are uploaded: read back via an FBO, or check with
    `glGetTexImage`-free means such as drawing the slot into an
    offscreen target and checking alpha > 0.
  - Grow: a tiny atlas (initial 64, max 128) filled with glyphs grows
    to 128 and bumps the generation. Filling it again at max clears it
    and bumps the generation again.
  - `removeFont` drops only that font's keys.
- Make sure the module is covered by the yguilib Meson unittest target
  in `yguilib/meson.build`. Add it to the source list if the list is
  explicit.

## Verify

`ninja -C _build && timeout 300 meson test -C _build`, all green. Commit
`glyph-atlas ph02: GlyphAtlas with shelf packer`.
