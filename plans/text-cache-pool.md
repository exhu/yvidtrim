# TextRunCache RunGlyph Pool & Cache Capacity Plan

## Overview

Replace per-miss `new RunGlyph[n]` GC allocations in
`yguilib/source/yguilib/render/internal/text_cache.d` with a single flat
`RunGlyph[]` pooled buffer supporting amortized in-place compaction, raise
`maxCacheEntries` from `512` to `2048` (hard cap `4096`), and benchmark RSS
and GC free heap drops with `textbench`.

## Pool Memory Layout & Invariants

```
fGlyphPool (RunGlyph[], single NO_SCAN GC allocation)
+----------+-------+----------+-------+---------------------+
| Entry A  | dead  | Entry B  | dead  | free tail           |
+----------+-------+----------+-------+---------------------+
0                                     ^fPoolUsed            ^fGlyphPool.length

Invariants:
  - fLiveGlyphs <= fPoolUsed <= fGlyphPool.length
  - Every entry in cache has:
      entry.run.glyphs.length > 0
      entry.glyphOffset + entry.run.glyphs.length <= fPoolUsed
      entry.run.glyphs.ptr is &fGlyphPool[entry.glyphOffset]
  - Active spans [glyphOffset .. glyphOffset + len) are pairwise disjoint.
```

## Phases

- [Phase 1: Flat RunGlyph Pool & Benchmark at 512](text-cache-pool-ph01.md)
  Implement flat `fGlyphPool`, `allocGlyphSpan`, `compactGlyphPool`,
  `growGlyphPool`, `ReusableArray` scratch buffers, and unit tests; keep
  `maxCacheEntries = 512` and measure `textbench pool-512`.
- [Phase 2: Raise maxCacheEntries to 2048 & Add thrash](text-cache-pool-ph02.md)
  Raise `maxCacheEntries` to `2048`, add the `thrash` scenario (5000 labels)
  to `textbench`, and measure `textbench pool-2048`.
- [Phase 3: Docs, Cleanup & Full Verification](text-cache-pool-ph03.md)
  Update `documentation/text-atlas-benchmark.md`, `ARCHITECTURE.md` (< 250
  lines), and `TODO.md`, then run tests and style/boundary checks.
