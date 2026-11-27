# ph08: `render/canvas` Shadows, Paths, Stroker & Zero-GC

Overview: `plans/yguilib-review-fixes.md`.
Review: `documentation/yguilib-review-report-render-canvas.md` (commit
`7a96feaa`). Paths below are relative to `yguilib/source/yguilib/render/`.

Goal: Address all 20 findings (1H, 7M, 12L) in `render/canvas/` and its
internal path/stroker/SVG modules.

## Files

- `canvas/package.d`, `canvas/package_test.d`, `canvas/path2d.d`,
  `canvas/types.d`
- `internal/path_flatten.d`, `internal/path_stroker.d`,
  `internal/svg_path_parser.d`

## Steps

1. **Text shadow blending, alpha & empty check (`1.1`, `1.2`, `1.3`)**:
   - In `drawImageShadowMask`, keep blending enabled (`GL_ONE,
     GL_ONE_MINUS_SRC_ALPHA` with mask alpha `1.0f` and `paintAlpha` applied
     in `compositeShadow`, or `GL_MAX`) so overlapping glyph quads
     (`strokeText`, kerning, `maxWidth` squeeze) accumulate instead of
     erasing neighbor shadows (`1.1`).
   - Render gradient/pattern text shadow masks with a glyph-masked paint
     pass into the shadow offscreen target so stop/pattern alphas control
     shadow opacity (`1.2`).
   - Add `if (fImageVerts[].length == 0) { return; }` right after
     `buildTextVerts(*run, p);` so whitespace-only shadowed text allocates
     no offscreen FBOs (`1.3`).
2. **Path, stroker & SVG parser correctness (`1.4`-`1.9`)**:
   - Set `fClosed = false;` in `Path2d.moveTo` (`1.4`).
   - Validate `Transform2d` finiteness and `isFinitePoint` outputs in
     `Path2d.addPath` (`1.5`).
   - In `Flattener.finish`, retain 1-point contours when a drawing verb was
     emitted on the subpath so `path_stroker` renders zero-length caps (`1.6`).
   - Clamp `if (phase >= period) { phase = 0; }` in `DashPhase` (`1.7`).
   - Guard `isFinitePoint(dst)` before updating `st.cur` in
     `svg_path_parser.d` (`1.8`).
   - Check `isFinite(e) && isFinite(f)` in `Transform2d.isInvertible()` and
     return `LineDash.init` if `!isFinite(sum)` in `LineDash.fromSegments`
     (`1.9`).
3. **Zero-GC & redundant work (`2.1`, `2.2`, `2.3`)**:
   - Replace dynamic array literal in `gradientUniforms` with direct element
     assignment / `const float[4]` and mark `gradientUniforms` `@nogc` (`2.1`).
   - Tighten `shadowBox` double-pad cull check (`2.2`).
   - Remove redundant `fRenderer.flush()` in `Canvas.restore()` (`2.3`).
4. **Encapsulation, reuse & style (`3.1`, `4.1`, `4.2`, `5.1`)**:
   - Make `GradientStops.stops` and `count` `private:` with `count()` and
     `items()` accessors (`3.1`).
   - Extract `@nogc` glyph quad & UV helper shared by `queueTransformedTextRun`
     and `buildTextVerts` (`4.1`).
   - Deduplicate star path & GC stats harness in tests (`4.2`).
   - Fix `FrameState` visibility section and `canvas/package_test.d`
     accessor/dead-statement nits (`5.1`).
5. **Regression tests (`6.1`, `6.2`)**:
   - Add all 7 missing regression tests in `canvas/package_test.d`:
     shadowed `strokeText`/overlapping `fillText`, shadowed gradient/pattern
     text with alpha < 1, shadowed `"   "`, gradient steady-state zero-GC,
     `clip(emptyPath)`, `clearRect` after batched `fillText`, and headless
     `Canvas`.
   - Add `assert(glGetError() == GL_NO_ERROR);` to the 4 missing GL tests.

## Verification

- `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`
