# `yguilib` Render Package Review

```
  date    2026-11-27
  branch  main
  commit  7a96feaa25bba66718bc02d342f18c7c42932731 (fix composite_view after review)
```

Line numbers below refer to that commit.

Scope: `yguilib/source/yguilib/render/` core, offscreen, pipeline, font, and
text-batching modules (16 modules total). Canvas and path/stencil modules
(`render/canvas/*` + `path_flatten.d`, `path_stroker.d`, `stencil_ops.d`,
`svg_path_parser.d`) are covered separately in
[yguilib-review-report-render-canvas.md](yguilib-review-report-render-canvas.md).

Paths below are relative to `yguilib/source/yguilib/render/`.
Severity: **H** high, **M** medium, **L** low.

```
  Summary
  -------
  correctness, safety & lifecycle .. 23 findings (5 H, 12 M,  6 L)
  memory allocations & perf ........ 13 findings (0 H,  7 M,  6 L)
  architecture & API design ........  5 findings (0 H,  1 M,  4 L)
  code reuse & duplication .........  5 findings (0 H,  0 M,  5 L)
  codestyle & maintainability ......  6 findings (0 H,  0 M,  6 L)
  tests & verification gaps ........  8 findings (0 H,  6 M,  2 L)
  ----------------------------------------------------------------
  total ............................ 60 findings (5 H, 26 M, 29 L)
```

Architectural invariants verified: GLES via `glad2.gles2` only; no GL/TTF calls
in GC `~this()`; all `internal/` modules use `package(yguilib):` + `private:`;
`TextRunCache` is GC-clean on cache hit. Static checker warnings at
`package.d:147,160,638` are valid property getter/setter pairs (`codestyle.md`
§2).

---

## Module Coverage

| Module | Lines | Role | Findings (`H/M/L`) |
|---|---:|---|---|
| `package.d` | 2,688 | `Renderer` facade, GL state tracking, targets, text batching | `2H / 5M / 6L` |
| `colors.d` | 20 | Named 16-color `ColorF` constants | Clean |
| `font.d` | 236 | SDL_ttf `Font` wrapper, monotonic `id`, main-thread `destroy()` | `0H / 3M / 2L` |
| `font_manager.d` | 466 | Font face registry, unscaled & quantized-scale caches | `0H / 4M / 3L` |
| `image.d` | 248 | CPU RGBA8 `Image` load/save (`SDL3_image`) and flip | Clean |
| `render_target.d` | 494 | Offscreen FBO/MSAA `RenderTarget`, resolve, `toImage()` | `0H / 0M / 2L` |
| `render_types.d` | 735 | `PointF`, `RectF`, `ColorF`, `DashPattern`, CSS colors | `0H / 0M / 1L` |
| `texture.d` | 182 | GPU `Texture` wrapper (owned & borrowed RT textures) | `0H / 0M / 1L` |
| `internal/clip_stack.d` | 358 | Scissor `ClipStack` with outward pixel snapping | `0H / 0M / 2L` |
| `internal/gl_test_util.d` | 210 | `version(unittest)` `GlTestWindow` & pixel readback helpers | `0H / 1M / 1L` |
| `internal/gl_util.d` | 615 | Blend state, shader compile, VBO/EBO, `ProgramTracker` | `2H / 2M / 3L` |
| `internal/glyph_atlas.d` | 580 | Single-page RGBA8 GL glyph atlas, `ShelfPacker`, reset hook | `1H / 2M / 2L` |
| `internal/offscreen.d` | 258 | `OffscreenTarget` (shadows), `SavedTargetState`, FBO helpers | `0H / 1M / 0L` |
| `internal/pipelines.d` | 1,107 | 7 shader pipelines (`Color`, `Texture`, `Blur`, `RoundRect`, ...) | `0H / 3M / 2L` |
| `internal/text_batch.d` | 250 | Per-frame indexed glyph quad batcher (`TextVertex[4]`) | `0H / 2M / 1L` |
| `internal/text_cache.d` | 912 | LRU `TextRunCache`, reused `fQuads`, pooled `RunGlyph` spans | `1H / 3M / 3L` |

*(Note: the uninitialized `allocRgbaTexture()` gutter bug is shared by
`internal/gl_util.d` and `internal/glyph_atlas.d` and deduplicated as 1 `[H]`
finding below.)*

---

## 1. Correctness, Safety & Lifecycle

### 1.1 [H] `allocRgbaTexture()` leaves glyph atlas texture gutters uninitialized
`internal/gl_util.d:556-577`, `internal/glyph_atlas.d:158-162, 198-200, 234-237`

`allocRgbaTexture` documents a zero-filled RGBA8 texture and `ShelfPacker`
leaves 1 px gutters around glyphs to prevent `GL_LINEAR` bleed, but
`glTexImage2D(..., null)` leaves texels undefined per the GLES spec. On GPUs
that recycle VRAM, uninitialized gutters cause linear-filtering artifacts.

Fix: Clear the texture after allocation (e.g., via scratch FBO + `glClear` to
`(0, 0, 0, 0)` or zeroed upload), or explicitly zero the 1 px border per glyph.

### 1.2 [H] Unchecked `malloc` return in `uploadAndDrawIndexedQuads()`
`internal/gl_util.d:261-277`

`(cast(ushort*) malloc(count * ushort.sizeof))[0 .. count]` slices and writes
through the pointer without checking for `null`.

Fix: Check `ptr !is null` (e.g. `assert(ptr !is null)` / `onOutOfMemoryError()`)
or use a reusable buffer.

### 1.3 [H] `Renderer.viewport()` lacks `!inTarget()` guard and leaves `ClipStack` stale
`package.d:122-129`

Calling `viewport()` while a render target is active mutates the target's
viewport (overwritten on `endTarget()`), and calling it with an active
`ClipStack` leaves GL's scissor box stale (scissor Y depends on `pixelH`),
unlike `onScalingChanged()` (`:1337-1341`).

Fix: `assert(!inTarget(), ...)` and call
`clipStack.reapply(pixelWidth, pixelHeight, totalScaling())` when
`initialized && !clipStack.isEmpty()`.

### 1.4 [H] `RenderTarget` size overflow, missing GL max-size check, and ignored resize failure
`package.d:772-809, 1294-1307`, `render_target.d:113-159`

- `targetPixelsFromLogic()` casts `ceil(logic * totalScaling())` directly to
  `int`: huge finite floats (`1e30f`) overflow `int` to negative.
- Neither `Renderer` nor `RenderTarget.allocate()` checks
  `min(GL_MAX_TEXTURE_SIZE, GL_MAX_RENDERBUFFER_SIZE)` (unlike `OffscreenTarget`).
- `resizeRenderTarget()` ignores `rt.allocate(pw, ph)`'s `bool` return value.

Fix: Reject sizes above cached `min(GL_MAX_TEXTURE_SIZE, GL_MAX_RENDERBUFFER_SIZE)`
before casting to `int`, and return `bool` from `resizeRenderTarget()`.

### 1.5 [H] `RunGlyph.dx`/`dy` silently overflow `short` (`32767`) on long strings or HiDPI
`internal/text_cache.d:23-34, 319-333`

`fillRunGlyphs` truncates `q.dstX - outlinePx` and `q.dstY - outlinePx` with
`cast(short)`. Long single-line strings (~2500+ chars at 16 px, fewer at 2x
DPI) wrap negative and render backwards over the start of the line.

Fix: Change `RunGlyph.dx` and `RunGlyph.dy` from `short` to `int`.

### 1.6 [M] `Font.fromMemory` does not retain a GC reference to `fontData`
`font.d:28-45, 189-205`

`SDL_IOFromConstMem` + `TTF_OpenFontIO` borrows `fontData.ptr` for the entire
lifetime of the TTF handle. Dropping the caller's slice risks GC collection
while the font is still in use.

Fix: Store `private const(void)[] fMemoryData;` on `Font` (cleared in
`destroy()`) and document lifetime requirements for non-GC buffers.

### 1.7 [M] Non-finite `ptSize`/`scale` (`float.infinity`) bypasses `> 0.0f` checks in `Font`
`font.d:35, 66, 167`

Guard with `isFinite(ptSize) && ptSize > 0.0f` and
`isFinite(scale) && scale > 0.0f`.

### 1.8 [M] Registering `"default"` in `FontManager` stores an unreachable face
`font_manager.d:90-120, 263-277, 307-328`

`registerFont*("default", ...)` inserts into `registry["default"]`, but
`resolveSource("default")` bypasses `registry` and `dropFace("default")` misses
cached `""` fonts.

Fix: Reject `"default"` (`assert(fontName != "default")`) or normalize
`"default"` to `""`.

### 1.9 [M] `FontManager.sizeMilliOf` int overflow and `quantizeScaleEighths` > 1024 px
`font_manager.d:251-257, 340-351`

`sanitizeSize` has no upper bound, so huge finite `ptSize` overflows
`cast(int)(size * 1000.0f + 0.5f)` and bypasses the 1024 px cap.

Fix: Clamp `ptSize` to a sane maximum in `sanitizeSize` (e.g. `<= 4096.0f`).

### 1.10 [M] `GlyphAtlas.makeRoom()` only doubles `fSize` once
`internal/glyph_atlas.d:194-209, 221-228`

When `fSize == 512` and `fMaxSize == 4096`, a glyph with `w = 1100` fails even
after one doubling to `1024`.

Fix: Pass `minDim = max(w, h) + 2` to `makeRoom(int minDim)` and double until
`fSize >= minDim || fSize >= fMaxSize`.

### 1.11 [M] `TextRunCache.resolveSlots` aborts after 2 attempts even while atlas is growing
`internal/text_cache.d:420-449`

If an atlas grows twice in one run (`512 -> 1024 -> 2048`), `resolveSlots`
treats the second generation bump as thrash and renders blank text for that
frame.

Fix: Keep retrying whenever `fAtlas.size()` increased; only flag thrash when
the atlas cleared at `fMaxSize` without growing.

### 1.12 [M] `TextBatch.beginRun` with 0 quads violates empty invariants
`internal/text_batch.d:39-47, 83-101`

`beginRun(texId, clip)` sets `fTexture`/`fStencilClip` eagerly while
`fQuadCount == 0`, so `texture()`/`stencilClip()` return non-empty values when
`empty()` is `true`. Also `appendQuad` lacks `assert(fTexture != 0)`.

Fix: Return `0`/`false` when `fQuadCount == 0` and assert `fTexture != 0` in
`appendQuad`.

### 1.13 [M] `NaN` bypass and float32 infinite loop in `ColorPipeline.drawDashedLine()`
`internal/pipelines.d:106-131, 212-254`

`<= 0.0f` guards miss `NaN`, and very large `f.dist / period` hits
`cur + period == cur` in float32, looping infinitely.

Fix: Use `!(x > 0.0f)` + `isFinite` guards, and break if `cur + period <= cur`.

### 1.14 [M] Missing `NaN`/degenerate-rect guards in `drawRectWithWidth()` and `RoundRectPipeline.draw()`
`internal/pipelines.d:139, 597-642`

Early-return on `!(rect.width > 0.0f && rect.height > 0.0f)` + `isFiniteRect`.

### 1.15 [M] Missing `initialized` guards in `clearFrame()`/`beginTarget()` and `textCache` not nulled
`package.d:74-107, 279-291, 818-858`

Guard `clearFrame()` with `if (!initialized) return;`, `assert(initialized)` in
`beginTarget()`, and set `textCache = null;` in `destroy()`.

### 1.16 [M] `ProgramTracker.invalidate()` can wrap `fEpoch` to `0`
`internal/gl_util.d:333-341`

Fix: `if (++fEpoch == 0) { fEpoch = 1; }`.

### 1.17 [M] `gl_test_util.px(x, y)` is off by 1 pixel in GL Y vs `readAt(x, y)`
`internal/gl_test_util.d:96-109`

Uses `testHeight - y` instead of `testHeight - 1 - y` (so `y == 0` reads out of
bounds). Delegate `px()` to `readAt()`.

### 1.18 [L] Minor safety & cleanup edge cases
- `internal/clip_stack.d:195-229`: `scissorBox()` passes negative dims on
  non-finite `RectF`; return `[0, 0, 0, 0]`.
- `internal/gl_util.d:532, 597`: assert `pitch >= w * 4 && pitch % 4 == 0`.
- `texture.d:87-97`: `borrowedFromInfo()` should assert
  `info.width > 0 && info.height > 0`.
- `render_target.d:123-136`: skip MSAA creation when `resolveFbo` `attachAndCheck`
  already failed.
- `internal/glyph_atlas.d:94-99, 136-138`: assert `maxSize <= short.max` and
  `f !is null` in `slotFor`.
- `internal/text_cache.d:209-217`: `clear()` should also release `fQuads` and
  reset `fLoggedThrash = false`.

---

## 2. Memory Allocations & Performance

### 2.1 [M] `internal/offscreen.d:233-257` — `attachAndCheck()` calls `glGetIntegerv(GL_FRAMEBUFFER_BINDING)`
Violates `ARCHITECTURE.md`'s no-GL-queries invariant. Pass the renderer's
tracked `GLuint currentFbo` parameter instead.

### 2.2 [M] `package.d:1310-1315` — `targetSampleCount()` queries `GL_MAX_SAMPLES` every MSAA target creation
Cache `fMaxSamples` on `Renderer`.

### 2.3 [M] `package.d:872-890`, `render_target.d:177-192` — Triple redundant GL state restore in `endTarget()`
`resolve()`, `f.saved.restore()`, and `clipStack.reapply()` each rebind/rewrite
FBO and scissor state in sequence. Restore directly to `f.saved.framebuffer` in
`resolve()` and eliminate duplicate scissor calls.

### 2.4 [M] `internal/pipelines.d:373, 537, 822, 884, 959, 1094` — Redundant constant sampler `glUniform1i` per draw
Set static sampler unit uniforms (`uTexture = 0`, `uMask = 0|1`) once in each
pipeline's `initialize()`.

### 2.5 [M] `internal/gl_util.d:125-145` — `uploadAndDrawDynamic()` does not orphan VBO before `glBufferSubData`
Can trigger implicit GPU/CPU sync stalls on repeated draws per frame; consider
orphaning or ring-buffering if profiling shows stalls.

### 2.6 [M] `internal/text_cache.d:256-258, 461-481` — O(N^2) eviction scans when a frame exceeds `maxEntries`
Every miss from `maxEntries` (2048) to `hardCap` (4096) scans the whole AA and
finds 0 stale candidates. Track `bool fNoStaleEntries` (reset in `beginFrame()`),
and consider `topN` instead of full `sort`.

### 2.7 [M] `font_manager.d:197-199, 299-304` — `destroyScaledFonts()` flushes all 64 scaled fonts in one burst
Triggers 64 full scans of `TextRunCache.cache` and `GlyphAtlas.fSlots`. Evict
an oldest subset or add a batch font-destruction hook.

### 2.8 [L] Minor allocation & GL redundancy nits
- `internal/glyph_atlas.d:146-156`: `removeFont()` allocates a fresh GC
  `GlyphKey[]`; reuse a `ReusableArray!GlyphKey` scratch buffer.
- `internal/text_cache.d:252-255`: whitespace-only strings miss cache every
  frame; consider caching zero-glyph runs.
- `font_manager.d:157-173, 331`: unscaled `cache` has no upper bound.
- `internal/clip_stack.d:50-53`: `reset()` calls `glDisable(GL_SCISSOR_TEST)`
  even when already empty.
- `internal/gl_util.d:504-515`: redundant `glBindTexture(GL_TEXTURE_2D, 0)`
  immediately before rebind.
- `internal/pipelines.d:39-41`: `ColorPipeline.destroy()` retains `fDashScratch`.

---

## 3. Architecture, Encapsulation & API Design

### 3.1 [M] Monolithic `render/package.d` (2,688 lines; 1,305 lines inline GL tests)
`package.d:1-2688`

Move the inline GL tests (`:1383-2688`) into `render/package_test.d`, matching
`canvas/package_test.d`.

### 3.2 [L] Minor API/encapsulation nits
- `package.d:649-659`: public `Renderer.drawTexture(GLuint, ...)` exposes raw
  GL handle; restrict to `package(yguilib.render)` if external callers don't
  need it.
- `package.d:258-269`: document that `coordinatesFrom*` inputs are in window
  points.
- `font.d:105-137, 180`: document pixel-space units on metric methods and make
  `handle` a read-only `package(yguilib)` accessor.
- `font_manager.d:340-351`: `quantizeScaleEighths` is file-local; move to
  `private:`.

---

## 4. Code Reuse & Duplication

### 4.1 [L] Duplicated GL test setup and helpers
- `render_target.d:280-320` and `internal/text_cache.d:517-911`: manually
  duplicate SDL/Window setup instead of using `GlTestWindow`.
- `package.d:1409-2039`: 630-line unittest repeats raw `glReadPixels(x, 240 - y)`
  instead of `gl_test_util.readAt`.
- `render_types.d:279-284, 318-323`: duplicate `nearColor` helper.
- `internal/text_batch.d:134-146`: `releaseMemory()` duplicates `clear()`.

---

## 5. Codestyle & Maintainability

### 5.1 [L] Minor codestyle nits across `render/`
- `internal/gl_util.d:193, 251`: line 193 is 85 chars; newline `else {` at `:251`.
- `package.d:551, 638`: `defaultFont` getter and setter separated by 87 lines.
- `internal/pipelines.d:457`: `quadVertices()` missing `nothrow @safe @nogc pure`.
- `internal/gl_test_util.d:1-6`: block doc comment missing leading `*` prefixes.
- `font.d:13, 26, 42, 57, 73`: `defaultTtfFontData` imported at module scope
  (test-only); docstrings say `(defaults to 1.0f)`; throw messages omit
  `lastError()`.
- `font_manager.d:225, 237`: redundant per-declaration `package(yguilib)`
  inside a `package(yguilib):` class.

---

## 6. Tests & Verification Gaps

### 6.1 [M] Tautological assertion in 600-string atlas unittest
`package.d:2378`

`assert(r.glyphAtlasTexture() == atlasTex || i > 0);` is always true for
`i = 1..599`. Verify explicitly that the atlas texture ID stayed constant or
grew at most once without per-string textures.

### 6.2 [M] Missing unit test coverage across font/text modules
- `font.d:214-235`: `fromFile`, `scale()`, metrics, `measureText`.
- `font_manager.d:353-465`: `scaledCache` overflow eviction (`maxScaledFonts`),
  `hasFont`, `quantizeScaleEighths` 1024 px cap.
- `internal/glyph_atlas.d:298-579`: glyphs with `initialSize < dim <= maxSize`;
  wrap FBO restore/delete in `readAtlas` (`:271-288`) with `scope(exit)`.
- `internal/text_batch.d:168-249`: `beginRun`, `appendQuad`, `remaining`, `flush`.
- `internal/text_cache.d:517-911`: `resolveSlots` mid-run growth & thrash,
  `fQuads` growth (>64 glyphs), `growGlyphPool`, `onBeforeAtlasReset`, UTF-8.

### 6.3 [L] Minor test hygiene & edge-case gaps
- `package.d:2182, 2352`: raw `glDeleteTextures` leaks `memstats` telemetry;
  use `deleteTexture()`.
- Missing edge-case tests for huge `createRenderTarget`/`resizeRenderTarget`
  dims, `NaN` dashes/rects, and `Renderer.viewport()` with active clip rect.

---

## Prioritized Action List

- **High**
  1. Zero-initialize `allocRgbaTexture()` (`internal/gl_util.d:556-577`).
  2. Check `malloc` return in `uploadAndDrawIndexedQuads()`
     (`internal/gl_util.d:261-277`).
  3. Widen `RunGlyph.dx`/`dy` to `int` (`internal/text_cache.d:23-34`).
  4. Add `!inTarget()` guard and `clipStack.reapply` to `Renderer.viewport()`,
     and clamp/validate `RenderTarget` pixel dimensions against GL limits
     (`package.d`, `render_target.d`).
- **Medium**
  5. Retain `fMemoryData` in `Font.fromMemory` (`font.d`), fix `makeRoom()`
     multi-doubling (`glyph_atlas.d`), and fix `resolveSlots` growth retries
     (`text_cache.d`).
  6. Remove `glGetIntegerv` in `attachAndCheck()` (`internal/offscreen.d`),
     cache `GL_MAX_SAMPLES`, and eliminate triple GL restore in `endTarget()`.
  7. Fix `NaN`/infinite-loop guards in `pipelines.d`, `fNoStaleEntries` in
     `text_cache.d`, and tautological atlas assertion in `package.d:2378`.
- **Low**
  8. Split `render/package.d` tests into `render/package_test.d` and clean up
     duplication/style nits.
