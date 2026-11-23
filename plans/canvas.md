# Canvas 2D API (TODO.md item 1)

## Goal
Implement `yguilib.render.canvas` (`Canvas`, `Path2d` and support types)
based on the TODO comments in `canvas.d`. The API is HTML-canvas-like, with
paths only through `Path2d`. Canvas and Renderer drawing must interoperate,
with no duplicated pipelines or shaders. Add a guidemo demo page.

## Decisions
- Anti-aliasing: MSAA 4x on the window GL context, falling back to no MSAA
  if creation fails. The context also gets an 8-bit stencil buffer.
- Fills and clips use stencil-then-cover: exact `nonZero` / `evenOdd`, and
  arbitrary path clipping.
- Solid fills, strokes and stencil passes reuse `ColorPipeline.drawArrays`
  (the existing color shader). Gradients add one new paint pipeline. All
  vertex shaders share a `logicToClip` snippet.
- Paths are flattened, and strokes generated, on the CPU in path-local space.
  The current transform is then applied on the CPU, so non-uniform scale
  skews strokes as in HTML canvas.
- The Canvas enables `GL_STENCIL_TEST` only inside its own calls. Renderer
  `draw*` calls ignore Canvas clip and transform. The scissor `ClipStack`
  affects both.
- `Renderer.clearCanvas(ColorF)` is renamed to `Renderer.clearFrame(ColorF)`
  so it isn't confused with the Canvas API. It also clears stencil and resets
  the Canvas frame state.
- The demo draws through `CustomDraw`, which becomes
  `delegate(Renderer, in Widget)` and is invoked by `WidgetPainter`.
- Shadows (FBO + separable blur) come in the last phase.

## Stencil bit layout
```
bit 7      : clip mask (1 = inside current clip), valid when clipActive
bits 0..6  : fill winding (INCR_WRAP/DECR_WRAP) / evenOdd parity (bit 0)
             / stroke "drawn once" marker; always reset to 0 after a call
```

## Phases
```
ph01  types + Path2d + flattening (CPU, unit tests)
  |
ph02  stroker: caps/joins/miter/dashes (CPU, unit tests)
  |
ph03  GL: stencil+MSAA ctx, clearFrame rename, Canvas state,
  |   transform, fill/stroke/clip/clearRect, pixel tests
ph04  gradients (paint pipeline) + shared vertex shader snippet
  |
ph05  CustomDraw hookup + guidemo Canvas page + ARCHITECTURE/TODO
  |
ph06  shadows (offscreen FBO + separable gaussian blur)
```
Details:
- [ph01](canvas-ph01.md)
- [ph02](canvas-ph02.md)
- [ph03](canvas-ph03.md)
- [ph04](canvas-ph04.md)
- [ph05](canvas-ph05.md)
- [ph06](canvas-ph06.md)

## Verification (every phase)
`ninja -C _build && meson test -C _build` must pass, and lines must be at most
80 chars. Manual checks after ph03, ph05 and ph06: run `./_build/guidemo` and
open the Canvas tab. Other pages must look unchanged, and idle CPU must be 0%.
