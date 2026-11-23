# ph09: Codestyle and wrap-up (review 5.1-5.4, 5.6-5.10)

Overview: `plans/canvas-render-refactor.md`. Review:
`documentation/canvas-render-review.md`, section 5. Paths are relative
to `yguilib/source/yguilib/render/`.

Callers outside `render/` (in `yguilib/`, `source/yvidtrim/`, guidemo
and the tests) must be updated in the same phase. Grep for each renamed
symbol.

## Steps

1. Default parameters (5.1): `drawFilledText(..., bool stroke = false)`
   becomes `drawTextBitmap(text, pos, maxWidth, outlinePx)`. Fill passes
   `0`, and stroke passes the computed outline width.
   `textTextureFor(..., int outlinePx = 0)` takes an explicit
   parameter. Grep `= ` inside the parameter lists of `render/` for any
   that remain.
2. Field names (5.2): `id_`, `width_`, `height_`, `premultiplied_`,
   `bottomUp_`, `borrowed_`, `pixelWidth_`, `pixelHeight_`, `samples_`
   and `tex_` become `fId`, `fWidth` and so on (in `font.d`,
   `texture.d`, `render_target.d` and `image.d`). The parameter
   `align_` (`canvas/types.d`) becomes `textAlign`/`a`.
3. get/set names (5.3): `FontManager.getFont` -> `fontWithSize`,
   `getFontAtScale` -> `fontAtScale`, `setScaling` -> `scaling(float)`,
   `Font.setScale` -> `scale(float)`, `TextCache.getOrCreate` ->
   `textureFor`.
4. Parameter structs (5.4): use `Viewport` (from ph08) in every pipeline
   call. Then add parameter structs for functions that still take more
   than 5 parameters: `RoundRectPipeline.draw`, `drawDashedThickLine`,
   `drawDashedLineWithPoints`, `drawSolidThickLine`,
   `drawTexturedTriangles*`, `ClipStack.push`,
   `Renderer.drawLineDashed` and `drawRoundRectDashed`. Keep
   `Path2d.ellipse` as it is, because it mirrors HTML; add a comment
   saying so. Public Renderer APIs used by widgets keep a readable call
   site; update the widget callers.
5. Visibility (5.6): use section labels instead of per-declaration
   `private` in `font.d`, `internal/clip_stack.d` and
   `internal/text_cache.d` (fix the mis-indented `private:`).
6. Const locals (5.7) in the places the review lists and wherever else
   you notice them.
7. Long functions (5.8): split `drawTextBitmap` (anchor and metrics
   computation, then the draw) and `dashContour` so each is 50 lines or
   fewer.
8. Imports (5.9): remove the function-scope `TextureMode` re-imports and
   the unused `GL_TRIANGLES` import in `Canvas.stroke`.
9. Docs (5.10): add module doc comments to `package.d`, `colors.d`,
   `render_types.d`, `font.d`, `font_manager.d`,
   `internal/pipelines.d`, `internal/gl_util.d`,
   `internal/clip_stack.d` and `internal/text_cache.d`. Turn the
   column-0 `//` class comment in `canvas/package.d` into a `///` doc.
   Convert `@param` to DDoc `Params:` in `package.d`.

## Wrap-up

- ARCHITECTURE.md: add the new modules (`internal/gl_test_util.d`,
  `canvas/package_test.d`), the clip storage and FrameState swap, the
  TextCache LRU and frame-protection policy, and the GL state cache.
  Keep the file under 250 lines.
- TODO.md: replace "human review of canvas and renderer implementation"
  with "glyph atlas for text (canvas-render-review 3.7)", plus any
  deferred item a phase reported (for example blur downsampling).
- `git mv plans/canvas-render-refactor*.md plans/archive/`.

## Verification

`ninja -C _build && timeout 300 meson test -C _build` is green, no line
in the touched files exceeds 80 columns, and `./_build/guidemo` and
`./_build/yvidtrim` start and quit cleanly.
