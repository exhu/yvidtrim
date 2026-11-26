# Phase 4: GPU upload - orphan VBO, final measurements

Files: `yguilib/source/yguilib/render/internal/gl_util.d`
(`uploadAndDrawIndexedQuads`), `documentation/text-batching-perf-report.md`,
`TODO.md`.

1. Before each `glBufferSubData`, orphan the VBO with
   `glBufferData(GL_ARRAY_BUFFER, qa.vboCapacity, null, GL_DYNAMIC_DRAW)`.
2. Re-run textbench (optimized build). Targets: `many`/`cjk-many` avg
   <= pool-2048, RSS delta <= pool-2048 + ~0.5 MiB, no `thrash` spikes.
3. Append results to the perf report; remove item 1 from `TODO.md`.
4. Update `ARCHITECTURE.md` only if the data flow changed (< 250 lines).

Done when: targets met or shortfalls documented; build + tests pass.
