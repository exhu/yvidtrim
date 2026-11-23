# Canvas ph01: types, Path2d, flattening (CPU only)

Overview: [canvas.md](canvas.md). Read `AGENTS.md` and `codestyle.md` first:
2-space indent, 80 cols, `{` on the same line, and getters/setters named
`name()` / `name(v)`.

## Context
- `yguilib/source/yguilib/render/canvas.d` is a stub. It is NOT in
  `yguilib/meson.build` `yguilib_src`, but `render/package.d` already does
  `import yguilib.render.canvas` and `new Canvas()`.
- Existing types are in `render/render_types.d`: `PointF`, `RectF` and
  `ColorF`. Reuse them. Keep the existing comments and docstrings in
  `canvas.d`, updating TODO comments once they're resolved.
- Canvas-only public types are declared in `canvas.d`, and internals go in
  `render/internal/*.d` with `package(yguilib):`.

## Steps
1. In `canvas.d`, add:
   - `struct Transform2d { float a = 1, b = 0, c = 0, d = 1, e = 0, f = 0; }`.
     This is an affine `[a c e; b d f]` matrix, as in DOMMatrix. Give it:
     - `static identity()`, `translation(PointF)`, `rotation(float rad)` and
       `scaling(PointF)`;
     - `opBinary!"*"` (`this * rhs`, so rhs is applied first);
     - `PointF apply(PointF) const`;
     - `Transform2d inverse() const` (returns identity when singular);
     - `bool isIdentity() const`;
     - `float maxScale() const`, the largest singular value, used for the
       flattening tolerance.
     Mark everything `nothrow @safe @nogc` where possible.
2. Implement `final class Path2d`:
   - Storage: `enum PathVerb : ubyte { moveTo, lineTo, quadTo, cubicTo,
     close }`, a `PathVerb[] verbs` and a `PointF[] points`. These are
     `package(yguilib)` read accessors for the flattener.
   - API, following MDN Path2D semantics:
     - `moveTo(PointF)` and `lineTo(PointF)`, where `lineTo` on an empty
       subpath acts as `moveTo`;
     - `quadraticCurveTo(PointF cp, PointF p)` and
       `bezierCurveTo(PointF cp1, PointF cp2, PointF p)`;
     - `arc(PointF center, float radius, float startAngle, float endAngle,
       bool counterclockwise = false)`;
     - `arcTo(PointF p1, PointF p2, float radius)`;
     - `ellipse(PointF center, PointF radii, float rotation, float
       startAngle, float endAngle, bool counterclockwise = false)`;
     - `rect(RectF)` and `roundRect(RectF, float radius)` (radius clamped to
       half the smaller side);
     - `closePath()`, `addPath(Path2d other, Transform2d t =
       Transform2d.identity)`, `clear()`, `bool isEmpty() const` and
       `RectF bounds() const` (control-point hull is fine).
   - Arcs and ellipses become at most 90° cubic Bézier segments when they're
     added (`k = 4/3*tan(θ/4)`). If a subpath exists, the arc start is
     connected with `lineTo`, as in the spec. Angle sweeps are normalized as
     in the spec (full circle when |sweep| ≥ 2π).
   - Negative radii are ignored (MDN throws, but we no-op and keep state).
     Non-finite inputs are ignored.
3. Fill in the remaining types:
   - `LineDash { float[] segments; }` with
     `static LineDash fromSegments(const float[])`. That duplicates an odd
     count and returns an empty dash if any value is negative or non-finite.
     Add `bool isSolid() const` and `float period() const`.
   - `GradientStop { float offset; ColorF color; }` and
     `enum maxGradientStops = 8`.
   - `LinearGradient { PointF p0, p1; GradientStop[maxGradientStops] stops;
     ubyte stopCount; ref LinearGradient addColorStop(float offset, ColorF
     c); }`. Offsets are clamped to [0, 1] and kept sorted (stable). Extra
     stops are ignored.
   - `RadialGradient { PointF c0; float r0; PointF c1; float r1; ...same
     stops API }`. Share the stop storage through a small
     `struct GradientStops` used by both.
   - `Pattern`: keep it empty, with its TODO comment.
   - `FillStyle { enum Kind { color, linearGradient, radialGradient } Kind
     kind; ColorF color = ColorF(0,0,0,1); LinearGradient linear;
     RadialGradient radial; }`, with the factories `solid(ColorF)`,
     `fromLinear(in LinearGradient)` and `fromRadial(in RadialGradient)`.
   - Keep `alias StrokeStyle = FillStyle;` and replace its TODO comment with
     a note that no difference is needed.
   - `Shadow { PointF offset; float blur = 0; ColorF color =
     ColorF(0,0,0,0); bool isVisible() const; }` (implemented in ph06).
4. Keep the `Canvas` method declarations, but give them bodies that do
   nothing for now. Add a comment that ph03 implements them. They must not
   assert, because `Renderer` constructs a Canvas.
5. Add `render/internal/path_flatten.d`:
   ```
   struct ContourInfo { size_t start; size_t count; bool closed; }
   struct Contours { Appender!(PointF[]) points;
     Appender!(ContourInfo[]) infos; void clear(); }
   void flattenPath(const Path2d p, float tolerance, ref Contours out)
   float flattenTolerance(float totalScaling, in Transform2d t)
     // = 0.25f / max(totalScaling * t.maxScale(), 1e-6f)
   ```
   - Curve subdivision uses Wang's formula,
     `n = ceil(sqrt(sqrt(dd) * 3/4 / tol))` for cubics (quads use 1/4),
     clamped to [1, 256].
   - Drop consecutive duplicate points and contours with fewer than 2 points.
   - `closePath` marks the contour as closed. A following verb that isn't
     `moveTo` starts a new contour at the last moveTo point.
6. Add `canvas.d` and `internal/path_flatten.d` to `yguilib_src` in
   `yguilib/meson.build`, keeping alphabetical order.

## Unit tests (in the modules; they run via `meson test`)
- Transform: multiplication order, `apply`, `inverse * t ≈ identity`, and
  `maxScale` of `scaling(2, 3)` == 3.
- Path2d:
  - `rect` gives 4 points and a close;
  - `arc` of a full circle starts and ends at the same point, with 4 cubics;
  - a ccw half arc;
  - `arcTo` tangent points for a right angle;
  - `lineTo` with no subpath acting as `moveTo`;
  - `addPath` with a translation shifting points;
  - `bounds`.
- Flatten:
  - every point of a flattened r=100 circle at tolerance 0.25 lies within
    [99.7, 100.0] of the center, and the contour is closed;
  - a line path stays 2 points;
  - an empty path gives 0 contours;
  - a tighter tolerance gives more points.
- LineDash odd duplication and invalid inputs, and gradient stop sorting,
  clamping and overflow.

## Done when
`ninja -C _build && meson test -C _build` passes, and no line exceeds 80
columns.
