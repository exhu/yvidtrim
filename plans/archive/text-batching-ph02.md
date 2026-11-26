# Phase 2: Renderer Batching, Smart Scissor & WidgetPainter Integration

## Scope & Target Files

- `yguilib/source/yguilib/render/internal/clip_stack.d` [MODIFY]
- `yguilib/source/yguilib/render/package.d` [MODIFY]
- `yguilib/source/yguilib/window.d` [MODIFY]
- `yguilib/source/yguilib/widget/internal/system_pipeline.d` [MODIFY]
- `yguilib/source/yguilib/widget/internal/widget_painter.d` [MODIFY]

Follow `codestyle.md` strictly (max 80 chars/line, 2-space indent, `f` prefix,
no default params, visibility sections). Always declare `scope(exit) w.destroy();`
before `scope(exit) w.endTargets();` in GL tests.

## Implementation Steps

1. **`yguilib/source/yguilib/render/internal/clip_stack.d`** [MODIFY]:
   - Add const scissor-change query methods (matching `push`/`pop`/`set`/`reset`):
     - `bool wouldPushChangeScissor(in RectF rect, int pixelW, int pixelH, float scale) const`:
       Compute `clipped` and `box = scissorBox(clipped, pixelW, pixelH, scale)`.
       Return `isEmpty() || box != fAppliedBox`.
     - `bool wouldPopChangeScissor(int pixelW, int pixelH, float scale) const`:
       If `stack[].length == 0`, return `false`.
       If `stack[].length == 1`, return `true` (scissor becomes disabled).
       Compute `box = scissorBox(stack[][$ - 2], pixelW, pixelH, scale)`.
       Return `box != fAppliedBox`.
     - `bool wouldSetChangeScissor(in RectF rect, int pixelW, int pixelH, float scale) const`:
       Compute `box = scissorBox(rect, pixelW, pixelH, scale)`.
       Return `isEmpty() || box != fAppliedBox`.
     - `bool wouldResetChangeScissor() const`:
       Return `!isEmpty()`.
   - In `push`/`pop`/`set`: avoid redundant `glEnable`/`glScissor` when scissor
     was already enabled before the call and `box == fAppliedBox`. Keep
     `fAppliedBox` and GL state identical to `Renderer.targetState()`.
   - Add unit tests for all four `would*ChangeScissor` methods.

2. **`yguilib/source/yguilib/render/package.d`** [MODIFY]:
   - Import `TextPipeline`, `TextVertex` from `yguilib.render.internal.pipelines`
     and `TextBatch`, `TextBatchStats` from `yguilib.render.internal.text_batch`.
   - Replace `Appender!(float[]) fTextVerts;` with `TextPipeline textPipeline;`
     and `TextBatch fTextBatch;`.
   - `initialize()`: call `textPipeline.initialize(&fPrograms);` and
     `textCache.onBeforeAtlasReset(&flush);`.
   - `destroy()`: if `textCache !is null`, `textCache.onBeforeAtlasReset(null);`;
     call `fTextBatch.releaseMemory();` before `clearTextCache()`; call
     `textPipeline.destroy();`.
   - Add public `void flush()`:
     ```d
     if (!initialized) {
       return;
     }
     fTextBatch.flush(textPipeline, logicViewport());
     ```
     Document that callers issuing direct raw GL calls (`glReadPixels`,
     `glFinish`) after text draws must call `flush()` first.
   - Add `package(yguilib.render)` method:
     ```d
     void queueTextQuad(GLuint texId, bool stencilClip, in TextVertex[4] quad) {
       if (!initialized || texId == 0) {
         return;
       }
       if (fTextBatch.needsFlushFor(texId, stencilClip)) {
         flush();
       }
       fTextBatch.pushQuad(texId, stencilClip, quad);
     }
     ```
   - Add `package(yguilib)` `version (unittest)` helpers:
     `TextBatchStats textBatchStats() const` and `void resetTextBatchStats()`.
   - Rewrite `drawTextRun(const(TextRun)* run, PointF pos, ColorF color)`:
     - Return if `run is null || !initialized`.
     - Fetch `atlasTex = glyphAtlasTexture()`, `atlasSz = glyphAtlasSize()`.
       Return if `atlasTex == 0 || atlasSz <= 0`.
     - Compute `screenX = round(pixelsFromLogicFloat(pos.x))`,
       `screenY = round(pixelsFromLogicFloat(pos.y))`, `invAtlas = 1.0f / atlasSz`,
       `invScale = totalScaling() > 0.0f ? 1.0f / totalScaling() : 1.0f`.
     - For each glyph with `g.slot.w > 0`:
       compute `(x0, y0, x1, y1)` using `invScale` (or `logicFromPixelsFloat`),
       `(u0, v0, u1, v1)`, build `TextVertex[4]` (TL, TR, BL, BR with `color`),
       call `queueTextQuad(atlasTex, false, quad)`.
   - Call `flush()` at the start (before GL/state mutation) of:
     - `drawFillRect`, `drawThinLineWithPoints`, `drawLineDashed`,
       `drawRectWithWidth`, `drawRoundRectDashed`, `drawTexture`,
       `drawImageRegion`
     - `clearFrame`, `clearPixelBox`, `viewport`, `onScalingChanged`,
       `beginTarget`, `endTarget`, `readPixels`, `clearTextCache`,
       `onFontDestroyed`
     - `colorPipelineRef`, `gradientPipelineRef`, `patternPipelineRef`,
       `texturePipelineRef`, `blurPipelineRef`
   - Update clip methods:
     - `pushClipRect`: `if (clipStack.wouldPushChangeScissor(...)) flush();`
     - `popClipRect`: `if (clipStack.wouldPopChangeScissor(...)) flush();`
     - `clipRect`: `if (clipStack.wouldSetChangeScissor(...)) flush();`
     - `resetClipRect`: `if (clipStack.wouldResetChangeScissor()) flush();`
   - Update existing raw `glReadPixels` text assertions in `render/package.d`
     unit tests (~lines 1511, 1535, 1586, 1608) to call `renderer.flush();`.
   - Add unit tests in `render/package.d`:
     1. Multi-font, multi-size, multi-color consecutive `drawTextWithFont` calls
        batch into `flushes == 1` with expected pixel colors.
     2. Interleaved `drawFillRect` flushes between text calls and preserves
        z-order.
     3. Scissor changes flush; redundant identical `pushClipRect` does not.
     4. Mid-batch atlas clear/growth flushes prior queued labels against old
        atlas before reallocating, keeping earlier labels intact.
     5. `beginTarget`/`endTarget` and `readPixels`/`captureFrame` auto-flush.
     6. Zero steady-state GC allocation across batched frames (`GC.stats()`).

3. **`yguilib/source/yguilib/window.d`** [MODIFY]:
   - In `swapBuffers()`: call `if (renderer !is null) renderer.flush();` before
     `yguilib_sdl3_gl_swap_window(handle);`.
   - In `clearWithColor()`: call `renderer.flush();` before `glClear(...)`
     when `renderer !is null`.

4. **`yguilib/source/yguilib/widget/internal/system_pipeline.d`** [MODIFY]:
   - In `runRenderPhase()`: after `foreach (s; renderSystems) s.render(ctx);`,
     call `if (ctx.renderer !is null) ctx.renderer.flush();`.

5. **`yguilib/source/yguilib/widget/internal/widget_painter.d`** [MODIFY]:
   - In `drawWidgets(VisibleWidgets widgets, Renderer r)`:
     Track `bool activeClip = false; RectF activeClipRect;` with
     `scope(exit) { if (activeClip) r.popClipRect(); }`.
     For each `vw`: if `!vw.hasClip`, pop if `activeClip`; if `vw.hasClip`,
     only pop+push when `!activeClip || vw.clipRect != activeClipRect`.
   - In `drawTree()`: call `r.flush();` after `drawWidgets(widgets, r);`.
   - Add unittest verifying consecutive clipped text-only sibling widgets
     share 1 flush (`renderer.textBatchStats().flushes == 1`).

## Verification

```bash
ninja -C _build && timeout 300 meson test -C _build
```
