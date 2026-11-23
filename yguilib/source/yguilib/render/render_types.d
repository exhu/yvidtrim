module yguilib.render.render_types;

struct PointF {
  float x = 0.0f;
  float y = 0.0f;
}

/**
 * Axis-aligned rectangle `(x, y, width, height)`.
 *
 * Note: `RectF.init` (and `RectF r;`) is the 1 x 1 unit rect at the
 * origin, not an empty rect. Write `RectF(0, 0, 0, 0)` for an empty one.
 */
struct RectF {
  float x = 0.0f;
  float y = 0.0f;
  float width = 1.0f;
  float height = 1.0f;

  bool contains(in PointF p) const {
    return (p.x >= x) && (p.y >= y) && (p.x < (x+width)) && (p.y < (y+height));
  }
}

// RectF
unittest {
  auto r = RectF(10, 12, 25, 35);
  auto p1 = PointF(10, 12);
  assert(r.contains(p1));
  auto p2 = PointF(0, 0);
  assert(!r.contains(p2));
  auto p3 = PointF(r.x + r.width, 0);
  assert(!r.contains(p3));

  assert(!RectF(840, 21, 162, 26).contains(PointF(921.734, 307.453)));
}

struct ColorF {
  float r = 0.0f;
  float g = 0.0f;
  float b = 0.0f;
  float a = 1.0f;
}

alias Color = ColorF;

/**
 * Returns the intersection of two rectangles.
 * Width/height are clamped to zero if they would be negative (no overlap).
 */
RectF intersectRects(in RectF a, in RectF b) {
  import std.algorithm : max, min;
  float x1 = max(a.x, b.x);
  float y1 = max(a.y, b.y);
  float x2 = min(a.x + a.width, b.x + b.width);
  float y2 = min(a.y + a.height, b.y + b.height);
  float w = x2 - x1;
  float h = y2 - y1;
  if (w < 0.0f) {
    w = 0.0f;
  }
  if (h < 0.0f) {
    h = 0.0f;
  }
  return RectF(x1, y1, w, h);
}

unittest {
  PointF p = PointF(10.0f, 20.0f);
  assert(p.x == 10.0f);
  assert(p.y == 20.0f);

  RectF r = RectF(5.0f, 6.0f, 100.0f, 200.0f);
  assert(r.x == 5.0f);
  assert(r.y == 6.0f);
  assert(r.width == 100.0f);
  assert(r.height == 200.0f);

  ColorF c = ColorF(0.2f, 0.4f, 0.6f, 0.8f);
  assert(c.r == 0.2f);
  assert(c.g == 0.4f);
  assert(c.b == 0.6f);
  assert(c.a == 0.8f);

  Color c2 = Color(1.0f, 1.0f, 1.0f, 1.0f);
  assert(c2.r == 1.0f);

  // intersectRects tests
  RectF r1 = RectF(10, 10, 50, 50);
  RectF r2 = RectF(20, 30, 60, 40);
  RectF inter = intersectRects(r1, r2);
  assert(
    inter.x == 20 && inter.y == 30 && inter.width == 40 && inter.height == 30
  );

  // Disjoint rects
  RectF r3 = RectF(100, 100, 10, 10);
  RectF disjoint = intersectRects(r1, r3);
  assert(disjoint.width == 0.0f && disjoint.height == 0.0f);
}

/// Linearly interpolates between `a` and `b`, clamping `t` to `[0.0f, 1.0f]`.
ColorF lerpColor(in ColorF a, in ColorF b, float t) nothrow @safe @nogc {
  import std.algorithm.comparison : clamp;

  const float k = clamp(t, 0.0f, 1.0f);
  return ColorF(
    a.r + (b.r - a.r) * k,
    a.g + (b.g - a.g) * k,
    a.b + (b.b - a.b) * k,
    a.a + (b.a - a.a) * k
  );
}

/// Returns the position of `p` normalized within `r` and clamped to `[0, 1]`.
/// Returns `PointF(0.5f, 0.5f)` when `r` has non-positive width or height.
PointF normalizedIn(in RectF r, in PointF p) nothrow @safe @nogc {
  import std.algorithm.comparison : clamp;

  if (r.width <= 0.0f || r.height <= 0.0f) {
    return PointF(0.5f, 0.5f);
  }
  const float nx = clamp((p.x - r.x) / r.width, 0.0f, 1.0f);
  const float ny = clamp((p.y - r.y) / r.height, 0.0f, 1.0f);
  return PointF(nx, ny);
}

unittest {
  import std.math : isClose;

  const ColorF cA = ColorF(0.0f, 0.2f, 0.4f, 0.6f);
  const ColorF cB = ColorF(1.0f, 0.6f, 0.8f, 1.0f);

  const ColorF c0 = lerpColor(cA, cB, 0.0f);
  assert(isClose(c0.r, 0.0f) && isClose(c0.g, 0.2f));
  assert(isClose(c0.b, 0.4f) && isClose(c0.a, 0.6f));

  const ColorF cHalf = lerpColor(cA, cB, 0.5f);
  assert(isClose(cHalf.r, 0.5f) && isClose(cHalf.g, 0.4f));
  assert(isClose(cHalf.b, 0.6f) && isClose(cHalf.a, 0.8f));

  const ColorF c1 = lerpColor(cA, cB, 1.0f);
  assert(isClose(c1.r, 1.0f) && isClose(c1.g, 0.6f));
  assert(isClose(c1.b, 0.8f) && isClose(c1.a, 1.0f));

  const ColorF cLow = lerpColor(cA, cB, -0.5f);
  assert(isClose(cLow.r, 0.0f) && isClose(cLow.a, 0.6f));

  const ColorF cHigh = lerpColor(cA, cB, 2.0f);
  assert(isClose(cHigh.r, 1.0f) && isClose(cHigh.a, 1.0f));

  const RectF rect = RectF(10.0f, 20.0f, 100.0f, 50.0f);
  const PointF center = normalizedIn(rect, PointF(60.0f, 45.0f));
  assert(isClose(center.x, 0.5f) && isClose(center.y, 0.5f));

  const PointF topLeft = normalizedIn(rect, PointF(10.0f, 20.0f));
  assert(isClose(topLeft.x, 0.0f) && isClose(topLeft.y, 0.0f));

  const PointF botRight = normalizedIn(rect, PointF(110.0f, 70.0f));
  assert(isClose(botRight.x, 1.0f) && isClose(botRight.y, 1.0f));

  const PointF clamped = normalizedIn(rect, PointF(-5.0f, 100.0f));
  assert(isClose(clamped.x, 0.0f) && isClose(clamped.y, 1.0f));

  const PointF zeroW = normalizedIn(RectF(0, 0, 0, 10), PointF(5, 5));
  assert(isClose(zeroW.x, 0.5f) && isClose(zeroW.y, 0.5f));

  const PointF zeroH = normalizedIn(RectF(0, 0, 10, -2), PointF(5, 5));
  assert(isClose(zeroH.x, 0.5f) && isClose(zeroH.y, 0.5f));
}
