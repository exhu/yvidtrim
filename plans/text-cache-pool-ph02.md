# Phase 2: Raise maxCacheEntries to 2048 & Add thrash

## Target Files

1. `yguilib/source/yguilib/render/internal/text_cache.d`
2. `yguilib/benchmarks/textbench/app.d`

## Implementation Steps

1. In `yguilib/source/yguilib/render/internal/text_cache.d`:
   Change `enum size_t maxCacheEntries = 512;` to
   `enum size_t maxCacheEntries = 2048;`.

2. In `yguilib/benchmarks/textbench/app.d`:
   - Keep `static`, `churn`, `many` (1500 labels), `cjk-mix`, and `cjk-many`
     unchanged. Update the comment above `many` to note 1500 labels (exceeded
     the historical 512 cap, fits inside the 2048 cap).
   - Add `thrash` immediately after `many`:
     ```d
     // more distinct strings per frame than the hard cap (2 * 2048)
     run(r, Scenario("thrash", 5000, 50, three.dup, null,
       (int f, int i) => format("Item %04d / file_%d.mp4", i, i * 37)));
     ```

## Verification & Benchmark

```bash
ninja -C _build && timeout 300 meson test -C _build
ninja -C _bench && timeout 120 ./_bench/yguilib/textbench pool-2048
```
Run `textbench pool-2048` twice to check consistency and record all metrics
across `static`, `churn`, `many`, `thrash`, `cjk-mix`, `cjk-many`, and
fidelity lines.
