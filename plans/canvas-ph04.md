# Canvas ph04: gradients and shared vertex snippet

Overview: [canvas.md](canvas.md). Read `AGENTS.md` and `codestyle.md` first.

## Context
- Shaders are in `yguilib/assets/yguilib/shaders/`: `color.*`,
  `texture.*` and `roundrect.*`. Each `*.vert.glsl` repeats the same
  logic-to-clip code:
  `zeroToOne = aPosition/uResolution; ... clipSpace = vec2(x*2-1,
  1-y*2)`.
- `yguilib/source/yguilib/internal/assets.d` imports them as
  `enum string ...Source = import("yguilib/shaders/x.glsl")`.
- Pipelines are in `render/internal/pipelines.d`, and GL helpers in
  `internal/gl_util.d`.
- From ph03, `Canvas.fill` and `Canvas.stroke` do a stencil pass, then a
  cover or colored pass through `ColorPipeline.drawArrays`. For gradient
  styles they currently use the first stop's color.
- `FillStyle` (`canvas.d`) has `kind` (color, linearGradient or
  radialGradient) plus `linear` / `radial` with `GradientStops`
  (max 8, sorted).

## Steps
1. **Dedupe the vertex shaders.**
   - Add `shaders/common/logic_to_clip.glsl`, which defines only
     `vec4 logicToClip(vec2 p, vec2 res)`, with a doc comment.
   - Remove `#version 300 es` from every `*.vert.glsl` and call
     `logicToClip`.
   - In `internal/assets.d`, compose each vertex shader:
     `enum string vertPrelude = "#version 300 es\n" ~
     import("yguilib/shaders/common/logic_to_clip.glsl");`, then
     `colorVertexShaderSource = vertPrelude ~ import(...)`.
   - Keep each shader's existing doc comments, below the prelude. The
     roundrect.vert comment currently sits before `#version`; it's fine
     wherever it ends up after composition, because `#version` comes first.
2. **Gradient shader.**
   - `paint.vert.glsl`: `aPosition` → `gl_Position`, and
     `out vec2 vPos = aPosition` (logic coordinates).
   - `paint.frag.glsl` uniforms: `uKind` (0 linear, 1 radial), `uInvXf`
     (mat3, from logic to gradient user space), `uP0`, `uP1`, `uR0`, `uR1`,
     `uStopColors[8]` (vec4), `uStopOffsets[8]` (float) and `uStopCount`
     (int).
   - Linear: `t = dot(p - p0, d) / dot(d, d)`, where `d = p1 - p0`. If `d`
     is 0, draw nothing (spec), i.e. discard.
   - Radial: the two-circle (conical) canvas spec formula. Solve for the
     largest `ω` with `r(ω) = r0 + ω(r1 - r0) >= 0`, where `p` lies on circle
     `c(ω)`; if there's no solution, discard. Write it as a documented helper
     function.
   - Pad spread: clamp `t` to [0, 1]. Interpolate the stops in premultiplied
     alpha, then un-premultiply for the output.
   - Output a non-premultiplied color; the existing blend func is
     SRC_ALPHA / ONE_MINUS_SRC_ALPHA.
3. **`GradientPipeline`** in `pipelines.d`. Mirror the init and destroy of
   `ColorPipeline`, using the same vertex layout (vec2), and add
   `drawTriangles(verts, in GradientUniforms u, vw, vh)`. Put the uniform
   packing in a small struct. Share the init/destroy boilerplate where
   practical; for example, extract a helper in `gl_util.d` for the vec2-only
   VAO/VBO setup used by both color and gradient pipelines.
4. Renderer owns the `GradientPipeline` and initializes and destroys it
   alongside the others. Give it a `package(yguilib.render)` accessor.
5. In Canvas, the cover pass and the colored stroke pass go through
   `drawPaint(verts, style)`. Solid styles use `ColorPipeline`; gradients use
   `GradientPipeline` with `uInvXf = xf.inverse()`, where `xf` is the
   transform at the time of the fill/stroke call. Stencil state is set
   before the call and works the same for both pipelines.

## Unit tests (window-based)
- Linear red→blue from x=0 to x=200 over a 200-wide rect: the pixel at x≈10
  is mostly red, x≈190 is mostly blue, and x=100 is ~(0.5, 0, 0.5).
- A 3-stop gradient: the middle stop's color shows at offset 0.5.
- Radial with c0 = c1 = center, r0 = 0, r1 = 50: the center has the first
  stop's color, radius 45 is close to the last, and outside r1 is padded
  with the last stop.
- A gradient combined with `translate` follows the transform.
- A gradient stroke draws.
- All existing renderer, text, roundrect and texture tests still pass after
  the shader refactor.
- `glGetError() == GL_NO_ERROR`.

## Done when
`ninja -C _build && meson test -C _build` passes, no line exceeds 80
columns, and no vertex shader body duplicates the clip-space math.
