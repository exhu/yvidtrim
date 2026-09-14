module yguilib.render_types;

struct PointF {
  float x = 0.0f;
  float y = 0.0f;
}

struct RectF {
  float x = 0.0f;
  float y = 0.0f;
  float width = 1.0f;
  float height = 1.0f;
}

struct ColorF {
  float r = 0.0f;
  float g = 0.0f;
  float b = 0.0f;
  float a = 1.0f;
}

alias Color = ColorF;

import std.algorithm : max, min;

/**
 * Returns the intersection of two rectangles.
 * Width/height are clamped to zero if they would be negative (no overlap).
 */
RectF intersectRects(in RectF a, in RectF b) {
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
  assert(inter.x == 20 && inter.y == 30 && inter.width == 40 && inter.height == 30);

  // Disjoint rects
  RectF r3 = RectF(100, 100, 10, 10);
  RectF disjoint = intersectRects(r1, r3);
  assert(disjoint.width == 0.0f && disjoint.height == 0.0f);
}
