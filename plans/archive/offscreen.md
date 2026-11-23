# Offscreen rendering + Canvas.drawImage (TODO.md item 1)

## Goal
TODO.md item 1: "support offscreen rendering to image, and image blitting".
Render any Renderer/Canvas drawing into a reusable GPU `RenderTarget`, draw
its texture back (blit) and read it into a CPU `Image`. Add an
HTML-canvas-like `Canvas.drawImage` that honors the Canvas transform, clip,
tint and shadow. The Canvas `Pattern` stub stays out of scope (it is the
next TODO item).

## Decisions
- API: `renderer.createRenderTarget(logicW, logicH, msaa)` returns a
  `RenderTarget` (caller owned, main-thread `destroy()`, like `Texture`).
  `renderer.beginTarget(rt, clear)` ... `renderer.endTarget()` redirects
  ALL Renderer + Canvas draws into it. Targets form a stack, so nesting is
  allowed. `rt.texture()` is drawable, and `rt.toImage()` reads it back.
- Size: given in logic units, pixels = ceil(logic * total scaling), so
  drawing code works the same as on screen.
  `renderer.resizeRenderTarget(rt, w, h)` reallocates only when the pixel
  size changes (call it each draw to follow display-scale changes).
- MSAA: optional, on by default (min(4, GL_MAX_SAMPLES) samples). The
  multisampled color + depth24-stencil8 renderbuffers are resolved into the
  texture with `glBlitFramebuffer` at `endTarget`. With MSAA off, the
  target uses a single FBO with texture + depth-stencil.
- Alpha: the global blend becomes `glBlendFuncSeparate(SRC_ALPHA,
  ONE_MINUS_SRC_ALPHA, ONE, ONE_MINUS_SRC_ALPHA)`, so a target cleared to
  transparent holds correct premultiplied color. Target textures are
  flagged premultiplied + bottom-up and are drawn with `(ONE,
  ONE_MINUS_SRC_ALPHA)`, with a premultiplied tint and flipped v.
  `toImage()` un-premultiplies and flips them to straight-alpha top-down
  RGBA8.
- Blitting = `Canvas.drawImage(tex, dest)`, `drawImage(tex, src, dest)`,
  plus overloads with a `ColorF tint`. These are textured triangles
  transformed on the CPU, tested against the clip bit. A visible shadow
  uses the texture alpha as the mask. There is no `globalAlpha` (the tint
  covers it). `Renderer.drawImage*` keep their behavior, but also handle
  the premultiplied/bottom-up flags.
- guidemo: the Canvas page section 9 uses `Canvas.drawImage` (rotated,
  clipped, shadowed). A new section 10, "Offscreen", shares slot 7 ([I]
  cycles interop -> images -> offscreen): a cached offscreen drawing
  blitted several times. [P] saves the offscreen image to a PNG.

## Phases
```
ph01  blend fix, Texture flags (premultiplied, bottomUp), TexturePipeline
      premultiplied/alpha-only modes + triangle draw, Renderer.drawImage
  |
ph02  RenderTarget (MSAA + resolve), Renderer create/resize/begin/end
      target stack (viewport, clip stack, canvas state), toImage
  |
ph03  Canvas.drawImage overloads (transform, clip, tint, shadow)
  |
ph04  guidemo sections, ARCHITECTURE.md, TODO.md
```
Details:
- [ph01](offscreen-ph01.md)
- [ph02](offscreen-ph02.md)
- [ph03](offscreen-ph03.md)
- [ph04](offscreen-ph04.md)

## Verification (every phase)
`ninja -C _build && meson test -C _build` must pass, and lines must be at most
80 chars. Manual check after ph04: run `SDL_LOGGING=app=trace
./_build/guidemo`, open the Canvas tab and press [I] to see the images and
offscreen sections. Edges should be antialiased, and alpha shouldn't show
dark fringes. [P] writes a PNG that matches the offscreen drawing and has a
transparent background. CPU stays at 0% when idle.
