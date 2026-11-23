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
- Phases 2-5: not started.
