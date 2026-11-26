# Cross-Label Text Batching Plan

Source: `TODO.md` item 1, `documentation/canvas-render-review.md` 3.7, and
`documentation/text-atlas-benchmark.md`.

## Goal

Batch glyph quads across consecutive `Renderer.drawText*` and solid-color
`Canvas.fillText` / `strokeText` calls into one dynamic vertex buffer,
using a dedicated indexed-quad `TextPipeline` with per-vertex float RGBA
color, and flush automatically on state changes, non-text draws, atlas
resets, readbacks, or swap.

## Design Decisions

- Dedicated `TextPipeline` with `TextVertex` (32 B: `x, y, u, v, r, g, b, a`)
  and static `GL_UNSIGNED_SHORT` EBO (`maxIndexedQuads = 16383`).
- Both `Renderer` text and solid-color `Canvas` text share `Renderer`'s
  `TextBatch`, tracking `(texture, stencilClip)`.
- `ClipStack` and `WidgetPainterSystem` avoid redundant scissor flushes when
  the effective GL scissor box does not change across sibling widgets.
- Public `Renderer.flush()` is called automatically at state/render-target
  boundaries, readbacks, and `Window.swapBuffers()`.

## Data Flow

```
  Renderer.drawText* / Canvas solid fillText, strokeText
         |
         v
  TextRunCache.runFor() --[atlas grow/clear]--> GlyphAtlas.onBeforeReset()
         |                                            |
         v                                            v
  Renderer.queueTextQuad(tex, stencilClip, quad[4])  Renderer.flush()
         |
    [tex / stencilClip change, 16383 quads, non-text draw,
     scissor change, target switch, readPixels, swapBuffers]
         |
         v
  TextBatch.flush() --> TextPipeline.drawGlyphQuads()
                        (glBufferSubData + glDrawElements)
```

## Phases

- [Phase 1: Shaders, IndexedQuadArray, TextPipeline & TextBatch](
  text-batching-ph01.md)
- [Phase 2: Renderer Batching, Smart Scissor & WidgetPainter](
  text-batching-ph02.md)
- [Phase 3: Canvas Solid-Color Text Batching & Tests](
  text-batching-ph03.md)
- [Phase 4: Benchmark, Docs, ARCHITECTURE.md, TODO.md & Checks](
  text-batching-ph04.md)
