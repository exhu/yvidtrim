# Canvas Pattern Implementation Plan

Replace the `Pattern` stub in `yguilib/source/yguilib/render/canvas.d` with
image pattern fills and strokes (first item in `TODO.md`).

## Goals
- `Pattern` paint type supporting any `Texture` (uploaded `Image` or borrowed
  `RenderTarget.texture()`), `PatternRepeat` (`noRepeat`, `repeatX`, `repeatY`,
  `repeat`), `Transform2d`, and straight-alpha `ColorF` tint.
- Dedicated `PatternPipeline` with GLES 3.0 sampler objects (`GL_REPEAT` /
  `GL_CLAMP_TO_EDGE` per axis without mutating texture parameters) and a
  stencil-safe fragment shader (`pattern.frag.glsl`, no `discard` so
  `beginCover` always zeroes stencil bits 0..6).
- Full integration with `Canvas.fill`, `Canvas.stroke`, transforms, `clip()`,
  `Shadow` masks, and `RenderTarget` textures.
- `guidemo` Page 10 showcase (`11. Patterns`, slot 7 cycled with `[I]`),
  `ARCHITECTURE.md` update, and `TODO.md` cleanup.

## Architecture
```text
Canvas.fill / stroke / drawShadowMask
  |
  +-- FillStyle.Kind.pattern
        |
        +-> uInvXf = S(1/tw, 1/th) * pattern.transform^-1 * st.xf^-1 [* T(org)]
        +-> PatternPipeline (paint.vert.glsl + pattern.frag.glsl)
              +-- GLuint[4] samplers (bit 0 = repeat X, bit 1 = repeat Y)
              +-- TextureMode: straight | premultiplied | alphaMask
```

## Phases
1. [Phase 1: Shader & PatternPipeline](canvas-pattern-ph01.md)
   Add `pattern.frag.glsl`, embed in `internal/assets.d`, implement
   `PatternUniforms` and `PatternPipeline` in `internal/pipelines.d`, and wire
   into `Renderer` (`render/package.d`).
2. [Phase 2: Pattern API, Canvas & Unit Tests](canvas-pattern-ph02.md)
   Implement `PatternRepeat`, `Pattern`, `FillStyle.Kind.pattern`, integrate
   into `Canvas` (fills, strokes, clips, shadows, render targets), and add
   comprehensive CPU and GL unit tests in `canvas.d`.
3. [Phase 3: guidemo Showcase, Docs & Verification](canvas-pattern-ph03.md)
   Add `"11. Patterns"` slot-7 card to `guidemo`, update `ARCHITECTURE.md` and
   `TODO.md`, and run all build, test, and style/boundary/null-safety checks.
