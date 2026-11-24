# Phase 3: Canvas Solid-Color Text Batching & Tests

## Scope & Target Files

- `yguilib/source/yguilib/render/canvas/package.d` [MODIFY]
- `yguilib/source/yguilib/render/canvas/package_test.d` [MODIFY]

Follow `codestyle.md` strictly (<= 80 chars/line, 2-space indent, `f` prefix,
functions <= ~50 lines, no default params).

## Implementation Steps

1. **`yguilib/source/yguilib/render/canvas/package.d`** [MODIFY]:
   - Import `TextVertex` from `yguilib.render.internal.pipelines`.
   - Add private helper struct & placement function to share anchor/squeeze
     math cleanly:
     ```d
     struct TextPlacement {
       float q;
       float ox;
       float oy;
       float sx;
       float invAtlas;
     }
     ```
     `TextPlacement computeTextPlacement(Font f, string text, int outlinePx, PointF pos, float maxWidth)`
     computing `q`, `m = textMetricsOf(f, text)`, `off = textAnchorOffset(...)`,
     `s = m.width > maxWidth ? maxWidth / m.width : 1.0f`,
     `ox = pos.x + off.x * s - (outlinePx / q) * s`,
     `oy = pos.y + off.y - outlinePx / q`,
     `invAtlas = 1.0f / fRenderer.glyphAtlasSize()`.
   - Add `buildTextVerts(in TextRun run, in TextPlacement p)` (fills
     `fImageVerts` using `p`, used for shadows and masked gradient/pattern
     text).
   - Add `queueTransformedTextRun(GLuint atlasTex, in TextRun run, in TextPlacement p, in ColorF color)`:
     - `const bool stencil = clipActive();`
     - For each glyph in `run.glyphs` with `g.slot.w > 0`:
       - Compute user-space rect `(gx0, gy0)` .. `(gx1, gy1)`:
         `gx0 = p.ox + g.dx / p.q * p.sx`, `gy0 = p.oy + g.dy / p.q`,
         `gx1 = gx0 + g.dw / p.q * p.sx`, `gy1 = gy0 + g.dh / p.q`.
       - Transform the 4 corners via `st.xf.apply(...)`:
         `p0 = (gx0, gy0)`, `p1 = (gx1, gy0)`, `p2 = (gx0, gy1)`,
         `p3 = (gx1, gy1)`.
       - Compute UVs `(u0, v0, u1, v1)` from `g.slot`, `g.src*`, `p.invAtlas`.
       - Build `TextVertex[4]` (TL, TR, BL, BR) with `color` and call
         `fRenderer.queueTextQuad(atlasTex, stencil, quad)`.
   - Update `drawTextBitmap(string text, PointF pos, float maxWidth, int outlinePx)`:
     - After resolving `run`, check `const GLuint atlasTex = fRenderer.glyphAtlasTexture();`
       and `const int atlasSz = fRenderer.glyphAtlasSize();`
       (`if (atlasTex == 0 || atlasSz <= 0) return;`).
     - Compute `const TextPlacement p = computeTextPlacement(f, text, outlinePx, pos, maxWidth);`.
     - `const bool solid = paint.kind == FillStyle.Kind.color;`
     - If `solid && !st.shadow.isVisible()`:
       `queueTransformedTextRun(atlasTex, *run, p, paint.color); return;`
     - Otherwise:
       `buildTextVerts(*run, p);`
       If `st.shadow.isVisible()`:
       `drawImageShadow(atlasTex, solid ? paint.color.a : 1.0f);`
       If `solid`:
       `queueTransformedTextRun(atlasTex, *run, p, paint.color);`
       Else:
       `beginClipTest(clipActive()); drawMaskedPaint(fImageVerts[], atlasTex, paint); endStencil();`
   - Flush before stencil bit 7 or offscreen target state changes:
     - In `clip(Path2d path)`: if `fRenderer.isInitialized()`, call
       `fRenderer.flush();` BEFORE `disableScissor()`.
     - In `restore()`: when `st.clipCount < fClips[].length`, call
       `fRenderer.flush();` BEFORE `rebuildClip()`.
     - In `beginShadowPass()`: call `fRenderer.flush();` BEFORE
       `fRenderer.targetState()`.

2. **`yguilib/source/yguilib/render/canvas/package_test.d`** [MODIFY]:
   - Add `r.flush();` before raw `glReadPixels` (`frameBounds` / `grabFrame`)
     in existing Canvas text tests:
     - `test_canvas_fill_text` (~lines 1059..1183)
     - `test_canvas_fill_text_paint` (~line 1205)
     - `test_canvas_stroke_text` (~lines 1330..1391)
     - `checkCenter` (~line 1639)
     - rotated / gradient / rtl / maxWidth test (~lines 2064..2161)
   - Add new unit tests in `package_test.d`:
     1. Consecutive solid `fillText` and `strokeText` with different colors
        and transforms batch into 1 flush (`r.textBatchStats().flushes == 1`).
     2. Clipped Canvas text batches under the same `clip()` and flushes on
        `clip()`, `restore()`, and when mixing unclipped `Renderer.drawText*`
        and clipped `Canvas.fillText`.
     3. Interleaved `Canvas.fill`, `stroke`, `drawImage`, gradient text, and
        shadowed text flush and preserve exact z-order.
     4. Zero steady-state GC allocation across repeated batched `Canvas.fillText`
        frames (`GC.stats()`).

## Verification

```bash
ninja -C _build && timeout 300 meson test -C _build
```
