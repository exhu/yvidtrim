# Phase 4: strokeText

Prereq: phases 1-3 (outline wrapper from phase 1).
Files: `render/internal/text_cache.d`, `render/font.d`, `canvas/package.d`,
`yguilib-clibs/yguilib_sdl3_ttf.c`.

Steps:
1. `TextCacheKey` gains `outlinePx`. `createTextTexture(font, text,
   outlinePx)` sets font outline, renders the outline bitmap (ring), resets
   outline to 0 afterwards (font handle is shared). Adjust glyph offset: the
   outlined surface is larger by `outlinePx` per side; position quad
   accordingly. Update the existing text_cache unittest and callers.
2. `strokeText(string, PointF)` and `strokeTextWithMaxWidth`: outline width
   `max(1, round(lineWidth * effScale))` px (cap to a sane maximum), paint
   from `strokeStyle` (solid, gradient, pattern via phase 3 path), clip and
   shadow as for fill. Line cap/join/dash are ignored (document).
3. Tests: stroke bitmap larger than fill, cache keys differ by outline,
   pixel test ring has hole at glyph center for large font, no-ops.

Done: build + tests pass.
