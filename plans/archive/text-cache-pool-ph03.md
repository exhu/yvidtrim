# Phase 3: Docs, Cleanup & Full Verification

## Measured Results (Baseline vs pool-512 vs pool-2048)

### Baseline (512 cap, no pool)
- `static` (200): cold 5.01ms, avg 0.863ms, rss +6948KiB,
  gc used +890KiB, free +3206KiB, malloc +1363KiB
- `churn` (100): cold 1.38ms, avg 0.845ms, rss +308KiB,
  gc used +510KiB, free -510KiB, malloc +6KiB
- `many` (1500): cold 17.75ms, avg 17.814ms, max 671.432ms, rss +7732KiB,
  gc used +1247KiB, free +5921KiB, malloc +277KiB
- `cjk-mix` (100): cold 3.39ms, avg 0.758ms, rss +5196KiB,
  gc used -2539KiB, free +2539KiB, malloc +4785KiB
- `cjk-many` (1500): cold 53.69ms, avg 11.063ms, rss +1492KiB,
  gc used +3282KiB, free -3282KiB, malloc +1277KiB

### pool-512 (RunGlyph pool, 512 cap, 2 runs)
- `static`: avg 0.748-0.886ms, rss +7308-7376KiB,
  gc used +1126-1127KiB, free +2969-2970KiB, malloc +1362-1363KiB
- `churn`: avg 0.717-0.846ms, rss +616-624KiB,
  gc used +602KiB, free -602KiB, malloc +5-6KiB
- `many`: cold 12.42-16.51ms, avg 11.920-12.079ms, max 13.916-17.203ms,
  rss +1964-2004KiB, gc used +906KiB, free -906KiB, malloc +41-43KiB
- `cjk-mix`: avg 0.844-0.850ms, rss +5020-5084KiB,
  gc used -2336KiB, free +2336KiB, malloc +4784-4785KiB
- `cjk-many`: avg 10.920-11.367ms, rss +1488KiB,
  gc used +959KiB, free -959KiB, malloc +1277KiB

### pool-2048 (RunGlyph pool, 2048 cap / 4096 hard cap, 2 runs)
- `static`: avg 0.772-0.785ms, rss +7280-7296KiB,
  gc used +1126-1127KiB, free +2970KiB, malloc +1362-1363KiB
- `churn`: avg 0.696-0.759ms, rss +2224-2228KiB,
  gc used +1177KiB, free -1177KiB, malloc +5-6KiB
- `many`: cold 8.87-8.89ms, avg 3.377-3.386ms, max 4.290-4.658ms,
  rss +1348-1388KiB, gc used +1399KiB, free -1399KiB, malloc +35-37KiB
- `thrash` (5000): cold 65.87-66.87ms, avg 66.838-67.773ms,
  rss +16140-17172KiB, gc used +12896KiB (after GC +2216KiB),
  free +4512KiB, malloc +349-350KiB
- `cjk-mix`: avg 0.874-0.895ms, rss +5768KiB,
  gc used +5274KiB, free -5274KiB, malloc +4784KiB
- `cjk-many`: cold 44.98-45.04ms, avg 2.975-2.984ms, rss +1488-1492KiB,
  gc used +217KiB, free -217KiB, malloc +1280KiB

Fidelity across all runs: `default-mixed` lit=633, `cjk-mixed` lit=1142,
`cjk-latin` lit=372 (unchanged).

## Implementation Steps

1. `documentation/text-atlas-benchmark.md` (max 80 chars/line):
   - Add `thrash` to the Scenarios table (`5000` labels, `50` frames,
     default font, more distinct strings than the `2 * 2048` hard cap).
   - Add a new subsection under "Memory investigation"
     (`### Follow-up: RunGlyph pool and maxCacheEntries = 2048`) showing
     baseline (`512`, no pool) vs `pool-512` vs `pool-2048` (including
     `thrash`), summarizing what dropped and why.

2. `ARCHITECTURE.md`:
   - Update the `**Text**:` paragraph (~lines 207-214) in place to mention
     the pooled `RunGlyph` buffer with in-place compaction
     (`maxCacheEntries = 2048`), keeping total file length strictly
     under 250 lines.

3. `TODO.md`:
   - Remove the completed first bullet item
     (`- experiment with a RunGlyph pool ...`).

## Final Verification

Run in one command after all edits:

```bash
ninja -C _build && timeout 300 meson test -C _build && ninja -C _bench && \
  rdmd .agents/skills/check-codestyle/scripts/check_style.d && \
  rdmd .agents/skills/check-line-length/scripts/check_line_length.d && \
  rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d && \
  rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
```

Verify all tests pass, all 4 checks report zero violations, and
`ARCHITECTURE.md` is strictly under 250 lines.
