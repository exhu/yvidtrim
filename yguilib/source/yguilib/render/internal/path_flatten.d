/// Flattens `Path2d` curves into polyline contours (CPU, path-local space).
module yguilib.render.internal.path_flatten;

package(yguilib):

import std.array : Appender;
import yguilib.render.canvas : Path2d, PathVerb, Transform2d;
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

  // flattenTolerance
  assert(flattenTolerance(1, Transform2d.identity()) == 0.25f);
  const t2 = Transform2d.scaling(PointF(2, 0.5f));
  assert(flattenTolerance(2, t2) == 0.25f / 4);
}
