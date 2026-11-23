# Phase 2: Full SVG `Path2d` Parser (`yguilib`)

Overview: [canvas-helpers-gamepad.md](canvas-helpers-gamepad.md).

## Goal
Implement full W3C SVG path data string decoding (`Path2d.fromSvgPath`,
`Path2d.addSvgPath`) with an internal zero-allocation parser and GL tests.

## Files & Steps

### 1. `yguilib/source/yguilib/render/canvas/path2d.d`
- Update `Path2d` doc comment (note SVG path string support via
  `fromSvgPath` and `addSvgPath`).
- Add public methods on `Path2d`:
  - `static Path2d fromSvgPath(string d) nothrow @safe`: creates
    `auto p = new Path2d(); p.addSvgPath(d); return p;`.
  - `bool addSvgPath(string d) nothrow @safe`: calls `parseSvgPathInto(this, d)`.
- Add `package(yguilib):` struct `SvgArcParams`:
  ```d
  struct SvgArcParams {
    PointF center;
    PointF radii;
    float rotation = 0;
    float startAngle = 0;
    float sweep = 0;
    PointF endPoint;
  }
  ```
  and method `void appendSvgArc(in SvgArcParams arc) nothrow @safe` on `Path2d`:
  - Emits cubic Bezier segments of at most 90 deg directly from the current
    point (without inserting a redundant `lineTo(start)`), using the same
    `4.0 / 3.0 * tan(step / 4)` formula as `appendArc`, snapping the final
    cubic segment's endpoint exactly to `arc.endPoint`.
  - If `arc.sweep == 0`, return without emitting curves.
  - Keep helper functions <= ~50 lines and <= 5 parameters per `codestyle.md`.
- Add a warmed-up GC zero-allocation `unittest` verifying
  `p.clear(); p.addSvgPath(...)` (including curves and arcs) allocates 0 bytes
  over 100 iterations.

### 2. `yguilib/source/yguilib/render/internal/svg_path_parser.d` (NEW)
- Module `yguilib.render.internal.svg_path_parser;`
- Top-level `package(yguilib):` (NEVER `public:`).
- `bool parseSvgPathInto(Path2d path, string d) nothrow @safe`:
  - `assert(path !is null);`
  - Zero-allocation `private struct SvgScanner` over `string d` + `size_t pos`:
    - Whitespace: `' '`, `'\t'`, `'\n'`, `'\r'`, `'\f'`.
    - `skipWsp()`, `skipCommaWsp()` (consumes wsp, optional single `','`, wsp;
      rejects double comma `,,`; no comma allowed before first argument of a
      command or before a command letter).
    - `readNumber()` -> `Nullable!float`: parses optional `[+-]`, digits /
      decimal (`digits(.digits)?` or `.digits`), optional `[eE][+-]?digits`.
      Handles compact adjacent tokens (`M10-20`, `L.5.5`, `1.2.3`, `1e-2-3`).
      Rejects non-finite overflow.
    - `readFlag()` -> `Nullable!bool`: strictly consumes `'0'` or `'1'` (no
      separator required before next flag or number, e.g. `0120`).
  - Parser state: `PointF cur`, `PointF start`, `bool hasSubpath`,
    `bool hasInitialCmd`, `char prevCmd`, `PointF lastCubicCp`,
    `PointF lastQuadCp`.
  - Grammar rules:
    - Empty / whitespace-only `d` returns `true`.
    - First non-whitespace token must be `'M'` or `'m'`; else return `false`.
    - `M`/`m`: first pair -> `moveTo` (for initial `m` when `!hasInitialCmd`,
      treat first pair as absolute from `(0, 0)`; for subsequent `m`, relative
      to `cur`). Subsequent implicit pairs act as `L` (after `M`) or `l`
      (after `m`).
    - `Z`/`z`: `path.closePath()`, `cur = start`.
    - `L`/`l`, `H`/`h`, `V`/`v`: `path.lineTo(...)`.
    - `C`/`c`: `path.bezierCurveTo(cp1, cp2, end)`, `lastCubicCp = cp2`.
    - `S`/`s`: `cp1 = (prevCmd is C/c/S/s) ? PointF(2*cur.x - lastCubicCp.x,
      2*cur.y - lastCubicCp.y) : cur`; `path.bezierCurveTo(cp1, cp2, end)`;
      `lastCubicCp = cp2`.
    - `Q`/`q`: `path.quadraticCurveTo(cp, end)`, `lastQuadCp = cp`.
    - `T`/`t`: `cp = (prevCmd is Q/q/T/t) ? PointF(2*cur.x - lastQuadCp.x,
      2*cur.y - lastQuadCp.y) : cur`; `path.quadraticCurveTo(cp, end)`;
      `lastQuadCp = cp`.
    - `A`/`a`: `(rx, ry, xAxisRotDeg, largeArc, sweep, x, y)+` via W3C SVG
      F.6.5/F.6.6 endpoint-to-center parameterization:
      - If `end == cur`: skip.
      - If `rx == 0 || ry == 0`: `path.lineTo(end)`.
      - `rx = abs(rx); ry = abs(ry);`
      - Rotate midpoint `(dx2, dy2)` by `-phi` (`phi = xAxisRotDeg * PI / 180`).
      - Upscale `rx, ry` by `sqrt(lambda)` if
        `lambda = x1p^2/rx^2 + y1p^2/ry^2 > 1`.
      - Center `(cxp, cyp)` with sign `(largeArc == sweep) ? -1.0 : 1.0` and
        radicand clamped `>= 0`; rotate center back to `(cx, cy)`.
      - Compute `theta1` and `dtheta` with `atan2(uy, ux)` difference; adjust
        `dtheta` so `!sweep => dtheta <= 0` and `sweep => dtheta >= 0`.
      - Call `path.appendSvgArc(SvgArcParams(...))`.
    - On any syntax error, stop immediately, keep already-emitted commands,
      and return `false`.
  - Split into clean private helper functions (each <= ~50 lines).
  - Add extensive `unittest` blocks covering empty strings, all commands
    `M/m/L/l/H/h/V/v/C/c/S/s/Q/q/T/t/A/a/Z/z`, implicit repeats, smooth
    reflections, compact syntax, scientific notation, all 4 `(largeArc, sweep)`
    arc cases + rotated/degenerate arcs, error handling, and the exact
    gamepad bumper & body SVG strings from
    `documentation/gamepad-canvas-by-gemini.html`.

### 3. `yguilib/source/yguilib/render/canvas/package_test.d`
- Add a GL rendering `unittest` (with `scope(exit) w.destroy();` and
  `scope(exit) w.endTargets();`) drawing a path built with `Path2d.fromSvgPath`
  (including a cubic curve and SVG arc) filled with
  `FillStyle.solidFromString("#2b3140")` and stroked with
  `StrokeStyle.solidFromString("#ef4444")`, verifying pixels with `isRgb`
  and `glGetError() == GL_NO_ERROR`.

### 4. `yguilib/meson.build`
- Add `'source/yguilib/render/internal/svg_path_parser.d'` in alphabetical
  order inside `yguilib_src`.

## Verification
```bash
ninja -C _build && timeout 300 meson test -C _build
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
```
