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

## Final Results (commit 9330be0 vs main, optimized build)

Re-measured on 2026-11-24 with the committed branch
(`cross-label-text-batching`, `9330be0`) against `main` (`2726853`,
`pool-2048`, built from a temporary worktree). Both use identical options
(`-Dbuildtype=debugoptimized -Db_ndebug=true -Dbenchmarks=true`), 3
interleaved runs each (main, branch, main, ...) with the machine idle.
The branch has: fixed `TextVertex[]` buffer and per-run state check,
2048-quad cap, one-time EBO, 20-byte vertices (`ubyte[4]` color) and VBO
orphaning before each `glBufferSubData`.

```
  scenario  config   avg ms        max ms       rss end KiB
  --------  -------  ------------  -----------  ---------------
  static    main     0.711-0.731   1.33-1.80    +7096-7264
            branch   0.364-0.377   1.10-1.18    +7128-7148
  churn     main     0.618-0.635   1.19-1.22    +2220
            branch   0.486-0.523   1.11-1.26    +2300
  many      main     3.147-3.227   3.97-4.17    +1348-1388
            branch   2.124-2.208   3.53-3.75    +1336-1340
  thrash    main     24.53-26.26   29.3-31.4    +16072-17168
            branch   25.09-27.24   36.5-40.8    +17444-17512
  cjk-mix   main     0.630-0.657   1.29-1.45    +5768-5772
            branch   0.514-0.527   1.31-1.42    +8584-8588
  cjk-many  main     2.419-2.503   3.35-4.04    +1488
            branch   2.190-2.533   2.96-4.97    +3500-3564
  multicolor branch  0.315-0.323   0.53-0.59    -1072-0
```

Findings:
- Faster: `static` -48%, `many` -31%, `churn` -20%, `cjk-mix` -19%.
  `cjk-many` is -9% on average but the ranges overlap (one branch run
  2.533 vs main 2.503), so it is equal within noise.
- `thrash` is NOT improved: avg 25.1-27.2 ms vs 24.5-26.3 ms (ranges
  overlap, branch slightly slower), and max frame is worse, 36.5-40.8 ms vs
  29.3-31.4 ms (p95 36 ms vs 27-29 ms on the branch). The old 2-3 s spikes
  of the uncommitted version are still gone. The earlier "max 28.7-30.1"
  figure did not reproduce; the tail regression looks real (all 3 branch
  runs) and is a candidate for investigation (flush count / orphaning
  with ~120k quads per frame).
- RSS: on target for `static`, `churn`, `many` (within ~0.1 MiB). `thrash`
  is +0.3 to +1.4 MiB over main. CJK scenarios are still over: `cjk-mix`
  +2.8 MiB, `cjk-many` +2.0 MiB (identical to the earlier measurement).

Shortfall: the CJK RSS excess appears only with the `cjk` font scenarios and
is not explained by the vertex buffers (those are identical to `many`, which
is on target). It likely comes from glyph rasterization / cache allocations
that differ in the batch path (to be investigated); the Latin scenarios show
no excess. Orphaning the VBO did not measurably change frame times on this
GPU/driver (radeonsi) since uploads are already small after the 2048 cap.
