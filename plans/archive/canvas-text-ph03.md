# Phase 3: gradient and pattern text fills

Prereq: phase 2. Files: `render/internal/pipelines.d` (GradientPipeline,
PatternPipeline, shaders), `canvas/package.d` (`drawPaint`).

Steps:
1. Extend gradient and pattern pipelines with an optional alpha-mask mode:
   vertices (x, y, u, v), mask texture sampler, output = paint * mask.a.
   Keep existing non-mask paths unchanged (separate program variant or
   uniform flag).
2. `fillText` for `FillStyle.Kind.linearGradient/radialGradient/pattern`
   draws glyph quad through the mask variant using the same uniforms as
   `drawPaint` (gradient inverse transform, pattern logicToPattern).
3. Shadow for these styles uses the glyph alpha (as for solid).
4. Tests: gradient text left/right colors differ; pattern text samples
   pattern; invisible styles draw nothing.

Done: build + tests pass.
