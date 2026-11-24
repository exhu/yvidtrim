# Text Batching Performance and Memory Report

Investigation of the uncommitted cross-label text batching implementation
(`TextBatch`, `TextPipeline`, `IndexedQuadArray`) compared against `HEAD`
(`pool-2048`, commit `2726853`).

## Summary

The uncommitted cross-label text batching changes worsen frame times on
multi-label scenes (`many`, `cjk-many`, `thrash`) and increase process RSS and
D GC heap usage by roughly 2 to 4+ MiB compared with `pool-2048`.

## Measured Comparison (`pool-2048` vs `batch` in `_bench`)

Data from `documentation/text-atlas-benchmark.md` (`pool-2048` baseline and
two `textbench batch` runs) plus a follow-up `textbench current` run on the
same uncommitted working tree:

```
  scenario  config     avg ms         rss end KiB     notes
  --------  ---------  -------------  --------------  ----------------------
  static    pool-2048  0.772-0.785    +7280 to +7296  baseline
            batch      0.697-0.833    +9132 to +9196  +1.9 MiB; +1309 KiB gc
  churn     pool-2048  0.696-0.759    +2224 to +2228  baseline
            batch      0.663-0.885    +1160 to +1168  less GC churn
  many      pool-2048  3.377-3.386    +1348 to +1388  baseline
            batch      4.532-4.730    +5432 to +5456  +35% time, +4.0 MiB
  thrash    pool-2048  66.84-67.77    +16140-17172    baseline
            batch      76.65-141.40   +20864-20960    max 2076-3044 ms spike
  cjk-mix   pool-2048  0.874-0.895    +5768           baseline
            batch      0.841-1.103    +6588 to +6780  +0.8 to +1.0 MiB RSS
  cjk-many  pool-2048  2.975-2.984    +1488 to +1492  baseline
            batch      4.135-5.073    +1628           +39-70% time
```

Heap details on the `current` run:
- `static`: `after GC.collect+minimize` leaves `gc used +1309 KiB` (retaining
  the 1 MiB `fVerts` vertex array); total RSS delta `+9132 KiB` vs `+7280 KiB`
  even though `malloc` is `+1296 KiB` vs `+1362 KiB`.
- `many`: `gc free` grows to `+5180 KiB` (vs `-1399 KiB` on `pool-2048`).
- `thrash`: `gc free` grows to `+19401 KiB` (vs `+4512 KiB`), with single-frame
  spikes of `2075.897 ms` and `3043.973 ms`.

## Root Causes: Performance

1. **`_bench` is built at `-O0` (`buildtype=debug`), exposing ~28 uninlined
   calls per glyph**

   `_bench/compile_commands.json` compiles with `-g -d-debug` (no `-O2`, no
   `-enable-inlining`, `b_ndebug=false`). For every glyph in
   `Renderer.drawTextRun` (`yguilib/source/yguilib/render/package.d`), the
   inner loop calls:

   ```
   drawTextRun
     -> queueTextQuad
       -> TextBatch.needsFlushFor
       -> TextBatch.pushQuad (assert(!needsFlushFor))
         -> 4x ReusableArray!TextVertex.push (32 B by value)
           -> __invariant -> __invariant0 (entry + exit)
           -> ensureCapacityForPush
           -> core.lifetime.move!TextVertex
   ```

   Disassembly of `_bench/yguilib/textbench` confirms none of these are
   inlined: `ReusableArray.push` alone executes 24 function calls per glyph
   (~28 calls/glyph total, ~1M calls/frame in `many`, ~3.4M in `thrash`),
   versus a single `Appender!(float[]).put(quad[])` per glyph previously. Note
   that `_build` (`debugoptimized`) also keeps `b_ndebug=false`, so asserts and
   `ReusableArray`'s `invariant` run there as well.

2. **33% larger vertex payload per glyph quad**

   Previously `TexturePipeline` emitted 6 vertices x 4 floats (`x, y, u, v`) =
   96 bytes/quad with `uColor` passed as a uniform. `TextPipeline`
   (`yguilib/source/yguilib/render/internal/pipelines.d`) uses `TextVertex`
   with 4 float RGBA channels = 32 bytes/vertex x 4 = 128 bytes/quad (+33% CPU
   writes and GL upload bandwidth).

3. **Multi-MiB `glBufferSubData(..., 0, ...)` without buffer orphaning**

   `uploadAndDrawIndexedQuads`
   (`yguilib/source/yguilib/render/internal/gl_util.d`) repeatedly writes to
   offset 0 of the same 2 MiB VBO on each flush without orphaning
   (`glBufferData(..., null, GL_DYNAMIC_DRAW)`). In `many` (~36k quads,
   3 flushes/frame) and `thrash` (~120k quads, 8 flushes/frame = 16 MiB/frame),
   overwriting an in-flight 2 MiB VBO forces the GL driver (`radeonsi`) to
   stall or allocate staging/shadow copies, unlike the tiny ~2-3 KiB per-label
   uploads before.

## Root Causes: Memory

1. **Large batch cap (`maxIndexedQuads = 16383`) that never shrinks**

   Previously only one label was buffered (~3 KiB CPU + 4 KiB VBO). Now a
   single peak frame permanently retains buffers sized for up to 16,383 quads
   (65,532 vertices).

2. **GC-backed `TextBatch.fVerts` and doubling bloat**

   `ReusableArray!TextVertex` doubles up to 32,768 vertices (1.0 MiB) in
   `static` and 65,536 vertices (2.0 MiB) in `many`, abandoning intermediate
   buffers on the GC heap and expanding GC pools (`gc free +5.2 MiB` in `many`),
   which `GC.minimize()` does not unmap back to the OS.

3. **2 MiB VBO + 192 KiB EBO + GL driver staging copies**

   `IndexedQuadArray.vbo` grows to 1 MiB (`static`) and 2 MiB (`many`) and
   never shrinks. Combined with GL driver shadow/staging buffers, this accounts
   for the +1.9 MiB RSS increase in `static` and part of the +4.0 MiB increase
   in `many`. `IndexedQuadArray.ebo` also grows up to 192 KiB, allocating
   temporary `new ushort[newQuads * 6]` GC arrays on each doubling.

## Proposed Fixes for Future Improvement

1. **Lower the batch quad cap**

   Cap `TextBatch` at e.g. 1,024 or 2,048 quads instead of 16,383. This still
   batches ~40-80 labels per draw call while cutting CPU, VBO, and EBO memory
   by 8-16x, and makes a fixed/pre-sized buffer practical with zero doubling
   GC churn.

2. **Pack per-vertex color as `ubyte[4]` (`GL_UNSIGNED_BYTE`, normalized)**

   Replace `float r, g, b, a` in `TextVertex` with 4 normalized unsigned bytes
   (`GL_TRUE`). Vertex size drops from 32 bytes to 20 bytes (80 bytes/quad):
   37.5% smaller than current `TextVertex` and 17% smaller than the unbatched
   96 bytes/quad path.

3. **Eliminate per-glyph `push` and `invariant` overhead**

   Replace per-vertex `ReusableArray.push` inside `TextBatch` with a plain
   pre-allocated/capped `TextVertex[]` buffer (or a bulk per-run append helper)
   that checks `(texId, stencilClip)` and remaining quad capacity once per run
   or chunk and writes 4 vertices directly without `invariant`, `move`, or
   per-glyph `needsFlushFor` calls.

4. **Orphan the VBO on flush (or sub-allocate in a ring buffer)**

   Call `glBufferData(GL_ARRAY_BUFFER, qa.vboCapacity, null, GL_DYNAMIC_DRAW)`
   before `glBufferSubData` (or stream into a larger ring buffer using
   offset/base-vertex draws) so multiple flushes per frame do not stall on
   in-flight GPU draws.

5. **Benchmark with optimized build settings**

   Configure `_bench` with `-Dbuildtype=debugoptimized` or `release` (matching
   baseline and candidate) so timings reflect production code rather than `-O0`
   debug-contract overhead, and record `gc used`, `gc free`, and `malloc`
   deltas alongside RSS.

## Final Results (phases 1-4, optimized build)

Optimized builds (`-Dbuildtype=debugoptimized -Db_ndebug=true
-Dbenchmarks=true`), 3 interleaved runs each, `pool-2048` is commit
`2726853` in a temporary worktree, `batch` is the working tree with: fixed
`TextVertex[]` buffer and per-run state check, 2048-quad cap, one-time EBO,
20-byte vertices (`ubyte[4]` color) and VBO orphaning before each
`glBufferSubData`.

```
  scenario  config     avg ms        max ms      rss end KiB
  --------  ---------  ------------  ----------  --------------
  static    pool-2048  0.640-0.741   1.20-1.48   +7240-7388
            batch      0.329-0.333   0.85-1.62   +7136-7156
  churn     pool-2048  0.516-0.639   1.13-1.24   +2220-2228
            batch      0.359-0.407   0.96-1.31   +2228
  many      pool-2048  3.034-3.163   3.98-4.23   +1348-1416
            batch      1.806-1.869   2.91-3.33   +1364
  thrash    pool-2048  25.61-27.18   30.8-37.6   +16164-17384
            batch      25.18-25.80   28.7-30.1   +16408-17508
  cjk-mix   pool-2048  0.635-0.637   1.29-1.73   +5768
            batch      0.513-0.549   1.43-1.53   +8584
  cjk-many  pool-2048  2.422-2.479   3.43-3.51   +1488-1492
            batch      2.193-2.458   3.49-4.16   +3508-3560
  multicolor batch     0.314-0.331   0.55-0.77   +0-232
```

Against the targets:
- avg time <= pool-2048: met in every scenario (`many` 41% faster,
  `cjk-many` equal to 10% faster, `thrash` equal within noise).
- No `thrash` spikes: met (max 28.7-30.1 ms; the 2-3 s spikes are gone).
- RSS delta <= pool-2048 + ~0.5 MiB: met for `static`, `churn`, `many`,
  `thrash`. NOT met for the CJK scenarios: `cjk-mix` +2.8 MiB and
  `cjk-many` +2.0 MiB over the baseline.

Shortfall: the CJK RSS excess appears only with the `cjk` font scenarios and
is not explained by the vertex buffers (those are identical to `many`, which
is on target). It likely comes from glyph rasterization / cache allocations
that differ in the batch path (to be investigated); the Latin scenarios show
no excess. Orphaning the VBO did not measurably change frame times on this
GPU/driver (radeonsi) since uploads are already small after the 2048 cap.
