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
  ph03   done         see notes below
  ph04   not started
  ph05   not started
  ph06   not started
  ph07   not started
  ph08   not started
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
