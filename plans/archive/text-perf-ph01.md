# Phase 1: fair benchmark baseline

Files: `yguilib/meson.build` (benchmarks option),
`documentation/text-atlas-benchmark.md`.

1. Set up `_bench` with `-Dbuildtype=debugoptimized -Dbenchmarks=true`
   (also try `-Db_ndebug=true`) so asserts/invariants do not dominate.
2. Run `textbench` for `pool-2048` (checkout 2726853 in a worktree) and
   the current `batch` code, scenarios: static, churn, many, thrash,
   cjk-mix, cjk-many.
3. Record avg ms, max ms, rss, gc used/free, malloc deltas in
   `documentation/text-atlas-benchmark.md`.

Done when: a table comparing both configs on the optimized build exists.
No source changes besides docs/notes.
