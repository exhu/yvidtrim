# Canvas and Renderer review

```
  date    2026-11-23
  branch  main
  commit  69bbc2870eab600e87ddef786144f14977eb39a4 (shadow blur demo)
```

Line numbers below refer to that commit.

Scope: `yguilib/source/yguilib/render/` (Renderer, Font, FontManager,
Texture, RenderTarget, Image, types) and `render/canvas/` (Canvas, Path2d,
types), plus `render/internal/` (pipelines, gl_util, stencil_ops,
clip_stack, offscreen, path_flatten, path_stroker, text_cache).

Paths below are relative to `yguilib/source/yguilib/render/`.
Severity: **H** high, **M** medium, **L** low.

```
  Summary
  -------
  per-frame GC churn ..... 8 findings (2 H)
  possible bugs .......... 10 findings (2 H)
  optimizations .......... 9 findings
  code reuse ............. 11 findings
  codestyle .............. 10 groups
```

---

## 1. Memory allocations (per call / per frame)

The Canvas already keeps reusable `Appender` buffers (`fContours`,
`fLocalTris`, `fVerts`, `fShadowVerts`, `fImageVerts`). The hot spots
below sit outside that scheme.

### 1.1 [H] TextCache allocates a DList node on every cache hit
`internal/text_cache.d:90-95`

```d
accessOrder.popFirstOf(p.orderRef);
accessOrder.insertFront(key);      // new GC node every hit
p.orderRef = accessOrder[];
```

Every `drawTextWithFont` / `fillText` of an already cached string
allocates one list node, so every visible label allocates every frame.
Old nodes become garbage, and the GC has to collect them regularly.

Fix options (recommended first):
- Store a `ulong lastUse` tick in `TextCacheEntry` and increment a counter
  on each hit. Eviction is rare, so it can scan the AA (512 entries) or
  partially sort it. No allocation on a hit.
- Use an intrusive index-based LRU list: entries live in an array with
  `prev`/`next` indices and a free list, and the AA maps key to index.

### 1.2 [H] Stroker builds a GC array literal for every triangle
`internal/path_stroker.d:425-427`

```d
void tri(PointF a, PointF b, PointF c) nothrow @safe {
  tris.put([a.x, a.y, b.x, b.y, c.x, c.y]);   // dynamic array literal
}
```

A dynamic array literal passed to `Appender.put` is a GC allocation.
LDC's GC2Stack pass may remove it in optimized builds, but nothing
guarantees that, and debug builds always allocate. A round join/cap fan
makes up to 256 triangles, so one stroke can mean hundreds of
allocations. Use a static array, as `Canvas.buildFan` already does:

```d
const float[6] v = [a.x, a.y, b.x, b.y, c.x, c.y];
tris.put(v[]);
```

Suggest making `Stroker`/`strokeContours` `@nogc`-checked (apart from
`Appender` growth) or checking the module with `-vgc` to catch this
class of issue.

### 1.3 [M] `applyDash` returns a fresh `Contours` for every dashed stroke
`internal/path_stroker.d:47, 62-77`

Each dashed `stroke()` allocates two new `Appender`s and grows them from
zero. Pass a reusable `ref Contours` scratch owned by `Canvas` (as
`fContours` is), e.g. `applyDashInto(c, dash, offset, ref dst)`.

### 1.4 [M] Dashed thick lines allocate an Appender per call
`internal/pipelines.d:248-251` (`ColorPipeline.drawDashedThickLine`)

`Renderer.drawLineDashed` is a widget-level primitive (focus rects,
separators). Keep an `Appender!(float[])` scratch field in
`ColorPipeline` and `clear()` it per call.

### 1.5 [M] `Path2d.clear()` throws away capacity
`canvas/path2d.d:291-298`

```d
fVerbs = null;
fPoints = null;
```

`Canvas.clearRect` reuses `fRectPath` precisely to avoid allocation, but
`clear()` drops the buffers, so every call reallocates (three times as
the arrays grow). The same happens for users who keep a `Path2d` and
rebuild it each frame. Use `Appender` for `fVerbs`/`fPoints` (as
`Contours` does), or `length = 0` + `assumeSafeAppend` (in a `@trusted`
helper, because `assumeSafeAppend` is `@system`). `addPath` should also
`reserve` before its element-by-element `~=` loops (`path2d.d:278-283`).

### 1.6 [M] `clip()` and `save()` allocate
`canvas/package.d:299-303, 352-358`

- `save()` does `st.clips.dup`. Clips are append-only and a saved state
  is always a prefix of the current one, so a single
  `Appender!(ClipEntry[]) fClips` plus a `size_t clipCount` in `State`
  is enough. `restore()` then only compares counts and shrinks.
- `clip()` deep-copies the path with `new Path2d()` + `addPath`, which
  is 1 object + 2-3 array allocations per clip. Keep a pool of
  `Path2d` objects indexed by clip depth (reused after `restore()`), or
  store the flattened, transformed fan triangles of each clip in a shared
  float buffer. That also makes `rebuildClip()` cheaper, because it
  would not flatten again.

`WidgetPainter.drawCustom` (`widget/internal/widget_painter.d:126`) calls
`save()`/`restore()` once per custom-drawn widget per frame. With an
active clip, that allocates once per widget.

### 1.7 [L] `lineDash` setter and getter both allocate
`canvas/package.d:136-142`, `canvas/types.d:154-168`

`lineDash()` (the getter) builds a new normalized copy on every call.
Because gradients already use a fixed-capacity `GradientStops`, a
`LineDash` with a fixed capacity (e.g. 16 segments + count) would make
dash state `@nogc` and copy-cheap.

### 1.8 [L] Render target passes copy the Canvas stack
`canvas/package.d:506-511`, `package.d:803-809`

`saveFrameState` does `fStack[].dup` per `beginTarget`, and a fresh
`ClipStack.init` re-grows its `Appender` per target. This is acceptable
for occasional targets. If targets are used per widget per frame (cached
widget layers), keep a per-depth pool of `FrameState` buffers in
`Renderer`.

### 1.9 [L] `State` is about 1 KB, copied on every save/restore
`canvas/types.d:354-399`

`FillStyle` holds a `LinearGradient`, a `RadialGradient` (about 180 B
each, with 8 stops) and a `Pattern` all at once, and `State` has two
`FillStyle`s. Making `FillStyle` a tagged union (`kind` + `union { ColorF;
LinearGradient; RadialGradient; Pattern; }`) roughly halves `State`. It
also shrinks every `fillStyle()` getter return and every `save()` copy.

---

## 2. Possible bugs

### 2.1 [H] Finalizers call SDL_ttf / GL
`package.d:70-72` (`Renderer.~this`), `font.d:86-88` (`Font.~this`),
`font_manager.d:45-47`, `internal/text_cache.d:54-56`

`texture.d:16-20` and `render_target.d:23-26` set the rule that GPU and
native objects are freed only by explicit `destroy()` on the main thread,
because the GC may finalize on any thread or after the context or
`TTF_Quit()` is gone. Four classes break that rule:
- `TextCache.~this` → `glDeleteTextures` without a current context.
- `Font.~this` → `TTF_CloseFont`, possibly after `TTF_Quit`.
- `FontManager.~this` / `Renderer.~this` walk AAs and other GC objects
  that may already have been finalized in the same collection.

Recommendation: remove these destructors (or have them only
`assert`/log a leak in debug builds) and rely on `Window.destroy()` →
`Renderer.destroy()`.

### 2.2 [H] FontManager serves stale fonts after (re)registration
`font_manager.d:74-98, 142-176`

`getFont("Foo", ...)` for an unregistered name falls back to the default
face, but caches the result under key `"Foo"`. A later
`registerFontFromMemory("Foo", data)` does not invalidate `cache` or
`scaledCache`, so `"Foo"` keeps rendering with the default face.
Re-registering a name with new data has the same effect. Fix: in both
`register*` methods, drop (and `destroy()`) cache entries whose
`faceName` matches. Do not cache unresolved fallbacks under the
requested name (cache them under `""`).

### 2.3 [M] Unbounded blur kernel
`assets/yguilib/shaders/blur.frag.glsl` (`radius = ceil(3 * sigma)`),
`canvas/package.d:169-175, 853-855`

`Shadow.blur` has no upper bound. `blur = 200` at 2x scaling gives
sigma = 200 px, which is 300 loop iterations x 2 taps per pixel per pass
over a box padded by 600 px. That can stall or reset the GPU (TDR).
Clamp sigma (e.g. 64 px). For larger blurs, downsample the mask (blur at
1/2 or 1/4 resolution and upscale with linear filtering).

### 2.4 [M] Destroyed scaled fonts leave textures in TextCache
`font_manager.d:203-210`

When `scaledCache` reaches 64 entries, all scaled fonts are destroyed.
Their `TextCache` textures (keyed by the dead font ids) stay on the GPU
until LRU eviction pushes them out. Either evict per font (LRU) instead
of flushing everything, or have the manager notify the cache (e.g.
`TextCache.removeFont(id)`).

### 2.5 [M] TextCache thrashes once a frame has more than 512 strings
`internal/text_cache.d:98-100, 160-175`

When a frame draws more distinct strings than `maxEntries`, eviction
drops 25 % of the entries, including ones drawn earlier in the same
frame. Each later frame then re-rasterizes and re-uploads them through
SDL_ttf. Consider a per-frame "in use" mark (don't evict entries touched
in the current frame) or a byte budget instead of an entry count. A
glyph atlas is the long-term fix (see 3.7).

### 2.6 [L] The nonZero winding wraps at 128
`internal/stencil_ops.d:21-29`

Winding uses `INCR_WRAP`/`DECR_WRAP` on the 7 low bits. A pixel whose
winding is a multiple of 128 counts as outside. This is unlikely in UI
code, but should be documented in the module header next to the bit
layout.

### 2.7 [L] `arcTo` without a current point adds an extra `lineTo`
`canvas/path2d.d:121-134`

With no subpath, `ensureSubpath(p1)` emits `moveTo(p1)`, then
`l1 == 0` emits `lineTo(p1)`. HTML only does the `moveTo`. This is
harmless for fills, but a stroke with round/square caps draws a dot,
which differs from the spec.

### 2.8 [L] Text alignment width differs from `measureText`
`canvas/package.d:1137-1146` vs `419-437`

`fillText` aligns with the bitmap width (`tex.width - 2*op`) at the
quantized raster scale, while `measureText` returns the TTF advance at
`totalScaling()`. With `textAlign = end/center`, or under a scaling
transform, the drawn text can be offset by a pixel or two from what
`measureText` predicts. Use the advance width at the same raster scale
for both, e.g. `f.measureText(text).x / q`.

### 2.9 [L] `OffscreenTarget.ensureSize` ignores failure and size limits
`internal/offscreen.d:26-43`

The return value of `attachAndCheck` is discarded, and the size is not
checked against `GL_MAX_TEXTURE_SIZE` / `GL_MAX_RENDERBUFFER_SIZE`. An
incomplete FBO then makes shadows silently draw garbage or nothing.
Return a `bool`, and have `beginShadowPass` skip the shadow on failure.

### 2.10 [L] API pitfalls worth a comment or change
- `RectF.init` is 1 x 1 (`render_types.d:8-12`), not empty, so
  `RectF r;` is a visible unit rect. `Path2d.bounds()` already works
  around it with an explicit `RectF(0, 0, 0, 0)`.
- `onScalingChanged` (`package.d:1130-1141`) silently drops a
  user-assigned (non-owned) default font with `defaultFont(null)`. Either
  document it or re-create it at the new scale.
- `onScalingChanged` does not re-apply the clip stack scissor. Its
  rects are in logic units, so after a mid-frame scaling change the
  scissor box is stale until the next push/pop.

---

## 3. Optimizations

### 3.1 [M] One `glBufferData` + VAO bind/unbind per draw
`internal/gl_util.d:107-125`

Every primitive re-specifies its VBO (`glBufferData`, which can mean a
driver allocation), then unbinds the VAO and buffer. A Canvas fill is
3+ draws (winding, cover, sometimes reset). Options, cheapest first:
- Keep a per-pipeline capacity and use `glBufferSubData` when the data
  fits, growing only when needed (or orphan with `glBufferData(null)`
  once per frame).
- Drop the `glBindVertexArray(0)` / `glBindBuffer(0)` after each draw.
  The next draw binds its own VAO anyway.
- Longer term: one streaming VBO ring shared by all pipelines.

### 3.2 [M] Redundant program and uniform updates
Every draw calls `glUseProgram` and re-uploads `uResolution`, plus all
gradient uniforms (`GradientLocs.set` uploads 8 stops every time).
Cache the current program and the last `(vw, vh)` per program in
`Renderer`, and re-upload only on change (invalidate on viewport or
target switch).

### 3.3 [M] Fast path for convex single-contour fills
`canvas/package.d:758-797`

Rects, round rects and circles without a clip go through stencil
winding, cover and endStencil, which is 2 draws and about 12 state
changes. A single closed contour that is convex (cheap to test while
flattening) can be drawn directly as its fan. `clearRect` without a
transform is just a scissored `glClear`.

### 3.4 [L] `SavedTargetState.capture()` queries GL state
`internal/offscreen.d:91-99`, `render_target.d:178-182`

Each shadow pass and each MSAA resolve performs 5-7 `glGet*` calls.
These can force a sync on some GLES drivers. `Renderer` already knows
the viewport, scissor and bound FBO (it sets them all), so track this
state in `Renderer` and pass it down.

### 3.5 [L] Shadow box ignores the scissor and Canvas clip
`canvas/package.d:882-905`

The box is limited to the viewport only. Intersecting it with the active
scissor rect (known from `ClipStack`) avoids blurring pixels that the
composite discards anyway (scrolled-out content).

### 3.6 [L] Extra copy in `stroke()`
`canvas/package.d:210-212`

`fLocalTris` → `transformVerts` → `fVerts`. Transform in place in
`fLocalTris` and pass it on, or swap the buffers, to save one full copy
of the stroke geometry.

### 3.7 [L] Text: one texture per string
`internal/text_cache.d:115-157`

Each distinct string is its own GL texture and its own draw, with a
texture bind per label. For many small labels a glyph atlas (cache
glyphs, draw quads in one batch) cuts texture count and draw calls. This
is a larger change for later. For now, 1.1 and 2.5 are the cheap fixes.

### 3.8 [L] Double font lookup in `measureText`
`canvas/package.d:425-429`

`measureTextWithFontName` and `font(...)` each perform the AA lookup.
Resolve the `Font` once and call `f.measureText`.

### 3.9 [L] `isActiveTargetTexture` walks the target stack per draw
`package.d:1027-1037`

This is cheap with shallow stacks and appears only in `assert`s and the
pattern path. It could be wrapped in `debug`/`version (assert)` where it
is used only in asserts.

---

## 4. Code reuse

1. **Pattern uniform setup is repeated 3 times** (`canvas/package.d:736-749,
   989-1001, 1077-1090`), and the feedback-loop assert 4 times. Extract
   `PatternUniforms patternUniformsFor(in FillStyle s, in Transform2d
   extra, TextureMode mode)` together with the assert. Do the same for
   `TextureMode` selection from `premultiplied()` (also in
   `package.d:682` and `canvas/package.d:288`).
2. **PatternPipeline duplicates uniform locations** for `program` and
   `maskProgram` (`pipelines.d:848-893, 937-945, 991-998`). Mirror
   `GradientLocs`: a `PatternLocs.query()` / `set()` struct.
3. **Program + VAO + VBO trio** is repeated in every pipeline, and
   `TexturePipeline.initialize` / `RoundRectPipeline.initialize`
   hand-roll `buildProgram` (`pipelines.d:311-318, 578-585`). Add
   `struct ProgramMesh { GLuint program, vao, vbo; void destroy(); }`
   and use `buildProgram` everywhere.
4. **Determinant / invertibility** is computed in 3 places:
   `Canvas.isInvertible`, `Transform2d.inverse`, `drawFilledText`
   (`canvas/package.d:611-616, 1114-1117`, `canvas/types.d:68-71`). Add
   `Transform2d.determinant()` and `isInvertible()`.
5. **Finite checks**: `Canvas.finitePoint`, `Canvas.rectDrawable`,
   `Path2d.finite`, `Path2d.finiteRect` can share helpers in
   `render_types.d` (`isFinitePoint`, `isFiniteRect`).
6. **Rect to two triangles** exists as `Canvas.quadFromRect`, the inline
   arrays in `ColorPipeline.drawFillRect`, and `quadVertices` (xyuv). Keep
   one vec2 helper next to `quadVertices` in `pipelines.d`.
7. **Bounds of points**: `Canvas.boundsOfVerts` and `Path2d.bounds` use
   the same min/max loop.
8. **Dash period** is summed in `LineDash.period`, `isDashed`,
   `tooManyDashes` and the `DashPattern` constructor. `LineDash` is
   already normalized (even length, validated), so the stroker can
   take `LineDash` and use `period()`/`isSolid()`.
9. **FontManager**: `getFont` and `getFontAtScale` duplicate size
   sanitizing, face resolution and `fromMemory`/`fromFile` dispatch
   (`font_manager.d:136-176, 191-230`). Extract `resolveSource(face)` and
   `openFont(source, size, scale)`.
10. **Renderer draw wrappers** repeat
    `if (!initialized) return; pipeline.x(..., logicWidth(), logicHeight())`.
    A private `Viewport vp()` returning `{vw, vh, scale}` would shorten
    them and would also serve as the parameter struct from 5.4.
11. **Unit test helpers** (`px`, `isRgb`, `near`, `rectPath`, `bounds`,
    window setup) are copied into 8 GL unittest blocks in
    `canvas/package.d` and several in `package.d`. Move them into a
    `version (unittest)` module (e.g. `internal/gl_test_util.d`) with a
    `GlTestWindow` fixture that also carries the `scope(exit)` target
    cleanup required by AGENTS.md. Moving the 1580 lines of Canvas tests
    to `canvas/package_test.d` (or similar) would also make
    `canvas/package.d` (2939 lines) easier to review.

Unused code:
- `Renderer.createTextTexture` (`package.d:1058-1063`): private, no caller.
- `ColorPipeline.drawLineWithWidth`, `drawRectDefaultWidth`
  (`pipelines.d:104-115, 201-208`): no caller.
- `TexturePipeline.drawTexture` has one caller and could be inlined.

---

## 5. Codestyle (`codestyle.md`) violations

1. **Default parameter values** (forbidden):
   - `canvas/package.d:1102` `drawFilledText(..., bool stroke = false)`.
     Split it into `drawTextBitmap(text, pos, maxWidth, outlinePx)`,
     because the name "Filled" is also misleading for the stroke path.
   - `package.d:958` `textTextureFor(..., int outlinePx = 0)`.
   - `internal/text_cache.d:62, 81, 116` `outlinePx = 0`.
   - test helper `canvas/package.d:2507` `int ch = 0`.
2. **Trailing-underscore fields** (must use the `f` prefix):
   `font.d` `id_`; `texture.d` `id_`, `width_`, `height_`,
   `premultiplied_`, `bottomUp_`, `borrowed_`; `render_target.d`
   `pixelWidth_`, `pixelHeight_`, `samples_`, `tex_`; `image.d`
   `width_`, `height_`; parameter `align_` in `canvas/types.d:516`.
3. **get/set naming**: `FontManager.getFont`, `getFontAtScale`,
   `setScaling`; `Font.setScale`; `TextCache.getOrCreate` (e.g.
   `fontWithSize`, `fontAtScale`, `scaling(float)`, `textureFor`).
4. **More than 5 parameters without a parameter struct**:
   `RoundRectPipeline.draw` (9), `ColorPipeline.drawDashedThickLine`
   (11), `drawDashedLineWithPoints` (8), `drawSolidThickLine` (7),
   `drawTexturedTriangles*` (6), `ClipStack.push` (6),
   `Renderer.drawLineDashed` (6), `drawRoundRectDashed` (6),
   `Path2d.ellipse` (6, mirrors HTML, so it may be acceptable). A shared
   `Viewport { float vw, vh, scale; }` struct removes 2-3 parameters from
   all pipeline calls.
5. **`out` parameters**: test helper `lit(int c, out int x0, out int x1)`
   (`canvas/package.d:2844`). Return a struct.
6. **Per-declaration visibility** instead of section labels:
   `font.d:7-8, 102, 176, 184`; `internal/clip_stack.d:121`;
   `internal/text_cache.d:159` (`private:` mis-indented inside the
   class).
7. **Const by default**: many non-const locals that never change, e.g.
   `pipelines.d:72-75, 167-177, 615-632`, `clip_stack.d:94-102`,
   `render_types.d:47-52`, `package.d:85, 100, 1131`, `font.d:43, 74,
   133-134`.
8. **Function size over 50 lines**: `Canvas.drawFilledText` (about 68
   lines), `dashContour` (about 55). Split into anchor/metrics
   computation and the draw.
9. **Imports**: `TextureMode` is re-imported in function scope although
   the module imports it (`canvas/package.d:275, 1017, 1105, 1200`);
   `GL_TRIANGLES` is imported but unused in `Canvas.stroke`
   (`canvas/package.d:188`).
10. **Docs**: no module doc comment in `package.d`, `colors.d`,
    `render_types.d`, `font.d`, `font_manager.d`, `internal/pipelines.d`,
    `internal/gl_util.d`, `internal/clip_stack.d`,
    `internal/text_cache.d`. The class-level comment at
    `canvas/package.d:49-50` uses `//` at column 0 inside the class.
    `package.d` mixes `@param` (Doxygen) with `Params:` (DDoc). Pick
    DDoc.

No lines over 80 columns and no tabs were found.

---

## 6. Suggested order of work

```
  step  items                         effort  gain
  ----  ----------------------------  ------  -----------------------
  1     2.1 finalizers                S       crash safety
  2     2.2 font cache invalidation   S       correctness
  3     1.1 TextCache LRU, 1.2 tri()  S       per-frame GC churn gone
  4     1.3-1.6 scratch buffers       M       Canvas @nogc-ish path
  5     2.3 blur clamp, 2.9           S       GPU safety
  6     3.1, 3.2 GL state caching     M       fewer driver calls
  7     4.x reuse + 5.x style         M       maintainability
  8     4.11 test helper module       M       smaller canvas/package.d
  9     3.3, 3.7 fast paths / atlas   L       throughput
```
