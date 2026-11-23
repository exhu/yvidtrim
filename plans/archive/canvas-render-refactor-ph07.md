# ph07: GL state caching (review 3.1, 3.2, 3.4, 3.5, 3.9)

Overview: `plans/canvas-render-refactor.md`. Review:
`documentation/canvas-render-review.md`. Paths are relative to
`yguilib/source/yguilib/render/`.

All GL calls go through `glad2.gles2` on the main thread.

## Steps

1. VBO streaming (3.1) in `internal/gl_util.d` (draw helper, around
   lines 107-125) and the pipelines:
   - Each pipeline keeps `size_t fVboCapacity` (in bytes). When the data
     fits, call `glBufferSubData`. Otherwise call `glBufferData` with
     the next power of two (`GL_DYNAMIC_DRAW`) and then
     `glBufferSubData`.
   - Remove the `glBindVertexArray(0)` / `glBindBuffer(0)` after each
     draw. Check that no code relies on VAO 0 being bound, such as
     code that sets up attributes without binding its own VAO.
2. Program and uniform cache (3.2), in `Renderer` and the pipelines:
   - `Renderer` tracks `GLuint fCurrentProgram`. The pipelines call a
     `useProgram(p)` that skips the GL call when `p` is already
     current.
   - Each pipeline stores the last uploaded `(vw, vh)` per program and
     uploads `uResolution` only when it changes. `GradientLocs.set`
     uploads the stops only when the stop data differs from the last
     upload for that program. Keep a copy of the last stops.
   - Invalidate everything (set the stored values to NaN or 0) on
     viewport change, `beginTarget`/`endTarget`, `onScalingChanged`,
     and any code that calls `glUseProgram` directly, such as the
     offscreen/blur passes. Grep `glUseProgram` to find them.
3. Tracked target state (3.4): `Renderer` already sets the viewport,
   scissor and FBO. Store the current values and pass them to
   `SavedTargetState` (`internal/offscreen.d:91-99`,
   `render_target.d:178-182`) instead of reading them with `glGet*`.
   Keep a `debug` assert that compares the stored values with `glGet*`
   so the assumption can be checked.
4. Shadow box (3.5): intersect the shadow pixel box with the active
   scissor rect from `ClipStack` (converted to pixels), in addition to
   the viewport. An empty result skips the shadow pass.
5. `isActiveTargetTexture` (3.9): where it is used only in asserts,
   wrap the call in `version (assert)`. Keep the pattern-path use.

## Tests

- All existing pixel tests stay green. They cover the correctness of
  every pipeline.
- New: draw a large path and then a small one (buffer growth, then
  subdata), and check both pixels.
- New: a gradient fill, a solid fill, then the same gradient again:
  pixels are correct, so the stop cache invalidates properly.
- New: a shadowed shape inside a scissor clip still renders the shadow
  correctly in the visible area.

## Verification

`ninja -C _build && timeout 300 meson test -C _build` is green. Run
`./_build/guidemo` and click through all demos (canvas, text, shadow,
render targets).
