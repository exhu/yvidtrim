# Glyph atlas ph04: Canvas fillText / strokeText

Overview: `plans/glyph-atlas.md`. Read `AGENTS.md` and `codestyle.md`
first. Depends on ph03: `Renderer.textRunFor`, `glyphAtlasTexture`,
`glyphAtlasSize`, `TextRun` / `RunGlyph` in
`render/internal/text_cache.d`. ph03 may already have ported Canvas
minimally; check `git log -1` and the code first, then finish the port
and add the tests.

## Goal

Canvas text (`yguilib/source/yguilib/render/canvas/package.d`,
`drawTextBitmap` / `buildTextVerts` / `TextBitmap`, ~lines 1316-1392)
draws per-glyph quads from the atlas. All paint kinds (color, gradient,
pattern), the shadow, the clip, transforms, maxWidth and the stroke
outline ring keep working.

## Changes

- `drawTextBitmap(text, pos, maxWidth, outlinePx)`: get
  `fRenderer.textRunFor(f, text, outlinePx)` and the atlas texture id.
  Use the run instead of `TextTexture`.
- `buildTextVerts`: `q = f.scaledSize / f.size` (bitmap px per user
  unit), and the metrics come from `textMetricsOf` (TTF advance) as
  now. The anchor is `textAnchorOffset` and the squeeze factor
  `s = gw > maxWidth ? maxWidth / gw : 1`. The run origin is
  `x0 - margin * s`, `y0 = pos.y + off.y - margin`, with
  `margin = outlinePx / q`. For each glyph with w > 0, emit the quad
  `RectF(ox + dx / q * s, oy + dy / q, dw / q * s, dh / q)` with uv =
  slot / atlas size into `fImageVerts`, transformed by the current
  transform. Add an appending sibling of `buildImageVertsUv`, or a
  flag, and reset `fImageVerts` once per string.
- Shadow (`drawImageShadow`) and masked paint (`drawMaskedPaint`): pass
  the atlas texture id. The verts are already in `fImageVerts`. The
  atlas is a single page, so there are no structural changes. The 1 px
  gutters keep neighbouring glyphs out of the sampling.
- Remove `TextBitmap` if it is no longer needed. Keep each function
  under 50 lines (codestyle) and split anchor/metrics from the draw if
  needed.
- Update the module doc (~line 12), which mentions TextCache bitmaps.

## Tests (`render/canvas/package_test.d`)

- All existing text tests pass unchanged: align, baseline, direction,
  maxWidth, strokeText ring, gradient and pattern fill, shadow and
  clip.
- New: atlas bleed under rotation. Draw "W" first (so it is cached next
  to the next glyph in the atlas), clear, then draw "I" rotated 30°
  about its center. Lit pixels must lie only within a small distance of
  the rotated I box, with no stray pixels from the W.
- New: fillText with a gradient and a shadow, using several glyphs, in
  one call. Shadow pixels appear for each glyph.
- Use the `gl_test_util.d` fixture and the AGENTS.md scope(exit)
  target cleanup.

## Manual check

`SDL_LOGGING=app=trace ./_build/guidemo`: the text and shadow demos look
the same as before, with no atlas errors in the log. If you cannot run
it, say so.

## Verify

`ninja -C _build && timeout 300 meson test -C _build`, all green. Commit
`glyph-atlas ph04: canvas text from glyph atlas`.
