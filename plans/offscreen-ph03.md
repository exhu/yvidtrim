# Phase 3: Canvas.drawImage

Overview: [offscreen.md](offscreen.md). Phases 1-2 added `TextureMode`,
`TexturePipeline.drawTexturedTriangles[WithCurrentState]`, the
`Renderer.textureUv` helper, the `Texture` premultiplied/bottomUp flags,
and `RenderTarget`.

## Context
- `render/canvas.d` `Canvas`: `st.xf` (`Transform2d`, applied on the
  CPU), the clip bit tested with `stencil_ops.beginClipTest(clipActive())`
  / `endStencil()`, shadows via `drawShadow(shape, rule, style)` ->
  `shadowBox` (bounds of `fVerts`) -> `drawShadowMask` -> blur ->
  `compositeShadow`.
- HTML semantics: `drawImage(img, dx, dy, dw, dh)` and `drawImage(img,
  sx, sy, sw, sh, dx, dy, dw, dh)`. The dest rect is in user space
  (transformed), and src is in image pixels.

## Steps
1. Public API on `Canvas` (doc comments, `Texture` may be null -> no-op):
   - `void drawImage(Texture t, RectF dest)`
   - `void drawImage(Texture t, RectF dest, ColorF tint)`
   - `void drawImage(Texture t, RectF srcPx, RectF dest)`
   - `void drawImage(Texture t, RectF srcPx, RectF dest, ColorF tint)`
   Skip when not initialized, the texture is invalid, the dest/src are
   empty or non-finite, or tint.a <= 0. Do not clamp src (clamp-to-edge
   sampling, same as `Renderer.drawImageRegion`).
2. Geometry: transform the 4 dest corners by `st.xf` into a reused
   `Appender!(float[])` scratch of (x, y, u, v) for 2 triangles, with uv
   from `Renderer.textureUv(t, srcPx)` (which handles bottomUp).
3. Shadow first, when `st.shadow.isVisible()`: add a `ShadowShape.image`
   (or a separate small path) that reuses `shadowBox` (fill `fVerts` with
   the xy of the triangles) and the mask pass. In the mask pass draw the
   image triangles shifted to the box origin with blending disabled in
   `TextureMode.alphaMask`, with color `(1, 1, 1, tint.a)`. Then run the
   existing blur + `compositeShadow`. Keep the shadow alpha = shadow color
   alpha * image alpha * tint alpha.
4. Image pass: `beginClipTest(clipActive())`, draw the triangles with the
   mode from the texture flags (straight / premultiplied), then
   `endStencil()`.
5. Update the `Canvas` class doc (drawImage honors the transform, clip and
   shadow, but `Renderer.drawImage` does not) and the comment on
   `Pattern` (images now exist; the pattern is still a TODO).
6. Tests (GL window pattern):
   - an untransformed `drawImage` matches `Renderer.drawImage` pixels.
   - with a 90 degree rotation and translate, a 2-color image lands in the
     expected place (sample pixels from each half).
   - a clip circle/rect limits the image.
   - src sub-rect selection picks the right half of the image.
   - the tint alpha halves the result alpha.
   - a hard shadow (blur 0, offset) appears in the image shape and is
     transparent where the image alpha is 0 (use an image with a
     transparent half).
   - drawImage of a `RenderTarget.texture()` is upright and colored the
     same as the drawing.
7. Run `ninja -C _build && meson test -C _build`.

## Done when
Build and tests pass. `Canvas.drawImage` works for both `Image` textures
and render-target textures, with transform, clip, tint and shadow.
