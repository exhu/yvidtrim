# Canvas / Renderer refactoring

Source: `documentation/canvas-render-review.md` (commit 69bbc28). Review
item numbers (1.1, 2.3, ...) refer to that document. Its line numbers
refer to 69bbc28 and drift as phases land, so re-grep before editing.

Paths are relative to `yguilib/source/yguilib/render/` unless noted.

## Decisions

- Do not use `yguilib/allochelpers.d`. Its containers cannot be copied,
  and the Canvas `State`/`FrameState` structs are copied. Fix
  allocations with `std.array.Appender` (`clear()`, `shrinkTo()`),
  fixed-capacity structs (like `GradientStops`) and buffer swapping.
- Scope: review sections 1, 2, 4 and 5, plus 3.1-3.6, 3.8 and 3.9.
  3.7 (glyph atlas) is deferred to TODO.md.
- Canvas tests move to `canvas/package_test.d`, and shared GL test
  helpers go in `internal/gl_test_util.d`.

## Phases

```
  phase  file                            items
  -----  ------------------------------  ------------------------------
  ph01   canvas-render-refactor-ph01.md  4.11, 5.5, test 5.1
  ph02   canvas-render-refactor-ph02.md  2.1, 2.2, 2.4, 4.9
  ph03   canvas-render-refactor-ph03.md  1.1, 2.5, 1.2
  ph04   canvas-render-refactor-ph04.md  1.3, 1.4, 1.5, 1.7, 3.6, 4.8
  ph05   canvas-render-refactor-ph05.md  1.6, 1.8, 1.9
  ph06   canvas-render-refactor-ph06.md  2.3, 2.6-2.10
  ph07   canvas-render-refactor-ph07.md  3.1, 3.2, 3.4, 3.5, 3.9
  ph08   canvas-render-refactor-ph08.md  3.3, 3.8, 4.1-4.7, 4.10
  ph09   canvas-render-refactor-ph09.md  5.1-5.4, 5.6-5.10, docs
```

Phases run one after another, because they touch the same files.

## Status

```
  phase  status       notes
  -----  -----------  ---------------------------------------------
  ph01   done         committed 1696c79; see notes below
  ph02   done         committed 6b04e76; see notes below
  ph03   done         committed b5b2f74; see notes below
  ph04   done         committed 7572814; see notes below
  ph05   done         committed 507922a; see notes below
  ph06   done         committed fb3ece8; see notes below
  ph07   done         committed 279f05f; see notes below
  ph08   done         see notes below
  ph09   not started
```

ph01 notes (2026-11-23):
- New `internal/gl_test_util.d`. It holds the `GlTestWindow` fixture
  (320 x 240; teardown order is in its doc comment) and the shared
  helpers (`px`, `readAt`, `nearPixel`, `near`, `isRgb`, `rectPath`,
  `bounds`, `frameBounds`, `grabFrame`, `channelAt`, `litSpan`).
- New `canvas/package_test.d` holds the 9 Canvas unittest blocks.
  `canvas/package.d` went from 2939 to 1356 lines. The 5 blocks in
  `package.d` stay there and now use the fixture.
- `LitSpan` has a `count` field as well as `x0`/`x1`, because the
  strokeText test asserts on the count.
- The test runner counts modules, not unittest blocks: "65 modules
  passed unittests" before and after. Use
  `./_build/yguilib/yguilib_test` to check the count.
- Canvas tests can only use public or `package(yguilib)` API now.

ph02 notes (2026-11-23):
- 2.1: no `~this()` in `Renderer`, `Font`, `FontManager`, `TextCache`.
  `Renderer.destroy()` doc comment states the teardown order.
- 2.2: unregistered names resolve to the default face and are cached
  under face key `""`. `register*` calls private `dropFace(name)`.
- 2.4: `TextCache.removeFont(fontId)`; `FontManager.onFontDestroyed(dg)`
  setter, wired in `Renderer.initialize()`. The delegate is not
  `nothrow` (glad `glDeleteTextures` is not).
- 4.9: shared helpers `resolveSource`, `openFont`, `sanitizeSize`,
  `sizeMilliOf` in `font_manager.d`.
- Test-only helpers: `TextCache.countForFont`,
  `FontManager.countForFace`, `FontManager.scaledCount`.
- For ph03: `removeFont` uses `accessOrder.popFirstOf(p.orderRef)`;
  update it when the DList is replaced (1.1).
- Fonts made by `Renderer.createFontFrom*` (or a user default font)
  are not reported by the callback; their textures stay until LRU
  eviction or `clearTextCache`.
- Still 65 modules; meson test 10/10 OK.

ph03 notes (2026-11-23):
- 1.1: `TextCache` LRU uses a `lastUse` tick per entry (no DList). Hits
  and inserts do not allocate. Eviction sorts candidates in a reused
  `Appender!(EvictCandidate[]) fEvictScratch`; `removeFont` uses it too.
- 2.5: `TextCache.beginFrame()`, called by `Renderer.clearFrame` when
  not in a target. Entries used this frame are never evicted; the
  cache may grow up to `2 * maxEntries` (hard cap, then all entries are
  candidates). Direct `TextCache` users must call `beginFrame()`.
- 1.2: stroker `tri()` puts a `float[6]` static array; `-vgc` is clean
  for `path_stroker.d` and `path_flatten.d`.
- 5.1 (part): `outlinePx` default removed from `TextCache.contains`,
  `getOrCreate`, `createTextTexture` and `Renderer.textTextureFor`.
- The new stroker GC test may not have failed on the old code (LDC
  -O2 may elide the literal); it guards regressions.
- Still 65 modules; meson test 10/10 OK.

ph04 notes (2026-11-23):
- 1.7/4.8: `LineDash` stores up to `maxSegments = 32` segments inline
  (private `fSegs`, `fCount`, `fPeriod`); build it only via
  `fromSegments` (or `.init` for solid). More than 32 segments after
  odd doubling gives a solid dash (documented HTML deviation). Stroker
  uses `period()` instead of re-summing. `State.dash` is ~140 bytes
  inline; keep in mind for 1.9 (ph05).
- 1.3: `applyDashInto(c, dash, offset, ref dst)`. `strokeContours`
  takes an explicit `ref Contours dashScratch`; Canvas owns
  `fDashContours`.
- 1.4: `ColorPipeline.fDashScratch` Appender reused per call.
- 1.5: `Path2d` uses Appenders; `clear()` keeps capacity; `addPath`
  reserves first and is safe for `addPath(this)`.
- 3.6: `stroke()` strokes straight into `fVerts` and transforms in
  place (`transformInPlace`, skips identity). `fLocalTris` and
  `transformVerts` are gone.
- Still 65 modules; meson test 10/10 OK.

ph05 notes (2026-11-23):
- 1.6: `State.clipCount`; Canvas owns `fClips` (ClipEntry with
  `triStart`/`triCount`/`rule`) and `fClipTris`. Append-only between
  `save`/`restore`; `restore()` shrinks both and replays stored
  triangles (no re-flatten). Clips keep the tolerance they were made
  with. New `appendFan(xf, ref dst)`.
- 1.8: `Canvas.FrameState` and `Renderer.targetFrames` (per-depth pool,
  `fTargetDepth`) swap buffers instead of copying. Debug asserts check
  no shared storage (`ClipStack.sharesStorage`). Never copy a
  `TargetFrame`/`FrameState` that holds buffers.
- 1.9: `FillStyle` is a tagged union with read-only `kind()`.
  Deviation: `Pattern` is inside the union (outside, `State` missed
  the size target); `pattern()`/`fromPattern` are `@trusted` and
  assert the kind. `State` is ~680 bytes (was 1176), checked by a
  `static assert`.
- Still 65 modules; meson test 10/10 OK.

ph06 notes (2026-11-23):
- 2.3: `Shadow.maxBlurSigmaPx = 64`; `shadowBlurFromSigmaPx` picks
  full res (sigma <= 32), 1/2 (<= 64) or clamp + 1/4. Mask is drawn,
  blurred and composited at `totalScaling / downsample`; composite
  uses linear filtering with a half-texel inset. `ShadowPass.scale`
  now means mask pixels per logic unit (use it in 3.5, ph07).
  Downsampled masks have no AA; thin shapes may shimmer at sigma > 32.
- 2.9: `OffscreenTarget.ensureSize` returns `bool`, checks cached
  `maxSize()`, frees objects on FBO failure. `beginShadowPass` sizes
  both targets first and skips the shadow on failure.
- 2.6 documented; 2.7 `arcTo` without a current point only moves;
  2.8 text align uses `measureText` width.
- 2.10: `RectF.init` doc; `onScalingChanged` rescales a user default
  font in place (`setScale`; source data is not kept) and re-applies
  the scissor only when `ClipStack` is not empty (`isEmpty()`).
- Follow-ups: `measureText` ignores the transform (drawn advance at
  1.5x differs by ~3.5 px); `fOwnsDefaultFont` is never set (dead).
- Still 65 modules; meson test 10/10 OK.

ph07 notes (2026-11-23):
- 3.1: `VertexArrayHandles.capacity` (bytes);
  `uploadAndDrawDynamic(mode, va, vertices, count)` uses
  `glBufferSubData`, grows to the next power of two (min 256). No
  VAO/VBO unbind after draws. Pipeline fields renamed `vao`/`vbo` ->
  `va` (and `maskVa`).
- 3.2: `ProgramTracker` (`use`, `invalidate`, `epoch`) owned by
  `Renderer.fPrograms`; pipelines get a pointer in `initialize`.
  `Vec2UniformCache` for `uResolution`; `GradientLocs.set` skips
  unchanged stops. Invalidation bumps the epoch (viewport, targets,
  scaling).
- 3.4: Renderer tracks FBO, viewport, clear color; scissor comes from
  `ClipStack` (`appliedBox()`, `top()`). `targetState()` builds
  `SavedTargetState` without GL queries (debug assert vs
  `capture()`). New `package(yguilib)` `Renderer.clearColor(ColorF)`,
  used by `Window.clearWithColor`. `RenderTarget.resolve` takes the
  state as parameters.
- 3.5: `shadowBox` limits by `scissorLogicRect()` padded by the blur
  pad; empty area skips the pass. The Canvas stencil clip is not used.
- 3.9: `isActiveTargetTexture` and its asserts are in `version
  (assert)`.
- Rule for new GL code: use `fPrograms.use()`, the tracked
  FBO/viewport/clear-color setters and `ClipStack`; never touch a
  pipeline VBO directly. Otherwise the `targetState()` assert fires.
- Module count is now 66 (new unittest in `gl_util.d`); meson test
  10/10 OK.

ph08 notes (2026-11-23):
- 3.3: `isSingleConvex(contours)` in `path_flatten.d` (rejects spikes
  and the pentagram). `fillWithRule` draws a single convex contour
  directly when blending without a Canvas clip. `clearRect` with an
  axis-aligned transform and no Canvas clip uses
  `Renderer.clearPixelBox` -> `ClipStack.clearBox` (pixel-center rule;
  non-AA at fractional edges on the multisampled window - document in
  ph09). Rotation/skew/clip fall back to the stencil path. Relies on
  every Canvas call ending with `endStencil()`.
- 3.8: `measureText` looks up the font once.
- 4.1-4.3: `patternUniformsFor`, `textureModeFor`, `PatternLocs`,
  `ProgramMesh` (`mesh`/`maskMesh` replace `program`/`va` fields;
  `uniform(name)` needs a NUL-terminated literal).
- 4.4-4.7: `Transform2d.determinant()`/`isInvertible()`;
  `isFinitePoint`/`isFiniteRect`, `boundsOfPoints`/`boundsOfXy` in
  `render_types.d`; `rectTriangles(RectF)` replaces `quadFromRect`.
- 4.10: `struct Viewport` and `Renderer.vp()`; pipeline signatures
  unchanged (ph09 can switch them).
- Removed unused `Renderer.createTextTexture`,
  `ColorPipeline.drawLineWithWidth`, `drawRectDefaultWidth`;
  `TexturePipeline.drawTexture` inlined.
- Test-only `Canvas.PathStats`/`pathStats()`.
- Still 66 modules; meson test 10/10 OK.

## Rules for every phase

- Follow AGENTS.md and `codestyle.md` (2-space indent, max 80 columns,
  `f`-prefixed private fields, no default parameters, const locals).
- Keep existing docstrings and comments.
- Verify with `ninja -C _build && timeout 300 meson test -C _build`.
  Never tee the test output into a log file. The number of tests must
  not drop.
- Allocation tests: use `core.memory.GC.stats()` around a warmed-up loop
  and assert that `usedSize + freeSize` does not grow (or that
  `allocatedInCurrentThread` stays put, where it is available).
- GL tests use the `GlTestWindow` fixture from ph01.

## Final tasks (end of ph09)

- Update ARCHITECTURE.md for new modules and data flow (under 250
  lines).
- TODO.md: replace "human review of canvas and renderer implementation"
  with "glyph atlas for text (canvas-render-review 3.7)".
- Move `plans/canvas-render-refactor*.md` to `plans/archive/`.
