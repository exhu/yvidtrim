# ph06: GPU safety and small bugs (review 2.3, 2.6-2.10)

Overview: `plans/canvas-render-refactor.md`. Review:
`documentation/canvas-render-review.md`. Paths are relative to
`yguilib/source/yguilib/render/`.

## Steps

1. Blur bound (2.3), in `canvas/package.d` (shadow code) and
   `assets/yguilib/shaders/blur.frag.glsl`:
   - Clamp the effective sigma in pixels to `maxBlurSigmaPx = 64`
     (enum, documented on `Shadow.blur`).
   - Downsample: when sigma is over 32 px, blur the mask at 1/2
     resolution (sigma halved). Use 1/4 when the requested sigma is
     over 64 px. Upscale in the composite with linear filtering. If
     downsampling is too invasive for the current offscreen design,
     implement the clamp only, add a TODO.md item for downsampling,
     and say so in the phase report.
   - The box padding (3 * sigma) uses the clamped sigma.
2. Offscreen failure (2.9) in `internal/offscreen.d`: `ensureSize`
   returns `bool`. Query `GL_MAX_TEXTURE_SIZE` and
   `GL_MAX_RENDERBUFFER_SIZE` once and reject larger sizes. Return the
   result of `attachAndCheck`. `beginShadowPass` skips the shadow,
   drawing the shape without it, when `ensureSize` fails.
3. Document the nonZero winding wrap at 128 in the module header of
   `internal/stencil_ops.d`, next to the bit layout (2.6).
4. `arcTo` (2.7) in `canvas/path2d.d`: with no current point, emit only
   `moveTo(p1)` and return, as the HTML spec does.
5. Text alignment (2.8): in the Canvas text drawing code, compute the
   align width from the font advance at the raster scale
   (`f.measureText(text).x / q`), the same value that `measureText`
   uses, instead of the bitmap width.
6. Pitfalls (2.10):
   - Doc comment on `RectF` (`render_types.d`) saying that `RectF.init`
     is 1 x 1.
   - `onScalingChanged` (`package.d`): re-create a user-assigned (not
     owned) default font at the new scale through the FontManager,
     instead of dropping it. If that isn't possible, document it.
     Re-apply the ClipStack scissor, because its rects are in logic
     units.

## Tests

- `arcTo` on an empty path followed by a round-cap stroke draws no dot
  at `p1`.
- `textAlign = center`: the drawn text's pixel bounds are centered on
  `x` within 1 px, compared with `measureText`. Test both an identity
  transform and a 1.5x scale transform.
- A shadow with `blur = 1000` finishes (the test passes within the
  meson timeout), and the shadow box stays within the clamped padding.
- `ensureSize` with a size over the max returns false, and the shape
  still draws.

## Verification

`ninja -C _build && timeout 300 meson test -C _build` is green. Run
`./_build/guidemo` and look at the shadow blur demo.
