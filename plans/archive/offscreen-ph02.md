# Phase 2: RenderTarget and the Renderer target stack

Overview: [offscreen.md](offscreen.md). Phase 1 added the separate alpha
blend, the `Texture` flags `premultiplied` / `bottomUp` / `borrowed`, and
`TextureMode` in `TexturePipeline`.

## Context
- `render/internal/offscreen.d` `OffscreenTarget` (non-MSAA, grow-only,
  used by Canvas shadows) and `SavedTargetState` (fbo, viewport, scissor,
  clear color). Shadows capture/restore the *current* fbo, so they work
  inside a target as long as `Renderer.getPixelWidth/Height` report the
  target size.
- `render/package.d` `Renderer`: `viewportPixelWidth/Height`, the logic
  size is derived from it, `clipStack` (`internal/clip_stack.d`, scissor
  in viewport pixels), `fCanvas`, `readPixels`.
- `render/canvas.d` `Canvas` state: `st` (`State`) + `fStack`;
  `resetFrame()`. The Canvas clip lives in stencil bit 7 of the bound
  framebuffer, so every target has its own stencil.
- The GL context is GLES 3.0: `glRenderbufferStorageMultisample` and
  `glBlitFramebuffer` are available. `glBlitFramebuffer` honors the
  scissor, so disable the scissor around the resolve.

## Steps
1. New public module `render/render_target.d`: `final class
   RenderTarget`. It has the same RAII rule as `Texture` (no destructor,
   explicit main-thread `destroy()`, idempotent).
   - its fields hold the pixel size, the `msaa` flag, the sample count, the
     resolve FBO + RGBA8 texture (linear, clamp) + depth24-stencil8
     renderbuffer when not MSAA, and the MSAA FBO + color RB + depth-stencil
     RB when MSAA.
   - `pixelWidth()`, `pixelHeight()`, `isValid()`, `isMsaa()`,
     `texture()` (a borrowed `Texture`, premultiplied + bottomUp,
     recreated on resize; document "owned by the target").
   - `Image toImage()`: binds the resolve FBO, `glReadPixels`,
     un-premultiplies (rgb = rgb * 255 / a when a > 0, rounded and
     clamped), flips, and restores the previous fbo. It returns null if the
     target is invalid. Assert that the target is not active
     (`Renderer` keeps an `active` package counter on it).
   - package: `allocate(pw, ph)` (deletes and recreates the attachments,
     checks completeness, logs errors), `drawFbo()` (MSAA or resolve), and
     `resolve()` (blit color MSAA -> resolve, scissor off, then restore
     the read/draw bindings).
   - Put shared GL helpers in `internal/offscreen.d` or `gl_util.d` if that
     avoids duplicating the code with `OffscreenTarget`.
2. `Renderer` additions (doc comments on each):
   - `RenderTarget createRenderTarget(float logicW, float logicH, bool
     msaa)`: pixels = `max(1, ceil(logic * getTotalScaling()))`. Return
     null when not initialized or the size is not finite/positive. Samples
     = min(4, GL_MAX_SAMPLES); fall back to no MSAA when it is < 2.
   - `void resizeRenderTarget(RenderTarget rt, float logicW, float
     logicH)`: reallocates only if the pixel size changes. Assert that the
     target is not active. Content is undefined after a reallocation.
   - `void beginTarget(RenderTarget rt, bool clear)`: push a frame record
     {SavedTargetState, viewportPixelWidth/Height, the moved-out
     `clipStack`, the Canvas frame state (package
     `Canvas.saveFrameState()` returning st + stack copy, then
     `resetFrame()`)}. Bind `rt.drawFbo()`, set the viewport to the target
     size, scissor off, and optionally clear (color transparent + stencil
     0). Assert that `rt` is not already on the stack.
   - `void endTarget()`: resolve if MSAA, pop the record, restore the fbo,
     viewport, clip stack (add `ClipStack.reapply(pixelW, pixelH, scale)`
     that re-sets the top scissor or disables it) and the Canvas state
     (`Canvas.restoreFrameState`). Assert that the stack is not empty.
   - `bool inTarget() const`. `clearFrame` keeps working inside a target
     (document that the clear color is stored as-is, i.e. it should be
     premultiplied).
   - `Renderer.destroy()` must not destroy user targets; only clear the
     stack.
3. Drawing the texture of the target that is currently being drawn into
   is a feedback loop: assert against it in `drawImageRegion` (compare the
   texture id with the active targets' textures).
4. Tests (GL window pattern as in `canvas.d`):
   - create a 40x30 target, begin/clear, fill a rect with alpha 0.5 red,
     end; `toImage()` gives straight (255, 0, 0, ~128) and transparent
     elsewhere. Row 0 = top (check the orientation with a rect in the top
     half only).
   - after `endTarget` the viewport, scissor (push a clip rect before
     begin) and fbo are restored; drawing to the window still clips.
   - a Canvas clip set before `beginTarget` does not affect target
     drawing and is still active after `endTarget`. Canvas state (fill
     style) is restored too.
   - nested targets: draw target B's texture into target A, and A's
     image has B's content.
   - MSAA vs non-MSAA: both produce the expected interior pixels; an MSAA
     diagonal edge has intermediate alpha values (skip gracefully if
     `isMsaa()` is false on the test driver).
   - `drawImage(rt.texture(), ...)` onto the window: correct colors over
     an opaque background (premultiplied blend, no dark fringe: a
     half-alpha white over black gives ~128 gray).
   - resize keeps the size when the pixel size is unchanged and grows it
     otherwise; `destroy()` is idempotent.
5. Run `ninja -C _build && meson test -C _build`.

## Done when
Build and tests pass, and the target stack round-trips every piece of GL
and Canvas state it touches.
