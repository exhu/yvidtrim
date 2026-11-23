/// Flattens `Path2d` curves into polyline contours (CPU, path-local space).
module yguilib.render.internal.path_flatten;

package(yguilib):

import std.array : Appender;
import yguilib.render.canvas.path2d : Path2d, PathVerb;
import yguilib.render.canvas.types : Transform2d;
import yguilib.render.render_types : PointF;

/// One polyline in `Contours.points[start .. start + count]`.
struct ContourInfo {
  size_t start;
  size_t count;
  bool closed;
}

/// Reusable output buffers of `flattenPath`.
struct Contours {
  Appender!(PointF[]) points;
  Appender!(ContourInfo[]) infos;

  /// Empties both buffers, keeping their capacity.
  void clear() nothrow @safe {
    points.clear();
    infos.clear();
  }
}

/**
 * Flattens `p` into `dst` (cleared first) so that curves deviate from
 * their chords by roughly `tolerance` at most. Consecutive duplicate
 * points and contours with fewer than 2 points are dropped. A closed
 * contour does not repeat its first point at the end.
 */
void flattenPath(const Path2d p, float tolerance, ref Contours dst)
  nothrow @safe {
  assert(p !is null);
  dst.clear();
  const float tol = tolerance > 1e-6f ? tolerance : 1e-6f;
  Flattener fl;
  const verbs = p.verbs();
  const pts = p.points();
  size_t pi = 0;
  foreach (v; verbs) {
    final switch (v) {
    case PathVerb.moveTo:
      fl.finish(dst, false);
      fl.lastMove = pts[pi];
      fl.begin(dst, pts[pi]);
      pi += 1;
      break;
    case PathVerb.lineTo:
      fl.ensureOpen(dst);
      fl.add(dst, pts[pi]);
      pi += 1;
      break;
    case PathVerb.quadTo:
      fl.ensureOpen(dst);
      fl.quad(dst, pts[pi], pts[pi + 1], tol);
      pi += 2;
      break;
    case PathVerb.cubicTo:
      fl.ensureOpen(dst);
      fl.cubic(dst, pts[pi], pts[pi + 1], pts[pi + 2], tol);
      pi += 3;
      break;
    case PathVerb.close:
      fl.finish(dst, true);
      break;
    }
  }
  fl.finish(dst, false);
}

/**
 * True when `c` is one contour (closed, or implicitly closed as a fill
 * closes it) forming a convex polygon of non-zero area, so its fan
 * triangles do not overlap and fill it exactly once for both fill rules.
 * Zero-length edges are skipped; collinear edges are allowed only when
 * they continue forward. Every turn must have the same sign and each
 * axis direction may flip at most twice around the contour (rejects
 * contours that wind more than once, like a pentagram).
 */
bool isSingleConvex(const ref Contours c) nothrow @safe @nogc {
  const ContourInfo[] infos = c.infos[];
  if (infos.length != 1 || infos[0].count < 3) {
    return false;
  }
  const PointF[] pts =
    c.points[][infos[0].start .. infos[0].start + infos[0].count];
  ConvexScan s;
  foreach (i, a; pts) {
    const PointF b = pts[i + 1 < pts.length ? i + 1 : 0];
    if (!s.edge(PointF(b.x - a.x, b.y - a.y))) {
      return false;
    }
  }
  return s.finish();
}

/// Path-local flattening tolerance for a device tolerance of 0.25 px.
float flattenTolerance(float totalScaling, in Transform2d t)
  nothrow @safe @nogc {
  const float s = totalScaling * t.maxScale();
  return 0.25f / (s > 1e-6f ? s : 1e-6f);
}

private:

enum int maxSegments = 256;

struct Flattener {
  PointF lastMove;
  PointF cur;
  size_t start;
  bool open;

  void begin(ref Contours dst, PointF p) nothrow @safe {
    start = dst.points[].length;
    open = true;
    dst.points.put(p);
    cur = p;
  }

  /// After closePath, a non-moveTo verb starts at the last moveTo point.
  void ensureOpen(ref Contours dst) nothrow @safe {
    if (!open) {
      begin(dst, lastMove);
    }
  }

  void add(ref Contours dst, PointF p) nothrow @safe {
    if (p == cur) {
      return;
    }
    dst.points.put(p);
    cur = p;
  }

  void finish(ref Contours dst, bool closed) nothrow @safe {
    if (!open) {
      return;
    }
    open = false;
    size_t count = dst.points[].length - start;
    if (closed && count > 1 && dst.points[][$ - 1] == dst.points[][start]) {
      count -= 1;
      shrinkPoints(dst, start + count);
    }
    if (count < 2) {
      shrinkPoints(dst, start);
    } else {
      dst.infos.put(ContourInfo(start, count, closed));
    }
    cur = lastMove;
  }

  void quad(ref Contours dst, PointF c, PointF e, float tol) nothrow @safe {
    const PointF s = cur;
    const float ddx = s.x - 2 * c.x + e.x;
    const float ddy = s.y - 2 * c.y + e.y;
    const int n = segmentCount(ddx * ddx + ddy * ddy, 0.25f, tol);
    foreach (i; 1 .. n) {
      const float t = cast(float) i / n;
      const float u = 1 - t;
      add(dst, PointF(
        u * u * s.x + 2 * u * t * c.x + t * t * e.x,
        u * u * s.y + 2 * u * t * c.y + t * t * e.y
      ));
    }
    add(dst, e);
  }

  void cubic(
    ref Contours dst, PointF c1, PointF c2, PointF e, float tol
  ) nothrow @safe {
    const PointF s = cur;
    const float d1x = s.x - 2 * c1.x + c2.x;
    const float d1y = s.y - 2 * c1.y + c2.y;
    const float d2x = c1.x - 2 * c2.x + e.x;
    const float d2y = c1.y - 2 * c2.y + e.y;
    const float dd1 = d1x * d1x + d1y * d1y;
    const float dd2 = d2x * d2x + d2y * d2y;
    const int n = segmentCount(dd1 > dd2 ? dd1 : dd2, 0.75f, tol);
    foreach (i; 1 .. n) {
      const float t = cast(float) i / n;
      const float u = 1 - t;
      const float b0 = u * u * u;
      const float b1 = 3 * u * u * t;
      const float b2 = 3 * u * t * t;
      const float b3 = t * t * t;
      add(dst, PointF(
        b0 * s.x + b1 * c1.x + b2 * c2.x + b3 * e.x,
        b0 * s.y + b1 * c1.y + b2 * c2.y + b3 * e.y
      ));
    }
    add(dst, e);
  }
}

/// Edge-by-edge state of `isSingleConvex`.
struct ConvexScan {
  PointF first;
  PointF prev;
  bool any;
  /// Sign of the turns seen so far (0: none yet).
  int turn;
  /// Direction sign flips per axis and the first/last non-zero sign.
  AxisFlips xs;
  AxisFlips ys;

  /// Adds edge `e`; false as soon as the polygon cannot be convex.
  bool edge(PointF e) nothrow @safe @nogc {
    if (e.x == 0 && e.y == 0) {
      return true;
    }
    if (!any) {
      first = e;
      any = true;
    } else if (!turnOk(prev, e)) {
      return false;
    }
    prev = e;
    xs.add(e.x);
    ys.add(e.y);
    return xs.flips <= 2 && ys.flips <= 2;
  }

  /// Closes the scan (last edge to first edge).
  bool finish() nothrow @safe @nogc {
    if (!any || !turnOk(prev, first)) {
      return false;
    }
    return turn != 0 && xs.cyclicFlips() <= 2 && ys.cyclicFlips() <= 2;
  }

  bool turnOk(PointF p, PointF e) nothrow @safe @nogc {
    import std.math : abs;

    const float cross = p.x * e.y - p.y * e.x;
    const float dot = p.x * e.x + p.y * e.y;
    // relative tolerance: rounding noise on nearly collinear edges
    const float tol =
      1e-6f * (abs(p.x) + abs(p.y)) * (abs(e.x) + abs(e.y));
    if (abs(cross) <= tol) {
      return dot > 0;
    }
    const int s = cross > 0 ? 1 : -1;
    if (turn == 0) {
      turn = s;
    }
    return s == turn;
  }
}

/// Sign changes of one coordinate along the edges of a contour.
struct AxisFlips {
  int firstSign;
  int lastSign;
  int flips;

  void add(float v) nothrow @safe @nogc {
    const int s = v > 0 ? 1 : (v < 0 ? -1 : 0);
    if (s == 0) {
      return;
    }
    if (firstSign == 0) {
      firstSign = s;
    } else if (s != lastSign) {
      ++flips;
    }
    lastSign = s;
  }

  /// `flips` plus the change from the last edge back to the first.
  int cyclicFlips() const nothrow @safe @nogc {
    return flips + (lastSign != firstSign ? 1 : 0);
  }
}

/// `Appender.shrinkTo` only throws when growing, which never happens here.
void shrinkPoints(ref Contours dst, size_t len) nothrow @safe {
  try {
    dst.points.shrinkTo(len);
  } catch (Exception e) {
    assert(0, e.msg);
  }
}

/// Wang's formula: `ceil(sqrt(sqrt(dd) * k / tol))` clamped to [1, 256].
int segmentCount(float dd, float k, float tol) nothrow @safe @nogc {
  import std.math : ceil, isFinite, sqrt;

  const float n = ceil(sqrt(sqrt(dd) * k / tol));
  if (!isFinite(n) || n > maxSegments) {
    return maxSegments;
  }
  return n < 1 ? 1 : cast(int) n;
}

unittest {
  import std.math : PI, sqrt;
  import yguilib.render.render_types : RectF;

  Contours c;

  // circle r=100: points lie on the curve; cubic approximation bulges
  // outward by up to ~0.027% of the radius
  auto circle = new Path2d();
  circle.arc(PointF(50, 50), 100, 0, cast(float)(2 * PI), false);
  circle.closePath();
  flattenPath(circle, 0.25f, c);
  assert(c.infos[].length == 1);
  assert(c.infos[][0].closed);
  const size_t coarse = c.points[].length;
  assert(coarse > 8);
  foreach (p; c.points[]) {
    const float dx = p.x - 50;
    const float dy = p.y - 50;
    const float r = sqrt(dx * dx + dy * dy);
    assert(r >= 99.7f && r <= 100.03f);
  }

  // tighter tolerance gives more points
  flattenPath(circle, 0.01f, c);
  assert(c.points[].length > coarse);

  // a line stays 2 points
  auto line = new Path2d();
  line.moveTo(PointF(0, 0));
  line.lineTo(PointF(10, 5));
  line.lineTo(PointF(10, 5));
  flattenPath(line, 0.25f, c);
  assert(c.infos[].length == 1);
  assert(c.points[] == [PointF(0, 0), PointF(10, 5)]);
  assert(!c.infos[][0].closed);

  // empty path and lone moveTo give no contours
  flattenPath(new Path2d(), 0.25f, c);
  assert(c.infos[].length == 0 && c.points[].length == 0);
  auto lone = new Path2d();
  lone.moveTo(PointF(1, 1));
  lone.moveTo(PointF(2, 2));
  lone.lineTo(PointF(3, 3));
  flattenPath(lone, 0.25f, c);
  assert(c.infos[].length == 1);
  assert(c.points[] == [PointF(2, 2), PointF(3, 3)]);

  // rect is closed; a lineTo after close starts at the moveTo point
  auto r = new Path2d();
  r.rect(RectF(0, 0, 10, 10));
  r.lineTo(PointF(-5, -5));
  flattenPath(r, 0.25f, c);
  assert(c.infos[].length == 2);
  assert(c.infos[][0] == ContourInfo(0, 4, true));
  assert(c.infos[][1] == ContourInfo(4, 2, false));
  assert(c.points[][4 .. 6] == [PointF(0, 0), PointF(-5, -5)]);

  // isSingleConvex
  auto rr = new Path2d();
  rr.rect(RectF(0, 0, 10, 10));
  flattenPath(rr, 0.25f, c);
  assert(isSingleConvex(c));
  // negative size (reversed winding) is still convex
  rr.clear();
  rr.rect(RectF(10, 10, -10, -5));
  flattenPath(rr, 0.25f, c);
  assert(isSingleConvex(c));
  flattenPath(circle, 0.01f, c);
  assert(isSingleConvex(c));
  rr.clear();
  rr.roundRect(RectF(5, 5, 100, 40), 12);
  flattenPath(rr, 0.1f, c);
  assert(isSingleConvex(c));
  // open contour: filled as if closed
  rr.clear();
  rr.moveTo(PointF(0, 0));
  rr.lineTo(PointF(10, 0));
  rr.lineTo(PointF(5, 8));
  flattenPath(rr, 0.25f, c);
  assert(isSingleConvex(c));
  // collinear forward point is fine
  rr.clear();
  rr.moveTo(PointF(0, 0));
  rr.lineTo(PointF(5, 0));
  rr.lineTo(PointF(10, 0));
  rr.lineTo(PointF(10, 10));
  rr.closePath();
  flattenPath(rr, 0.25f, c);
  assert(isSingleConvex(c));
  // concave arrow
  rr.clear();
  rr.moveTo(PointF(0, 0));
  rr.lineTo(PointF(10, 5));
  rr.lineTo(PointF(0, 10));
  rr.lineTo(PointF(4, 5));
  rr.closePath();
  flattenPath(rr, 0.25f, c);
  assert(!isSingleConvex(c));
  // pentagram: all turns have the same sign but it winds twice
  rr.clear();
  foreach (k; 0 .. 5) {
    import std.math : cos, sin;

    const float ang = cast(float)(-PI / 2 + k * 4 * PI / 5);
    const PointF pt = PointF(50 + 40 * cos(ang), 50 + 40 * sin(ang));
    if (k == 0) {
      rr.moveTo(pt);
    } else {
      rr.lineTo(pt);
    }
  }
  rr.closePath();
  flattenPath(rr, 0.25f, c);
  assert(!isSingleConvex(c));
  // two contours, a degenerate line, a back-and-forth spike
  rr.clear();
  rr.rect(RectF(0, 0, 5, 5));
  rr.rect(RectF(10, 0, 5, 5));
  flattenPath(rr, 0.25f, c);
  assert(!isSingleConvex(c));
  rr.clear();
  rr.moveTo(PointF(0, 0));
  rr.lineTo(PointF(5, 5));
  rr.lineTo(PointF(10, 10));
  rr.closePath();
  flattenPath(rr, 0.25f, c);
  assert(!isSingleConvex(c));
  flattenPath(line, 0.25f, c);
  assert(!isSingleConvex(c));

  // flattenTolerance
  assert(flattenTolerance(1, Transform2d.identity()) == 0.25f);
  const t2 = Transform2d.scaling(PointF(2, 0.5f));
  assert(flattenTolerance(2, t2) == 0.25f / 4);
}
