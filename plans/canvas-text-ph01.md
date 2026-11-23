# Phase 1: types, state, measureText

Context: `yguilib/source/yguilib/render/canvas/{package,types}.d`,
`render/font.d`, `render/font_manager.d`, `clibs/sdl3_ttf.d`,
`yguilib/yguilib-clibs/yguilib_sdl3_ttf.[c|h]`.

Steps:
1. In `canvas/types.d` add `FontSpec {float ptSize = defaultFontPtSize;
   string name;}`, `enum TextAlign {start, end, left, right, center}`,
   `enum TextBaseline {alphabetic, top, hanging, middle, ideographic,
   bottom}`, `enum TextDirection {ltr, rtl}`, `struct TextMetrics {float
   width, fontAscent, fontDescent;}` (logic units).
2. Add to `Canvas.State`: fontSpec, textAlign, textBaseline, direction;
   getter/setter pairs (ignore non-finite/non-positive ptSize); replace the
   "Text/font-related functions are omitted" comment.
3. `measureText(string)` returns metrics via `Renderer.measureTextWithFontName`
   and font ascent/descent converted to logic units; zeros when the renderer
   is uninitialized or text empty.
4. C wrapper: add `yguilib_sdl3_ttf_set_font_outline(font, int)` and
   `_get_font_outline` (+ D binding, + test in the clibs test file).
5. Internal helper (private, unit-tested headlessly): anchor offset from
   width/ascent/descent + align/baseline/direction -> PointF of top-left.
   HTML mapping: alphabetic baseline at ascent from top; top=0; hanging
   ~0.2*h below... use documented approximations; middle = h/2;
   bottom = h.
6. Unit tests: state save/restore, invalid inputs, anchor offsets.

Done: build and tests pass; line length <= 80.
