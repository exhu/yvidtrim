# `yguilib` Render Canvas Package Review

```
  date    2026-11-27
  branch  main
  commit  7a96feaa25bba66718bc02d342f18c7c42932731 (fix composite_view after review)
```

Line numbers below refer to that commit.

Scope: `yguilib/source/yguilib/render/canvas/` (4 modules) and canvas-specific
`yguilib/source/yguilib/render/internal/` modules (`path_flatten.d`,
`path_stroker.d`, `stencil_ops.d`, `svg_path_parser.d`) — 8 modules total.
Core renderer, pipelines, targets, and text/font modules are covered in
[yguilib-review-report-render.md](yguilib-review-report-render.md).

Paths below are relative to `yguilib/source/yguilib/render/`.
Severity: **H** high, **M** medium, **L** low.

```
  Summary
  -------
  correctness, safety & lifecycle ..  9 findings (1 H, 5 M,  3 L)
  memory allocations & perf ........  3 findings (0 H, 1 M,  2 L)
  architecture & API design ........  1 finding  (0 H, 0 M,  1 L)
  code reuse & duplication .........  2 findings (0 H, 0 M,  2 L)
  codestyle & maintainability ......  3 findings (0 H, 0 M,  3 L)
  tests & verification gaps ........  2 findings (0 H, 1 M,  1 L)
  ---------------------------------------------------------------
  total ............................ 20 findings (1 H, 7 M, 12 L)
```

Architectural invariants verified: valid module declarations
(`yguilib.render.canvas`, `yguilib.render.canvas.package_test`); all 4
`internal/` modules use `package(yguilib):` + `private:`; stencil bit 7 (`0x80`)
clip / bits 0..6 (`0x7F`) winding invariants hold; all 13 `unittest` blocks in
`canvas/package_test.d` place `scope(exit) w.endTargets();` after `destroy()`.
Static checker warnings on `canvas/package.d` property getter/setter pairs and
`internal/stencil_ops.d:33` (`glStencilOpSeparate`) are false positives.

---

## Module Coverage

| Module | Lines | Role | Findings (`H/M/L`) |
|---|---:|---|---|
| `canvas/package.d` | 1,665 | `Canvas` 2D API: fills, strokes, clips, shadows, images, text | `1H / 3M / 4L` |
| `canvas/package_test.d` | 2,479 | GL integration tests (13 `unittest` blocks) & GC checks | `0H / 1M / 4L` |
| `canvas/path2d.d` | 661 | `Path2d` geometry builder (`moveTo`..`ellipse`, `addSvgPath`) | `0H / 2M / 0L` |
| `canvas/types.d` | 749 | `Transform2d`, `LineDash`, gradients, `Pattern`, `Shadow` | `0H / 0M / 2L` |
| `internal/path_flatten.d` | 438 | Curve flattening (Wang's formula), `Contours`, `isSingleConvex` | `0H / 1M / 0L` |
| `internal/path_stroker.d` | 811 | Dash splitting, caps, joins, miter limit, stroke triangles | `0H / 0M / 1L` |
| `internal/stencil_ops.d` | 151 | Stencil bit-7 clip & bits 0..6 winding/cover GL helpers | Clean |
| `internal/svg_path_parser.d` | 878 | Zero-alloc W3C SVG `d` parser & arc conversion | `0H / 0M / 1L` |

---

## 1. Correctness, Safety & Lifecycle

### 1.1 [H] `drawImageShadowMask` disables blending, causing overlapping glyph quads to erase shadows
`canvas/package.d:1189-1212, 1434-1437`

`drawImageShadowMask` calls `glDisable(GL_BLEND)` (`:1206`) before drawing
`fShadowVerts[]`. Fine for a single `drawImage` quad, but `drawTextBitmap`
(`:1434-1437`) passes all glyph quads of a string into `drawImageShadow`.
Whenever adjacent glyph quads overlap — always in `strokeText` (expanded by
`outlinePx`), and frequently with `maxWidth` squeeze, kerning, or italics —
transparent margin pixels of glyph N overwrite glyph N-1's shadow mask with
`0`, punching rectangular holes in the shadow.

Fix: Keep blending enabled for multi-quad masks (`GL_ONE, GL_ONE_MINUS_SRC_ALPHA`
with `alpha = 1.0f` in the mask and `paintAlpha` applied in `compositeShadow`,
or `GL_MAX` blend equation on GLES 3).

### 1.2 [M] Gradient/pattern text shadows ignore paint alpha
`canvas/package.d:1435-1437`

`drawTextBitmap` calls `drawImageShadow(atlasTex, solid ? paint.color.a : 1.0f)`.
Unlike `drawShadow`, gradient stop alphas and `Pattern.tint.a`/texture alpha
are ignored, casting opaque shadows for semi-transparent gradient/pattern text.

Fix: Render gradient/pattern text shadow masks with a glyph-masked paint pass
into the shadow offscreen target.

### 1.3 [M] Whitespace-only text with shadow allocates/blurs empty offscreen FBOs
`canvas/package.d:1434-1445`

When all glyphs have `g.slot.w <= 0` (e.g., `"   "`), `fImageVerts` is empty,
yet `drawImageShadow` computes `boundsOfVerts([])` -> `RectF(-1, -1, 2, 2)`,
allocating/clearing/blurring two offscreen FBOs and running a stencil pass for
gradient/pattern text.

Fix: Add `if (fImageVerts[].length == 0) { return; }` right after
`buildTextVerts(*run, p);` (`:1434`).

### 1.4 [M] `Path2d.moveTo` does not reset `fClosed`
`canvas/path2d.d:45-54, 270, 288`

After `closePath()` (including `rect()`/`roundRect()`), a subsequent `moveTo`
leaves `fClosed == true`, causing an immediate `closePath()` to be skipped
(`:270`) and `addPath` (`:288`) to propagate stale `fClosed = true`.

Fix: Set `fClosed = false;` in `Path2d.moveTo`.

### 1.5 [M] `Path2d.addPath` does not validate `Transform2d` finiteness
`canvas/path2d.d:279-301`

Applies `t.apply(p)` without checking `t` or output points for finiteness,
allowing `NaN`/`Infinity` into `fPoints` and `fCurrent`.

Fix: Early-return if any field of `t` is non-finite (and guard `isFinitePoint`).

### 1.6 [M] Zero-length subpaths dropped before stroking
`internal/path_flatten.d:141-157`

`Flattener.finish` (`:151`) discards contours with `count < 2`. Zero-length
segments (`moveTo(p); lineTo(p);` or SVG `M 10 10 h 0`) never reach
`path_stroker.d:312-313`'s `dot(pts[0])` cap implementation.

Fix: Retain 1-point contours when a drawing verb was emitted on the subpath
(fills already skip `info.count < 3` in `appendFan`).

### 1.7 [L] `DashPhase` can produce `phase == period` for tiny negative offsets
`internal/path_stroker.d:133-136`

For `offset = -1e-20f`, `fmod(offset, period) + period` rounds to `period` in
float32, advancing `startIdx` past a full cycle.

Fix: Clamp `if (phase >= period) { phase = 0; }` after `if (phase < 0)`.

### 1.8 [L] Relative SVG coordinate overflow poisons `st.cur`
`internal/svg_path_parser.d:334, 354, 376, 398, 433, 467, 496, 524, 654`

If `cur + delta` overflows to `±infinity`, `Path2d` ignores it, but the parser
still stores `st.cur = dst`, poisoning subsequent relative commands.

Fix: Only update `st.cur` (or return `false`) when `isFinitePoint(dst)`.

### 1.9 [L] Minor finiteness edge cases in `Transform2d` and `LineDash`
`canvas/types.d:70-75, 188-195`

`Transform2d.isInvertible()` omits `isFinite(e) && isFinite(f)`;
`LineDash.fromSegments` can sum large finite segments to `float.infinity`
(return `LineDash.init` if `!isFinite(sum)`).

---

## 2. Memory Allocations & Performance

### 2.1 [M] Dynamic array literal assigned to runtime slice in `gradientUniforms`
`canvas/package.d:814-815`

`u.stopColors[i * 4 .. i * 4 + 4] = [stop.color.r, stop.color.g, stop.color.b, stop.color.a];`
types the RHS literal as a GC-allocated `float[]` per stop on every gradient
draw unless elided by the optimizer.

Fix: Assign the 4 elements directly or via `const float[4]`, and mark
`gradientUniforms` `@nogc`.

### 2.2 [L] `shadowBox` double-pad admits off-screen shadows within `2 * pad`
`canvas/package.d:1077-1081`

Check `r.x * scale - pad < vx1 && (r.x + r.width) * scale + pad > vx0` (and Y)
before building the box.

### 2.3 [L] Redundant `fRenderer.flush()` in `Canvas.restore()`
`canvas/package.d:338, 1567`

Line 338 flushes immediately before `rebuildClip()` flushes again at `:1567`.

---

## 3. Architecture, Encapsulation & API Design

### 3.1 [L] `GradientStops` exposes mutable `stops` and `count` fields
`canvas/types.d:264-267`

Unlike `LineDash` (`private fSegs`/`fCount`), `GradientStops` leaves `stops`
and `count` public, allowing callers to bypass sorting/clamping or exceed
`maxGradientStops`. Make them private with `count()`/`items()` accessors.

---

## 4. Code Reuse & Duplication

### 4.1 [L] Duplicated glyph quad placement and UV math in `canvas/package.d`
`canvas/package.d:1369-1391, 1454-1472`

`queueTransformedTextRun` and `buildTextVerts` repeat identical local rect and
UV math. Extract a small `@nogc` helper.

### 4.2 [L] Duplicated star path and GC stats harness in tests
`canvas/package_test.d:46-56, 1897-1907`

5-point star loop and 10-line `GC.collect()`/`GC.stats()` harness are repeated
across `package_test.d`, `path2d.d`, `path_flatten.d`, and `path_stroker.d`.

---

## 5. Codestyle & Maintainability

### 5.1 [L] Minor codestyle nits in `canvas/package.d` and `canvas/package_test.d`
- `canvas/package.d:550-555`: `FrameState` uses per-declaration `private`
  instead of a `private:` section label (`codestyle.md` §4).
- `canvas/package_test.d:985-1017, 1051-1054, 1644-1645, 2069-2070, 2155, 2238-2239`:
  mixes `cv.fontSpec = ...` with `cv.textAlign(a)` on non-`@property` accessors.
- `canvas/package_test.d:1054, 2181-2182`: dead statement before `clear()` at
  `:1054`, and redundant assertion at `:2181` subsumed by `:2182`.

---

## 6. Tests & Verification Gaps

### 6.1 [M] Key behavioral & regression coverage gaps in `canvas/package_test.d`
Missing tests for:
1. Shadowed `strokeText` and overlapping/squeezed `fillText` (catches 1.1).
2. Shadowed gradient/pattern text with alpha < 1 (catches 1.2).
3. Whitespace-only text (`"   "`) with shadow (catches 1.3).
4. Gradient fill steady-state zero-GC test (guards 2.1).
5. `Canvas.clip(emptyPath)` masking out all drawing.
6. `clearRect` after batched `fillText`.
7. Headless `Canvas` (`!fRenderer.isInitialized()`) across draw/clip/text ops.

### 6.2 [L] Missing `glGetError()` checks in 4 GL tests
`canvas/package_test.d:977-1034, 1037-1194, 1315-1405, 1408-1464`

`test_canvas_text_state`, `test_canvas_fill_text`, `test_canvas_stroke_text`,
and `test_canvas_dash_gc` omit `assert(glGetError() == GL_NO_ERROR);`.

---

## Prioritized Action List

- **High**
  1. Keep blending enabled in `drawImageShadowMask` for overlapping glyph quads
     (`canvas/package.d:1189-1212, 1434-1437`).
- **Medium**
  2. Eliminate the dynamic array literal in `gradientUniforms` and mark `@nogc`
     (`canvas/package.d:814-815`).
  3. Early-return on empty `fImageVerts` in `drawTextBitmap`, honor gradient/
     pattern alpha in text shadows, reset `fClosed` in `Path2d.moveTo`, validate
     `Transform2d` in `Path2d.addPath`, and retain 1-point contours for
     stroking zero-length subpaths.
  4. Add the missing regression tests in `canvas/package_test.d`.
- **Low**
  5. Encapsulate `GradientStops`, extract glyph quad helper, and fix minor
     edge/style nits.
