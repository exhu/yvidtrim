module yguilib.render_types;

struct PointF {
  float x = 0.0f;
  float y = 0.0f;
}

struct RectF {
  float x = 0.0f;
  float y = 0.0f;
  float w = 1.0f;
  float h = 1.0f;
}

struct ColorF {
  float r = 0.0f;
  float g = 0.0f;
  float b = 0.0f;
  float a = 1.0f;
}

alias Color = ColorF;

unittest {
  PointF p = PointF(10.0f, 20.0f);
  assert(p.x == 10.0f);
  assert(p.y == 20.0f);

  RectF r = RectF(5.0f, 6.0f, 100.0f, 200.0f);
  assert(r.x == 5.0f);
  assert(r.y == 6.0f);
  assert(r.w == 100.0f);
  assert(r.h == 200.0f);

  ColorF c = ColorF(0.2f, 0.4f, 0.6f, 0.8f);
  assert(c.r == 0.2f);
  assert(c.g == 0.4f);
  assert(c.b == 0.6f);
  assert(c.a == 0.8f);

  Color c2 = Color(1.0f, 1.0f, 1.0f, 1.0f);
  assert(c2.r == 1.0f);
}
