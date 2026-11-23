# Phase 2: fillText (solid color)

Prereq: phase 1 done. Files: `canvas/package.d` (see `drawImageRegionTinted`,
`buildImageVerts`, `drawImageShadow`), `render/package.d` (`font`,
`drawTextTexture`), `render/font_manager.d`, `render/internal/text_cache.d`.

Steps:
1. Effective scale: `effScale = totalScaling * sqrt(|det st.xf|)`, quantized
   (1/8 steps, clamped sane range). Extend `FontManager.getFont` (or add
   `getFontAtScale`) so fonts for quantized scales are cached; `TextCache`
   key already uses `scaledSize`.
2. `fillText(string, PointF)` : resolve font, get `TextTexture` via
   `Renderer` package(yguilib.render) accessor, compute dest rect in logic
   units (bitmap px / effScale) positioned by align/baseline anchor,
   transform vertices with `st.xf`, draw using texture pipeline with
   `tint = fillStyle.color` (solid only here), under `beginClipTest`, with
   shadow via the image-shadow path. Needs a `TextTexture`-based variant
   of `drawImageShadow` (texture id instead of `Texture`) - refactor to share.
3. `fillTextWithMaxWidth(string, PointF, float maxWidth)`: scale x by
   `maxWidth/width` about the anchor when wider; nothing for invalid
   maxWidth (<=0, non-finite).
4. No-ops: uninitialized renderer, empty text, non-finite point, invisible
   fill. Non-solid fill styles: treated as no-op until phase 3 (document).
5. Tests: geometry (headless where possible), GL pixel tests: translated,
   rotated 90deg bounding box, clip, shadow, maxWidth shrink.

Done: build + tests pass.
