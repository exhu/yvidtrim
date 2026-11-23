# Canvas ph02: stroker (CPU only)

Overview: [canvas.md](canvas.md). Read `AGENTS.md` and `codestyle.md` first.

## Context
- ph01 added `render/canvas.d`: `Path2d`, `Transform2d`, `LineCap`,
  `LineJoin` and `LineDash` (`segments`, `isSolid`, `period`).
- It also added `render/internal/path_flatten.d`: `Contours` (`points`,
  `infos` of `ContourInfo{start, count, closed}`), `flattenPath` and
  `flattenTolerance`.
- The stroker turns flattened contours into triangles (x, y float pairs,
  3 vertices each) in path-local space. Canvas (ph03) transforms them and
  draws with `ColorPipeline.drawArrays(GL_TRIANGLES, ...)`.

## Steps
1. Add `render/internal/path_stroker.d` (`package(yguilib):`):
   ```
   struct StrokeParams {
     float width = 1; LineCap cap = LineCap.butt;
     LineJoin join = LineJoin.miter; float miterLimit = 10;
     const(float)[] dash; float dashOffset = 0;
     float tolerance = 0.25f; // for round caps/joins tessellation
   }
   void strokeContours(ref const Contours c, in StrokeParams p,
     ref Appender!(float[]) tris)
   ```
2. Dashing comes first. `applyDash(contours, dash, offset) -> Contours`
   splits each contour into open sub-contours along its arc length.
   - The offset is taken modulo the period. A negative offset is wrapped.
   - A closed contour is dashed across its closing segment.
   - If the contour starts and ends "on", merge the first and last dash so
     there's no false cap at the seam.
3. Segments: each segment is a quad of half-width `w/2` along the normal.
4. Joins at interior vertices, and at the start/end vertex of closed
   contours, go on the outer side of the turn:
   - bevel: triangle `(p, p+n0, p+n1)`;
   - miter: when `1/sin(θ/2) <= miterLimit`, add the miter tip triangles,
     otherwise fall back to bevel;
   - round: a fan with the segment count from the tolerance,
     `n = ceil(angle / (2*acos(1 - tol/r)))`, at least 1.
   - Skip the join for collinear segments, |cross| < eps with dot > 0. A
     180° reversal gets a bevel (and round still works).
5. Caps on open contours: butt adds nothing, square extends by `w/2`, and
   round adds a half-disc fan.
6. A degenerate contour (all points equal) with round or square caps draws a
   dot or square of size `w`, as in the spec. With butt caps it draws
   nothing. Width ≤ 0 or non-finite draws nothing.
7. Add the module to `yguilib_src` in `yguilib/meson.build`.

Overlapping triangles are allowed: ph03 uses a stencil "draw once" pass, so
alpha isn't double-blended.

## Unit tests
Use a helper that computes the triangle bounding box and total area, and a
point-in-any-triangle test.
- Horizontal line (0,0)→(100,0), w=10:
  - butt: bbox [0,100]x[-5,5], area ≈ 1000;
  - square: bbox [-5,105];
  - round: bbox ≈ [-5,105], with area between square and butt.
- L-shape (0,0)→(100,0)→(100,100), w=10:
  - miter covers the point (104,-4);
  - bevel doesn't cover it;
  - round covers (103,-3) but not (104.9,-4.9).
- Sharp angle (~10°) with the default miterLimit falls back to bevel: the tip
  point beyond the bevel isn't covered.
- Dash [10,10] on the 100-long line gives 5 dashes. Points at x=5 are
  covered and x=15 aren't. With offset 5, x=2 is covered and x=7 isn't.
- Closed square contour: all 4 corners have joins, there are no caps, and
  the area is ≈ the ring area.
- Zero width, an empty contour, and a dot with round cap (covers the center).

## Done when
`ninja -C _build && meson test -C _build` passes, and no line exceeds 80
columns.
