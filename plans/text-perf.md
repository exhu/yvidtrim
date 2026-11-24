# Text batching performance and memory

Source: `documentation/text-batching-perf-report.md`. Cross-label batching
(e8736db) is 35-70% slower on `many`/`cjk-many`/`thrash` and uses +2..4 MiB
more memory than `pool-2048` (2726853). Goal: match or beat the baseline.

Phases (each verified with
`ninja -C _build && timeout 300 meson test -C _build`):

- `plans/text-perf-ph01.md` - fair benchmark baseline (optimized build)
- `plans/text-perf-ph02.md` - CPU: remove per-glyph push/invariant overhead
- `plans/text-perf-ph03.md` - memory: 2048-quad cap, 20-byte vertex
- `plans/text-perf-ph04.md` - GPU: orphan VBO on upload, final measurements

## Status

- ph01 DONE: optimized build (`debugoptimized`, `b_ndebug=true`) shows
  batch is NOT slower (15-40% faster on static/churn/many/cjk-mix; equal on
  thrash/cjk-many). The -O0 CPU regression does not reproduce. Memory
  regression is real (RSS +1.9 MiB static, +4.0 many, +3 thrash; gc free
  grows in many/thrash). Results in `documentation/text-atlas-benchmark.md`.
  Implication: ph02 is low-value CPU-wise (helps debug builds); ph03/ph04
  carry the real gains.

- ph02 DONE: `TextBatch.fVerts` is a fixed `TextVertex[]` (allocated once,
  `maxIndexedQuads * 4`); new `remaining()/beginRun()/appendQuad()`;
  `drawTextRun` checks state once per run (plus a cheap capacity check per
  glyph for runs longer than the cap). Build + 10/10 tests pass. textbench
  not re-run (deferred to ph04 final measurements).

- ph03 DONE: `maxIndexedQuads` 2048; EBO built once via malloc buffer
  (`fillQuadIndices`); `TextVertex` is 20 B (`ubyte[4]` color,
  `packTextColor`); ARCHITECTURE.md updated. Build + 10/10 tests pass.
  Optimized textbench RSS delta: static +9.2 -> +7.2 MiB, many +5.4 -> +1.3
  MiB, thrash +19.1 -> +16.3..17.5 MiB; avg frame times unchanged. Visual
  check of colored text not done (fidelity counts unchanged).

- ph04 DONE (targets partly met): VBO orphaned before each upload (no
  measurable effect on time). Final optimized textbench vs pool-2048: avg
  time <= baseline everywhere (many 1.8 vs 3.1 ms), no thrash spikes; RSS
  within +0.5 MiB for static/churn/many/thrash. Shortfall: cjk-mix +2.8 MiB
  and cjk-many +2.0 MiB RSS vs baseline, not explained by vertex buffers
  (likely glyph raster/cache allocations in batch path); uninvestigated.
  TODO.md item 1 left in place pending that follow-up. Results in
  `documentation/text-batching-perf-report.md`.

After completion: remove item 1 from `TODO.md`; update `ARCHITECTURE.md`
only if the text batching data flow description changes.
