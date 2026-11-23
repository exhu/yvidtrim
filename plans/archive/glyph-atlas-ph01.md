# Glyph atlas ph01: C wrapper layout + glyph image

Overview: `plans/glyph-atlas.md`. Read `AGENTS.md` and `codestyle.md`
first.

## Goal

Extend the private SDL3_ttf wrapper (SDL3_ttf 3.2.2) so D can get shaped
glyph positions for a string and rasterize single glyphs by glyph
index. Nothing in D uses it yet, apart from the binding.

## Files

- `yguilib/yguilib-clibs/yguilib_sdl3_ttf.h`, `.c`
- `yguilib/yguilib-clibs/yguilib_sdl3_ttf_test.c`
- `yguilib/yguilib-clibs/meson.build` (only if needed)
- `yguilib/source/yguilib/clibs/sdl3_ttf.d` (D `extern(C)` binding)

## API (add to the header, doc comments in the existing style)

```c
typedef struct yguilib_sdl3_ttf_GlyphQuad {
  uint32_t glyph_index;
  int src_x, src_y, src_w, src_h;   /* area within the glyph image */
  int dst_x, dst_y, dst_w, dst_h;   /* px, relative to text top-left */
} yguilib_sdl3_ttf_GlyphQuad;

/* Lays out text: writes up to `cap` copy ops to `out` (out may be NULL
 * when cap is 0), sets the text area size *w / *h, returns the total
 * glyph count (call again with a bigger buffer if > cap), or -1 on
 * error. */
int yguilib_sdl3_ttf_layout_text(
  yguilib_sdl3_ttf_Font *font, const char *text, size_t length,
  yguilib_sdl3_ttf_GlyphQuad *out, int cap, int *w, int *h);

/* Glyph image for `glyph_index` converted to RGBA32 (same format as
 * render_text_blended). Free with yguilib_sdl3_ttf_destroy_surface. */
yguilib_sdl3_ttf_Surface *yguilib_sdl3_ttf_render_glyph(
  yguilib_sdl3_ttf_Font *font, uint32_t glyph_index);
```
Split the struct fields one per line if the style requires it.

## Implementation

- `#include <SDL3_ttf/SDL_textengine.h>`.
- Define a static `TTF_TextEngine`, initialized with
  `SDL_INIT_INTERFACE`. Its `CreateText` sets
  `text->internal->engine_text` to a non-NULL sentinel (e.g. the
  address of a static) and returns true. Its `DestroyText` does
  nothing.
- `layout_text`: call `TTF_CreateText(&engine, font, text, length)` and
  make sure the layout is up to date. `CreateText` is called after
  layout; if `needs_layout_update` is set, call `TTF_GetTextSize` or
  `TTF_UpdateText` first. Read `text->internal->ops`, `num_ops`, `w`
  and `h`. Copy only `TTF_DRAW_COMMAND_COPY` ops (skip FILL: underline
  and strikethrough are not used). Skip ops whose `glyph_font != font`,
  since no fallback fonts are registered. Count every copy op, but write
  only the first `cap`. Then `TTF_DestroyText`.
- `render_glyph`: `TTF_GetGlyphImageForIndex(font, glyph_index, NULL)`,
  then `SDL_ConvertSurface(..., SDL_PIXELFORMAT_RGBA32)`, freeing the
  original. Return it through the existing opaque Surface type, so the
  existing size, pitch, pixels and destroy getters work.
- Outline: the caller sets it with `yguilib_sdl3_ttf_set_font_outline`
  before calling. Both the layout and the glyph images then include the
  ring. Note this in the docs.

## Tests (`yguilib_sdl3_ttf_test.c`)

- "Hi": returns 2. w and h equal `yguilib_sdl3_ttf_get_text_size`.
  With `cap` 0 and `out` NULL it still returns 2.
- `dst` rects lie within [0, w] x [0, h]. The second glyph's dst_x is
  greater than the first's.
- Outline 3: w and h equal the size of the `render_text_blended`
  surface for "Hi" with outline 3. Reset the outline afterwards.
- `render_glyph(font, quad[0].glyph_index)` is non-NULL, its pixels are
  non-NULL, and its size is >= src_w x src_h.
- Empty string: returns 0 or -1, documented either way, with no crash.

## D binding

Add to `yguilib/source/yguilib/clibs/sdl3_ttf.d` an `extern(C)` struct
`yguilib_sdl3_ttf_GlyphQuad` with an identical layout (`uint`, then 8
`int`s) and both functions. Add a `static assert` on
`GlyphQuad.sizeof == 36`.

## Verify

`ninja -C _build && timeout 300 meson test -C _build`, all green. Commit
`glyph-atlas ph01: SDL_ttf layout and glyph image wrapper`.
