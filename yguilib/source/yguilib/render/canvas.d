/** 2d drawing api similar to HTML canvas 2d api or svg. Reduced in features,
    simplified, uses float, int and other efficient types.
    https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial

    A radial gradient with a negative radius, or a negative path radius, draws
    nothing instead of raising an error.

    Square caps on zero-length segments: they stay axis-aligned instead of
    rotating with the path, which shows on diagonal lines.
*/
module yguilib.render.canvas;
import std.array : Appender;
import yguilib.render : Renderer;
import yguilib.render.internal.path_flatten : Contours;
import yguilib.render.internal.pipelines : GradientUniforms;
import yguilib.render.render_types;

// Types that are only used with Canvas are declared here.

/**
 * Affine 2d transform `[a c e; b d f]` (same layout as DOMMatrix).
 * Maps `(x, y)` to `(a*x + c*y + e, b*x + d*y + f)`.
 */
struct Transform2d {
  float a = 1;
  float b = 0;
  float c = 0;
  float d = 1;
  float e = 0;
  float f = 0;

  /// The identity transform.
  static Transform2d identity() nothrow @safe @nogc pure {
    return Transform2d.init;
  }

  /// Translation by `offset`.
  static Transform2d translation(PointF offset) nothrow @safe @nogc pure {
    return Transform2d(1, 0, 0, 1, offset.x, offset.y);
  }

  /// Rotation by `rad` radians (positive is clockwise with y down).
  static Transform2d rotation(float rad) nothrow @safe @nogc pure {
    import std.math : cos, sin;

    const float cs = cos(rad);
    const float sn = sin(rad);
    return Transform2d(cs, sn, -sn, cs, 0, 0);
  }

  /// Scaling by `factor` per axis (negative mirrors).
  static Transform2d scaling(PointF factor) nothrow @safe @nogc pure {
    return Transform2d(factor.x, 0, 0, factor.y, 0, 0);
  }

  /// `this * rhs`: `rhs` is applied first, then `this`.
  Transform2d opBinary(string op : "*")(in Transform2d rhs)
    const nothrow @safe @nogc pure {
    return Transform2d(
      a * rhs.a + c * rhs.b,
      b * rhs.a + d * rhs.b,
      a * rhs.c + c * rhs.d,
      b * rhs.c + d * rhs.d,
      a * rhs.e + c * rhs.f + e,
      b * rhs.e + d * rhs.f + f
    );
  }

  /// Transforms point `p`.
  PointF apply(PointF p) const nothrow @safe @nogc pure {
    return PointF(a * p.x + c * p.y + e, b * p.x + d * p.y + f);
  }

  /// Inverse transform; returns identity when the matrix is singular.
  Transform2d inverse() const nothrow @safe @nogc pure {
    import std.math : abs, isFinite;

    const float det = a * d - b * c;
    if (!isFinite(det) || abs(det) < 1e-12f) {
      return Transform2d.identity();
    }
    const float inv = 1.0f / det;
    return Transform2d(
      d * inv,
      -b * inv,
      -c * inv,
      a * inv,
      (c * f - d * e) * inv,
      (b * e - a * f) * inv
    );
  }

  /// True when this is exactly the identity transform.
  bool isIdentity() const nothrow @safe @nogc pure {
    return a == 1 && b == 0 && c == 0 && d == 1 && e == 0 && f == 0;
  }

  /// Largest singular value of the linear part (max stretch factor).
  float maxScale() const nothrow @safe @nogc pure {
    import std.math : sqrt;

    const float s = a * a + b * b + c * c + d * d;
    const float det = a * d - b * c;
    float disc = s * s - 4 * det * det;
    if (disc < 0) {
      disc = 0;
    }
    return sqrt((s + sqrt(disc)) * 0.5f);
  }
}

// Transform2d
unittest {
  import std.math : isClose, PI;

  bool near(PointF p, PointF q) {
    return isClose(p.x, q.x, 1e-5, 1e-5) && isClose(p.y, q.y, 1e-5, 1e-5);
  }

  const t = Transform2d.translation(PointF(10, 0));
  const s = Transform2d.scaling(PointF(2, 2));
  // rhs applied first: scale then translate
  assert(near((t * s).apply(PointF(1, 1)), PointF(12, 2)));
  // translate then scale
  assert(near((s * t).apply(PointF(1, 1)), PointF(22, 2)));

  const r = Transform2d.rotation(cast(float) PI / 2);
  assert(near(r.apply(PointF(1, 0)), PointF(0, 1)));

  const m = t * r * Transform2d.scaling(PointF(3, -0.5f));
  const id = m.inverse() * m;
  assert(near(id.apply(PointF(7, -3)), PointF(7, -3)));
  assert(isClose(id.a, 1, 1e-5) && isClose(id.d, 1, 1e-5));
  assert(isClose(id.b + 1, 1, 1e-5) && isClose(id.c + 1, 1, 1e-5));

  assert(Transform2d.identity().isIdentity());
  assert(!t.isIdentity());
  assert(Transform2d.scaling(PointF(0, 0)).inverse().isIdentity());

  assert(isClose(Transform2d.scaling(PointF(2, 3)).maxScale(), 3.0f));
  assert(isClose((r * Transform2d.scaling(PointF(-4, 1))).maxScale(), 4.0f));
}

/// Path command stored in `Path2d`.
enum PathVerb : ubyte {
  moveTo,
  lineTo,
  quadTo,
  cubicTo,
  close,
}

/// Number of points stored for each `PathVerb`.
size_t pointCountOfVerb(PathVerb v) nothrow @safe @nogc pure {
  final switch (v) {
  case PathVerb.moveTo:
    return 1;
  case PathVerb.lineTo:
    return 1;
  case PathVerb.quadTo:
    return 2;
  case PathVerb.cubicTo:
    return 3;
  case PathVerb.close:
    return 0;
  }
}

/**
 * Similar to Canvas web API Path2D (MDN semantics), but without text
 * strings; uses float for coords and angles (radians).
 * Arcs and ellipses are stored as cubic Bézier segments of at most 90°.
 * Negative radii and non-finite inputs are ignored (no-op).
 */
final class Path2d {
  /// Starts a new subpath at `p`.
  void moveTo(PointF p) nothrow @safe {
    if (!finite(p)) {
      return;
    }
    fVerbs ~= PathVerb.moveTo;
    fPoints ~= p;
    fHasSubpath = true;
    fSubpathStart = p;
    fCurrent = p;
  }

  /// Line to `p`; acts as `moveTo` when there is no subpath.
  void lineTo(PointF p) nothrow @safe {
    if (!finite(p)) {
      return;
    }
    if (!fHasSubpath) {
      moveTo(p);
      return;
    }
    ensureMoveAfterClose();
    fVerbs ~= PathVerb.lineTo;
    fPoints ~= p;
    fCurrent = p;
  }

  /// Quadratic Bézier with control point `cp` ending at `p`.
  void quadraticCurveTo(PointF cp, PointF p) nothrow @safe {
    if (!finite(cp) || !finite(p)) {
      return;
    }
    ensureSubpath(cp);
    fVerbs ~= PathVerb.quadTo;
    fPoints ~= cp;
    fPoints ~= p;
    fCurrent = p;
  }

  /// Cubic Bézier with control points `cp1`, `cp2` ending at `p`.
  void bezierCurveTo(PointF cp1, PointF cp2, PointF p) nothrow @safe {
    if (!finite(cp1) || !finite(cp2) || !finite(p)) {
      return;
    }
    ensureSubpath(cp1);
    fVerbs ~= PathVerb.cubicTo;
    fPoints ~= cp1;
    fPoints ~= cp2;
    fPoints ~= p;
    fCurrent = p;
  }

  /**
   * Circular arc around `center`. Angles are in radians from the +x axis.
   * Connects from the current point with a line if a subpath exists.
   */
  void arc(
    PointF center,
    float radius,
    float startAngle,
    float endAngle,
    bool counterclockwise
  ) nothrow @safe {
    ellipse(
      center, PointF(radius, radius), 0, startAngle, endAngle,
      counterclockwise
    );
  }

  /**
   * Arc of radius `radius` tangent to lines (current, p1) and (p1, p2).
   * Degenerate cases (coincident points, collinear, zero radius) add a line
   * to `p1`.
   */
  void arcTo(PointF p1, PointF p2, float radius) nothrow @safe {
    import std.math : abs, acos, atan2, isFinite, PI, sqrt, tan, sin;

    if (!finite(p1) || !finite(p2) || !isFinite(radius) || radius < 0) {
      return;
    }
    ensureSubpath(p1);
    const PointF p0 = fCurrent;
    const float v1x = p0.x - p1.x;
    const float v1y = p0.y - p1.y;
    const float v2x = p2.x - p1.x;
    const float v2y = p2.y - p1.y;
    const float l1 = sqrt(v1x * v1x + v1y * v1y);
    const float l2 = sqrt(v2x * v2x + v2y * v2y);
    const float cross = v1x * v2y - v1y * v2x;
    if (radius == 0 || l1 == 0 || l2 == 0
        || abs(cross) <= 1e-6f * l1 * l2) {
      lineTo(p1);
      return;
    }
    const PointF u1 = PointF(v1x / l1, v1y / l1);
    const PointF u2 = PointF(v2x / l2, v2y / l2);
    float cosA = u1.x * u2.x + u1.y * u2.y;
    cosA = cosA > 1 ? 1 : (cosA < -1 ? -1 : cosA);
    const float half = acos(cosA) * 0.5f;
    const float dist = radius / tan(half);
    const PointF t1 = PointF(p1.x + u1.x * dist, p1.y + u1.y * dist);
    const PointF t2 = PointF(p1.x + u2.x * dist, p1.y + u2.y * dist);
    float bx = u1.x + u2.x;
    float by = u1.y + u2.y;
    const float bl = sqrt(bx * bx + by * by);
    bx /= bl;
    by /= bl;
    const float cd = radius / sin(half);
    const PointF c = PointF(p1.x + bx * cd, p1.y + by * cd);
    const float a0 = atan2(t1.y - c.y, t1.x - c.x);
    const float a1 = atan2(t2.y - c.y, t2.x - c.x);
    float sweep = a1 - a0;
    if (sweep > PI) {
      sweep -= 2 * PI;
    } else if (sweep < -PI) {
      sweep += 2 * PI;
    }
    appendArc(c, PointF(radius, radius), 0, a0, sweep);
  }

  /**
   * Elliptical arc around `center` with `radii`, rotated by `rotation`
   * radians. Sweeps are normalized as in the HTML spec (full ellipse when
   * the sweep in the given direction is at least 2π).
   */
  void ellipse(
    PointF center,
    PointF radii,
    float rotation,
    float startAngle,
    float endAngle,
    bool counterclockwise
  ) nothrow @safe {
    import std.math : fmod, isFinite, PI;

    if (!finite(center) || !finite(radii) || !isFinite(rotation)
        || !isFinite(startAngle) || !isFinite(endAngle)) {
      return;
    }
    if (radii.x < 0 || radii.y < 0) {
      return;
    }
    const float tau = 2 * PI;
    float sweep = endAngle - startAngle;
    if (!counterclockwise) {
      if (sweep >= tau) {
        sweep = tau;
      } else {
        sweep = fmod(sweep, tau);
        if (sweep < 0) {
          sweep += tau;
        }
      }
    } else {
      if (sweep <= -tau) {
        sweep = -tau;
      } else {
        sweep = fmod(sweep, tau);
        if (sweep > 0) {
          sweep -= tau;
        }
      }
    }
    appendArc(center, radii, rotation, startAngle, sweep);
  }

  /// Closed rectangle subpath; a new subpath then starts at `r.x, r.y`.
  void rect(RectF r) nothrow @safe {
    if (!finiteRect(r)) {
      return;
    }
    moveTo(PointF(r.x, r.y));
    lineTo(PointF(r.x + r.width, r.y));
    lineTo(PointF(r.x + r.width, r.y + r.height));
    lineTo(PointF(r.x, r.y + r.height));
    closePath();
  }

  /**
   * Closed rounded rectangle subpath with the same `radius` for all
   * corners, clamped to half the smaller side. Negative radius is ignored.
   * A new subpath then starts at `r.x, r.y`.
   */
  void roundRect(RectF r, float radius) nothrow @safe {
    import std.math : abs, isFinite;

    if (!finiteRect(r) || !isFinite(radius) || radius < 0) {
      return;
    }
    const float maxR = 0.5f * (abs(r.width) < abs(r.height)
      ? abs(r.width) : abs(r.height));
    const float rad = radius < maxR ? radius : maxR;
    if (rad == 0) {
      rect(r);
      return;
    }
    // signs keep the winding direction of negative-size rects
    const float sx = r.width < 0 ? -rad : rad;
    const float sy = r.height < 0 ? -rad : rad;
    const float x0 = r.x;
    const float y0 = r.y;
    const float x1 = r.x + r.width;
    const float y1 = r.y + r.height;
    moveTo(PointF(x0 + sx, y0));
    lineTo(PointF(x1 - sx, y0));
    cornerTo(PointF(x1 - sx, y0), PointF(x1, y0), PointF(x1, y0 + sy));
    lineTo(PointF(x1, y1 - sy));
    cornerTo(PointF(x1, y1 - sy), PointF(x1, y1), PointF(x1 - sx, y1));
    lineTo(PointF(x0 + sx, y1));
    cornerTo(PointF(x0 + sx, y1), PointF(x0, y1), PointF(x0, y1 - sy));
    lineTo(PointF(x0, y0 + sy));
    cornerTo(PointF(x0, y0 + sy), PointF(x0, y0), PointF(x0 + sx, y0));
    closePath();
    moveTo(PointF(x0, y0));
  }

  /// Closes the current subpath; next subpath starts at its start point.
  void closePath() nothrow @safe {
    if (!fHasSubpath || fClosed) {
      return;
    }
    fVerbs ~= PathVerb.close;
    fCurrent = fSubpathStart;
    fClosed = true;
  }

  /// Appends `other` transformed by `t` (`other` may be `this`).
  void addPath(Path2d other, Transform2d t) nothrow @safe {
    assert(other !is null);
    const size_t nv = other.fVerbs.length;
    const size_t np = other.fPoints.length;
    if (nv == 0) {
      return;
    }
    const bool otherClosed = other.fClosed;
    const PointF otherStart = other.fSubpathStart;
    const PointF otherCur = other.fCurrent;
    for (size_t i = 0; i < nv; ++i) {
      fVerbs ~= other.fVerbs[i];
    }
    for (size_t i = 0; i < np; ++i) {
      fPoints ~= t.apply(other.fPoints[i]);
    }
    fHasSubpath = true;
    fClosed = otherClosed;
    fSubpathStart = t.apply(otherStart);
    fCurrent = t.apply(otherCur);
  }

  /// Removes all subpaths.
  void clear() nothrow @safe {
    fVerbs = null;
    fPoints = null;
    fHasSubpath = false;
    fClosed = false;
    fSubpathStart = PointF.init;
    fCurrent = PointF.init;
  }

  /// True when no verbs were added.
  bool isEmpty() const nothrow @safe @nogc {
    return fVerbs.length == 0;
  }

  /// Bounds of all points including control points; empty is all zeros.
  RectF bounds() const nothrow @safe @nogc {
    if (fPoints.length == 0) {
      return RectF(0, 0, 0, 0);
    }
    float x0 = fPoints[0].x;
    float y0 = fPoints[0].y;
    float x1 = x0;
    float y1 = y0;
    foreach (p; fPoints[1 .. $]) {
      x0 = p.x < x0 ? p.x : x0;
      y0 = p.y < y0 ? p.y : y0;
      x1 = p.x > x1 ? p.x : x1;
      y1 = p.y > y1 ? p.y : y1;
    }
    return RectF(x0, y0, x1 - x0, y1 - y0);
  }

package(yguilib):
  /// Stored verbs; see `pointCountOfVerb` for points per verb.
  const(PathVerb)[] verbs() const nothrow @safe @nogc {
    return fVerbs;
  }

  /// Stored points for all verbs, in order.
  const(PointF)[] points() const nothrow @safe @nogc {
    return fPoints;
  }

private:
  PathVerb[] fVerbs;
  PointF[] fPoints;
  bool fHasSubpath;
  /// true right after closePath (until the next verb)
  bool fClosed;
  PointF fSubpathStart;
  PointF fCurrent;

  static bool finite(PointF p) nothrow @safe @nogc {
    import std.math : isFinite;

    return isFinite(p.x) && isFinite(p.y);
  }

  static bool finiteRect(RectF r) nothrow @safe @nogc {
    return finite(PointF(r.x, r.y)) && finite(PointF(r.width, r.height));
  }

  void ensureSubpath(PointF p) nothrow @safe {
    if (!fHasSubpath) {
      moveTo(p);
    } else {
      ensureMoveAfterClose();
    }
  }

  /// After closePath the next segment implicitly starts at the subpath
  /// start; the flattener handles that, so only the flag is reset.
  void ensureMoveAfterClose() nothrow @safe @nogc {
    fClosed = false;
  }

  /// Quarter-ellipse corner from `p0` toward `corner` ending at `p3`.
  void cornerTo(PointF p0, PointF corner, PointF p3) nothrow @safe {
    enum float k = 0.5522847498f;
    bezierCurveTo(
      PointF(p0.x + (corner.x - p0.x) * k, p0.y + (corner.y - p0.y) * k),
      PointF(p3.x + (corner.x - p3.x) * k, p3.y + (corner.y - p3.y) * k),
      p3
    );
  }

  /**
   * Appends an elliptical arc as cubic segments of at most 90°. Connects
   * to the arc start with `lineTo` when a subpath exists.
   */
  void appendArc(
    PointF center,
    PointF radii,
    float rotation,
    float startAngle,
    float sweep
  ) nothrow @safe {
    import std.math : abs, ceil, cos, PI, sin, tan;

    const double cr = cos(cast(double) rotation);
    const double sr = sin(cast(double) rotation);
    PointF map(double ux, double uy) {
      const double x = ux * radii.x;
      const double y = uy * radii.y;
      return PointF(
        cast(float)(center.x + x * cr - y * sr),
        cast(float)(center.y + x * sr + y * cr)
      );
    }

    const double a0 = startAngle;
    const PointF start = map(cos(a0), sin(a0));
    if (fHasSubpath) {
      lineTo(start);
    } else {
      moveTo(start);
    }
    if (sweep == 0) {
      return;
    }
    const bool full = abs(sweep) >= 2 * PI - 1e-6;
    int n = cast(int) ceil(abs(sweep) / (PI / 2) - 1e-4);
    n = n < 1 ? 1 : n;
    const double step = cast(double) sweep / n;
    const double k = 4.0 / 3.0 * tan(step / 4);
    foreach (i; 0 .. n) {
      const double s0 = a0 + step * i;
      const double s1 = s0 + step;
      const double c0 = cos(s0);
      const double n0 = sin(s0);
      const double c1 = cos(s1);
      const double n1 = sin(s1);
      const PointF end = (full && i == n - 1) ? start : map(c1, n1);
      bezierCurveTo(
        map(c0 - k * n0, n0 + k * c0),
        map(c1 + k * n1, n1 - k * c1),
        end
      );
    }
  }
}

// Path2d
unittest {
  import std.math : isClose, PI;

  bool near(PointF p, PointF q) {
    return isClose(p.x, q.x, 1e-4, 1e-4) && isClose(p.y, q.y, 1e-4, 1e-4);
  }

  // rect: 4 points + close
  auto p = new Path2d();
  assert(p.isEmpty());
  p.rect(RectF(1, 2, 10, 20));
  assert(p.verbs == [
    PathVerb.moveTo, PathVerb.lineTo, PathVerb.lineTo, PathVerb.lineTo,
    PathVerb.close
  ]);
  assert(p.points.length == 4);
  assert(p.bounds() == RectF(1, 2, 10, 20));

  // full circle: moveTo + 4 cubics, ends at start
  p.clear();
  assert(p.isEmpty());
  p.arc(PointF(0, 0), 10, 0, cast(float)(2 * PI), false);
  assert(p.verbs.length == 5);
  assert(p.verbs[0] == PathVerb.moveTo);
  foreach (v; p.verbs[1 .. $]) {
    assert(v == PathVerb.cubicTo);
  }
  assert(p.points[0] == p.points[$ - 1]);
  assert(near(p.points[0], PointF(10, 0)));
  const b = p.bounds();
  assert(isClose(b.width, b.height, 1e-4) && b.width > 20);

  // ccw half arc from 0 to π passes through the top (y = -r)
  p.clear();
  p.arc(PointF(0, 0), 10, 0, cast(float) PI, true);
  assert(p.verbs.length == 3);
  assert(near(p.points[3], PointF(0, -10)));
  assert(near(p.points[$ - 1], PointF(-10, 0)));
  // cw half arc passes through y = +r
  p.clear();
  p.arc(PointF(0, 0), 10, 0, cast(float) PI, false);
  assert(near(p.points[3], PointF(0, 10)));

  // negative radius and non-finite are no-ops
  p.clear();
  p.arc(PointF(0, 0), -1, 0, 1, false);
  p.lineTo(PointF(float.nan, 0));
  assert(p.isEmpty());

  // arcTo right angle: tangent points at distance r from the corner
  p.clear();
  p.moveTo(PointF(0, 0));
  p.arcTo(PointF(10, 0), PointF(10, 10), 3);
  assert(p.verbs[0 .. 2] == [PathVerb.moveTo, PathVerb.lineTo]);
  assert(near(p.points[1], PointF(7, 0)));
  assert(near(p.points[$ - 1], PointF(10, 3)));
  assert(p.verbs[$ - 1] == PathVerb.cubicTo);
  assert(p.verbs.length == 3);
  // collinear arcTo is a line to p1
  p.clear();
  p.moveTo(PointF(0, 0));
  p.arcTo(PointF(5, 0), PointF(10, 0), 3);
  assert(p.verbs == [PathVerb.moveTo, PathVerb.lineTo]);

  // lineTo without subpath acts as moveTo
  p.clear();
  p.lineTo(PointF(3, 4));
  assert(p.verbs == [PathVerb.moveTo]);
  p.lineTo(PointF(5, 6));
  assert(p.verbs == [PathVerb.moveTo, PathVerb.lineTo]);

  // addPath with translation
  auto q = new Path2d();
  q.addPath(p, Transform2d.translation(PointF(10, 100)));
  assert(q.verbs == p.verbs);
  assert(q.points == [PointF(13, 104), PointF(15, 106)]);
  q.lineTo(PointF(0, 0));
  assert(q.verbs.length == 3);
  // addPath to itself
  p.addPath(p, Transform2d.identity());
  assert(p.points.length == 4);

  // bounds include control points
  p.clear();
  p.moveTo(PointF(0, 0));
  p.quadraticCurveTo(PointF(5, -10), PointF(10, 0));
  assert(p.bounds() == RectF(0, -10, 10, 10));
  assert(new Path2d().bounds() == RectF(0, 0, 0, 0));

  // roundRect radius clamp: 4 cubics, ends with moveTo(x, y)
  p.clear();
  p.roundRect(RectF(0, 0, 10, 4), 100);
  assert(p.bounds() == RectF(0, 0, 10, 4));
  assert(near(p.points[0], PointF(2, 0)));
  size_t cubics = 0;
  foreach (v; p.verbs) {
    cubics += v == PathVerb.cubicTo;
  }
  assert(cubics == 4);
  assert(p.verbs[$ - 2 .. $] == [PathVerb.close, PathVerb.moveTo]);

  // ellipse rotated by 90°: x radius maps to y
  p.clear();
  p.ellipse(
    PointF(0, 0), PointF(10, 2), cast(float)(PI / 2), 0, 0.1f, false
  );
  assert(near(p.points[0], PointF(0, 10)));
}

enum LineCap {
  butt,
  round,
  square,
}

enum LineJoin {
  round,
  bevel,
  miter,
}

/// Dash pattern: alternating dash/gap lengths; empty means solid.
struct LineDash {
  float[] segments;

  /**
   * Builds a dash from `src`: an odd count is duplicated, any negative or
   * non-finite value gives an empty (solid) dash.
   */
  static LineDash fromSegments(const float[] src) nothrow @safe {
    import std.math : isFinite;

    foreach (v; src) {
      if (!isFinite(v) || v < 0) {
        return LineDash.init;
      }
    }
    LineDash res;
    res.segments = src.dup;
    if (src.length % 2 == 1) {
      res.segments ~= src;
    }
    return res;
  }

  /// True when no dashing applies (empty or zero period).
  bool isSolid() const nothrow @safe @nogc {
    return segments.length == 0 || period() <= 0;
  }

  /// Sum of all segment lengths.
  float period() const nothrow @safe @nogc {
    float sum = 0;
    foreach (v; segments) {
      sum += v;
    }
    return sum;
  }
}

// LineDash
unittest {
  const d = LineDash.fromSegments([1.0f, 2, 3]);
  assert(d.segments == [1.0f, 2, 3, 1, 2, 3]);
  assert(d.period() == 12);
  assert(!d.isSolid());
  assert(LineDash.fromSegments([4.0f, 5]).segments == [4.0f, 5]);
  assert(LineDash.fromSegments([1.0f, -2]).isSolid());
  assert(LineDash.fromSegments([1.0f, float.nan]).segments.length == 0);
  assert(LineDash.fromSegments([1.0f, float.infinity]).isSolid());
  assert(LineDash.fromSegments([0.0f, 0]).isSolid());
  assert(LineDash.init.isSolid());
}

/// Gradient color stop at `offset` in [0, 1].
struct GradientStop {
  float offset;
  ColorF color;
}

/// Maximum number of color stops per gradient; extra stops are ignored.
enum maxGradientStops = 8;

/// Fixed-capacity sorted color stops shared by gradients.
struct GradientStops {
  GradientStop[maxGradientStops] stops;
  ubyte count;

  /**
   * Inserts a stop keeping offsets sorted (stable: equal offsets keep
   * insertion order). Offset is clamped to [0, 1]; non-finite offsets and
   * stops beyond `maxGradientStops` are ignored.
   */
  void add(float offset, ColorF c) nothrow @safe @nogc {
    import std.math : isFinite;

    if (!isFinite(offset) || count >= maxGradientStops) {
      return;
    }
    const float o = offset < 0 ? 0 : (offset > 1 ? 1 : offset);
    size_t pos = count;
    while (pos > 0 && stops[pos - 1].offset > o) {
      stops[pos] = stops[pos - 1];
      --pos;
    }
    stops[pos] = GradientStop(o, c);
    ++count;
  }

  /// Used stops in offset order.
  const(GradientStop)[] items() const return nothrow @safe @nogc {
    return stops[0 .. count];
  }
}

/// Linear gradient from `p0` to `p1`.
struct LinearGradient {
  PointF p0;
  PointF p1;
  GradientStops stops;

  /// Adds a color stop; see `GradientStops.add`.
  ref LinearGradient addColorStop(float offset, ColorF c)
    return nothrow @safe @nogc {
    stops.add(offset, c);
    return this;
  }
}

/// Radial gradient between circles (`c0`, `r0`) and (`c1`, `r1`).
struct RadialGradient {
  PointF c0;
  float r0 = 0;
  PointF c1;
  float r1 = 0;
  GradientStops stops;

  /// Adds a color stop; see `GradientStops.add`.
  ref RadialGradient addColorStop(float offset, ColorF c)
    return nothrow @safe @nogc {
    stops.add(offset, c);
    return this;
  }
}

// gradient stops
unittest {
  LinearGradient g;
  g.addColorStop(0.5f, ColorF(1, 0, 0, 1))
    .addColorStop(-3, ColorF(0, 1, 0, 1))
    .addColorStop(7, ColorF(0, 0, 1, 1))
    .addColorStop(0.5f, ColorF(1, 1, 1, 1))
    .addColorStop(float.nan, ColorF(0, 0, 0, 1));
  const s = g.stops.items();
  assert(s.length == 4);
  assert(s[0].offset == 0 && s[0].color.g == 1);
  assert(s[1].offset == 0.5f && s[1].color == ColorF(1, 0, 0, 1));
  assert(s[2].offset == 0.5f && s[2].color == ColorF(1, 1, 1, 1));
  assert(s[3].offset == 1 && s[3].color.b == 1);

  RadialGradient r;
  foreach (i; 0 .. maxGradientStops + 3) {
    r.addColorStop(1.0f - i * 0.05f, ColorF(i, 0, 0, 1));
  }
  assert(r.stops.count == maxGradientStops);
  assert(r.stops.items()[0].color.r == maxGradientStops - 1);
  assert(r.stops.items()[$ - 1].offset == 1);
}

struct Pattern {
  // TODO image, postpone for now until we support loading images
}

/// Paint for fills and strokes: solid color or gradient.
struct FillStyle {
  enum Kind {
    color,
    linearGradient,
    radialGradient,
  }

  Kind kind;
  ColorF color = ColorF(0, 0, 0, 1);
  LinearGradient linear;
  RadialGradient radial;

  /// Solid color paint.
  static FillStyle solid(ColorF c) nothrow @safe @nogc {
    FillStyle s;
    s.kind = Kind.color;
    s.color = c;
    return s;
  }

  /// Linear gradient paint.
  static FillStyle fromLinear(in LinearGradient g) nothrow @safe @nogc {
    FillStyle s;
    s.kind = Kind.linearGradient;
    s.linear = g;
    return s;
  }

  /// Radial gradient paint.
  static FillStyle fromRadial(in RadialGradient g) nothrow @safe @nogc {
    FillStyle s;
    s.kind = Kind.radialGradient;
    s.radial = g;
    return s;
  }
}

// Strokes use the same paint kinds as fills; no separate type is needed.
alias StrokeStyle = FillStyle;

// FillStyle
unittest {
  assert(FillStyle.init.kind == FillStyle.Kind.color);
  assert(FillStyle.init.color == ColorF(0, 0, 0, 1));
  assert(FillStyle.solid(ColorF(1, 0, 0, 1)).color.r == 1);
  LinearGradient lg;
  lg.p1 = PointF(10, 0);
  const fl = FillStyle.fromLinear(lg);
  assert(fl.kind == FillStyle.Kind.linearGradient && fl.linear.p1.x == 10);
  RadialGradient rg;
  rg.r1 = 5;
  const fr = FillStyle.fromRadial(rg);
  assert(fr.kind == FillStyle.Kind.radialGradient && fr.radial.r1 == 5);
}

/**
 * Drop shadow of Canvas fills and strokes: the shape's coverage, blurred
 * with a Gaussian of standard deviation `blur / 2` (logic units), tinted
 * with `color` and drawn at `offset` (not transformed) under the shape.
 */
struct Shadow {
  PointF offset;
  float blur = 0;
  ColorF color = ColorF(0, 0, 0, 0);

  /// True when the shadow would produce visible output.
  bool isVisible() const nothrow @safe @nogc {
    return color.a > 0
      && (blur > 0 || offset.x != 0 || offset.y != 0);
  }
}

unittest {
  assert(!Shadow.init.isVisible());
  Shadow s;
  s.color = ColorF(0, 0, 0, 0.5f);
  assert(!s.isVisible());
  s.blur = 4;
  assert(s.isVisible());
}

enum FillRule {
  nonZero,
  evenOdd,
}

/**
 * canvas context
 *
 * Fills and strokes `Path2d` with the Renderer's color or gradient
 * pipeline using stencil-then-cover (exact `nonZero` / `evenOdd`); the
 * current transform is applied on the CPU (gradients get its inverse).
 * `clip()` lives in stencil bit 7 and affects only Canvas calls: the
 * Canvas enables `GL_STENCIL_TEST` only inside its own calls, so Renderer
 * `draw*` calls ignore the Canvas clip and transform. The Renderer
 * scissor clip (`pushClipRect`) limits both. `Renderer.clearFrame`
 * resets the Canvas state.
 */
final class Canvas {
// do not replicate standalone path functions, like ctx.arc or ctx.beginPath,
// the user is expected to use Path2d instead to draw paths

  /// Created by `Renderer`; `r` must not be null.
  this(Renderer r) {
    assert(r !is null);
    fRenderer = r;
    fRectPath = new Path2d();
  }

  invariant {
    assert(fRenderer !is null);
    assert(fRectPath !is null);
  }

  /**
   * Sets `rect` (transformed by the current transform) to transparent
   * black, honoring the Canvas clip and the scissor.
   */
  void clearRect(RectF rect) {
    fRectPath.clear();
    fRectPath.rect(rect);
    fillWithRule(
      fRectPath, FillRule.nonZero, FillStyle.solid(ColorF(0, 0, 0, 0)),
      false
    );
  }

  void fillStyle(FillStyle style) {
    st.fill = style;
  }

  FillStyle fillStyle() const {
    return st.fill;
  }

  void strokeStyle(StrokeStyle style) {
    st.stroke = style;
  }

  StrokeStyle strokeStyle() const {
    return st.stroke;
  }

  /// Ignores zero, negative and non-finite widths.
  void lineWidth(float w) {
    import std.math : isFinite;

    if (isFinite(w) && w > 0) {
      st.lineWidth = w;
    }
  }

  float lineWidth() const {
    return st.lineWidth;
  }

  void lineCap(LineCap cap) {
    st.cap = cap;
  }

  LineCap lineCap() const {
    return st.cap;
  }

  void lineJoin(LineJoin join) {
    st.join = join;
  }

  LineJoin lineJoin() const {
    return st.join;
  }

  /// Ignores zero, negative and non-finite limits.
  void miterLimit(float miter) {
    import std.math : isFinite;

    if (isFinite(miter) && miter > 0) {
      st.miterLimit = miter;
    }
  }

  float miterLimit() const {
    return st.miterLimit;
  }

  /// Stores a normalized copy (see `LineDash.fromSegments`).
  void lineDash(LineDash dash) {
    st.dash = LineDash.fromSegments(dash.segments);
  }

  LineDash lineDash() const {
    return LineDash.fromSegments(st.dash.segments);
  }

  /// Ignores non-finite offsets.
  void lineDashOffset(float offset) {
    import std.math : isFinite;

    if (isFinite(offset)) {
      st.dashOffset = offset;
    }
  }

  float lineDashOffset() const {
    return st.dashOffset;
  }

  void fillRule(FillRule rule) {
    st.fillRule = rule;
  }

  FillRule fillRule() const {
    return st.fillRule;
  }

  /**
   * Sets the shadow of later fills and strokes; ignored when `s` has a
   * non-finite offset or blur, or a negative blur.
   */
  void shadow(Shadow s) {
    import std.math : isFinite;

    if (finitePoint(s.offset) && isFinite(s.blur) && s.blur >= 0) {
      st.shadow = s;
    }
  }

  Shadow shadow() const {
    return st.shadow;
  }

  /// Fills `path` with `fillStyle` using `fillRule`.
  void fill(Path2d path) {
    fillWithRule(path, st.fillRule, st.fill, true);
  }

  /// Strokes `path` with `strokeStyle`; overlaps are painted once.
  void stroke(Path2d path) {
    import glad2.gles2 : GL_TRIANGLES;
    import yguilib.render.internal.path_flatten : flattenPath;
    import yguilib.render.internal.path_stroker : StrokeParams,
      strokeContours;
    import yguilib.render.internal.stencil_ops : beginResetLow,
      beginStrokeOnce, endStencil;

    assert(path !is null);
    if (!canDraw(path) || !paintVisible(st.stroke)) {
      return;
    }
    const float tol = tolerance(st.xf);
    flattenPath(path, tol, fContours);
    StrokeParams p;
    p.width = st.lineWidth;
    p.cap = st.cap;
    p.join = st.join;
    p.miterLimit = st.miterLimit;
    p.dash = st.dash.segments;
    p.dashOffset = st.dashOffset;
    p.tolerance = tol;
    fLocalTris.clear();
    strokeContours(fContours, p, fLocalTris);
    transformVerts(fLocalTris[], st.xf);
    if (fVerts[].length == 0) {
      return;
    }
    if (st.shadow.isVisible()) {
      drawShadow(ShadowShape.stroke, FillRule.nonZero, st.stroke);
    }
    beginStrokeOnce(clipActive());
    drawPaint(fVerts[], st.stroke);
    beginResetLow();
    drawVerts(fVerts[], ColorF(0, 0, 0, 0));
    endStencil();
  }

  // push state
  void save() {
    State copy = st;
    copy.clips = st.clips.dup;
    fStack.put(copy);
  }

  // pop state
  void restore() {
    const size_t n = fStack[].length;
    if (n == 0) {
      return;
    }
    const bool clipsChanged = fStack[][n - 1].clips.length
      != st.clips.length;
    st = fStack[][n - 1];
    fStack.shrinkTo(n - 1);
    if (clipsChanged) {
      rebuildClip();
    }
  }

  void translate(PointF offset) {
    if (finitePoint(offset)) {
      st.xf = st.xf * Transform2d.translation(offset);
    }
  }

  void rotate(float radians) {
    import std.math : isFinite;

    if (isFinite(radians)) {
      st.xf = st.xf * Transform2d.rotation(radians);
    }
  }

  /// supports negative for axis mirroring
  void scale(PointF factor) {
    if (finitePoint(factor)) {
      st.xf = st.xf * Transform2d.scaling(factor);
    }
  }

  /// to the identity matrix
  void resetTransform() {
    st.xf = Transform2d.identity();
  }

  /// Current transform (local to logic coordinates).
  Transform2d transform() const {
    return st.xf;
  }

  /// sets clipping mask; use save() and then restore() to undo clipping.
  void clip(Path2d path) {
    assert(path !is null);
    auto copy = new Path2d();
    copy.addPath(path, Transform2d.identity());
    ClipEntry e = ClipEntry(copy, st.xf, st.clipRule);
    const bool first = st.clips.length == 0;
    st.clips ~= e;
    if (!fRenderer.isInitialized()) {
      return;
    }
    const bool scissor = disableScissor();
    if (first) {
      clearClipBit(true);
    }
    applyClip(e);
    restoreScissor(scissor);
  }

  void clipFillRule(FillRule rule) {
    st.clipRule = rule;
  }

  FillRule clipFillRule() const {
    return st.clipRule;
  }

  // Text/font-related functions are omitted for now.

package(yguilib.render):
  /// Resets to the default state with an empty save stack (new frame).
  void resetFrame() {
    st = State.init;
    fStack.clear();
  }

private:
  /// One `clip()` call, replayed to rebuild the clip bit on `restore()`.
  struct ClipEntry {
    Path2d path;
    Transform2d xf;
    FillRule rule;
  }

  /// Drawing state saved by `save()`.
  struct State {
    FillStyle fill;
    StrokeStyle stroke;
    float lineWidth = 1;
    LineCap cap = LineCap.butt;
    LineJoin join = LineJoin.miter;
    float miterLimit = 10;
    LineDash dash;
    float dashOffset = 0;
    FillRule fillRule = FillRule.nonZero;
    FillRule clipRule = FillRule.nonZero;
    Transform2d xf;
    ClipEntry[] clips;
    Shadow shadow;
  }

  /// Geometry in `fVerts` for `drawShadow`.
  enum ShadowShape {
    /// fan triangles filled by stencil-then-cover with a fill rule
    fill,
    /// stroke triangles drawn directly
    stroke,
  }

  /// Pixel rectangle of a shadow pass (origin top-left, y down).
  struct PixelBox {
    int x;
    int y;
    int width;
    int height;
  }

  Renderer fRenderer;
  State st;
  Appender!(State[]) fStack;
  /// Reused scratch buffers (no per-call GC churn).
  Contours fContours;
  Appender!(float[]) fLocalTris;
  Appender!(float[]) fVerts;
  Appender!(float[]) fShadowVerts;
  Path2d fRectPath;

  bool clipActive() const {
    return st.clips.length > 0;
  }

  bool canDraw(const Path2d path) const {
    return fRenderer.isInitialized() && !path.isEmpty();
  }

  float tolerance(in Transform2d xf) const {
    import yguilib.render.internal.path_flatten : flattenTolerance;

    return flattenTolerance(fRenderer.getTotalScaling(), xf);
  }

  static bool finitePoint(PointF p) {
    import std.math : isFinite;

    return isFinite(p.x) && isFinite(p.y);
  }

  /**
   * False when `s` cannot paint anything: transparent color, gradient
   * without visible stops, or a radial gradient with a negative radius.
   */
  static bool paintVisible(in FillStyle s) {
    final switch (s.kind) {
    case FillStyle.Kind.color:
      return s.color.a > 0;
    case FillStyle.Kind.linearGradient:
      return stopsVisible(s.linear.stops);
    case FillStyle.Kind.radialGradient:
      return s.radial.r0 >= 0 && s.radial.r1 >= 0
        && stopsVisible(s.radial.stops);
    }
  }

  static bool stopsVisible(in GradientStops stops) {
    foreach (ref stop; stops.items()) {
      if (stop.color.a > 0) {
        return true;
      }
    }
    return false;
  }

  /**
   * Gradient shader uniforms of gradient style `s`; `invXf` maps logic
   * coordinates to the gradient's user space.
   */
  static GradientUniforms gradientUniforms(
    in FillStyle s,
    in Transform2d invXf
  ) {
    const bool linear = s.kind == FillStyle.Kind.linearGradient;
    GradientUniforms u;
    u.invXf = [invXf.a, invXf.b, 0, invXf.c, invXf.d, 0, invXf.e,
      invXf.f, 1];
    const(GradientStop)[] items;
    if (linear) {
      u.kind = 0;
      u.p0 = s.linear.p0;
      u.p1 = s.linear.p1;
      items = s.linear.stops.items();
    } else {
      u.kind = 1;
      u.p0 = s.radial.c0;
      u.p1 = s.radial.c1;
      u.r0 = s.radial.r0;
      u.r1 = s.radial.r1;
      items = s.radial.stops.items();
    }
    static assert(GradientUniforms.maxStops == maxGradientStops);
    foreach (i, ref stop; items) {
      u.stopOffsets[i] = stop.offset;
      u.stopColors[i * 4 .. i * 4 + 4] = [stop.color.r, stop.color.g,
        stop.color.b, stop.color.a];
    }
    u.stopCount = cast(int)items.length;
    return u;
  }

  /**
   * Colored pass of a fill (cover) or stroke: solid styles use the color
   * pipeline, gradients the gradient pipeline with the inverse of the
   * current transform. The stencil state must already be set.
   */
  void drawPaint(const(float)[] verts, in FillStyle style) {
    if (verts.length == 0) {
      return;
    }
    if (style.kind == FillStyle.Kind.color) {
      drawVerts(verts, style.color);
      return;
    }
    const GradientUniforms u = gradientUniforms(style, st.xf.inverse());
    fRenderer.gradientPipelineRef().drawTriangles(
      verts, u, fRenderer.getLogicWidth(), fRenderer.getLogicHeight()
    );
  }

  /**
   * Stencil-then-cover fill of `path`. With `blend` false the cover pass
   * overwrites pixels with the solid color of `style` (used by
   * `clearRect`); with `blend` true an invisible `style` draws nothing.
   */
  void fillWithRule(
    Path2d path,
    FillRule rule,
    in FillStyle style,
    bool blend
  ) {
    import glad2.gles2 : GL_BLEND, GL_TRIANGLES, glDisable;
    import yguilib.render.internal.path_flatten : flattenPath;
    import yguilib.render.internal.stencil_ops : beginCover, beginWinding,
      endStencil;

    assert(path !is null);
    if (!canDraw(path) || (blend && !paintVisible(style))) {
      return;
    }
    flattenPath(path, tolerance(st.xf), fContours);
    buildFan(st.xf);
    if (fVerts[].length == 0) {
      return;
    }
    if (blend && st.shadow.isVisible()) {
      drawShadow(ShadowShape.fill, rule, style);
    }
    const float[12] cover = quadFromRect(boundsOfVerts(fVerts[]));
    beginWinding(rule);
    drawVerts(fVerts[], ColorF(0, 0, 0, 0));
    beginCover(rule, clipActive());
    if (blend) {
      drawPaint(cover[], style);
    } else {
      glDisable(GL_BLEND);
      fRenderer.colorPipelineRef().drawArraysWithCurrentState(
        GL_TRIANGLES, cover[], style.color, fRenderer.getLogicWidth(),
        fRenderer.getLogicHeight()
      );
      // the next draw re-enables blending via setupAlphaBlendState
    }
    endStencil();
  }

  /**
   * Shadow of `fVerts` (logic coordinates): a mask of `shape` carrying the
   * alpha of `style` in offscreen target 0 over the padded device bounds,
   * blurred through target 1, then composited with `st.shadow.color` at
   * the offset under the Canvas clip, so shadow alpha = shadow color alpha
   * * paint alpha (as in HTML canvas). Framebuffer, viewport, scissor and
   * clear color are saved before and restored after the offscreen passes.
   */
  void drawShadow(ShadowShape shape, FillRule rule, in FillStyle style) {
    import yguilib.render.internal.offscreen : OffscreenTarget,
      SavedTargetState;

    const float scale = fRenderer.getTotalScaling();
    const float sigma = st.shadow.blur * 0.5f * scale;
    const box = shadowBox(sigma, scale);
    if (box.isNull) {
      return;
    }
    const PixelBox b = box.get;
    OffscreenTarget* a = &fRenderer.offscreenTargetRef(0);
    const SavedTargetState saved = SavedTargetState.capture();
    a.ensureSize(b.width, b.height);
    a.bindRegion(b.width, b.height, true);
    drawShadowMask(shape, rule, style, b, scale);
    if (sigma > 0) {
      blurShadow(b, sigma);
    }
    saved.restore();
    compositeShadow(b, scale);
  }

  /**
   * Device box of the shadow pass: `fVerts` bounds in pixels padded by
   * 3 sigma (+1), limited to what can reach the viewport after the
   * offset. Null when empty.
   */
  auto shadowBox(float sigma, float scale) {
    import std.algorithm : max, min;
    import std.math : ceil, floor;
    import std.typecons : Nullable;

    const RectF r = boundsOfVerts(fVerts[]);
    const float pad = ceil(3 * sigma) + 1;
    const float offX = st.shadow.offset.x * scale;
    const float offY = st.shadow.offset.y * scale;
    const float pw = fRenderer.getPixelWidth();
    const float ph = fRenderer.getPixelHeight();
    const float x0 = max(floor(r.x * scale), floor(-offX)) - pad;
    const float y0 = max(floor(r.y * scale), floor(-offY)) - pad;
    const float x1 = min(ceil((r.x + r.width) * scale), ceil(pw - offX))
      + pad;
    const float y1 = min(ceil((r.y + r.height) * scale), ceil(ph - offY))
      + pad;
    Nullable!PixelBox res;
    if (x1 > x0 && y1 > y0) {
      res = PixelBox(cast(int)x0, cast(int)y0, cast(int)(x1 - x0),
        cast(int)(y1 - y0));
    }
    return res;
  }

  /**
   * Draws `fVerts` shifted to the origin of box `b` into the bound
   * offscreen region (no Canvas clip there). The colored pass runs with
   * blending disabled so the mask alpha equals the paint alpha of `style`
   * (blending onto the cleared target would square it).
   */
  void drawShadowMask(
    ShadowShape shape,
    FillRule rule,
    in FillStyle style,
    in PixelBox b,
    float scale
  ) {
    import glad2.gles2 : GL_TRIANGLES;
    import yguilib.render.internal.pipelines : ColorPipeline;
    import yguilib.render.internal.stencil_ops : beginCover, beginWinding,
      endStencil;

    const float ox = b.x / scale;
    const float oy = b.y / scale;
    const float vw = b.width / scale;
    const float vh = b.height / scale;
    const(float)[] verts = fVerts[];
    fShadowVerts.clear();
    for (size_t i = 0; i + 1 < verts.length; i += 2) {
      fShadowVerts.put(verts[i] - ox);
      fShadowVerts.put(verts[i + 1] - oy);
    }
    ColorPipeline* color = &fRenderer.colorPipelineRef();
    final switch (shape) {
    case ShadowShape.fill:
      beginWinding(rule);
      color.drawArrays(GL_TRIANGLES, fShadowVerts[], ColorF(0, 0, 0, 0),
        vw, vh);
      beginCover(rule, false);
      const float[12] cover = quadFromRect(RectF(0, 0, vw, vh));
      drawMaskPaint(cover[], style, PointF(ox, oy), vw, vh);
      endStencil();
      break;
    case ShadowShape.stroke:
      // no blending: overlapping triangles rewrite the same alpha
      drawMaskPaint(fShadowVerts[], style, PointF(ox, oy), vw, vh);
      break;
    }
  }

  /**
   * Writes the alpha of `style` (white RGB for solid colors) over `verts`
   * with blending disabled. `origin` is the logic position of the mask
   * region origin, so gradients map mask coordinates back to user space.
   */
  void drawMaskPaint(
    const(float)[] verts,
    in FillStyle style,
    PointF origin,
    float vw,
    float vh
  ) {
    import glad2.gles2 : GL_BLEND, GL_TRIANGLES, glDisable;

    glDisable(GL_BLEND);
    // the next draw re-enables blending via setupAlphaBlendState
    if (style.kind == FillStyle.Kind.color) {
      fRenderer.colorPipelineRef().drawArraysWithCurrentState(
        GL_TRIANGLES, verts, ColorF(1, 1, 1, style.color.a), vw, vh
      );
      return;
    }
    const Transform2d inv =
      st.xf.inverse() * Transform2d.translation(origin);
    GradientUniforms u = gradientUniforms(style, inv);
    // the composite tints the mask RGB too: keep only the stop alphas
    foreach (i; 0 .. u.stopCount) {
      u.stopColors[i * 4 .. i * 4 + 3] = 1.0f;
    }
    fRenderer.gradientPipelineRef().drawTrianglesWithCurrentState(
      verts, u, vw, vh
    );
  }

  /// Blurs region `b` of target 0 horizontally into 1, vertically back.
  void blurShadow(in PixelBox b, float sigma) {
    import yguilib.render.internal.offscreen : OffscreenTarget;
    import yguilib.render.internal.pipelines : BlurPass;

    OffscreenTarget* a = &fRenderer.offscreenTargetRef(0);
    OffscreenTarget* t = &fRenderer.offscreenTargetRef(1);
    t.ensureSize(b.width, b.height);
    BlurPass p;
    p.width = b.width;
    p.height = b.height;
    p.sigma = sigma;
    p.source = a.texture;
    p.textureWidth = a.width;
    p.textureHeight = a.height;
    p.vertical = false;
    t.bindRegion(b.width, b.height, false);
    fRenderer.blurPipelineRef().draw(p);
    p.source = t.texture;
    p.textureWidth = t.width;
    p.textureHeight = t.height;
    p.vertical = true;
    a.bindRegion(b.width, b.height, false);
    fRenderer.blurPipelineRef().draw(p);
  }

  /// Draws region `b` of target 0 tinted at `b` + offset (logic units).
  void compositeShadow(in PixelBox b, float scale) {
    import yguilib.render.internal.offscreen : OffscreenTarget;
    import yguilib.render.internal.pipelines : TexturedQuad;
    import yguilib.render.internal.stencil_ops : beginClipTest, endStencil;

    const OffscreenTarget* a = &fRenderer.offscreenTargetRef(0);
    const float tw = a.width;
    const float th = a.height;
    TexturedQuad q;
    q.dest = RectF(
      b.x / scale + st.shadow.offset.x, b.y / scale + st.shadow.offset.y,
      b.width / scale, b.height / scale
    );
    // GL rows grow upward while logic y grows downward: flip v
    q.uv = RectF(0, b.height / th, b.width / tw, -b.height / th);
    q.color = st.shadow.color;
    beginClipTest(clipActive());
    fRenderer.texturePipelineRef().drawTexturedQuad(
      a.texture, q, fRenderer.getLogicWidth(), fRenderer.getLogicHeight()
    );
    endStencil();
  }

  /// Intersects the clip bit with clip entry `e` (scissor must be off).
  void applyClip(in ClipEntry e) {
    import yguilib.render.internal.path_flatten : flattenPath;
    import yguilib.render.internal.stencil_ops : beginClipIntersect,
      beginResetLow, beginWinding, endStencil;

    flattenPath(e.path, tolerance(e.xf), fContours);
    buildFan(e.xf);
    const ColorF none = ColorF(0, 0, 0, 0);
    beginWinding(e.rule);
    drawVerts(fVerts[], none);
    beginClipIntersect(e.rule);
    const float[12] all = quadFromRect(RectF(
      -1, -1, fRenderer.getLogicWidth() + 2,
      fRenderer.getLogicHeight() + 2
    ));
    drawVerts(all[], none);
    if (fVerts[].length > 0) {
      const float[12] cover = quadFromRect(boundsOfVerts(fVerts[]));
      beginResetLow();
      drawVerts(cover[], none);
    }
    endStencil();
  }

  /// Rebuilds the clip bit from `st.clips` after `restore()`.
  void rebuildClip() {
    if (!fRenderer.isInitialized()) {
      return;
    }
    const bool scissor = disableScissor();
    clearClipBit(st.clips.length > 0);
    foreach (ref e; st.clips) {
      applyClip(e);
    }
    restoreScissor(scissor);
  }

  /// Sets (`inside` true) or clears stencil bit 7 in the whole viewport.
  static void clearClipBit(bool inside) {
    import glad2.gles2 : GL_STENCIL_BUFFER_BIT, glClear, glClearStencil,
      glStencilMask;
    import yguilib.render.internal.stencil_ops : clipBit;

    glStencilMask(clipBit);
    glClearStencil(inside ? clipBit : 0);
    glClear(GL_STENCIL_BUFFER_BIT);
    glClearStencil(0);
    glStencilMask(0xFF);
  }

  /**
   * Disables the scissor so the clip bit is valid in the whole viewport
   * (also outside a later, larger scissor). Returns the previous state.
   */
  static bool disableScissor() {
    import glad2.gles2 : GL_SCISSOR_TEST, GL_TRUE, glDisable, glIsEnabled;

    const bool was = glIsEnabled(GL_SCISSOR_TEST) == GL_TRUE;
    glDisable(GL_SCISSOR_TEST);
    return was;
  }

  static void restoreScissor(bool enabled) {
    import glad2.gles2 : GL_SCISSOR_TEST, glEnable;

    if (enabled) {
      glEnable(GL_SCISSOR_TEST);
    }
  }

  void drawVerts(const(float)[] verts, ColorF color) {
    import glad2.gles2 : GL_TRIANGLES;

    if (verts.length == 0) {
      return;
    }
    fRenderer.colorPipelineRef().drawArrays(
      GL_TRIANGLES, verts, color, fRenderer.getLogicWidth(),
      fRenderer.getLogicHeight()
    );
  }

  /// Fan triangles of every `fContours` contour, transformed into `fVerts`.
  void buildFan(in Transform2d xf) {
    fVerts.clear();
    const PointF[] pts = fContours.points[];
    foreach (info; fContours.infos[]) {
      if (info.count < 3) {
        continue;
      }
      const PointF p0 = xf.apply(pts[info.start]);
      PointF prev = xf.apply(pts[info.start + 1]);
      foreach (i; info.start + 2 .. info.start + info.count) {
        const PointF cur = xf.apply(pts[i]);
        const float[6] tri = [p0.x, p0.y, prev.x, prev.y, cur.x, cur.y];
        fVerts.put(tri[]);
        prev = cur;
      }
    }
  }

  /// `fVerts` = `local` (x, y pairs) transformed by `xf`.
  void transformVerts(const(float)[] local, in Transform2d xf) {
    fVerts.clear();
    for (size_t i = 0; i + 1 < local.length; i += 2) {
      const PointF p = xf.apply(PointF(local[i], local[i + 1]));
      fVerts.put(p.x);
      fVerts.put(p.y);
    }
  }

  /// Bounds of `verts` grown by 1 unit so the cover hits edge samples.
  static RectF boundsOfVerts(const(float)[] verts) {
    float x0 = verts[0];
    float y0 = verts[1];
    float x1 = x0;
    float y1 = y0;
    for (size_t i = 2; i + 1 < verts.length; i += 2) {
      x0 = verts[i] < x0 ? verts[i] : x0;
      x1 = verts[i] > x1 ? verts[i] : x1;
      y0 = verts[i + 1] < y0 ? verts[i + 1] : y0;
      y1 = verts[i + 1] > y1 ? verts[i + 1] : y1;
    }
    return RectF(x0 - 1, y0 - 1, x1 - x0 + 2, y1 - y0 + 2);
  }

  static float[12] quadFromRect(RectF r) {
    const float x0 = r.x;
    const float y0 = r.y;
    const float x1 = r.x + r.width;
    const float y1 = r.y + r.height;
    return [x0, y0, x1, y0, x0, y1, x0, y1, x1, y0, x1, y1];
  }
}

// Canvas GL rendering (stencil-then-cover, transforms, strokes, clips)
unittest {
  import glad2.gles2;
  import std.math : PI, cos, sin;
  import yguilib.clibs.sdl3;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_canvas");
  win.create();
  scope(exit) win.destroy();
  win.setDisplayScaling(1.0f);
  auto r = win.renderer;
  r.setViewport(320, 240);
  auto cv = r.canvas();
  assert(cv !is null);

  GLint stencilBits = 0;
  glGetIntegerv(GL_STENCIL_BITS, &stencilBits);
  assert(stencilBits >= 8);

  // logic (x, y) with y down; GL y = 240 - y
  ubyte[4] px(int x, int y) {
    ubyte[4] p;
    glReadPixels(x, 240 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p.ptr);
    return p;
  }

  bool isRgb(int x, int y, int cr, int cg, int cb) {
    const p = px(x, y);
    return p[0] == cr && p[1] == cg && p[2] == cb;
  }

  Path2d rectPath(RectF rc) {
    auto p = new Path2d();
    p.rect(rc);
    return p;
  }

  const black = ColorF(0, 0, 0, 1);
  const red = ColorF(1, 0, 0, 1);
  const green = FillStyle.solid(ColorF(0, 1, 0, 1));
  const blue = FillStyle.solid(ColorF(0, 0, 1, 1));
  auto full = rectPath(RectF(0, 0, 320, 240));

  // 1. rect fill
  r.clearFrame(red);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(20, 20, 60, 40)));
  assert(isRgb(50, 40, 0, 255, 0));
  assert(isRgb(150, 150, 255, 0, 0));

  // 2. self-intersecting star: nonZero fills the center, evenOdd not
  auto star = new Path2d();
  foreach (k; 0 .. 5) {
    const float a = cast(float)(-PI / 2 + k * 4 * PI / 5);
    const PointF pt = PointF(160 + 80 * cos(a), 120 + 80 * sin(a));
    if (k == 0) {
      star.moveTo(pt);
    } else {
      star.lineTo(pt);
    }
  }
  star.closePath();
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.fill(star);
  assert(isRgb(160, 120, 0, 255, 0));
  assert(isRgb(160, 60, 0, 255, 0));
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.fillRule(FillRule.evenOdd);
  cv.fill(star);
  assert(isRgb(160, 120, 0, 0, 0));
  assert(isRgb(160, 60, 0, 255, 0));
  cv.fillRule(FillRule.nonZero);

  // 3. transforms and save/restore
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.save();
  cv.translate(PointF(100, 50));
  cv.rotate(cast(float)(PI / 4));
  cv.fill(rectPath(RectF(-10, -10, 20, 20)));
  cv.restore();
  assert(cv.transform().isIdentity());
  assert(isRgb(100, 50, 0, 255, 0));
  assert(isRgb(112, 50, 0, 255, 0)); // inside the rotated diamond only
  assert(isRgb(108, 42, 0, 0, 0)); // unrotated corner area
  cv.save();
  cv.scale(PointF(2, 3));
  cv.fill(rectPath(RectF(10, 10, 10, 10))); // -> (20, 30, 20, 30)
  assert(!cv.transform().isIdentity());
  cv.restore();
  assert(isRgb(30, 45, 0, 255, 0));
  assert(isRgb(15, 45, 0, 0, 0));
  assert(isRgb(30, 65, 0, 0, 0));
  cv.restore(); // empty stack: no-op
  cv.fill(rectPath(RectF(200, 200, 10, 10)));
  assert(isRgb(205, 205, 0, 255, 0));

  // 4. self-overlapping stroke is painted once
  r.clearFrame(black);
  auto cross = new Path2d();
  cross.moveTo(PointF(50, 50));
  cross.lineTo(PointF(200, 200));
  cross.lineTo(PointF(200, 50));
  cross.lineTo(PointF(50, 200));
  cv.strokeStyle(FillStyle.solid(ColorF(1, 1, 1, 0.5f)));
  cv.lineWidth(10);
  cv.stroke(cross);
  const ov = px(125, 125);
  assert(ov[0] >= 125 && ov[0] <= 131);
  const single = px(80, 80);
  assert(single[0] >= 125 && single[0] <= 131);

  // 5. dashes: [20, 20] along y = 100 from x = 20
  r.clearFrame(black);
  cv.strokeStyle(FillStyle.solid(ColorF(1, 1, 1, 1)));
  cv.lineWidth(6);
  cv.lineDash(LineDash([20.0f, 20]));
  assert(cv.lineDash().segments == [20.0f, 20]);
  auto line = new Path2d();
  line.moveTo(PointF(20, 100));
  line.lineTo(PointF(220, 100));
  cv.stroke(line);
  assert(isRgb(30, 100, 255, 255, 255));
  assert(isRgb(50, 100, 0, 0, 0));
  assert(isRgb(70, 100, 255, 255, 255));
  assert(isRgb(30, 110, 0, 0, 0));
  cv.lineDash(LineDash.init);
  cv.lineWidth(1);

  // 6. circle clip; restore() removes it
  r.clearFrame(black);
  auto circle = new Path2d();
  circle.arc(PointF(160, 120), 60, 0, cast(float)(2 * PI), false);
  cv.fillStyle(blue);
  cv.save();
  cv.clip(circle);
  cv.fill(full);
  assert(isRgb(160, 120, 0, 0, 255));
  assert(isRgb(5, 5, 0, 0, 0));
  assert(isRgb(315, 235, 0, 0, 0));
  assert(isRgb(160, 50, 0, 0, 0));
  cv.restore();
  cv.fillStyle(green);
  cv.fill(full);
  assert(isRgb(5, 5, 0, 255, 0));
  assert(isRgb(160, 120, 0, 255, 0));

  // 7. nested clips intersect; restoring one level keeps the outer clip
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.save();
  cv.clip(rectPath(RectF(20, 20, 100, 100)));
  cv.save();
  cv.clip(rectPath(RectF(70, 70, 100, 100)));
  cv.fill(full);
  assert(isRgb(90, 90, 0, 255, 0));
  assert(isRgb(40, 40, 0, 0, 0));
  assert(isRgb(150, 150, 0, 0, 0));
  cv.restore();
  cv.fillStyle(blue);
  cv.fill(full);
  assert(isRgb(40, 40, 0, 0, 255));
  assert(isRgb(150, 150, 0, 0, 0));
  // 8. Renderer draws ignore the Canvas clip
  r.drawFillRect(RectF(0, 0, 320, 240), ColorF(1, 0, 0, 1));
  assert(isRgb(150, 150, 255, 0, 0));
  assert(isRgb(5, 5, 255, 0, 0));
  cv.restore();

  // evenOdd clip with the star excludes its center
  r.clearFrame(black);
  cv.save();
  cv.clipFillRule(FillRule.evenOdd);
  cv.clip(star);
  cv.fillStyle(green);
  cv.fill(full);
  assert(isRgb(160, 120, 0, 0, 0));
  assert(isRgb(160, 60, 0, 255, 0));
  assert(isRgb(5, 5, 0, 0, 0));
  cv.restore();
  assert(cv.clipFillRule() == FillRule.nonZero);

  // 9. Renderer scissor limits Canvas fills
  r.clearFrame(black);
  cv.fillStyle(green);
  r.pushClipRect(RectF(50, 50, 50, 50));
  cv.fill(full);
  r.popClipRect();
  assert(isRgb(60, 60, 0, 255, 0));
  assert(isRgb(10, 10, 0, 0, 0));
  assert(isRgb(150, 150, 0, 0, 0));

  // 10. clearRect overwrites with transparent black
  r.clearFrame(ColorF(1, 1, 1, 1));
  cv.clearRect(RectF(10, 10, 50, 50));
  assert(isRgb(30, 30, 0, 0, 0));
  assert(isRgb(100, 100, 255, 255, 255));
  // and the next Renderer draw blends again
  r.drawFillRect(RectF(0, 0, 320, 240), ColorF(1, 1, 1, 0.5f));
  const half = px(100, 100);
  assert(half[0] == 255);

  // clearFrame resets the Canvas state
  cv.save();
  cv.translate(PointF(5, 5));
  cv.clip(rectPath(RectF(0, 0, 1, 1)));
  r.clearFrame(black);
  assert(cv.transform().isIdentity());
  assert(cv.fillStyle().color == ColorF(0, 0, 0, 1));
  cv.fillStyle(green);
  cv.fill(full);
  assert(isRgb(100, 100, 0, 255, 0));

  assert(glGetError() == GL_NO_ERROR);
}

// Canvas gradients (linear, multi-stop, radial, transformed, stroke)
unittest {
  import glad2.gles2;
  import std.math : abs;
  import yguilib.clibs.sdl3;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_canvas_gradients");
  win.create();
  scope(exit) win.destroy();
  win.setDisplayScaling(1.0f);
  auto r = win.renderer;
  r.setViewport(320, 240);
  auto cv = r.canvas();

  // logic (x, y) with y down; GL y = 240 - y
  ubyte[4] px(int x, int y) {
    ubyte[4] p;
    glReadPixels(x, 240 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p.ptr);
    return p;
  }

  bool near(int x, int y, int cr, int cg, int cb, int tol) {
    const p = px(x, y);
    return abs(p[0] - cr) <= tol && abs(p[1] - cg) <= tol
      && abs(p[2] - cb) <= tol;
  }

  Path2d rectPath(RectF rc) {
    auto p = new Path2d();
    p.rect(rc);
    return p;
  }

  const black = ColorF(0, 0, 0, 1);
  const red = ColorF(1, 0, 0, 1);
  const green = ColorF(0, 1, 0, 1);
  const blue = ColorF(0, 0, 1, 1);

  LinearGradient rb;
  rb.p0 = PointF(0, 0);
  rb.p1 = PointF(200, 0);
  rb.addColorStop(0, red).addColorStop(1, blue);

  // 1. linear red -> blue across a 200-wide rect
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromLinear(rb));
  cv.fill(rectPath(RectF(0, 0, 200, 50)));
  assert(near(10, 25, 242, 0, 13, 6));
  assert(near(190, 25, 13, 0, 242, 6));
  assert(near(100, 25, 128, 0, 128, 4));
  assert(near(250, 25, 0, 0, 0, 0)); // outside the rect

  // 2. three stops: the middle stop's color shows at offset 0.5
  LinearGradient rgb;
  rgb.p0 = PointF(0, 0);
  rgb.p1 = PointF(200, 0);
  rgb.addColorStop(0, red).addColorStop(0.5f, green).addColorStop(1, blue);
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromLinear(rgb));
  cv.fill(rectPath(RectF(0, 0, 200, 50)));
  assert(near(100, 25, 0, 255, 0, 3));
  assert(near(50, 25, 128, 128, 0, 4));

  // degenerate linear gradient (p0 == p1) draws nothing
  LinearGradient flat;
  flat.addColorStop(0, red);
  cv.fillStyle(FillStyle.fromLinear(flat));
  cv.fill(rectPath(RectF(0, 0, 200, 50)));
  assert(near(100, 25, 0, 255, 0, 3));

  // 3. radial: center is the first stop, near r1 the last, padded outside
  RadialGradient rad;
  rad.c0 = PointF(160, 120);
  rad.c1 = PointF(160, 120);
  rad.r0 = 0;
  rad.r1 = 50;
  rad.addColorStop(0, red).addColorStop(1, blue);
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromRadial(rad));
  cv.fill(rectPath(RectF(0, 0, 320, 240)));
  assert(near(160, 120, 255, 0, 0, 6));
  assert(near(205, 120, 25, 0, 230, 8));
  assert(near(160, 165, 25, 0, 230, 8));
  assert(near(240, 120, 0, 0, 255, 0));
  assert(near(5, 5, 0, 0, 255, 0));

  // 4. gradient follows the transform at the time of the fill
  r.clearFrame(black);
  cv.save();
  cv.translate(PointF(100, 0));
  cv.fillStyle(FillStyle.fromLinear(rb));
  cv.fill(rectPath(RectF(0, 0, 200, 50)));
  cv.restore();
  assert(near(110, 25, 242, 0, 13, 6));
  assert(near(290, 25, 13, 0, 242, 6));
  assert(near(200, 25, 128, 0, 128, 4));
  assert(near(50, 25, 0, 0, 0, 0));

  // 5. gradient stroke
  LinearGradient sg;
  sg.p0 = PointF(20, 0);
  sg.p1 = PointF(220, 0);
  sg.addColorStop(0, red).addColorStop(1, blue);
  r.clearFrame(black);
  cv.strokeStyle(FillStyle.fromLinear(sg));
  cv.lineWidth(10);
  auto line = new Path2d();
  line.moveTo(PointF(20, 150));
  line.lineTo(PointF(220, 150));
  cv.stroke(line);
  assert(near(30, 150, 242, 0, 13, 6));
  assert(near(210, 150, 13, 0, 242, 6));
  assert(near(120, 150, 128, 0, 128, 4));
  assert(near(120, 170, 0, 0, 0, 0));

  assert(glGetError() == GL_NO_ERROR);
}

// Canvas shadows (offscreen mask, blur, clip, scissor and state restore)
unittest {
  import glad2.gles2;
  import yguilib.clibs.sdl3;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_canvas_shadows");
  win.create();
  scope(exit) win.destroy();
  win.setDisplayScaling(1.0f);
  auto r = win.renderer;
  r.setViewport(320, 240);
  auto cv = r.canvas();

  // logic (x, y) with y down; GL y = 240 - y
  ubyte[4] px(int x, int y) {
    ubyte[4] p;
    glReadPixels(x, 240 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p.ptr);
    return p;
  }

  bool isRgb(int x, int y, int cr, int cg, int cb) {
    const p = px(x, y);
    return p[0] == cr && p[1] == cg && p[2] == cb;
  }

  Path2d rectPath(RectF rc) {
    auto p = new Path2d();
    p.rect(rc);
    return p;
  }

  const black = ColorF(0, 0, 0, 1);
  const green = FillStyle.solid(ColorF(0, 1, 0, 1));
  // right angle at the top-left: catches flipped shadow textures
  auto tri = new Path2d();
  tri.moveTo(PointF(50, 50));
  tri.lineTo(PointF(110, 50));
  tri.lineTo(PointF(50, 90));
  tri.closePath();

  // 1. invisible shadow (alpha 0) takes no FBO path, same pixels
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.fill(tri);
  ubyte[] plain = new ubyte[320 * 240 * 4];
  glReadPixels(0, 0, 320, 240, GL_RGBA, GL_UNSIGNED_BYTE, plain.ptr);
  Shadow hidden;
  hidden.offset = PointF(10, 10);
  hidden.blur = 4;
  cv.shadow(hidden);
  assert(!cv.shadow().isVisible());
  r.clearFrame(black); // resets the shadow too
  assert(cv.shadow().blur == 0);
  cv.shadow(hidden);
  cv.fillStyle(green);
  cv.fill(tri);
  ubyte[] same = new ubyte[320 * 240 * 4];
  glReadPixels(0, 0, 320, 240, GL_RGBA, GL_UNSIGNED_BYTE, same.ptr);
  assert(plain == same);
  assert(r.offscreenTargetRef(0).fbo == 0);

  // 2. hard shadow (blur 0) at offset (10, 10) under the shape
  Shadow hard;
  hard.offset = PointF(10, 10);
  hard.color = ColorF(1, 0, 0, 1);
  r.clearFrame(black);
  cv.save();
  cv.shadow(hard);
  assert(cv.shadow().isVisible());
  cv.fillStyle(green);
  cv.fill(tri);
  cv.restore();
  assert(!cv.shadow().isVisible());
  assert(r.offscreenTargetRef(0).fbo != 0);
  assert(isRgb(55, 55, 0, 255, 0)); // shape over the shadow
  assert(isRgb(65, 65, 0, 255, 0));
  assert(isRgb(115, 62, 255, 0, 0)); // shadow outside the shape
  assert(isRgb(62, 98, 255, 0, 0));
  assert(isRgb(115, 95, 0, 0, 0));
  assert(isRgb(45, 45, 0, 0, 0));
  // 2b. shadow alpha = shadow color alpha * paint alpha
  bool near(int v, int expected) {
    return v >= expected - 3 && v <= expected + 3;
  }

  r.clearFrame(black);
  cv.shadow(hard);
  cv.fillStyle(FillStyle.solid(ColorF(0, 1, 0, 0.5f)));
  cv.fill(tri);
  // shadow only: red at 0.5 over black
  auto halfShadow = px(115, 62);
  assert(near(halfShadow[0], 128) && halfShadow[1] == 0);
  // overlap: 0.5 green over the 0.5 red shadow
  auto overlap = px(65, 65);
  assert(near(overlap[0], 64) && near(overlap[1], 128));
  // gradient paint fading to transparent: the shadow fades the same way
  r.clearFrame(black);
  cv.shadow(hard);
  LinearGradient fade;
  fade.p0 = PointF(100, 0);
  fade.p1 = PointF(200, 0);
  fade.addColorStop(0, ColorF(0, 1, 0, 1));
  fade.addColorStop(1, ColorF(0, 1, 0, 0));
  cv.fillStyle(FillStyle.fromLinear(fade));
  cv.fill(rectPath(RectF(100, 100, 100, 40)));
  // below the shape (y 140..150) only the shadow shows
  const sLeft = px(112, 145)[0];
  const sMid = px(160, 145)[0];
  const sRight = px(205, 145)[0];
  assert(sLeft > 200 && near(sMid, 128) && sRight < 20);
  cv.shadow(Shadow.init);

  // invalid shadows are ignored
  Shadow bad = hard;
  bad.blur = -1;
  cv.shadow(bad);
  assert(!cv.shadow().isVisible());

  // 3. blur 8 (sigma 4 px): partial alpha falling off outward
  Shadow soft;
  soft.blur = 8;
  soft.color = ColorF(1, 0, 0, 1);
  r.clearFrame(black);
  cv.shadow(soft);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(100, 80, 80, 60)));
  const edge = px(181, 110);
  assert(edge[0] > 0 && edge[0] < 255 && edge[1] == 0);
  foreach (x; 181 .. 196) {
    assert(px(x, 110)[0] >= px(x + 1, 110)[0]);
  }
  assert(px(181, 110)[0] > px(186, 110)[0]);
  assert(px(196, 110)[0] <= 2);
  assert(isRgb(178, 110, 0, 255, 0));

  // 4. shadow on a stroke
  r.clearFrame(black);
  cv.shadow(hard);
  cv.strokeStyle(FillStyle.solid(ColorF(0, 0, 1, 1)));
  cv.lineWidth(6);
  auto line = new Path2d();
  line.moveTo(PointF(20, 200));
  line.lineTo(PointF(120, 200));
  cv.stroke(line);
  assert(isRgb(60, 200, 0, 0, 255));
  assert(isRgb(60, 210, 255, 0, 0));
  assert(isRgb(60, 190, 0, 0, 0));

  // 5. Canvas clip applies; scissor and viewport are restored
  r.clearFrame(black);
  r.pushClipRect(RectF(0, 0, 200, 200));
  GLint[4] boxBefore;
  glGetIntegerv(GL_SCISSOR_BOX, boxBefore.ptr);
  GLint[4] vpBefore;
  glGetIntegerv(GL_VIEWPORT, vpBefore.ptr);
  cv.save();
  cv.clip(rectPath(RectF(0, 0, 160, 240)));
  cv.shadow(hard);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(140, 50, 40, 40)));
  cv.restore();
  assert(isRgb(155, 95, 255, 0, 0)); // shadow inside the clip
  assert(isRgb(165, 95, 0, 0, 0)); // shadow outside the clip
  assert(isRgb(150, 70, 0, 255, 0));
  GLint[4] boxAfter;
  glGetIntegerv(GL_SCISSOR_BOX, boxAfter.ptr);
  GLint[4] vpAfter;
  glGetIntegerv(GL_VIEWPORT, vpAfter.ptr);
  assert(boxAfter == boxBefore && vpAfter == vpBefore);
  assert(glIsEnabled(GL_SCISSOR_TEST) == GL_TRUE);
  GLint fbo = -1;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fbo);
  assert(fbo == 0);
  r.drawFillRect(RectF(0, 0, 320, 240), ColorF(0, 0, 1, 1));
  r.popClipRect();
  assert(isRgb(5, 5, 0, 0, 255));
  assert(isRgb(210, 210, 0, 0, 0));
  assert(isRgb(250, 100, 0, 0, 0));

  // the shadow is limited by the Renderer scissor too
  r.clearFrame(black);
  r.pushClipRect(RectF(0, 0, 100, 240));
  cv.shadow(hard);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(60, 50, 40, 40)));
  r.popClipRect();
  assert(isRgb(95, 95, 255, 0, 0));
  assert(isRgb(105, 95, 0, 0, 0));

  assert(glGetError() == GL_NO_ERROR);
}
