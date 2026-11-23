# ph08: Fast paths and code reuse (review 3.3, 3.8, 4.1-4.7, 4.10)

Overview: `plans/canvas-render-refactor.md`. Review:
`documentation/canvas-render-review.md`. Paths are relative to
`yguilib/source/yguilib/render/`.

## Steps

1. Convex fast path (3.3):
   - In `internal/path_flatten.d` (or in Canvas right after
     flattening), compute whether `fContours` is a single closed
     contour that is strictly convex. Every cross product of
     consecutive edges must have the same sign. Skip zero-length edges,
     and treat a wrong turn count as non-convex. A single closed convex
     contour gives the same result for nonZero and evenOdd.
   - In `Canvas.fill` (and the gradient/pattern fill paths), when there
     is no clip, the contour is convex and the alpha is any value, draw
     the fan triangles directly with the paint pipeline. There is no
     winding, cover or reset stencil pass. The shadow path keeps
     working, whichever path it uses.
   - `clearRect`: with an axis-aligned translate/scale transform and no
     clip, convert the rect to pixels and do a scissored `glClear` of
     color only. Save and restore the current scissor through
     `ClipStack`, intersecting with it.
2. `measureText` (3.8): resolve the `Font` once and use
   `f.measureText` for the width.
3. Reuse:
   - 4.1: `PatternUniforms patternUniformsFor(in FillStyle s,
     in Transform2d extra, TextureMode mode)` together with the
     feedback-loop assert. Use it in the three pattern sites. Add
     `TextureMode textureModeFor(const Texture t)` and use it at
     `package.d` (about line 682) and `canvas/package.d` (about line
     288).
   - 4.2: `struct PatternLocs { ... static PatternLocs query(GLuint);
     void set(...) }`. PatternPipeline uses it for both `program` and
     `maskProgram`.
   - 4.3: `struct ProgramMesh { GLuint program, vao, vbo;
     void destroy(); }`, used in every pipeline (it pairs with the
     ph07 VBO capacity, which can live in it). `TexturePipeline` and
     `RoundRectPipeline` use `buildProgram`.
   - 4.4: `Transform2d.determinant()` and `isInvertible()`, used in
     `Canvas.isInvertible`, `Transform2d.inverse` and the text code.
   - 4.5: `isFinitePoint` and `isFiniteRect` in `render_types.d`, used
     by Canvas and Path2d.
   - 4.6: one vec2 `rectTriangles(RectF)` helper next to `quadVertices`
     in `pipelines.d`, used by `Canvas.quadFromRect` and
     `ColorPipeline.drawFillRect`.
   - 4.7: shared `boundsOfPoints` in `render_types.d`, used by
     `Canvas.boundsOfVerts` (a float-pair variant) and `Path2d.bounds`.
   - 4.10: `struct Viewport { float vw; float vh; float scale; }` in
     `internal/pipelines.d` or `render_types.d` (package visibility),
     and a private `Viewport vp()` in `Renderer`. Use it in the
     Renderer draw wrappers. The pipeline signatures switch to
     `Viewport` in ph09.
4. Unused code: delete `Renderer.createTextTexture`,
   `ColorPipeline.drawLineWithWidth` and `drawRectDefaultWidth`. Inline
   `TexturePipeline.drawTexture` into its only caller. Grep first to
   confirm that nothing else calls them.

## Tests

- Convex fast path: a rect, a circle and a round rect, alpha 0.5,
  nonZero and evenOdd: the pixels match the expected values, with no
  double blending at the fan seams. A concave star still renders
  correctly through the stencil path. Add a unittest-only counter or
  flag showing which path was taken.
- `clearRect` scissored: clears the right pixels with a translate and a
  scale transform, and falls back to the stencil path with a rotation
  or a clip.

## Verification

`ninja -C _build && timeout 300 meson test -C _build` is green. Run
`./_build/guidemo` and look at the canvas demos.
