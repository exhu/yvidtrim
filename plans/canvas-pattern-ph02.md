# Phase 2: Pattern API, Canvas Integration & Unit Tests

## Scope
Implement `PatternRepeat`, `Pattern`, `FillStyle.Kind.pattern`, and wire
pattern fills, strokes, clips, shadows, and render-target textures in
`yguilib/source/yguilib/render/canvas.d`, with thorough CPU and GL unit tests.

## Constraints
- Follow `codestyle.md` (2-space indent, LF, max 80 chars/line, opening `{` on
  same line).
- `Pattern.texture` MUST be `const(Texture)` so `Canvas.fillStyle() const` and
  `Canvas.strokeStyle() const` continue returning `FillStyle` by value without
  breaking constness.
- In GL tests that create a `RenderTarget`, declare
  `scope(exit) { while (r.inTarget()) r.endTarget(); }` AFTER `rt.destroy()`'s
  `scope(exit)` (see `AGENTS.md`).
- Never skip `assert(!fRenderer.isActiveTargetTexture(p.texture), ...)` when
  drawing a pattern whose texture belongs to an active render target.

## Steps

### 1. Public types in `yguilib/source/yguilib/render/canvas.d`
- Replace the `Pattern` stub with:
  - `enum PatternRepeat` (values match `pattern.frag.glsl` bitmask):
    - `noRepeat = 0`
    - `repeatX = 1`
    - `repeatY = 2`
    - `repeat = 3`
  - `struct Pattern`:
    - `const(Texture) texture;` (null or destroyed texture draws nothing)
    - `PatternRepeat repeat = PatternRepeat.repeat;`
    - `Transform2d transform = Transform2d.identity();` (pattern -> user space)
    - `ColorF tint = ColorF(1, 1, 1, 1);` (straight-alpha tint)
    - `static Pattern fromTexture(const(Texture) tex, PatternRepeat rep = PatternRepeat.repeat) nothrow @safe @nogc`
    - `ref Pattern withTransform(Transform2d xf) return nothrow @safe @nogc`
    - `ref Pattern withTint(ColorF c) return nothrow @safe @nogc`
- Update `FillStyle`:
  - Update doc comment ("solid color, gradient, or image pattern").
  - Add `pattern` to `FillStyle.Kind`.
  - Add `Pattern pattern;` field.
  - Add `static FillStyle fromPattern(in Pattern p) nothrow @safe @nogc`.

### 2. Canvas drawing & shadow integration in `canvas.d`
- Import `PatternUniforms` and `TextureMode` from
  `yguilib.render.internal.pipelines`.
- Add private helper `static bool isInvertible(in Transform2d m) nothrow @safe @nogc`:
  returns `isFinite(det) && abs(det) >= 1e-12f` for `det = m.a * m.d - m.b * m.c`.
- Update `paintVisible(in FillStyle s)`:
  - `case FillStyle.Kind.pattern:` return `s.pattern.texture !is null && s.pattern.texture.isValid() && s.pattern.texture.width() > 0 && s.pattern.texture.height() > 0 && s.pattern.tint.a > 0 && isInvertible(s.pattern.transform)`.
- Add helper `bool patternDrawable(in FillStyle s) const`:
  - Returns `true` for non-pattern styles; for `Kind.pattern`, checks
    `isInvertible(st.xf * s.pattern.transform)`.
  - Call in `fillWithRule` (when `blend` is true) and `stroke` alongside
    `paintVisible`, so a singular combined transform returns early before
    touching the stencil buffer.
- Add `static PatternUniforms patternUniforms(in Pattern p, in Transform2d logicToPattern, TextureMode mode)`:
  - Computes `uvXf = Transform2d.scaling(PointF(1.0f / tw, 1.0f / th)) * logicToPattern`.
  - Fills column-major `u.invXf`, `u.textureId = p.texture.id()`, `u.tint = p.tint`,
    `u.repeat = cast(int)p.repeat`, `u.mode = mode`, `u.bottomUp = p.texture.bottomUp()`.
- Update `drawPaint(const(float)[] verts, in FillStyle style)`:
  - For `FillStyle.Kind.pattern`:
    - `assert(!fRenderer.isActiveTargetTexture(style.pattern.texture), "drawing the texture of an active render target (feedback loop)");`
    - `const Transform2d logicToPat = (st.xf * style.pattern.transform).inverse();`
    - `const TextureMode mode = style.pattern.texture.premultiplied() ? TextureMode.premultiplied : TextureMode.straight;`
    - Call `fRenderer.patternPipelineRef().drawTriangles(verts, patternUniforms(style.pattern, logicToPat, mode), fRenderer.getLogicWidth(), fRenderer.getLogicHeight())`.
- Update `drawMaskPaint(const(float)[] verts, in FillStyle style, PointF origin, float vw, float vh)`:
  - For `FillStyle.Kind.pattern`:
    - `assert(!fRenderer.isActiveTargetTexture(style.pattern.texture), "drawing the texture of an active render target (feedback loop)");`
    - `const Transform2d logicToPat = (st.xf * style.pattern.transform).inverse() * Transform2d.translation(origin);`
    - Call `fRenderer.patternPipelineRef().drawTrianglesWithCurrentState(verts, patternUniforms(style.pattern, logicToPat, TextureMode.alphaMask), vw, vh)`.

### 3. Unit tests in `yguilib/source/yguilib/render/canvas.d`
1. Extend the CPU `FillStyle` unittest:
   - `Pattern.init` defaults (`texture is null`, `repeat == repeat`,
     `transform.isIdentity()`, `tint == ColorF(1, 1, 1, 1)`).
   - `Pattern.fromTexture(null, PatternRepeat.noRepeat).withTransform(...).withTint(...)`.
   - `FillStyle.fromPattern(p)` sets `Kind.pattern` and preserves fields.
2. Add a GL unittest for Canvas patterns (`test_canvas_patterns`):
   - Create a 20x20 4-quadrant test texture (TL red, TR green, BL blue, BR white).
   - `repeat`: tiles across a 100x60 rect (check tile (0,0), (1,0), (0,1), (3,2)).
   - `repeatX`: tiles horizontally for `y in [0, 20)`, background for `y >= 20`.
   - `repeatY`: tiles vertically for `x in [0, 20)`, background for `x >= 20`.
   - `noRepeat`: draws once in `[0, 20) x [0, 20)`, background outside, AND
     a subsequent `fill()` over the whole area works (proves stencil low bits
     were properly zeroed despite out-of-bounds fragments).
   - `Pattern.transform`: translation, 90-degree rotation, 2x scaling, and
     combined with `Canvas.translate`.
   - `Pattern.tint`: half alpha (`0.5f`) and color tinting.
   - Pattern stroke: thick line + self-overlapping cross with 0.5 tint alpha
     painted once (no double-blending at intersection) + dashed stroke.
   - Canvas `clip()` limits pattern fill; `save()`/`restore()` preserves
     `fillStyle()` / `strokeStyle()`.
   - Pattern shadow: half-transparent texture casts shadow only under opaque
     pixels; `noRepeat` casts no shadow outside `[0, 20) x [0, 20)`; `tint.a`
     scales shadow alpha.
   - `RenderTarget.texture()` used as a `Pattern`: upright (top red, bottom
     semi-transparent blue) and tiled cleanly.
   - Invalid patterns (null texture, destroyed texture, `tint.a == 0`,
     singular `Pattern.transform`) draw nothing.
   - `assert(glGetError() == GL_NO_ERROR);`.

## Verification
Run:
```bash
ninja -C _build && timeout 300 meson test -C _build
```
All unit tests must pass cleanly.
