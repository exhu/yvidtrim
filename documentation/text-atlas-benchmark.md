# Text rendering benchmark: per-label textures vs glyph atlas

Measures CPU time per frame, process memory and GL texture memory of the
`Renderer` text path before and after the glyph atlas
(`plans/archive/glyph-atlas.md`).

## What was compared

```
  branch                 base                              text path
  ---------------------  --------------------------------  ----------------
  bench-text-pre-atlas   3779408 (= tag before-font-atlas) one GL texture
                                                           per label
  bench-text-atlas       main (564e071)                    shared glyph
                                                           atlas
  main                   has the benchmark program too (see "Running")
```

Both benchmark branches carry the same `textbench` source. It only uses
the public `Renderer` text API (`drawTextWithFontName`,
`measureTextWithFontName`, `registerFontFromFile`, `clearTextCache`), so
it builds unchanged on both text implementations.

## Running

The program is excluded from the default build and compiled on request:

```
meson setup _bench . -Dbenchmarks=true      # or --reconfigure in _build
ninja -C _bench
./_bench/yguilib/textbench some-label       # needs a display / GL
```

On the pre-atlas branch the target is built unconditionally:
`git checkout bench-text-pre-atlas && ninja -C _build`, then
`./_build/yguilib/textbench`.

## Method

A 1024x768 window, display scaling 1, `glFinish()` at the end of every
frame so the time includes GPU work. Each scenario starts with
`clearTextCache()`. "cold" is the first frame (cache and atlas empty),
"avg" is the mean of the following frames.

Memory:
- RSS and peak from `/proc/self/status`.
- GL texture memory: every live texture id is enumerated with
  `glIsTexture` and sized with `glGetTexLevelParameteriv` (level 0,
  RGBA8, 4 bytes per pixel), as a delta against the scenario start.

Scenarios:

```
  name       labels  frames  font     content
  ---------  ------  ------  -------  ---------------------------------
  static        200     300  default  fixed text, 3 sizes (all hits)
  churn         100     300  default  digits change every frame
  many         1500     100  default  more distinct strings than the
                                      512-entry cache cap, 3 sizes
  cjk-mix       100     300  Noto     "视频剪辑 Video Trim 第N段 00:SS
                                      完成 OK", 3 sizes
  cjk-many     1500     100  Noto     8 distinct han chars per label,
                                      about 4000 distinct glyphs
```

The CJK scenarios use `NotoSansCJK-Regular.ttc` from
`/usr/share/fonts/opentype/noto/` registered as font `cjk`; they are
skipped when that file does not exist.

## Results

Frame times are the range over the runs; runs of the two builds were
interleaved (3 runs each) because the machine was noisy. A first set of
runs on a quieter machine gave the same ordering with larger gaps
(`many`: 14.1 vs 6.1 ms, `churn`: 1.10 vs 0.49 ms). Treat absolute
numbers as approximate, the ratios as the result.

```
  scenario   metric          pre-atlas        atlas
  ---------  --------------  ---------------  ---------------
  static     avg frame       0.47 - 0.54 ms   0.76 - 0.80 ms
             GL textures     200 (4.1 MiB)    1 (1.0 MiB)
  churn      avg frame       0.95 - 1.23 ms   0.73 - 0.80 ms
             GL tex at end   404 (2.7 MiB)    1 (1.0 MiB)
  many       avg frame       18.3 - 18.8 ms   12.0 - 12.1 ms
             GL textures     988 (18.1 MiB)   1 (1.0 MiB)
             RSS at end      +1.7 MiB         +7.5 MiB
  cjk-mix    avg frame       1.24 - 1.28 ms   0.79 - 0.83 ms
             GL tex at end   404 (10.2 MiB)   1 (1.0 MiB)
             RSS at end      +3.8 MiB         +5.0 MiB
  cjk-many   avg frame       17.7 - 18.3 ms   11.4 ms
             GL textures     988 (13.6 MiB)   1 (4.0 MiB)
             cold frame      49 - 58 ms       49 - 53 ms
```

### Mixed Chinese and English text

Output is pixel-equivalent between the two implementations:

```
  text (14 pt)          measure     lit pixels   x range
  --------------------  ----------  -----------  ---------
  default font, mixed   200x18      633          11..209
  Noto CJK, mixed       221x21      1142         11..230
  Noto CJK, latin only  92x21       372          10..101
```

These three lines are identical on `bench-text-pre-atlas` and on the atlas
build, so shaping, glyph placement and measurement of mixed
Chinese/English text did not change.

Findings:
- The default font (`GoogleSansCode`) has no CJK glyphs and the renderer
  has no fallback font, so Chinese text needs a registered CJK font. The
  default-font line only shows that both builds draw the same thing (the
  glyph shapes were not inspected).
- With a CJK font the atlas is about 1.5x faster per frame for changing
  or many-label scenes, like the Latin scenarios, and needs one texture
  instead of hundreds.
- CJK stresses the atlas more: about 4000 distinct glyphs made it grow
  from 512x512 to 1024x1024 (4 MiB), still far below the 13.6 MiB of the
  per-label textures. A 4096 page holds roughly 50000 glyphs at this
  size, so the clear-and-repack path is not expected in normal use.
- The cold frame is the same on both builds: it is dominated by
  rasterizing thousands of new glyphs through SDL_ttf.

## Conclusions

- The atlas wins on GL memory in every scenario and on frame time when
  text changes or exceeds the cache cap.
- Steady-state static text, which is all cache hits, is about 1.5x slower
  on this machine (about 0.3 ms for 200 labels, about 1.5 us per label):
  a label is now a quad per glyph instead of one pre-rendered texture.
  Cross-label batching (the TODO.md follow-up) targets this cost.
- Process RSS grows more with the atlas in `many` (+7.5 MiB vs +1.7 MiB)
  and `cjk-mix`. The cause was not investigated (the glyph runs the
  cache keeps per string are the likely part).

## Caveats

- One machine, one GL driver, a noisy desktop; no pinning of CPU
  frequency.
- `glFinish()` per frame makes timings include driver and GPU latency,
  which is not what an app with vsync sees.
- GL memory counts only level 0 of each texture.
