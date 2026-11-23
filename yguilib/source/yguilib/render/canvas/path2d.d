/**
 * 2D vector path geometry (`Path2d` and `PathVerb`) for `Canvas`.
 */
module yguilib.render.canvas.path2d;

import std.array : Appender;
import yguilib.render.canvas.types : Transform2d;
import yguilib.render.render_types : PointF, RectF, boundsOfPoints,
  isFinitePoint, isFiniteRect;

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
 * Similar to Canvas web API Path2D (MDN semantics), including SVG path
 * data strings via `fromSvgPath` and `addSvgPath`; uses float for coords
 * and angles (radians).
 * Arcs and ellipses are stored as cubic Bézier segments of at most 90°.
 * Negative radii and non-finite inputs are ignored (no-op).
 */
final class Path2d {
  /// Starts a new subpath at `p`.
  void moveTo(PointF p) nothrow @safe {
    if (!isFinitePoint(p)) {
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
    if (!isFinitePoint(p)) {
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
    if (!isFinitePoint(cp) || !isFinitePoint(p)) {
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
    if (!isFinitePoint(cp1) || !isFinitePoint(cp2) || !isFinitePoint(p)) {
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
   * to `p1`. With no current point it only moves to `p1` (as in HTML).
   */
  void arcTo(PointF p1, PointF p2, float radius) nothrow @safe {
    import std.math : abs, acos, atan2, isFinite, PI, sqrt, tan, sin;

    if (!isFinitePoint(p1) || !isFinitePoint(p2) || !isFinite(radius)
      || radius < 0) {
      return;
    }
    if (!fHasSubpath) {
      moveTo(p1);
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
   *
   * Takes 6 parameters without a parameter struct on purpose: it mirrors
   * HTML `CanvasPath.ellipse()` argument by argument.
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

    if (!isFinitePoint(center) || !isFinitePoint(radii) || !isFinite(rotation)
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
    if (!isFiniteRect(r)) {
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

    if (!isFiniteRect(r) || !isFinite(radius) || radius < 0) {
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
    // slices taken before reserving stay valid when other is this (the
    // GC keeps the old buffer alive if reserve moves the data)
    const PathVerb[] srcVerbs = other.fVerbs[];
    const PointF[] srcPoints = other.fPoints[];
    if (srcVerbs.length == 0) {
      return;
    }
    const bool otherClosed = other.fClosed;
    const PointF otherStart = other.fSubpathStart;
    const PointF otherCur = other.fCurrent;
    fVerbs.reserve(fVerbs[].length + srcVerbs.length);
    fPoints.reserve(fPoints[].length + srcPoints.length);
    fVerbs.put(srcVerbs);
    foreach (p; srcPoints) {
      fPoints.put(t.apply(p));
    }
    fHasSubpath = true;
    fClosed = otherClosed;
    fSubpathStart = t.apply(otherStart);
    fCurrent = t.apply(otherCur);
  }

  /// Creates a `Path2d` parsed from an SVG path data string `d`.
  static Path2d fromSvgPath(string d) nothrow @safe {
    auto p = new Path2d();
    p.addSvgPath(d);
    return p;
  }

  /**
   * Parses SVG path data string `d` and appends its commands to `this`.
   * Stops on the first syntax error, keeping any already-emitted commands,
   * and returns `false` on error (`true` on success).
   */
  bool addSvgPath(string d) nothrow @safe {
    import yguilib.render.internal.svg_path_parser : parseSvgPathInto;

    return parseSvgPathInto(this, d);
  }

  /// Removes all subpaths, keeping the buffer capacity.
  void clear() nothrow @safe {
    fVerbs.clear();
    fPoints.clear();
    fHasSubpath = false;
    fClosed = false;
    fSubpathStart = PointF.init;
    fCurrent = PointF.init;
  }

  /// True when no verbs were added.
  bool isEmpty() const nothrow @safe @nogc {
    return fVerbs[].length == 0;
  }

  /// Bounds of all points including control points; empty is all zeros.
  RectF bounds() const nothrow @safe @nogc {
    return boundsOfPoints(fPoints[]);
  }

package(yguilib):
  /// Stored verbs; see `pointCountOfVerb` for points per verb.
  const(PathVerb)[] verbs() const nothrow @safe @nogc {
    return fVerbs[];
  }

  /// Stored points for all verbs, in order.
  const(PointF)[] points() const nothrow @safe @nogc {
    return fPoints[];
  }

  /**
   * Appends an SVG elliptical arc as cubic Bézier segments of at most 90°
   * directly from the current point (without inserting a `lineTo` to the
   * arc start) and snaps the final endpoint to `arc.endPoint`.
   */
  void appendSvgArc(in SvgArcParams arc) nothrow @safe {
    import std.math : isFinite;

    if (arc.sweep == 0 || !isFinitePoint(arc.center)
        || !isFinitePoint(arc.radii) || !isFinitePoint(arc.endPoint)
        || !isFinite(arc.rotation) || !isFinite(arc.startAngle)
        || !isFinite(arc.sweep)) {
      return;
    }
    appendArcCubics(arc, true);
  }

private:
  Appender!(PathVerb[]) fVerbs;
  Appender!(PointF[]) fPoints;
  bool fHasSubpath;
  /// true right after closePath (until the next verb)
  bool fClosed;
  PointF fSubpathStart;
  PointF fCurrent;

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
    import std.math : abs, cos, PI, sin;

    const double cr = cos(cast(double) rotation);
    const double sr = sin(cast(double) rotation);
    const double a0 = startAngle;
    const double x0 = cos(a0) * radii.x;
    const double y0 = sin(a0) * radii.y;
    const PointF start = PointF(
      cast(float)(center.x + x0 * cr - y0 * sr),
      cast(float)(center.y + x0 * sr + y0 * cr)
    );
    if (fHasSubpath) {
      lineTo(start);
    } else {
      moveTo(start);
    }
    if (sweep == 0) {
      return;
    }
    const bool full = abs(sweep) >= 2 * PI - 1e-6;
    const SvgArcParams params = SvgArcParams(
      center, radii, rotation, startAngle, sweep, start
    );
    appendArcCubics(params, full);
  }

  void appendArcCubics(in SvgArcParams arc, bool snapEnd) nothrow @safe {
    import std.math : abs, ceil, cos, PI, sin, tan;

    const double cr = cos(cast(double) arc.rotation);
    const double sr = sin(cast(double) arc.rotation);
    PointF map(double ux, double uy) {
      const double x = ux * arc.radii.x;
      const double y = uy * arc.radii.y;
      return PointF(
        cast(float)(arc.center.x + x * cr - y * sr),
        cast(float)(arc.center.y + x * sr + y * cr)
      );
    }

    int n = cast(int) ceil(abs(cast(double) arc.sweep) / (PI / 2) - 1e-4);
    n = n < 1 ? 1 : n;
    const double step = cast(double) arc.sweep / n;
    const double k = 4.0 / 3.0 * tan(step / 4);
    const double a0 = arc.startAngle;
    foreach (i; 0 .. n) {
      const double s0 = a0 + step * i;
      const double s1 = s0 + step;
      const double c0 = cos(s0);
      const double n0 = sin(s0);
      const double c1 = cos(s1);
      const double n1 = sin(s1);
      const PointF end = (snapEnd && i == n - 1)
        ? arc.endPoint : map(c1, n1);
      bezierCurveTo(
        map(c0 - k * n0, n0 + k * c0),
        map(c1 + k * n1, n1 - k * c1),
        end
      );
    }
  }
}

package(yguilib):

/// Center-parameterized arc descriptor for `Path2d.appendSvgArc`.
struct SvgArcParams {
  PointF center;
  PointF radii;
  float rotation = 0;
  float startAngle = 0;
  float sweep = 0;
  PointF endPoint;
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
  // arcTo without a current point only moves to p1 (HTML)
  p.clear();
  p.arcTo(PointF(5, 0), PointF(10, 10), 3);
  assert(p.verbs == [PathVerb.moveTo]);
  assert(p.points == [PointF(5, 0)]);

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

// clearing and rebuilding a warmed-up Path2d does not allocate
unittest {
  import core.memory : GC;

  auto p = new Path2d();
  auto q = new Path2d();
  void build() {
    p.clear();
    p.rect(RectF(0, 0, 10, 10));
    p.roundRect(RectF(1, 1, 8, 8), 2);
    p.arc(PointF(5, 5), 4, 0, 6, false);
    q.clear();
    q.addPath(p, Transform2d.translation(PointF(3, 4)));
  }
  build();
  const size_t nv = p.verbs.length;
  const size_t nq = q.points.length;

  GC.collect();
  const before = GC.stats();
  foreach (_; 0 .. 100) {
    build();
  }
  const after = GC.stats();
  assert(p.verbs.length == nv && q.points.length == nq);
  assert(after.allocatedInCurrentThread == before.allocatedInCurrentThread);
  assert(
    after.usedSize + after.freeSize <= before.usedSize + before.freeSize
  );
}

// warmed-up Path2d.addSvgPath (curves and arcs) allocates 0 bytes
unittest {
  import core.memory : GC;

  enum string svg =
    "M 10 20 L 30 40 H 50 V 60 "
    ~ "C 60 10, 90 10, 100 60 S 130 90, 150 60 "
    ~ "Q 160 20, 180 60 T 210 60 "
    ~ "A 25 15 30 0 1 260 60 Z";
  auto p = new Path2d();
  assert(p.addSvgPath(svg));
  const size_t nv = p.verbs.length;
  const size_t np = p.points.length;

  GC.collect();
  const before = GC.stats();
  foreach (_; 0 .. 100) {
    p.clear();
    assert(p.addSvgPath(svg));
  }
  const after = GC.stats();
  assert(p.verbs.length == nv && p.points.length == np);
  assert(after.allocatedInCurrentThread == before.allocatedInCurrentThread);
  assert(
    after.usedSize + after.freeSize <= before.usedSize + before.freeSize
  );
}
