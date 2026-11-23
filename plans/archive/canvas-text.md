# Canvas text support

Add HTML-canvas-like text to `yguilib.render.canvas.Canvas` (`fillText`,
`strokeText`, `*WithMaxWidth`, `font`, `textAlign`, `textBaseline`,
`direction`, `measureText`). Honors transform, clip, shadow, fill/stroke
style. Textured-quad approach reusing `TextCache`; stroke via SDL_ttf outline.

Design summary:
- Font spec = `(ptSize, fontName)` as in `Renderer.font()`.
- Bitmap rasterized at `ptSize * totalScaling * sqrt(|det xf|)` (quantized
  scale in `FontManager`), drawn as transformed quad.
- Gradient/pattern paint multiplies by glyph bitmap alpha.
- `direction` stored; used for start/end alignment only (no RTL shaping).

Phases (run each by a fresh subagent given only its file):
1. `canvas-text-ph01.md` types, state, `measureText`, wrapper additions.
2. `canvas-text-ph02.md` `fillText` solid color + maxWidth.
3. `canvas-text-ph03.md` gradient/pattern paint via alpha mask.
4. `canvas-text-ph04.md` `strokeText` via outline bitmaps.
5. `canvas-text-ph05.md` guidemo demo, ARCHITECTURE.md, TODO.md cleanup.

Common rules: see AGENTS.md; verify each phase with
`ninja -C _build && timeout 300 meson test -C _build`.

## Status

- Phase 1: DONE. `ninja -C _build` builds, `timeout 300 meson test -C
  _build` passes all 10 tests. Line-length check script not run.
  - C wrapper: `yguilib_sdl3_ttf_set_font_outline` / `_get_font_outline`
    (0 ok, -1 error), D binding in `clibs/sdl3_ttf.d`, checks in
    `yguilib_sdl3_ttf_test.c`.
  - `canvas/types.d`: `FontSpec`, `TextAlign`, `TextBaseline`,
    `TextDirection`, `TextMetrics`, helper `package(yguilib)
    textAnchorOffset(metrics, align, baseline, dir)` with headless unittest.
    Anchor approximations: top = 0; hanging = 0.2*ascent; alphabetic =
    ascent; middle = (ascent+descent)/2; ideographic and bottom =
    ascent+descent; start/end flip under rtl.
  - `canvas/package.d`: `State` has font spec, align, baseline, direction
    with getters/setters (`fontSpec` ignores non-finite or non-positive
    sizes); `measureText(string)` returns `TextMetrics` in logic units
    (zeros for empty text or uninitialized renderer; descent is absolute).
  - Limitation: the save/restore, invalid-size and `measureText` unittest
    creates a `Window`, so it is not headless.
- Phase 2: DONE. `ninja -C _build` builds, `timeout 300 meson test -C
  _build` passes all 10 tests.
  - `FontManager.getFontAtScale(ptSize, name, scale)`: separate cache keyed
    by quantized scale (1/8 steps, clamped to [1/8, 16] and px size <=
    1024), untouched by `setScaling`, cleared when it exceeds 64 fonts.
  - `Renderer` package accessors `fontAtScale` and `textTextureFor`.
  - `Canvas.fillText` / `fillTextWithMaxWidth`: effective scale =
    `totalScaling * sqrt(|det xf|)`; quad sized bitmap px / quantized scale,
    anchored via `textAnchorOffset` (uses the scaled font's ascent/descent
    and the bitmap width), tinted with the solid fill color, honors clip
    and shadow. maxWidth squeezes x about the anchor.
  - Refactor: `drawImageShadow`/`drawImageShadowMask` take a GL texture id;
    new `buildImageVertsUv`.
  - No-ops: uninitialized renderer, empty text, non-finite point, invisible
    or non-solid fill (gradient/pattern until phase 3), singular transform,
    invalid maxWidth.
  - Tests: GL pixel unittest (position, translate, rotate 90, scale, clip,
    tint, shadow, maxWidth, no-ops). Note `clearFrame` resets Canvas state,
    including the font.
- Phase 3: DONE. `ninja -C _build` builds, `timeout 300 meson test -C
  _build` passes all 10 tests.
  - Shaders: `paint.frag.glsl` / `pattern.frag.glsl` got an `#ifdef MASK`
    variant (mask sampler `uMask`, alpha times mask alpha); new
    `paint_mask.vert.glsl` (x, y, u, v); `assets.d` `withMaskDefine`.
  - `GradientPipeline.drawMasked` (new `GradientLocs`) and
    `PatternPipeline.drawMasked` (mask on texture unit 1); existing paths
    unchanged.
  - `Canvas.drawMaskedPaint`; `fillText` now accepts gradient/pattern
    fills (no-op when `paintVisible` / `patternDrawable` fail); shadow uses
    glyph alpha (times solid alpha for solid fills).
  - Tests: new GL unittest (linear/radial gradient, pattern sampling and
    transform, shadow, invisible styles); the phase 2 no-op case now uses a
    transparent gradient and a null-texture pattern.
- Phase 4: DONE. `ninja -C _build` builds, `timeout 300 meson test -C
  _build` passes all 10 tests.
  - `TextCacheKey`/`TextCache.getOrCreate`/`contains`/`createTextTexture`
    and `Renderer.textTextureFor` take `outlinePx` (default 0); outline is
    set on the shared font and reset to 0 afterwards (scope exit).
  - `Canvas.strokeText` / `strokeTextWithMaxWidth` share `drawFilledText`
    (`stroke` flag): ring width `max(1, round(lineWidth * effScale))` px,
    capped at `maxTextOutlinePx` (64); quad extends by the outline margin
    per side, anchor uses the glyph box without the margin. Paint from
    `strokeStyle` (solid/gradient/pattern), clip and shadow as fill. Cap,
    join and dash are ignored.
  - Tests: text_cache unittest (outline key, bitmap +2*outline, font
    outline reset) and a GL canvas unittest (ring hole, wider line, gradient,
    maxWidth, no-ops).
- Phase 5: DONE. `ninja -C _build` builds, `timeout 300 meson test -C
  _build` passes all 10 tests.
  - guidemo canvas page: new slot 7 section `12. Text (fillText)`
    (`CanvasSlot7.text`, [I] cycle now images -> offscreen -> patterns ->
    text -> interop): alignment/baseline guides, rtl start, rotation,
    gradient fill, stroked text, shadow, maxWidth.
  - Docs: canvas module header, ARCHITECTURE.md Text paragraph, TODO.md
    item removed, stale `fillText` docstring fixed.
