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
                                      512 cap (fits inside 2048), 3 sizes
  thrash       5000      50  default  more distinct strings than the
                                      2 * 2048 hard cap, 3 sizes
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
  and `cjk-mix`. The cause is a larger D GC heap, not a leak; see
  "Memory investigation".

## Memory investigation

`textbench` now also prints the D GC heap (used / free) and the C heap
(`mallinfo2`) deltas, and the RSS after `GC.collect(); GC.minimize()`.
Same program on both branches, KiB, delta over the scenario start:

```
  scenario  build      rss end  gc used  gc free  malloc  rss after GC
  --------  ---------  -------  -------  -------  ------  ------------
  static    pre-atlas    6660      828     3268    2482      6724
            atlas        6908      890     3206    1363      7036
  churn     pre-atlas    1212      555     -555    1272      1212
            atlas         308      510     -510       5       308
  many      pre-atlas    1672      205     -205    3075      1672
            atlas        7736     1244     5924     275      7736
  cjk-mix   pre-atlas    3828    -2254     2254    5996      3828
            atlas        5196    -2539     2539    4785      5196
  cjk-many  pre-atlas    2592      198     -198    4305      2592
            atlas        1492     3285    -3285    1279      1492
```

Findings:
- `many` (+7.7 MiB vs +1.7 MiB): the live GC data is only about 1.2 MiB
  (the cache's runs); the other 5.9 MiB is GC free space, i.e. heap that
  grew to hold garbage and is never returned. 1500 distinct strings per
  frame against a 512-entry cache make every label a miss, and each miss
  allocates `new RunGlyph[n]` (28 bytes per glyph) in `layoutRun`; the
  evicted entries and their arrays become garbage, about 1 MiB per
  frame. The pre-atlas build keeps its per-label data in malloc/GL
  (+3 MiB malloc), so its GC heap stays flat. The growth is a high-water
  mark: 400 frames end at the same +7.7 MiB as 100 frames, and
  `GC.minimize()` does not release it (pages stay fragmented).
- `static`: both builds are about +6.7 MiB; that is first-use cost shared
  by both (font and SDL_ttf glyph caches, GC heap for strings). No
  atlas penalty.
- `cjk-mix`: malloc is the larger part on both builds (+4.8 vs +6.0 MiB),
  which is the SDL_ttf/FreeType glyph cache of the CJK font. The atlas
  build's higher RSS (+5.2 vs +3.8 MiB) is not explained by the GC or C
  heap (both are lower); it is most likely driver memory for the 1 MiB
  atlas texture, which was not verified.
- `churn` and `cjk-many`: the atlas build uses less RSS than pre-atlas.
- So the atlas does not retain more memory per label. Extra RSS appears
  only when the entry cap is exceeded every frame, as GC garbage from
  per-miss run allocation.

Follow-up fixes (first two now implemented, see below):
- store the glyphs of all cached runs in one pooled buffer (implemented:
  `TextRunCache` packs `RunGlyph` spans into `fGlyphPool` with in-place
  compaction and reuses `fQuads` in `layoutQuads`);
- raise `maxCacheEntries` above the number of labels a screen shows
  (implemented: `maxCacheEntries` raised from 512 to 2048; a run costs
  about 28 bytes per glyph plus the key string);
- calling `GC.collect()` is not an answer: it does not shrink RSS.

### Follow-up: RunGlyph pool and maxCacheEntries = 2048

Measured on the same machine comparing the pre-pool `512` baseline (1 run),
`pool-512` (2 runs), and `pool-2048` (`maxCacheEntries = 2048`, hard cap
`4096`, 2 runs).

Frame times (ms):

```
  scenario  config     cold ms      avg ms         max ms
  --------  ---------  -----------  -------------  -------------
  static    baseline   5.01         0.863          -
            pool-512   -            0.748-0.886    -
            pool-2048  -            0.772-0.785    -
  churn     baseline   1.38         0.845          -
            pool-512   -            0.717-0.846    -
            pool-2048  -            0.696-0.759    -
  many      baseline   17.75        17.814         671.432
            pool-512   12.42-16.51  11.920-12.079  13.916-17.203
            pool-2048  8.87-8.89    3.377-3.386    4.290-4.658
  thrash    pool-2048  65.87-66.87  66.838-67.773  -
  cjk-mix   baseline   3.39         0.758          -
            pool-512   -            0.844-0.850    -
            pool-2048  -            0.874-0.895    -
  cjk-many  baseline   53.69        11.063         -
            pool-512   -            10.920-11.367  -
            pool-2048  44.98-45.04  2.975-2.984    -
```

Memory deltas over scenario start (KiB):

```
  scenario  config     rss KiB       gc used KiB  gc free KiB  malloc KiB
  --------  ---------  ------------  -----------  -----------  ----------
  static    baseline   +6948         +890         +3206        +1363
            pool-512   +7308-7376    +1126-1127   +2969-2970   +1362-1363
            pool-2048  +7280-7296    +1126-1127   +2970        +1362-1363
  churn     baseline   +308          +510         -510         +6
            pool-512   +616-624      +602         -602         +5-6
            pool-2048  +2224-2228    +1177        -1177        +5-6
  many      baseline   +7732         +1247        +5921        +277
            pool-512   +1964-2004    +906         -906         +41-43
            pool-2048  +1348-1388    +1399        -1399        +35-37
  thrash    pool-2048  +16140-17172  +12896*      +4512        +349-350
  cjk-mix   baseline   +5196         -2539        +2539        +4785
            pool-512   +5020-5084    -2336        +2336        +4784-4785
            pool-2048  +5768         +5274        -5274        +4784
  cjk-many  baseline   +1492         +3282        -3282        +1277
            pool-512   +1488         +959         -959         +1277
            pool-2048  +1488-1492    +217         -217         +1280
```

`*` In `thrash`, `gc used` drops to `+2216 KiB` after `GC.collect()`.

What dropped and why:
- `pool-512` removes per-miss `RunGlyph[]` and layout quad allocations: in
  `many` (100% miss rate at 512), RSS falls from `+7732 KiB` to
  `+1964-2004 KiB`, `gc free` bloat disappears (`+5921` to `-906 KiB`),
  `malloc` falls from `+277` to `+41-43 KiB`, and the max frame spike drops
  from `671.432 ms` (GC pause) to `13.916-17.203 ms`.
- `pool-2048` raises the cap so `many` (1500) and `cjk-many` (1500) stay
  cached after frame 1: `many` avg frame drops from `17.814 ms` to
  `3.377-3.386 ms` (RSS `+1348-1388 KiB`), and `cjk-many` avg frame drops
  from `11.063 ms` to `2.975-2.984 ms`.
- `thrash` (5000 labels > 4096 hard cap) forces eviction and in-place pool
  compaction every frame while keeping `malloc` low (`+349-350 KiB`) and
  live GC data bounded (`+2216 KiB` after `GC.collect()`).
- Output fidelity across all runs is unchanged (`default-mixed` lit=633,
  `cjk-mixed` lit=1142, `cjk-latin` lit=372).

### Follow-up: Cross-label text batching

Added `TextBatch` + indexed-quad `TextPipeline` with per-vertex RGBA color
and `Renderer.flush()` before `glFinish()` in `textbench`, plus a `multicolor`
scenario (200 labels, 300 frames, 3 sizes, 4-color cycle). Two consecutive
`textbench batch` runs on this machine:

Frame times (ms, `pre-atlas` / `pool-2048` vs `batch` 2 runs):

```
  scenario    pre-atlas    pool-2048      batch (cold)   batch (avg)
  ----------  -----------  -------------  -------------  -------------
  static      0.47-0.54    0.772-0.785    4.74-5.81      0.697-0.810
  churn       0.95-1.23    0.696-0.759    0.85-1.25      0.663-0.885
  many        18.3-18.8    3.377-3.386    11.46-15.00    4.532-4.730
  thrash      -            66.838-67.773  73.36-78.74    76.649-117.725*
  multicolor  -            -              2.54-5.35      0.702-0.963
  cjk-mix     1.24-1.28    0.874-0.895    3.62-5.37      0.864-1.103
  cjk-many    17.7-18.3    2.975-2.984    46.94-50.39    4.850-5.073
```

`*` Run 1 of `thrash` hit a single-frame `max=2075.897 ms` spike (`p95` was
`81.042 ms`); Run 2 was `avg=76.649 ms`, `p95=79.016 ms`, `max=80.183 ms`.

Full `batch` run details (run 1 / run 2, `p95`, `max`, RSS delta):

```
  scenario    p95 (ms)      max (ms)        rss end (KiB)
  ----------  ------------  --------------  ----------------
  static      1.131-1.134   1.542-2.064     +9188 to +9196
  churn       0.997-1.317   1.086-3.954     +1160 to +1168
  many        5.618-6.270   6.505-7.337     +5456
  thrash      79.016-81.042 80.183-2075.897 +20864 to +20960
  multicolor  1.169-1.583   1.580-1.701     +0
  cjk-mix     1.369-1.617   2.146-2.673     +6588 to +6780
  cjk-many    6.375-7.025   7.917-9.649     +1628
```

Observations:
- `static` (`0.697-0.810 ms`) and `multicolor` (`0.702-0.963 ms`) match on
  avg frame time (Run 2: `0.697 ms` vs `0.702 ms`), confirming per-vertex color
  keeps 200 multi-color labels in a single batched draw without flushing on
  color changes.
- Compared with `pre-atlas`, `batch` remains slower on steady-state `static`
  (`0.697-0.810 ms` vs `0.47-0.54 ms`, dominated by `glFinish()` and
  per-frame CPU quad emission) and faster on `churn`, `many`, `cjk-mix`,
  and `cjk-many` (Run 2 `churn`: `0.663 ms` vs `0.95-1.23 ms`).
- Compared with `pool-2048` on this noisy desktop, Run 2 `static`
  (`0.697 ms`) and `churn` (`0.663 ms`) slightly improve on `pool-2048`
  (`0.772-0.785 ms` and `0.696-0.759 ms`), while `many` (`4.532-4.730 ms`)
  and `cjk-many` (`4.850-5.073 ms`) sit higher than the earlier `pool-2048`
  baseline (`3.377-3.386 ms` and `2.975-2.984 ms`) due to run-to-run host
  variance and larger batched `glBufferSubData` uploads under `glFinish()`.
- Output fidelity counts remain unchanged across both runs (`default-mixed`
  `lit=633`, `cjk-mixed` `lit=1142`, `cjk-latin` `lit=372`).

## Caveats

- One machine, one GL driver, a noisy desktop; no pinning of CPU
  frequency.
- `glFinish()` per frame makes timings include driver and GPU latency,
  which is not what an app with vsync sees.
- GL memory counts only level 0 of each texture.
