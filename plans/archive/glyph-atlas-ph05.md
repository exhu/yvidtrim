# Glyph atlas ph05: docs, TODO, cleanup

Overview: `plans/glyph-atlas.md`. Read `AGENTS.md` first. ph01-ph04 are
done: the C layout and glyph wrapper, `render/internal/glyph_atlas.d`,
`TextRunCache` in `render/internal/text_cache.d`, and Renderer and
Canvas text drawn from the atlas.

## Steps

1. `ARCHITECTURE.md`:
   - The module list (~line 64, `clip_stack, text_cache, gl_util, …`)
     adds `glyph_atlas`.
   - The **Text** paragraph (~line 212): text runs (shaped by SDL_ttf
     through a no-op text engine) are cached LRU by use tick. Glyphs
     live in one growing RGBA8 atlas page that is cleared and repacked
     at max size, and its generation invalidates the run slots. Each
     label is one draw. The glyph alpha masks the paint; stroke uses
     the outline ring glyphs.
   - Keep the file under 250 lines and lines at 80 columns or less.
2. `documentation/canvas-render-review.md`: under 3.7 and 2.5, add the
   line `Done: glyph atlas (plans/archive/glyph-atlas.md).`
3. `TODO.md`: remove `- glyph atlas for text (canvas-render-review
   3.7)`. Add `- cross-label text batching (queue glyph quads, flush on
   state change)` as the first item.
4. grep for stale references (`TextTexture`, `textTextureFor`,
   `createTextTexture`, "one texture per string") in `yguilib/`,
   `source/` and `*.md` (excluding `plans/archive/` and the review
   doc), and fix them.
5. Move `plans/glyph-atlas*.md` to `plans/archive/` with `git mv`.

## Verify

`ninja -C _build && timeout 300 meson test -C _build`, all green. Commit
`glyph-atlas ph05: docs and TODO`.
