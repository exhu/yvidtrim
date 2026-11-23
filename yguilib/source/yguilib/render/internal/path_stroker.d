/**
 * Turns flattened contours into stroke triangles (CPU, path-local space).
 * Output is a flat list of `x, y` float pairs, 3 vertices per triangle.
 * Triangles may overlap; the caller draws them with a "draw once" stencil.
 */
module yguilib.render.internal.path_stroker;

package(yguilib):

import std.array : Appender;
import std.math : PI, abs, acos, atan2, ceil, cos, isFinite, sin, sqrt;
import yguilib.render.canvas.types : LineCap, LineDash, LineJoin;
import yguilib.render.internal.path_flatten : ContourInfo, Contours;
import yguilib.render.render_types : PointF;

/// Stroke style for `strokeContours`.
struct StrokeParams {
  float width = 1;
  LineCap cap = LineCap.butt;
  LineJoin join = LineJoin.miter;
  float miterLimit = 10;
  /// Normalized dash/gap lengths (see `LineDash`); solid by default.
  LineDash dash;
  float dashOffset = 0;
  float tolerance = 0.25f; // for round caps/joins tessellation
}

/**
 * Appends the stroke triangles of all contours of `c` to `tris` (not
 * cleared). Width <= 0 or non-finite width draws nothing. A dashed `p`
 * writes its dash sub-contours into `dashScratch` (overwritten; passed
 * explicitly so the caller keeps its capacity across strokes).
 */
void strokeContours(
  ref const Contours c,
  in StrokeParams p,
  ref Appender!(float[]) tris,
  ref Contours dashScratch
) nothrow @safe {
  if (!isFinite(p.width) || p.width <= 0) {
    return;
  }
  Stroker s;
  s.tris = () @trusted { return &tris; }();
  s.hw = p.width * 0.5f;
  s.cap = p.cap;
  s.join = p.join;
  s.miterLimit = p.miterLimit;
  s.tolerance = isFinite(p.tolerance) && p.tolerance > 1e-4f
    ? p.tolerance : 1e-4f;
  if (isDashed(p.dash)) {
    applyDashInto(c, p.dash, p.dashOffset, dashScratch);
    s.strokeAll(dashScratch);
  } else {
    s.strokeAll(c);
  }
}

/**
 * Splits each contour of `c` into open sub-contours along its arc length
 * using the dash/gap lengths `dash` starting at phase `offset` (wrapped
 * into the period), written into `dst` (cleared first). A closed contour
 * is dashed across its closing segment and its first and last dash are
 * merged when both touch the seam. A zero-length dash gives a 1-point
 * contour. A solid or non-finite-period `dash`, or one producing more
 * than `maxDashes`, copies `c` into `dst`.
 */
void applyDashInto(
  ref const Contours c, in LineDash dash, float offset, ref Contours dst
) nothrow @safe {
  dst.clear();
  if (!isDashed(dash) || tooManyDashes(c, dash)) {
    dst.points.put(c.points[]);
    dst.infos.put(c.infos[]);
    return;
  }
  const DashPattern pat = DashPattern(dash, offset);
  foreach (info; c.infos[]) {
    const PointF[] pts = c.points[][info.start .. info.start + info.count];
    dashContour(pts, info.closed, pat, dst);
  }
}

/// Upper bound of dashes per `applyDashInto` call before dashing is
/// skipped.
enum size_t maxDashes = 100_000;

private:

enum float eps = 1e-6f;
enum int maxFanSegments = 256;

/// `LineDash` validates its segments; only the period sum can overflow.
bool isDashed(in LineDash dash) nothrow @safe @nogc {
  return !dash.isSolid() && isFinite(dash.period());
}

float contourLength(const PointF[] pts, bool closed) nothrow @safe @nogc {
  float len = 0;
  foreach (i; 1 .. pts.length) {
    len += dist(pts[i - 1], pts[i]);
  }
  if (closed && pts.length > 1) {
    len += dist(pts[$ - 1], pts[0]);
  }
  return len;
}

bool tooManyDashes(ref const Contours c, in LineDash dash)
  nothrow @safe @nogc {
  float total = 0;
  foreach (info; c.infos[]) {
    const PointF[] pts = c.points[][info.start .. info.start + info.count];
    total += contourLength(pts, info.closed);
  }
  const float n = total / dash.period() * dash.segments.length;
  return !isFinite(n) || n > maxDashes;
}

/// Dash pattern state: segment lengths and the phase start position.
struct DashPattern {
  LineDash dash;
  size_t len;
  size_t startIdx;
  float startLeft;

  this(in LineDash d, float offset) nothrow @safe @nogc {
    import std.math : fmod;

    dash = d;
    len = d.segments.length;
    const float period = d.period();
    float phase = isFinite(offset) ? fmod(offset, period) : 0;
    if (phase < 0) {
      phase += period;
    }
    size_t idx = 0;
    while (phase >= seg(idx) && phase > 0) {
      phase -= seg(idx);
      idx = (idx + 1) % len;
    }
    startIdx = idx;
    startLeft = seg(idx) - phase;
  }

  float seg(size_t i) const nothrow @safe @nogc {
    return dash.segments[i % len];
  }
}

/// Builds dash sub-contours of one contour into `dst`.
struct DashWriter {
  Contours* dst;
  bool open;
  size_t start;

  void startSub(PointF p) nothrow @safe {
    open = true;
    start = dst.points[].length;
    dst.points.put(p);
  }

  void addPoint(PointF p) nothrow @safe {
    if (dst.points[][$ - 1] != p) {
      dst.points.put(p);
    }
  }

  /// Drops the open sub-contour's points.
  void discardSub() nothrow @safe {
    open = false;
    try {
      dst.points.shrinkTo(start);
    } catch (Exception e) {
      assert(0, e.msg);
    }
  }

  /// Ends the open sub-contour and returns its info.
  ContourInfo endSub() nothrow @safe {
    open = false;
    return ContourInfo(start, dst.points[].length - start, false);
  }
}

void dashContour(
  const PointF[] pts, bool closed, in DashPattern pat, ref Contours dst
) nothrow @safe {
  const size_t firstInfo = dst.infos[].length;
  const size_t firstPoint = dst.points[].length;
  DashWriter w = DashWriter(() @trusted { return &dst; }());
  size_t idx = pat.startIdx;
  float left = pat.startLeft;
  const bool startedOn = idx % 2 == 0;
  size_t toggles = 0;
  if (startedOn) {
    w.startSub(pts[0]);
  }
  const size_t segCount = closed ? pts.length : pts.length - 1;
  foreach (i; 0 .. segCount) {
    const PointF a = pts[i];
    const PointF b = pts[(i + 1) % pts.length];
    const float len = dist(a, b);
    float pos = 0;
    while (left <= len - pos) {
      pos += left;
      const PointF pt = lerp(a, b, len > 0 ? pos / len : 1);
      if (idx % 2 == 0) {
        w.addPoint(pt);
        dst.infos.put(w.endSub());
      } else if (!closed && i + 1 == segCount && pos >= len) {
        return; // dashes only start before the end of an open contour
      } else {
        w.startSub(pt);
      }
      idx = (idx + 1) % pat.len;
      left = pat.seg(idx);
      toggles += 1;
    }
    left -= len - pos;
    if (w.open) {
      w.addPoint(b);
    }
  }
  if (!w.open) {
    return;
  }
  if (toggles == 0) {
    // fully "on": keep the contour as is (closed without the repeated end)
    w.discardSub();
    dst.points.put(pts);
    dst.infos.put(ContourInfo(firstPoint, pts.length, closed));
  } else if (closed && startedOn) {
    mergeSeam(w, firstInfo, dst);
  } else if (dst.points[].length - w.start > 1) {
    dst.infos.put(w.endSub());
  } else {
    // a dash starting exactly at the seam (rounding) has no length
    w.discardSub();
  }
}

/// Appends the first dash of a contour to its open last dash.
void mergeSeam(ref DashWriter w, size_t firstInfo, ref Contours dst)
  nothrow @safe {
  const ContourInfo first = dst.infos[][firstInfo];
  foreach (k; first.start + 1 .. first.start + first.count) {
    const PointF p = dst.points[][k];
    w.addPoint(p);
  }
  dst.infos[][firstInfo] = w.endSub();
}

struct Stroker {
  Appender!(float[])* tris;
  float hw;
  LineCap cap;
  LineJoin join;
  float miterLimit;
  float tolerance;

  void strokeAll(ref const Contours c) nothrow @safe {
    foreach (info; c.infos[]) {
      const PointF[] pts = c.points[][info.start .. info.start + info.count];
      if (pts.length > 0) {
        strokeContour(pts, info.closed);
      }
    }
  }

  void strokeContour(const PointF[] pts, bool closed) nothrow @safe {
    bool have = false;
    PointF firstStart;
    PointF firstDir;
    PointF prevDir;
    PointF lastEnd;
    const size_t segCount = closed ? pts.length : pts.length - 1;
    foreach (i; 0 .. segCount) {
      const PointF a = pts[i];
      const PointF b = pts[(i + 1) % pts.length];
      const float len = dist(a, b);
      if (!(len > eps)) {
        continue;
      }
      const PointF d = PointF((b.x - a.x) / len, (b.y - a.y) / len);
      segmentQuad(a, b, d);
      if (have) {
        joinAt(a, prevDir, d);
      } else {
        firstStart = a;
        firstDir = d;
        have = true;
      }
      prevDir = d;
      lastEnd = b;
    }
    if (!have) {
      dot(pts[0]);
    } else if (closed) {
      joinAt(firstStart, prevDir, firstDir);
    } else {
      capAt(firstStart, PointF(-firstDir.x, -firstDir.y));
      capAt(lastEnd, prevDir);
    }
  }

  void segmentQuad(PointF a, PointF b, PointF d) nothrow @safe {
    const PointF n = PointF(-d.y * hw, d.x * hw);
    quad(add(a, n), add(b, n), sub(b, n), sub(a, n));
  }

  /// Join at `p` from incoming direction `d0` to outgoing `d1`.
  void joinAt(PointF p, PointF d0, PointF d1) nothrow @safe {
    const float cr = d0.x * d1.y - d0.y * d1.x;
    const float dt = d0.x * d1.x + d0.y * d1.y;
    if (abs(cr) < eps && dt > 0) {
      return;
    }
    // signed turn angle; a reversal sweeps through d0 (beyond p)
    const float theta = abs(cr) < eps ? cast(float) PI : atan2(cr, dt);
    const float s = theta > 0 ? -hw : hw;
    const PointF o0 = PointF(-d0.y * s, d0.x * s);
    const PointF o1 = PointF(-d1.y * s, d1.x * s);
    final switch (join) {
    case LineJoin.bevel:
      tri(p, add(p, o0), add(p, o1));
      break;
    case LineJoin.miter:
      tri(p, add(p, o0), add(p, o1));
      miterTip(p, o0, o1, theta);
      break;
    case LineJoin.round:
      fan(p, o0, theta);
      break;
    }
  }

  void miterTip(PointF p, PointF o0, PointF o1, float theta)
    nothrow @safe {
    // 1/sin(interior/2) == 1/cos(theta/2)
    const float c = cos(abs(theta) * 0.5f);
    if (!(c > eps) || 1 / c > miterLimit) {
      return;
    }
    const PointF m = PointF(o0.x + o1.x, o0.y + o1.y);
    const float ml = sqrt(m.x * m.x + m.y * m.y);
    if (!(ml > eps)) {
      return;
    }
    const float k = hw / c / ml;
    tri(add(p, o0), PointF(p.x + m.x * k, p.y + m.y * k), add(p, o1));
  }

  void capAt(PointF e, PointF d) nothrow @safe {
    const PointF n = PointF(-d.y * hw, d.x * hw);
    final switch (cap) {
    case LineCap.butt:
      break;
    case LineCap.square:
      const PointF ext = PointF(d.x * hw, d.y * hw);
      quad(add(e, n), add(add(e, n), ext), add(sub(e, n), ext), sub(e, n));
      break;
    case LineCap.round:
      // from +n rotating through d to -n
      fan(e, n, -cast(float) PI);
      break;
    }
  }

  /// Zero-length contour: a dot (round) or axis-aligned square of size w.
  void dot(PointF p) nothrow @safe {
    final switch (cap) {
    case LineCap.butt:
      break;
    case LineCap.square:
      quad(
        PointF(p.x - hw, p.y - hw), PointF(p.x + hw, p.y - hw),
        PointF(p.x + hw, p.y + hw), PointF(p.x - hw, p.y + hw)
      );
      break;
    case LineCap.round:
      fan(p, PointF(hw, 0), cast(float)(2 * PI));
      break;
    }
  }

  /// Fan around `c` from offset `o0` rotating by signed `angle`.
  void fan(PointF c, PointF o0, float angle) nothrow @safe {
    const int n = fanSegments(abs(angle));
    PointF prev = add(c, o0);
    foreach (k; 1 .. n + 1) {
      const float t = angle * k / n;
      const float cs = cos(t);
      const float sn = sin(t);
      const PointF cur = PointF(
        c.x + o0.x * cs - o0.y * sn, c.y + o0.x * sn + o0.y * cs
      );
      tri(c, prev, cur);
      prev = cur;
    }
  }

  /// `ceil(angle / (2*acos(1 - tol/r)))` clamped to [1, 256].
  int fanSegments(float angle) const nothrow @safe @nogc {
    float q = 1 - tolerance / hw;
    q = q < -1 ? -1 : q;
    const float step = 2 * acos(q);
    const float n = ceil(angle / step);
    if (!isFinite(n) || n > maxFanSegments) {
      return maxFanSegments;
    }
    return n < 1 ? 1 : cast(int) n;
  }

  void tri(PointF a, PointF b, PointF c) nothrow @safe {
    const float[6] v = [a.x, a.y, b.x, b.y, c.x, c.y];
    tris.put(v[]);
  }

  /// Quad `a b c d` in winding order as 2 triangles.
  void quad(PointF a, PointF b, PointF c, PointF d) nothrow @safe {
    tri(a, b, c);
    tri(a, c, d);
  }
}

float dist(PointF a, PointF b) nothrow @safe @nogc {
  const float dx = b.x - a.x;
  const float dy = b.y - a.y;
  return sqrt(dx * dx + dy * dy);
}

PointF lerp(PointF a, PointF b, float t) nothrow @safe @nogc {
  return PointF(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
}

PointF add(PointF a, PointF b) nothrow @safe @nogc {
  return PointF(a.x + b.x, a.y + b.y);
}

PointF sub(PointF a, PointF b) nothrow @safe @nogc {
  return PointF(a.x - b.x, a.y - b.y);
}

version (unittest) {
  struct TriStats {
    float minX = float.infinity;
    float minY = float.infinity;
    float maxX = -float.infinity;
    float maxY = -float.infinity;
    float area = 0;
  }

  TriStats triStats(const float[] t) {
    TriStats s;
    for (size_t i = 0; i + 6 <= t.length; i += 6) {
      foreach (k; 0 .. 3) {
        const float x = t[i + 2 * k];
        const float y = t[i + 2 * k + 1];
        s.minX = x < s.minX ? x : s.minX;
        s.maxX = x > s.maxX ? x : s.maxX;
        s.minY = y < s.minY ? y : s.minY;
        s.maxY = y > s.maxY ? y : s.maxY;
      }
      const float cr = (t[i + 2] - t[i]) * (t[i + 5] - t[i + 1])
        - (t[i + 4] - t[i]) * (t[i + 3] - t[i + 1]);
      s.area += abs(cr) * 0.5f;
    }
    return s;
  }

  bool covers(const float[] t, PointF p) {
    for (size_t i = 0; i + 6 <= t.length; i += 6) {
      float sign = 0;
      bool inside = true;
      foreach (k; 0 .. 3) {
        const size_t j = (k + 1) % 3;
        const float ax = t[i + 2 * k];
        const float ay = t[i + 2 * k + 1];
        const float bx = t[i + 2 * j];
        const float by = t[i + 2 * j + 1];
        const float cr = (bx - ax) * (p.y - ay) - (by - ay) * (p.x - ax);
        if (cr == 0) {
          continue;
        }
        if (sign == 0) {
          sign = cr;
        } else if ((cr > 0) != (sign > 0)) {
          inside = false;
        }
      }
      if (inside && sign != 0) {
        return true;
      }
    }
    return false;
  }

  /// Union area estimated by sampling a grid with `step` spacing.
  float coveredArea(const float[] t, float step) {
    const TriStats s = triStats(t);
    float area = 0;
    for (float y = s.minY + step / 2; y < s.maxY; y += step) {
      for (float x = s.minX + step / 2; x < s.maxX; x += step) {
        if (covers(t, PointF(x, y))) {
          area += step * step;
        }
      }
    }
    return area;
  }

  Contours contoursWith(const PointF[] pts, bool closed) {
    Contours c;
    c.points.put(pts);
    c.infos.put(ContourInfo(0, pts.length, closed));
    return c;
  }

  float[] strokeWith(const PointF[] pts, bool closed, in StrokeParams p) {
    const Contours c = contoursWith(pts, closed);
    Appender!(float[]) tris;
    Contours dashScratch;
    strokeContours(c, p, tris, dashScratch);
    return tris[];
  }

  Contours dashed(ref const Contours c, const float[] dash, float offset) {
    Contours res;
    applyDashInto(c, LineDash.fromSegments(dash), offset, res);
    return res;
  }

  bool near(float a, float b, float e) {
    return abs(a - b) <= e;
  }
}

// straight line caps
unittest {
  const PointF[] line = [PointF(0, 0), PointF(100, 0)];
  StrokeParams p;
  p.width = 10;

  p.cap = LineCap.butt;
  const butt = triStats(strokeWith(line, false, p));
  assert(near(butt.minX, 0, 1e-3f) && near(butt.maxX, 100, 1e-3f));
  assert(near(butt.minY, -5, 1e-3f) && near(butt.maxY, 5, 1e-3f));
  assert(near(butt.area, 1000, 0.5f));

  p.cap = LineCap.square;
  const sq = triStats(strokeWith(line, false, p));
  assert(near(sq.minX, -5, 1e-3f) && near(sq.maxX, 105, 1e-3f));
  assert(near(sq.area, 1100, 0.5f));

  p.cap = LineCap.round;
  const rd = triStats(strokeWith(line, false, p));
  // fan vertices stay within the tessellation tolerance of the disc
  assert(near(rd.minX, -5, 0.25f) && near(rd.maxX, 105, 0.25f));
  assert(rd.area > butt.area + 70 && rd.area < sq.area);
}

// joins on an L-shape
unittest {
  const PointF[] l = [PointF(0, 0), PointF(100, 0), PointF(100, 100)];
  StrokeParams p;
  p.width = 10;

  p.join = LineJoin.miter;
  assert(covers(strokeWith(l, false, p), PointF(104, -4)));

  p.join = LineJoin.bevel;
  const bevel = strokeWith(l, false, p);
  assert(!covers(bevel, PointF(104, -4)));
  assert(covers(bevel, PointF(101, -2)));
  // inner side gets no join geometry beyond the segment quads
  assert(!covers(bevel, PointF(94, 6)));

  p.join = LineJoin.round;
  const round = strokeWith(l, false, p);
  assert(covers(round, PointF(103, -3)));
  assert(!covers(round, PointF(104.9f, -4.9f)));
}

// sharp angle exceeds the miter limit
unittest {
  import std.math : tan;

  const float a = cast(float)(10 * PI / 180);
  const PointF v = PointF(100, 0);
  const PointF[] pts = [
    PointF(0, 0), v, PointF(0, 100 * tan(a))
  ];
  // outward bisector direction is d0 - d1
  const PointF d0 = PointF(1, 0);
  const float l1 = dist(v, pts[2]);
  const PointF d1 = PointF((pts[2].x - v.x) / l1, (pts[2].y - v.y) / l1);
  const PointF bis = PointF(d0.x - d1.x, d0.y - d1.y);
  const float bl = sqrt(bis.x * bis.x + bis.y * bis.y);
  const PointF tip = PointF(v.x + bis.x / bl * 20, v.y + bis.y / bl * 20);

  StrokeParams p;
  p.width = 10;
  p.join = LineJoin.miter;
  assert(!covers(strokeWith(pts, false, p), tip));
  p.miterLimit = 20;
  assert(covers(strokeWith(pts, false, p), tip));
}

// dashes
unittest {
  const PointF[] line = [PointF(0, 0), PointF(100, 0)];
  const Contours c = contoursWith(line, false);
  const float[] dash = [10, 10];

  const Contours d = dashed(c, dash, 0);
  assert(d.infos[].length == 5);
  StrokeParams p;
  p.width = 10;
  p.dash = LineDash.fromSegments(dash);
  const t = strokeWith(line, false, p);
  assert(covers(t, PointF(5, 0)) && covers(t, PointF(45, 0)));
  assert(!covers(t, PointF(15, 0)) && !covers(t, PointF(95, 0)));

  p.dashOffset = 5;
  const t5 = strokeWith(line, false, p);
  assert(covers(t5, PointF(2, 0)) && !covers(t5, PointF(7, 0)));
  assert(covers(t5, PointF(17, 0)));

  // a negative offset wraps: -5 == 15
  p.dashOffset = -5;
  const tn = strokeWith(line, false, p);
  assert(!covers(tn, PointF(2, 0)) && covers(tn, PointF(7, 0)));

  // odd count repeats: [10] == [10, 10]
  assert(dashed(c, [10.0f], 0).infos[].length == 5);
  // zero-length dashes become dots
  const Contours z = dashed(c, [0.0f, 50], 0);
  assert(z.infos[].length == 2);
  assert(z.infos[][0].count == 1 && z.infos[][1].count == 1);

  // dst is cleared first; a solid dash copies the input
  Contours dst;
  applyDashInto(c, LineDash.fromSegments(dash), 0, dst);
  applyDashInto(c, LineDash.fromSegments(dash), 0, dst);
  assert(dst.infos[].length == 5);
  applyDashInto(c, LineDash.init, 0, dst);
  assert(dst.infos[] == c.infos[] && dst.points[] == c.points[]);
}

// a warmed-up dashed stroke reuses tris and the dash scratch
unittest {
  import core.memory : GC;

  const PointF[] pts = [
    PointF(0, 0), PointF(100, 0), PointF(100, 100), PointF(0, 100)
  ];
  const Contours c = contoursWith(pts, true);
  StrokeParams p;
  p.width = 6;
  p.dash = LineDash.fromSegments([7.0f, 3, 2]);
  p.dashOffset = 4;
  Appender!(float[]) tris;
  Contours dashScratch;
  strokeContours(c, p, tris, dashScratch);
  const size_t len = tris[].length;
  assert(len > 0 && dashScratch.infos[].length > 10);

  GC.collect();
  const before = GC.stats();
  foreach (_; 0 .. 100) {
    tris.clear();
    strokeContours(c, p, tris, dashScratch);
  }
  const after = GC.stats();
  assert(tris[].length == len);
  assert(after.allocatedInCurrentThread == before.allocatedInCurrentThread);
  assert(
    after.usedSize + after.freeSize <= before.usedSize + before.freeSize
  );
}

// dashing a closed contour merges the seam
unittest {
  const PointF[] sq = [
    PointF(0, 0), PointF(100, 0), PointF(100, 100), PointF(0, 100)
  ];
  const Contours c = contoursWith(sq, true);
  const Contours d = dashed(c, [40.0f, 40], 20);
  // phase 20: on [0,20], off [20,60], on [60,100] ...; the last on
  // [380,400] merges with [0,20]
  assert(d.infos[].length == 5);
  bool seam = false;
  foreach (info; d.infos[]) {
    assert(!info.closed);
    const PointF[] pts = d.points[][info.start .. info.start + info.count];
    if (pts[0] == PointF(0, 20)) {
      seam = true;
      assert(pts == [PointF(0, 20), PointF(0, 0), PointF(20, 0)]);
    }
  }
  assert(seam);

  // a dash longer than the contour keeps it closed
  const Contours full = dashed(c, [1000.0f, 10], 0);
  assert(full.infos[].length == 1 && full.infos[][0].closed);
  assert(full.infos[][0].count == 4);
}

// closed square ring
unittest {
  const PointF[] sq = [
    PointF(0, 0), PointF(100, 0), PointF(100, 100), PointF(0, 100)
  ];
  StrokeParams p;
  p.width = 10;
  const t = strokeWith(sq, true, p);
  foreach (corner; [
    PointF(-4, -4), PointF(104, -4), PointF(104, 104), PointF(-4, 104)
  ]) {
    assert(covers(t, corner));
  }
  const float ring = 110 * 110 - 90 * 90;
  assert(near(coveredArea(t, 0.5f), ring, ring * 0.01f));

  // no caps: round joins leave the outer corner tips uncovered even with
  // square caps requested
  p.join = LineJoin.round;
  p.cap = LineCap.square;
  const r = strokeWith(sq, true, p);
  assert(!covers(r, PointF(-4.5f, -4.5f)));
  assert(covers(r, PointF(-3, -3)));
}

// degenerate inputs
unittest {
  StrokeParams p;
  p.width = 0;
  const PointF[] line = [PointF(0, 0), PointF(100, 0)];
  assert(strokeWith(line, false, p).length == 0);
  p.width = float.nan;
  assert(strokeWith(line, false, p).length == 0);

  p.width = 10;
  Contours empty;
  Appender!(float[]) tris;
  Contours dashScratch;
  strokeContours(empty, p, tris, dashScratch);
  assert(tris[].length == 0);

  const PointF[] dotPts = [PointF(7, 7), PointF(7, 7)];
  p.cap = LineCap.butt;
  assert(strokeWith(dotPts, false, p).length == 0);
  p.cap = LineCap.round;
  const rd = strokeWith(dotPts, false, p);
  assert(covers(rd, PointF(7, 7)) && covers(rd, PointF(7, 11.5f)));
  assert(!covers(rd, PointF(7, 12.5f)));
  p.cap = LineCap.square;
  const sd = strokeWith([PointF(7, 7)], false, p);
  assert(covers(sd, PointF(11.5f, 11.5f)));
  assert(!covers(sd, PointF(12.5f, 7)));
}

// a warmed-up round stroke into a cleared Appender does not allocate
unittest {
  import core.memory : GC;

  const PointF[] pts = [
    PointF(0, 0), PointF(100, 0), PointF(100, 100), PointF(0, 100)
  ];
  const Contours c = contoursWith(pts, false);
  StrokeParams p;
  p.width = 40;
  p.join = LineJoin.round;
  p.cap = LineCap.round;
  p.tolerance = 0.05f;
  Appender!(float[]) tris;
  Contours dashScratch;
  strokeContours(c, p, tris, dashScratch);
  const size_t len = tris[].length;
  assert(len > 6 * 64);

  GC.collect();
  const before = GC.stats();
  foreach (_; 0 .. 100) {
    tris.clear();
    strokeContours(c, p, tris, dashScratch);
  }
  const after = GC.stats();
  assert(tris[].length == len);
  assert(after.allocatedInCurrentThread == before.allocatedInCurrentThread);
  assert(
    after.usedSize + after.freeSize <= before.usedSize + before.freeSize
  );
}
