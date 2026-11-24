# Cross-Label Text Batching Benchmark: `main` vs `cross-label-text-batching`

Comparison of `textbench` frame times, process memory, GC/C heap deltas,
and GL texture memory between `main` (`e8736db`) and branch
`cross-label-text-batching` (`d1089eb`).

## What Was Compared

```
  ref                         commit   key text-batch characteristics
  --------------------------  -------  -------------------------------------
  main                        e8736db  initial cross-label batching:
                                       ReusableArray!TextVertex, 32 B float
                                       RGBA vertices, 16383-quad cap,
                                       dynamic EBO growth, no VBO orphaning
  cross-label-text-batching   d1089eb  adds commit 9330be0 optimizations:
                                       fixed TextVertex[] buffer, per-run
                                       state checks, 2048-quad cap, one-time
                                       EBO, 20 B ubyte[4] RGBA vertices, VBO
                                       orphaning before glBufferSubData
```

## Build & Run Setup

Both branches were configured and built in `_build` with identical Meson
options on 2026-11-24, followed by 3 consecutive `textbench` runs per
branch:

```
  meson configure --buildtype=debugoptimized -Dbenchmarks=true \
    -Dmemtelemetry=enabled _build
  ninja -C _build
  ./_build/yguilib/textbench
```

Resolved core build options in `_build`:
- `buildtype`: `debugoptimized`
- `b_ndebug`: `false` (contracts/asserts remain active)
- `benchmarks`: `true`
- `memtelemetry`: `enabled` (`textbench` prints its own stdout memory stats;
  no extra `SDL` log lines appeared under default logging)

## Frame Time Comparison

All times are in milliseconds (`ms`), across 3 consecutive runs per branch.
`avg` shows the `min..max` range of per-run averages and the delta of the
3-run mean (`branch` vs `main`). `cold`, `p95`, and `max` show the `min..max`
range across the 3 runs.

```
  scenario   branch cold (ms)    avg (ms)       delta  p95 (ms)    max (ms)
  ---------- ------ ------------ -------------- ------ ----------- ----------
  static     main   4.02..5.36   0.364..0.404   -      0.474..0.58 0.88..1.17
             batch  3.30..3.95   0.337..0.354   -9.5%  0.444..0.51 0.88..1.25
  churn      main   0.69..0.88   0.382..0.476   -      0.535..0.66 0.97..1.23
             batch  0.62..0.82   0.399..0.409   -3.4%  0.649..0.66 0.92..1.06
  many       main   8.01..9.78   2.042..2.085   -      2.485..2.62 2.70..3.63
             batch  7.37..7.72   1.804..1.882   -11.3% 2.238..2.41 2.72..3.02
  thrash     main   25.50..26.91 27.375..27.804 -      30.08..30.3 31.0..32.4
             batch  26.14..26.74 25.193..27.120 -4.6%  29.46..29.8 29.7..37.5
  multicolor main   1.46..1.63   0.361..0.399   -      0.408..0.51 0.47..1.00
             batch  1.34..1.57   0.327..0.335   -12.5% 0.396..0.44 0.60..1.01
  cjk-mix    main   2.92..3.13   0.522..0.539   -      0.683..0.74 0.89..1.20
             batch  3.03..3.17   0.499..0.562   -0.7%  0.630..0.88 1.38..1.43
  cjk-many   main   44.39..45.49 2.338..2.637   -      2.544..3.76 3.58..4.94
             batch  43.88..45.79 2.219..2.356   -7.2%  2.857..3.43 3.33..4.27
```

Three-run arithmetic means of `avg` (`main` -> `cross-label-text-batching`):
- `static`: `0.383 ms` -> `0.346 ms` (`-9.5%`)
- `churn`: `0.417 ms` -> `0.403 ms` (`-3.4%`)
- `many`: `2.068 ms` -> `1.835 ms` (`-11.3%`)
- `thrash`: `27.544 ms` -> `26.283 ms` (`-4.6%`)
- `multicolor`: `0.377 ms` -> `0.330 ms` (`-12.5%`)
- `cjk-mix`: `0.532 ms` -> `0.529 ms` (`-0.7%`)
- `cjk-many`: `2.446 ms` -> `2.271 ms` (`-7.2%`)

## Memory & Texture Comparison

Deltas are in `KiB` relative to each scenario's baseline (ranges across the
3 runs where values varied), plus absolute process peak RSS (`VmHWM`).

```
  scenario    branch  rss end       after GC rss  gc used (end/GC) malloc
  ----------  ------  ------------  ------------  ---------------- ---------
  static      main    +9144..9212   +9208..9276   +2135 / +1305    +1295..97
              batch   +7160..7168   +7224..7272   +1271 / +441     +1301..14
  churn       main    +1116..1120   +1116..1120   +1181 / +1098    +18..19
              batch   +2224         +2224..2228   +1181 / +1098    +6
  many        main    +5392..5436   +5392..5436   +1991 / +1896    +40..46
              batch   +1364         +1364         +1401 / +872     +34..35
  thrash      main    +19128..19204 +19128..19208 +4151 / +2216    +459..467
              batch   +16404..17504 +16404..17504 +12897 / +2217   +368..370
  multicolor  main    +348          +348          +5074 / -3838    +2..3
              batch   +0..232       +0..232       +5074 / -3838    +1
  cjk-mix     main    +7348..7616   +7348..7616   +13718 / +1224   +4781..83
              batch   +8584..8588   +8584..8588   +13718 / +1224   +4795..97
  cjk-many    main    +1628         +1628         +5018 / -2602    +1289..92
              batch   +3500..3560   +3500..3560   +208 / -2602     +1289
```

`gc free` delta at end, absolute process peak RSS (`VmHWM`), and GL texture
deltas (identical across all 3 runs on both branches):

```
  scenario    branch  gc free (KiB)  peak RSS (KiB)    gl textures (end)
  ----------  ------  -------------  ----------------  ------------------
  static      main    +1961          102968..103148    +1 / +1.00 MiB
              batch   +2825          100908..100996    +1 / +1.00 MiB
  churn       main    -1181          104152..104328    +1 / +1.00 MiB
              batch   -1181          103216..103284    +1 / +1.00 MiB
  many        main    +5177          109588..109724    +1 / +1.00 MiB
              batch   -1401          104580..104652    +1 / +1.00 MiB
  thrash      main    +19400         128716..128928    +1 / +1.00 MiB
              batch   +4511          121056..122084    +1 / +1.00 MiB
  multicolor  main    -5074          129064..129280    +1 / +1.00 MiB
              batch   -5074          121248..122084    +1 / +1.00 MiB
  cjk-mix     main    -13718         138364..138536    +1 / +1.00 MiB
              batch   -406           132512..132588    +1 / +1.00 MiB
  cjk-many    main    -5018          139992..140164    +1 / +4.00 MiB
              batch   -208           136016..136148    +1 / +4.00 MiB
```

## Rendering Fidelity

Output pixel counts and bounding boxes were identical across all 3 runs of
both branches:

```
  check          measure      lit pixels  x range
  -------------  -----------  ----------  ---------
  default-mixed  200.0x18.0   633         [11..209]
  cjk-mixed      221.0x21.0   1142        [11..230]
  cjk-latin      92.0x21.0    372         [10..101]
```

## Key Findings & Analysis

- **Consistent frame-time gains with `b_ndebug=false`**: Because
  `debugoptimized` leaves `b_ndebug=false`, contracts and asserts stay active.
  Replacing per-glyph `ReusableArray.push` (`invariant` + `move`) with a
  fixed `TextVertex[]` buffer, per-run checks, and 20-byte `ubyte[4]` color
  vertices reduces 3-run mean frame times across every scenario: `-12.5%` on
  `multicolor`, `-11.3%` on `many`, `-9.5%` on `static`, `-7.2%` on
  `cjk-many`, `-4.6%` on `thrash`, `-3.4%` on `churn`, and `-0.7%` on
  `cjk-mix` (noise-level overlap on `cjk-mix` and `churn`).
- **Tail latency in `thrash`**: Mean `thrash` time improved (`26.28 ms` vs
  `27.54 ms`) and `p95` was slightly lower (`29.46..29.77 ms` vs
  `30.08..30.34 ms`), while one run on the branch hit a `37.54 ms` max
  frame (compared to `31.01..32.41 ms` on `main`).
- **Substantial memory reduction in `static`, `many`, and `thrash`**:
  Capping the batch at 2048 quads (160 KiB CPU buffer instead of doubling
  up to 2 MiB) cuts `static` RSS delta by `~2.0 MiB` (`+7.2` vs `+9.2 MiB`),
  `many` RSS delta by `~4.0 MiB` (`+1.4` vs `+5.4 MiB`, eliminating the
  `+5177 KiB` `gc free` bloat), and `thrash` RSS delta by `1.7..2.8 MiB`
  (`+16.4..17.5` vs `+19.1..19.2 MiB`, `gc free` `+4511` vs `+19400 KiB`).
  Post-GC live `gc used` drops by `864 KiB` in `static` and `1024 KiB` in
  `many`.
- **Why `cjk-mix` / `cjk-many` deltas look higher while peak RSS is lower**:
  Although per-scenario RSS deltas in `churn`, `cjk-mix`, and `cjk-many`
  are `+1.1..+1.9 MiB` larger on the branch, absolute process peak RSS
  (`VmHWM`) is lower on the branch at every single stage, ending at
  `136.0..136.1 MiB` vs `140.0..140.2 MiB` (`-4.0 MiB`). On `main`, the GC
  heap had already expanded by `+19.4 MiB` `gc free` during `many`/`thrash`,
  so `cjk-mix` reused that pre-expanded pool (`gc used +13718 / free -13718`);
  on the branch, the heap stayed compact through `many`/`thrash`, so
  `cjk-mix` expanded the GC pool (`free -406 KiB`) when first caching CJK
  runs.
- **GL texture usage unchanged**: Both branches use identical atlas sizes
  (`1.00 MiB` for Latin/mixed scenarios, `4.00 MiB` for `cjk-many`).

## Caveats

- Measurements were taken on a single desktop GPU/driver in sequential
  blocks (3 `main` runs, then 3 branch runs), not interleaved.
- `textbench` calls `glFinish()` every frame, so frame timings include full
  GPU/driver synchronization latency rather than steady-state swap behavior.
- `debugoptimized` keeps `b_ndebug=false`, so D `in`/`invariant`/`assert`
  checks remain enabled in both binaries.
