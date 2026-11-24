# Phase 3: memory - smaller cap and compact vertex

Files: `yguilib/source/yguilib/render/internal/gl_util.d`,
`.../render/internal/pipelines.d`, `.../render/internal/text_batch.d`,
`.../render/package.d`.

1. `maxIndexedQuads` 16383 -> 2048 (keep the 16-bit index assert);
   update `indexedQuadCapacityFor` and its unittests.
2. Build the EBO once at full capacity (no doubling) without a temporary
   GC `new ushort[]` (use a malloc/stack buffer, freed after upload).
3. `TextVertex` color -> `ubyte[4]` (normalized): 32 -> 20 bytes. Update
   the `static assert`, `createTextQuadArray` attribute 2
   (`GL_UNSIGNED_BYTE, GL_TRUE`, stride 20), quad construction in
   `drawTextRun`, and unittests. Shader stays `vec4` input.
4. Verify colored text is visually identical.

Done when: build + tests pass; RSS/GC deltas in textbench drop vs phase 2.
