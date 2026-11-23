# Canvas ph03: GL integration (stencil, MSAA, fill/stroke/clip)

Overview: [canvas.md](canvas.md). Read `AGENTS.md` and `codestyle.md` first.

## Context
- From ph01 and ph02: `render/canvas.d` has the types and `Path2d`, and the
  Canvas method bodies are empty. `internal/path_flatten.d` provides
  `flattenPath` and `flattenTolerance`. `internal/path_stroker.d` provides
  `strokeContours` and `StrokeParams`.
- `render/package.d`:
  - `Renderer` owns `ColorPipeline colorPipeline` and `ClipStack clipStack`,
    with `getLogicWidth/Height()` and `getTotalScaling()`. Its
    `initialize()` does `fCanvas = new Canvas();`.
  - `ColorPipeline.drawArrays(GLenum mode, const(float)[] verts, ColorF,
    vw, vh)` is in `internal/pipelines.d`. It calls
    `setupAlphaBlendState()` from `internal/gl_util.d`.
- GL context attributes are set in
  `yguilib/yguilib-clibs/yguilib_sdl3.c` in
  `yguilib_sdl3_create_window` (~line 247). The context is created at
  ~line 319. Neither stencil nor MSAA is requested yet.
- `Window` calls `renderer.clearCanvas(...)` each frame (`window.d:211`).

## Steps
1. **Rename** `Renderer.clearCanvas(ColorF)` to `clearFrame(ColorF)`.
   Update every caller: `window.d`, the `render/package.d` unittests, and
   any `.md` docs that mention it (`grep -rn clearCanvas` outside
   `_build`, excluding `plans/archive`). `clearFrame` also:
   - sets `glStencilMask(0xFF)` and `glClearStencil(0)`;
   - clears `GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT`;
   - calls `fCanvas.resetFrame()`.
2. **Context**: in `yguilib_sdl3_create_window`, set
   `SDL_GL_STENCIL_SIZE 8`, `SDL_GL_MULTISAMPLEBUFFERS 1` and
   `SDL_GL_MULTISAMPLESAMPLES 4` before `SDL_CreateWindow`.
   - If window creation fails, retry with `MULTISAMPLEBUFFERS 0` and
     `MULTISAMPLESAMPLES 0`, keeping the stencil.
   - Do the same retry when `SDL_GL_CreateContext` fails. That may require
     recreating the window; keep the change minimal and the C style
     (`snake_case`).
   - Log the fallback with `SDL_Log`.
   - Keep `yguilib_sdl3_test.c` passing.
3. **Renderer access**: `Canvas` gets the constructor `this(Renderer r)`,
   called as `new Canvas(this)`. Add `package(yguilib.render)` accessors to
   `Renderer`: `ref ColorPipeline colorPipelineRef()`, plus the existing
   public logic size and scaling getters. Don't duplicate pipeline code.
   `canvas.d` imports `yguilib.render : Renderer`. That's a circular import
   with `package.d`, which D allows. If it causes trouble, move the Canvas
   construction so it's lazy.
4. **`render/internal/stencil_ops.d`** (`package(yguilib):`) gets small
   functions that each set the stencil, colorMask and blend state for one
   pass, with bits per [canvas.md](canvas.md):
   - `beginWindingNonZero()`: `glStencilFunc(ALWAYS, 0, 0xFF)`, writemask
     0x7F, `glStencilOpSeparate(FRONT, KEEP, KEEP, INCR_WRAP)` and
     `(BACK, KEEP, KEEP, DECR_WRAP)`, colorMask off, cull off.
   - `beginWindingEvenOdd()`: op `INVERT`, writemask 0x01.
   - `beginCover(FillRule, bool clipActive)`: colorMask on, writemask 0x7F,
     op `(KEEP, KEEP, ZERO)` on pass and `ZERO` on fail too. That way
     covered bounds reset the low bits wherever the cover quad touches; use
     `glStencilOp(ZERO, ZERO, ZERO)`.
     - nonZero: `LESS`, ref 0x80 mask 0xFF if clipActive, else ref 0 mask
       0x7F.
     - evenOdd: `EQUAL`, ref 0x81 mask 0x81 if clip, else ref 1 mask 1.
   - `beginStrokeOnce(bool clipActive)`: `EQUAL`, ref 0x80 mask 0xFF if clip
     (else ref 0 mask 0x7F), op `(KEEP, KEEP, INCR)`, writemask 0x7F,
     colorMask on.
   - `beginResetLow()`: `ALWAYS`, op `ZERO`, writemask 0x7F, colorMask off.
   - `beginClipIntersect(FillRule)`: colorMask off, writemask 0x80, op
     `(REPLACE, REPLACE, REPLACE)` with ref 0. The test passes where the
     point is outside the path: nonZero uses `EQUAL` ref 0 mask 0x7F, and
     evenOdd uses `EQUAL` ref 0 mask 0x01.
   - `endStencil()`: disable `GL_STENCIL_TEST`, colorMask on, writemask
     0xFF, op KEEP.
5. **Canvas state**:
   ```
   struct ClipEntry { Path2d path; Transform2d xf; FillRule rule; }
   struct State { FillStyle fill; StrokeStyle stroke; float lineWidth=1;
     LineCap cap=butt; LineJoin join=miter; float miterLimit=10;
     LineDash dash; float dashOffset=0; FillRule fillRule=nonZero;
     FillRule clipRule=nonZero; Transform2d xf; ClipEntry[] clips; }
   ```
   - The state stack is an `Appender`. `save()` pushes a copy, duplicating
     `clips`. `restore()` pops (a no-op when empty). If the clip list
     changed, rebuild bit 7: clear it inside the scissor (with `glClear`
     and writemask 0x80), then replay the clip entries.
   - `resetFrame()` resets to the default State with an empty stack.
   - Setters and getters follow `codestyle.md` naming. `lineDash(LineDash)`
     stores `LineDash.fromSegments(dash.segments)`.
   - `translate`, `rotate` and `scale` post-multiply:
     `xf = xf * Transform2d.translation(o)`. `resetTransform` sets identity.
6. **Drawing.** Scratch `Contours` and `Appender!(float[])` live in the
   Canvas and are reused so there's no per-call GC churn. Local points are
   transformed with `xf` into logic coordinates.
   - `fill(Path2d)`:
     1. Flatten with `flattenTolerance(r.getTotalScaling, xf)`.
     2. Build fan triangles for every contour (contours are implicitly
        closed).
     3. Enable the stencil test.
     4. Run the winding pass with `colorPipeline.drawArrays(GL_TRIANGLES)`.
     5. Run the cover pass over the transformed bounds quad (two triangles
        from the logic-space bbox of the transformed points) in
        `fill.color`. Gradients come in ph04; until then, use the first
        stop's color.
     6. Call `endStencil`.
   - `stroke(Path2d)`: flatten, then `strokeContours` (tolerance scaled
     like the fill), then transform. Run `beginStrokeOnce` and draw the
     triangles in the stroke color, then `beginResetLow` and draw the
     triangles again (or the bbox), then `endStencil`.
   - `clip(Path2d)`:
     - If there's no clip yet, set bit 7 everywhere by clearing stencil
       0x80 with writemask 0x80; scissor still applies, which is fine.
     - Run the winding pass, `beginClipIntersect` over the full viewport
       quad, and `beginResetLow` over the bbox.
     - Append a `ClipEntry` to `clips`. `clipActive` is
       `clips.length > 0`.
   - `clearRect(RectF)`: a rectangle path, filled with blending disabled in
     ColorF(0,0,0,0) and honoring the clip. Re-enable blending afterwards;
     `setupAlphaBlendState` already does this at the next draw.
   - Skip work for empty paths and when the renderer isn't initialized.
   - The Canvas never leaves `GL_STENCIL_TEST` enabled, so Renderer draws
     ignore Canvas clips (document this in the Canvas docstring).
7. Make sure `ColorPipeline.drawArrays` doesn't change stencil state. It
   only calls `setupAlphaBlendState`, which leaves the stencil alone.

## Unit tests (window-based, modeled on the `render/package.d` unittest)
Use a 320x240 window and `glReadPixels` (GL y = 240 - y). With MSAA, sample
pixel centers away from edges.
- Fill rect path green → the inside is green and the outside is the clear
  color.
- Five-point star (self-intersecting): with nonZero the center is filled,
  with evenOdd it isn't.
- `translate`, `rotate(π/4)` and `scale` on a rect → the expected pixel is
  covered. `save`/`restore` restores the transform.
- Stroke a self-overlapping path with ColorF(1,1,1,0.5) on black → the
  overlap pixel is ~128, not ~191.
- Stroke dash pattern on/off pixels.
- `clip(circle)` then fill the viewport → inside is colored and the corners
  aren't. After `restore()` a fill covers the corners.
- Nested clip of two overlapping rects → only the intersection is filled.
- After a Canvas `clip`, a `Renderer.drawFillRect` over the full viewport is
  NOT clipped.
- `Renderer.pushClipRect` limits a Canvas fill.
- `clearRect` sets pixels to 0.
- `assert(glGetError() == GL_NO_ERROR)`.
- Re-run all existing tests with MSAA on. Where exact edge-pixel asserts
  break, move the probe point off the edge. Don't weaken checks otherwise,
  and note each change in the commit message.

## Done when
`ninja -C _build && meson test -C _build` passes and no line exceeds 80
columns. `./_build/guidemo` still renders all pages unchanged.
