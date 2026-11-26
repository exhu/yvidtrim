# Phase 1: Flat RunGlyph Pool & Isolated Benchmark at 512

## Target File

- `yguilib/source/yguilib/render/internal/text_cache.d`

## Implementation Steps

1. **Imports**:
   Replace `import std.array : Appender;` with
   `import yguilib.allochelpers : ReusableArray;`.

2. **Types & Structs** (2-space indent, max 80 chars/line, `f` prefix for
   backing fields, visibility section labels, no `out`/`ref` return params):
   - Update `TextRun.glyphs` doc comment: slice into `TextRunCache`'s pooled
     glyph buffer, valid until the next `runFor` call.
   - Add private structs:
     - `struct LayoutResult { int count; int width; int height; }`
     - `struct CompactEntry { size_t offset; TextCacheEntry* entry; }`
   - Add `size_t glyphOffset;` to `TextCacheEntry` (start offset of
     `run.glyphs` in `fGlyphPool`).

3. **Keep `enum size_t maxCacheEntries = 512;`** during Phase 1 so
   `textbench many` isolates the pool's effect on RSS and GC free heap.

4. **`TextRunCache` Fields & Test Accessors**:
   - Add private fields:
     - `RunGlyph[] fGlyphPool;`
     - `size_t fPoolUsed;`
     - `size_t fLiveGlyphs;`
     - Replace `Appender!(EvictCandidate[]) fEvictScratch;` with
       `ReusableArray!EvictCandidate fEvictScratch;` (change `.put(...)`
       calls to `.push(...)`).
     - `ReusableArray!CompactEntry fCompactScratch;`
   - Under `private: version (unittest)`: `size_t fCompactionCount;`
   - Under `package(yguilib): version (unittest)`:
     - `size_t glyphPoolCapacity() const { return fGlyphPool.length; }`
     - `size_t glyphPoolUsed() const { return fPoolUsed; }`
     - `size_t liveGlyphCount() const { return fLiveGlyphs; }`
     - `size_t compactionCount() const { return fCompactionCount; }`

5. **Refactor Layout & Reorder `runFor`**:
   - Split `layoutRun` into:
     - `LayoutResult layoutQuads(Font font, string text)`: lays out into
       reused `fQuads`, growing `fQuads` if needed; returns
       `LayoutResult(0, 0, 0)` on failure or `LayoutResult(n, w, h)`.
     - `void fillRunGlyphs(RunGlyph[] glyphs, int outlinePx) const`: fills
       `glyphs[i]` from `fQuads[i]`, shifting `dx`/`dy` by `-outlinePx`.
   - In `runFor` miss path (after `applyOutline` + `scope(exit) resetOutline`):
     1. `const LayoutResult laid = layoutQuads(font, text);`
        If `laid.count <= 0`, return `null`.
     2. `if (cache.length >= maxEntries) { evictOldest(); }`
        (Evict before pool allocation so freed glyphs lower `fLiveGlyphs`.)
     3. `const size_t n = cast(size_t)laid.count;`
        `const size_t offset = allocGlyphSpan(n);`
     4. Build `TextRun run` with `width = laid.width`, `height = laid.height`,
        `glyphs = fGlyphPool[offset .. offset + n]`,
        `atlasGen = unresolvedGen`.
     5. `fillRunGlyphs(run.glyphs, outlinePx);`
     6. `resolveSlots(font, outlinePx, run);`
     7. `fLiveGlyphs += n;`
        `cache[key] = TextCacheEntry(run, offset, ++fTick);`
        `return &(key in cache).run;`

6. **Pool Methods**:
   - `size_t initialPoolCap() const`:
     `max(size_t(64), min(size_t(4096), maxEntries * 16))`
   - `size_t allocGlyphSpan(size_t count)`:
     - `assert(count > 0);`
     - `if (fLiveGlyphs == 0) { fPoolUsed = 0; }`
     - If `fPoolUsed + count > fGlyphPool.length`:
       - `const size_t needed = fLiveGlyphs + count;`
       - If `fPoolUsed > fLiveGlyphs && needed * 4 <= fGlyphPool.length * 3`:
         `compactGlyphPool();`
       - Else:
         `growGlyphPool(needed);`
     - `const size_t offset = fPoolUsed; fPoolUsed += count; return offset;`
   - `void compactGlyphPool()`:
     - Collect `CompactEntry(entry.glyphOffset, &entry)` into
       `fCompactScratch`, sort ascending by `offset`.
     - Slide in-place using an explicit forward loop (`foreach (i; 0 .. len)`
       `fGlyphPool[dst + i] = fGlyphPool[src + i];`) — NEVER slice assign
       `a[] = b[]` which throws on overlap when `dst < src`.
     - Update `e.glyphOffset = dst`, `e.run.glyphs = fGlyphPool[dst .. dst + len]`.
     - `assert(dst == fLiveGlyphs); fPoolUsed = dst; fCompactScratch.clear();`
     - Increment `fCompactionCount` under `version (unittest)`.
   - `void growGlyphPool(size_t minNeeded)`:
     - `const size_t targetCap = minNeeded + minNeeded / 3 + 1;`
     - `size_t newCap = fGlyphPool.length == 0 ? initialPoolCap() : fGlyphPool.length * 2;`
     - `while (newCap < targetCap) { newCap *= 2; }`
     - Allocate `auto next = new RunGlyph[newCap];`, copy each live entry
       sequentially into `next[dst .. dst + len]`, update `glyphOffset` and
       `run.glyphs`, `assert(dst == fLiveGlyphs)`, set `fGlyphPool = next`
       and `fPoolUsed = dst`.

7. **Cleanup & Accounting**:
   - `removeKey(const TextCacheKey key)`: decrement `fLiveGlyphs` by
     `p.run.glyphs.length`, remove key, reset `fPoolUsed = 0` when
     `fLiveGlyphs == 0`.
   - `clear()`: also `fCompactScratch.clear(); fGlyphPool = null; fPoolUsed = 0; fLiveGlyphs = 0;`.

8. **Unit Tests in `text_cache.d`**:
   - Compaction & steady-state capacity stability under eviction churn
     (`compactionCount() > 0`, constant `glyphPoolCapacity()` over 20+ cycles,
     surviving runs' `RunGlyph` contents match pre-compaction snapshot).
   - Overlapping in-place slide (`dst < src < dst + len`): short string then
     long string, evict short string, force compaction, verify all `RunGlyph`
     fields of the long string are intact and `glyphPoolUsed() == liveGlyphCount()`.
   - `removeFont` decrements `liveGlyphCount()` and resets `glyphPoolUsed() == 0`
     when all runs are removed.
   - `clear()` resets `glyphPoolCapacity() == 0`, `glyphPoolUsed() == 0`, and
     `liveGlyphCount() == 0`.

## Verification & Benchmark

```bash
ninja -C _build && timeout 300 meson test -C _build
ninja -C _bench && timeout 120 ./_bench/yguilib/textbench pool-512
```
Run `textbench pool-512` twice and record all metrics (`many` RSS, GC used,
GC free, avg frame time, fidelity counts).
