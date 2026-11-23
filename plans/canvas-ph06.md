# Canvas ph06: shadows (offscreen FBO + separable blur)

Overview: [canvas.md](canvas.md). Read `AGENTS.md` and `codestyle.md` first.

## Context
- The Canvas (`render/canvas.d`) is complete except for shadows. It has fill
  and stroke via the stencil passes in `internal/stencil_ops.d`, a
  `drawPaint(verts, style)` choosing between `ColorPipeline` and
  `GradientPipeline`, and the `Shadow` struct
  `{ PointF offset; float blur; ColorF color; isVisible() }`.
- `TexturePipeline.drawTexture(texId, destRect, color, vw, vh)` multiplies
  the texture by the color. The vertex shaders are composed from
  `shaders/common/logic_to_clip.glsl` in `internal/assets.d`.
- Scaling: logic units × `Renderer.getTotalScaling()` gives pixels.
- The guidemo Canvas page is `source/guidemo/pages/canvas_page.d`.

## Steps
1. Add Canvas state `Shadow shadow`, with `shadow(Shadow)` and `shadow()`.
   It's saved and restored with the rest of the state.
2. Add `render/internal/offscreen.d` (`package(yguilib):`): an
   `OffscreenTarget` with an RGBA8 texture, a depth24-stencil8 renderbuffer
   and an FBO, resized on demand to its maximum size.
   - The Renderer owns two of them (ping-pong) and destroys them in
     `Renderer.destroy`.
   - MSAA doesn't apply to the FBO, which is fine because the shadow gets
     blurred.
3. Blur shader: `shaders/blur.frag.glsl` uses `texture.vert`, a 1D Gaussian
   with `uDirection` and `uSigma` (pixels), and up to 3σ radius with linear
   sampling. Add a `BlurPipeline` in `pipelines.d` reusing the texture vertex
   layout, sharing the VAO setup helper.
4. When `shadow.isVisible()` in `fill` and `stroke`:
   1. Compute the device bounds of the transformed geometry, padded by 3σ
      (σ = blur / 2 in logic units, converted to pixels).
   2. Save GL state: viewport, scissor enabled/box, and the FBO binding.
   3. Bind target A, set the viewport to the padded box, and clear color and
      stencil. Draw the shape's stencil and cover passes in opaque white,
      with the logic coordinates offset to the box origin. The Canvas clip
      doesn't apply inside the FBO.
   4. If blur > 0, blur horizontally A→B and vertically B→A.
   5. Restore the default framebuffer, viewport and scissor.
   6. Composite with `TexturePipeline` tinted with `shadow.color` at
      `box + shadow.offset`. The offset is NOT transformed, as in the spec.
      Wrap it in a cover-style stencil test so the Canvas clip still
      applies: `EQUAL` 0x80 mask 0x80 when the clip is active.
   7. Draw the shape normally.
   - The texture's y-orientation must match `TexturePipeline` UVs. Verify it
     with a pixel test.
5. Guidemo: add a "Shadows" card with a blurred shadow under a rounded rect
   path, an offset hard shadow (blur 0), and a shadow on a stroke.
6. Update the `ARCHITECTURE.md` render section (offscreen targets, blur) and
   keep it under 250 lines.

## Unit tests (window-based)
- Blur 0 with offset (10,10): the shadow color shows at the offset position
  outside the shape, and the shape is drawn over it.
- Blur 8: the alpha at the shadow edge is between 0 and 1, and it falls off
  monotonically going outward.
- The shadow respects the Canvas clip, and scissor state is restored after
  the shadow pass (a following Renderer draw is clipped as before).
- An invisible shadow (alpha 0) takes no FBO path: the result is identical to
  the no-shadow case.
- `glGetError() == GL_NO_ERROR`.

## Done when
`ninja -C _build && meson test -C _build` passes and no line exceeds 80
columns. The guidemo Shadows card renders.
