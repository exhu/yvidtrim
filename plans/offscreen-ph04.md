# Phase 4: guidemo, ARCHITECTURE.md, TODO.md

Overview: [offscreen.md](offscreen.md). Phases 1-3 added `RenderTarget`
(`Renderer.createRenderTarget/resizeRenderTarget/beginTarget/endTarget`,
`rt.texture()`, `rt.toImage()`) and `Canvas.drawImage` (transform, clip,
tint, shadow).

## Context
- `source/guidemo/pages/canvas_page.d`: sections in a 4x2 grid. Slot 7
  alternates ([I]) between "7. Canvas + Renderer interop" and "9. Images".
  The sample PNG `Texture` is created lazily on the first draw and
  released in `releaseTextures()`.
- `source/guidemo/pages/canvas_controller.d`: handles [I]. Check how the
  toggle state lives in the page model (`source/guidemo/model.d`) and
  follow the same model/tracker pattern (AGENTS.md View-Controller rules).
- The F12 screenshot path lives in `source/guidemo/controller.d` and
  `UiSystem.requestScreenshot`.

## Steps
1. Section 9 "Images": keep the `Renderer.drawImage` sample and add
   `Canvas.drawImage` uses: one rotated + scaled, one under a circular
   clip, one with a soft shadow and a tint.
2. New section "10. Offscreen" in slot 7, so [I] cycles interop -> images
   -> offscreen (turn the bool toggle into a small enum or index in the
   model):
   - a `RenderTarget` (e.g. 80x80 logic, MSAA) created lazily in the draw
     delegate and kept in sync with `resizeRenderTarget` on every draw.
     It is redrawn only when dirty (first time, after resize, or after a
     scale change), then blitted with `Canvas.drawImage` 3+ times
     (rotated, small, with a shadow). Draw a gradient-filled star with an
     antialiased stroke and some text into it on a transparent background.
   - the target is released in `releaseTextures()` (rename it to
     `releaseGpuResources()` if it reads better, and update the callers).
3. [P] on the Canvas page saves the offscreen image as
   `offscreen-<timestamp>.png` (next to where the F12 screenshots go; reuse
   their naming helper if there is one). The save has to run on the main
   thread while GL is current: route it through the page view/model (e.g.
   a request flag the draw delegate consumes, then `rt.toImage().savePng`,
   called outside `beginTarget`/`endTarget`). Log the path at info level.
   Add [P] to the page help/status text where [I] is mentioned.
4. CPU idle: no timers needed; make sure nothing redraws continuously.
5. `ARCHITECTURE.md`: add `render_target.d` to the topology. Extend the
   Images/Canvas paragraph with the target stack (what begin/end save and
   restore), the premultiplied target textures + separate blend,
   `Canvas.drawImage`, and the section 10 note under guidemo pages. It must
   stay under 250 lines.
6. `TODO.md`: remove the line "support offscreen rendering to image, and
   image blitting". Keep "Canvas Pattern ..." (it can now build on
   `Texture`).
7. Run `ninja -C _build && meson test -C _build`, then run
   `rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d` if it
   exists.

## Done when
Build, tests and the boundary check pass. The manual check from the
overview works.
