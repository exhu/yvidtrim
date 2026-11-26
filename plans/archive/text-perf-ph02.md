# Phase 2: CPU - remove per-glyph overhead

Files: `yguilib/source/yguilib/render/internal/text_batch.d`,
`yguilib/source/yguilib/render/package.d` (`queueTextQuad` ~l.1048,
`drawTextRun` ~l.1235).

1. `TextBatch`: replace `ReusableArray!TextVertex fVerts` with a fixed
   `TextVertex[]` sized once to `maxIndexedQuads * 4`; `pushQuad` writes
   the 4 vertices by index (no `push`, `move`, `invariant`).
2. `drawTextRun`: texture and clip are constant within a run. Check
   `needsFlushFor` once per run, flush when remaining capacity is below
   the run's glyph count, then append glyphs without per-glyph state
   checks (add a bulk/unchecked append helper to `TextBatch`).
3. Keep `TextBatchStats`, `clear`, `releaseMemory` and existing unittests
   (adjust the no-GC-growth unittest to the new buffer).

Done when: build + tests pass; textbench `many`/`cjk-many` improves vs
phase 1 numbers.
