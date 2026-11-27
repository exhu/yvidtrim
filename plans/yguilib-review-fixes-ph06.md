# ph06: `render` Core Safety, GL State, Targets, Pipelines & `package_test.d`

Overview: `plans/yguilib-review-fixes.md`.
Review: `documentation/yguilib-review-report-render.md` (commit `7a96feaa`).
Paths below are relative to `yguilib/source/yguilib/render/`.

Goal: Address all non-font/text findings in `render/` (`1.1`-`1.4`,
`1.13`-`1.18`, `2.1`-`2.5`, `2.8`, `3.1`-`3.2`, `4.1`, `5.1`, `6.1`, `6.3`).

## Files

- `package.d`, `package_test.d` [NEW], `yguilib/meson.build`
- `render_target.d`, `texture.d`, `render_types.d`
- `internal/gl_util.d`, `internal/offscreen.d`, `internal/pipelines.d`,
  `internal/clip_stack.d`, `internal/gl_test_util.d`

## Steps

1. **Extract `render/package_test.d` & test hygiene (`3.1`, `1.17`, `4.1`, `6.1`, `6.3`)**:
   - Create `render/package_test.d` (`version (unittest):`) and add it to
     `yguilib/meson.build`. Move inline GL tests from `render/package.d`
     into it.
   - **Pitfall**: Every GL unittest must place `scope(exit) w.endTargets();`
     *after* `scope(exit) w.destroy();` (see `AGENTS.md`).
   - Fix `gl_test_util.px()` off-by-1 Y by delegating to `readAt()`.
   - Switch `render_target.d` and `package_test.d` to `GlTestWindow`,
     `readAt`, and `deleteTexture()` (instead of raw `glDeleteTextures`).
   - Fix tautological assertion `assert(r.glyphAtlasTexture() == atlasTex ||
     i > 0)` in 600-string atlas test (`6.1`).
   - Deduplicate `nearColor` in `render_types.d` (`4.1`).
   - Fix `gl_test_util.d` doc comment `*` prefixes (`5.1`).
2. **GL safety & allocation (`1.1`, `1.2`, `1.16`, `1.18`, `2.5`, `2.8`, `5.1`)**:
   - Zero-initialize `allocRgbaTexture()` (`1.1`, e.g., clear via scratch
     FBO or zeroed upload while respecting tracked FBO/clear color).
   - Check `malloc` return in `uploadAndDrawIndexedQuads()` (`1.2`).
   - Fix `ProgramTracker.invalidate()` epoch `0` wrap (`1.16`).
   - Assert `pitch >= w * 4 && pitch % 4 == 0` in `gl_util.d` (`1.18`);
     remove redundant `glBindTexture(GL_TEXTURE_2D, 0)` (`2.8`); orphan VBO
     before `glBufferSubData` in `uploadAndDrawDynamic()` (`2.5`); fix line
     193 length & `:251` `else {` (`5.1`).
3. **`Renderer`, `RenderTarget` & `Texture` (`1.3`, `1.4`, `1.15`, `1.18`, `3.2`, `5.1`)**:
   - In `Renderer.viewport()`: `assert(!inTarget())` and call
     `clipStack.reapply(...)` when `initialized && !clipStack.isEmpty()`
     (`1.3`).
   - Clamp/validate `RenderTarget` pixel dimensions against cached
     `min(GL_MAX_TEXTURE_SIZE, GL_MAX_RENDERBUFFER_SIZE)` before casting to
     `int`, and return `bool` from `resizeRenderTarget()` (`1.4`).
   - Skip MSAA allocation in `RenderTarget.allocate()` when `resolveFbo`
     `attachAndCheck` failed (`1.18`).
   - Guard `clearFrame()`/`beginTarget()` on `initialized`, null `textCache`
     in `destroy()` (`1.15`).
   - Restrict `Renderer.drawTexture(GLuint, ...)` to `package(yguilib.render)`
     (`3.2`); document `coordinatesFrom*` window-point units (`3.2`); group
     `defaultFont` getter/setter together (`5.1`).
   - Assert `info.width > 0 && info.height > 0` in `Texture.borrowedFromInfo`
     (`1.18`).
4. **Offscreen, pipelines & `ClipStack` (`2.1`-`2.4`, `1.13`, `1.14`, `1.18`, `2.8`, `5.1`)**:
   - Pass tracked `GLuint currentFbo` into `offscreen.d:attachAndCheck()`
     to remove `glGetIntegerv(GL_FRAMEBUFFER_BINDING)` (`2.1`).
   - Cache `fMaxSamples` (`GL_MAX_SAMPLES`) on `Renderer` (`2.2`).
   - Eliminate triple GL state restore in `endTarget()` (resolve directly to
     `f.saved.framebuffer` and apply scissor once) (`2.3`).
   - Set static sampler uniforms (`uTexture = 0`, `uMask = 0|1`) once in
     each pipeline's `initialize()` (`2.4`).
   - Fix `NaN` bypass & float32 infinite loop in `drawDashedLine()` (`1.13`),
     degenerate/NaN rect guards in `drawRectWithWidth()`/`RoundRectPipeline`
     (`1.14`), clear `fDashScratch` in `ColorPipeline.destroy()` (`2.8`),
     and add `nothrow @safe @nogc pure` to `quadVertices()` (`5.1`).
   - `clip_stack.d`: return `[0, 0, 0, 0]` on non-finite `RectF` (`1.18`),
     skip `glDisable(GL_SCISSOR_TEST)` in `reset()` when empty (`2.8`).
5. **Edge-case tests (`6.3`)**:
   - Add tests for huge `createRenderTarget`/`resizeRenderTarget` dims, `NaN`
     dashes/rects, and `Renderer.viewport()` with active clip rect.

## Verification

- `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`
- Verify `yguilib_test` module count increased by 1 (for `package_test.d`).
