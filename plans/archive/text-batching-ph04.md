# Phase 4: Benchmark, Documentation, ARCHITECTURE.md, TODO.md & Checks

## Scope & Target Files

- `yguilib/benchmarks/textbench/app.d` [MODIFY]
- `documentation/text-atlas-benchmark.md` [MODIFY]
- `ARCHITECTURE.md` [MODIFY]
- `TODO.md` [MODIFY]

## Implementation Steps

1. **`yguilib/benchmarks/textbench/app.d`** [MODIFY]:
   - Add `r.flush();` before `glFinish();` in `drawFrame()` and `fidelity()`.
   - Add an optional `ColorF[] colors` field (or `ColorF delegate(int, int)`
     helper) to `Scenario` (keep existing scenarios unchanged with white
     default) and add a `multicolor` scenario (200 labels, 300 frames,
     `[11.0f, 14.0f, 20.0f]`, cycling 4 distinct colors) to verify
     per-vertex color batching throughput.

2. **Build and Run `textbench` (twice)**:
   ```bash
   meson setup _bench . -Dbenchmarks=true --reconfigure 2>/dev/null \
     || meson setup _bench . -Dbenchmarks=true
   ninja -C _bench
   timeout 120 ./_bench/yguilib/textbench batch
   timeout 120 ./_bench/yguilib/textbench batch
   ```
   Verify output fidelity counts match `default-mixed` `lit=633`,
   `cjk-mixed` `lit=1142`, `cjk-latin` `lit=372`.

3. **`documentation/text-atlas-benchmark.md`** [MODIFY]:
   - Add a `### Follow-up: Cross-label text batching` section (<= 80 chars/line)
     recording the two `textbench batch` runs (`static`, `churn`, `many`,
     `thrash`, `cjk-mix`, `cjk-many`, `multicolor`), comparing frame times
     against `pool-2048` and `pre-atlas`, and noting the unchanged fidelity
     counts.

4. **`ARCHITECTURE.md`** [MODIFY]:
   - Add `text_batch` under `render/internal/` in the topology tree.
   - Update `**Text**` to concisely cover cross-label batching (`TextBatch`,
     `TextPipeline` indexed quads with per-vertex color, `Renderer.flush()`,
     atlas pre-reset flush hook).
   - Ensure `ARCHITECTURE.md` stays strictly `< 250` lines (`wc -l`).

5. **`TODO.md`** [MODIFY]:
   - Remove line 1:
     `- cross-label text batching (queue glyph quads, flush on state change) (canvas-render-review 3.7)`

## Final Verification

Run all tests and quality checks and verify zero failures/violations:
```bash
ninja -C _build && timeout 300 meson test -C _build
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-codestyle/scripts/check_codestyle.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
wc -l ARCHITECTURE.md
```
