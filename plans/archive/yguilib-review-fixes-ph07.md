# ph07: `render` Font, `GlyphAtlas`, `TextBatch` & `TextRunCache`

Overview: `plans/yguilib-review-fixes.md`.
Review: `documentation/yguilib-review-report-render.md` (commit `7a96feaa`).
Paths below are relative to `yguilib/source/yguilib/render/`.

Goal: Address all font, glyph atlas, and text cache/batch findings in
`render/` (`1.5`-`1.12`, `1.18`, `2.6`-`2.8`, `3.2`, `4.1`, `5.1`, `6.2`).

## Files

- `font.d`, `font_manager.d`
- `internal/glyph_atlas.d`, `internal/text_batch.d`, `internal/text_cache.d`

## Steps

1. **`Font` (`1.6`, `1.7`, `3.2`, `5.1`, `6.2`)**:
   - Store `private const(void)[] fMemoryData;` in `Font.fromMemory` and
     clear in `destroy()` (document lifetime for non-GC buffers) (`1.6`).
   - Guard `isFinite(ptSize) && ptSize > 0.0f` and `isFinite(scale) &&
     scale > 0.0f` (`1.7`).
   - Document pixel-space units on metric methods and make `handle` a
     read-only `package(yguilib)` accessor (`3.2`).
   - Scope test-only `defaultTtfFontData` import, fix `(defaults to 1.0f)`
     docstrings, include `lastError()` in throws (`5.1`).
   - Add tests for `fromFile`, `scale()`, metrics, and `measureText` (`6.2`).
2. **`FontManager` (`1.8`, `1.9`, `2.7`, `2.8`, `3.2`, `5.1`, `6.2`)**:
   - Reject `"default"` (`assert(fontName != "default")`) or normalize
     `"default"` -> `""` (`1.8`).
   - Clamp `ptSize <= 4096.0f` in `sanitizeSize` (`1.9`).
   - Replace 64-font burst flush in `destroyScaledFonts()` with oldest-subset
     eviction or batch font-destruction hook (`2.7`); bound unscaled `cache`
     (`2.8`).
   - Move `quantizeScaleEighths` to `private:` (`3.2`); remove redundant
     per-declaration `package(yguilib)` inside `package(yguilib):` class
     (`5.1`).
   - Add tests for `scaledCache` eviction, `hasFont`, and 1024 px cap (`6.2`).
3. **`GlyphAtlas` (`1.10`, `1.18`, `2.8`, `6.2`)**:
   - Update `makeRoom(int minDim)` (`minDim = max(w, h) + 2`) to loop
     doubling until `fSize >= minDim || fSize >= fMaxSize` (`1.10`).
   - Assert `maxSize <= short.max` and `f !is null` in `slotFor` (`1.18`).
   - Reuse a `ReusableArray!GlyphKey` scratch buffer in `removeFont()` (`2.8`).
   - Wrap FBO restore/delete in `readAtlas` with `scope(exit)` and test
     glyphs with `initialSize < dim <= maxSize` (`6.2`).
4. **`TextBatch` (`1.12`, `4.1`, `6.2`)**:
   - Return `0`/`false` from `texture()`/`stencilClip()` when
     `fQuadCount == 0`, and `assert(fTexture != 0)` in `appendQuad` (`1.12`).
   - Have `releaseMemory()` call `clear()` (`4.1`).
   - Add direct unit tests for `beginRun`, `appendQuad`, `remaining`, and
     `flush` (`6.2`).
5. **`TextRunCache` (`1.5`, `1.11`, `1.18`, `2.6`, `2.8`, `4.1`, `6.2`)**:
   - Widen `RunGlyph.dx` and `RunGlyph.dy` from `short` to `int` (`1.5`).
   - In `resolveSlots`, keep retrying while `fAtlas.size()` increases; only
     flag thrash when cleared at `fMaxSize` without growing (`1.11`).
   - Track `bool fNoStaleEntries` (reset in `beginFrame()`) to skip O(N^2)
     eviction scans (`2.6`).
   - Release `fQuads` and reset `fLoggedThrash = false` in `clear()` (`1.18`);
     cache zero-glyph (whitespace) runs (`2.8`).
   - Migrate `text_cache.d` tests to `GlTestWindow` (`4.1`) and add tests
     for mid-run growth & thrash, `fQuads > 64`, `growGlyphPool`,
     `onBeforeAtlasReset`, and UTF-8 (`6.2`).

## Verification

- `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`
