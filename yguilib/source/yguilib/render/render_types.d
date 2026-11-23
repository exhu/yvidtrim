/**
 * Plain value types shared by the Renderer, Canvas and widgets: points,
 * rects, colors, dash patterns and finite/bounds/color helpers (the 2D
 * transform is `yguilib.render.canvas.types.Transform2d`). No GL, no
 * allocation.
 */
module yguilib.render.render_types;

import std.typecons : Nullable, nullable;

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
  const float x1 = max(a.x, b.x);
  const float y1 = max(a.y, b.y);
  const float x2 = min(a.x + a.width, b.x + b.width);
  const float y2 = min(a.y + a.height, b.y + b.height);
  const float w = x2 - x1;
  const float h = y2 - y1;
  return RectF(x1, y1, w < 0.0f ? 0.0f : w, h < 0.0f ? 0.0f : h);
}

/**
 * Dash pattern of Renderer lines and outlines (logic units): visible
 * dashes of `dashLen` separated by gaps of `gapLen`. `DashPattern.init`
 * (or either length <= 0) draws a solid line.
 */
struct DashPattern {
  float dashLen = 0.0f;
  float gapLen = 0.0f;
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

/// True when both coordinates of `p` are finite.
bool isFinitePoint(in PointF p) nothrow @safe @nogc pure {
  import std.math : isFinite;

  return isFinite(p.x) && isFinite(p.y);
}

/// True when the origin and size of `r` are finite (any sign).
bool isFiniteRect(in RectF r) nothrow @safe @nogc pure {
  import std.math : isFinite;

  return isFinite(r.x) && isFinite(r.y) && isFinite(r.width)
    && isFinite(r.height);
}

/// Bounds of `pts`; an empty slice gives `RectF(0, 0, 0, 0)`.
RectF boundsOfPoints(const(PointF)[] pts) nothrow @safe @nogc pure {
  if (pts.length == 0) {
    return RectF(0, 0, 0, 0);
  }
  float x0 = pts[0].x;
  float y0 = pts[0].y;
  float x1 = x0;
  float y1 = y0;
  foreach (p; pts[1 .. $]) {
    x0 = p.x < x0 ? p.x : x0;
    y0 = p.y < y0 ? p.y : y0;
    x1 = p.x > x1 ? p.x : x1;
    y1 = p.y > y1 ? p.y : y1;
  }
  return RectF(x0, y0, x1 - x0, y1 - y0);
}

/**
 * `boundsOfPoints` of interleaved (x, y) floats; a trailing odd float is
 * ignored.
 */
RectF boundsOfXy(const(float)[] xy) nothrow @trusted @nogc pure {
  static assert(PointF.sizeof == 2 * float.sizeof);
  const size_t n = xy.length / 2;
  // PointF is two packed floats: view the pairs as points
  return boundsOfPoints((cast(const(PointF)*)xy.ptr)[0 .. n]);
}

unittest {
  assert(isFinitePoint(PointF(1, -2)));
  assert(!isFinitePoint(PointF(float.nan, 0)));
  assert(!isFinitePoint(PointF(0, float.infinity)));
  assert(isFiniteRect(RectF(0, 0, -5, 3)));
  assert(!isFiniteRect(RectF(0, 0, float.nan, 3)));

  assert(boundsOfPoints([]) == RectF(0, 0, 0, 0));
  const PointF[3] pts = [PointF(3, 4), PointF(-1, 10), PointF(5, 2)];
  assert(boundsOfPoints(pts[]) == RectF(-1, 2, 6, 8));
  const float[7] xy = [3, 4, -1, 10, 5, 2, 99];
  assert(boundsOfXy(xy[]) == RectF(-1, 2, 6, 8));
  assert(boundsOfXy([]) == RectF(0, 0, 0, 0));
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

/**
 * Decodes a CSS/hex color string (`"transparent"`, `#RGB`, `#RGBA`,
 * `#RRGGBB`, `#RRGGBBAA`, `rgb(...)`, or `rgba(...)`) into `ColorF`.
 * Returns `Nullable!ColorF.init` when the input is invalid.
 */
Nullable!ColorF parseColor(string s) nothrow @safe @nogc pure {
  const string t = trimAsciiSpace(s);
  if (t.length == 0) {
    return Nullable!ColorF.init;
  }
  if (equalsIgnoreCaseAscii(t, "transparent")) {
    return nullable(ColorF(0.0f, 0.0f, 0.0f, 0.0f));
  }
  if (t[0] == '#') {
    return parseHexColor(t[1 .. $]);
  }
  if (startsWithIgnoreCaseAscii(t, "rgb(") && t[$ - 1] == ')') {
    return parseRgbColor(t[4 .. $ - 1]);
  }
  if (startsWithIgnoreCaseAscii(t, "rgba(") && t[$ - 1] == ')') {
    return parseRgbColor(t[5 .. $ - 1]);
  }
  return Nullable!ColorF.init;
}

/// Decodes a CSS/hex color string via `parseColor`, asserting it is valid.
ColorF colorFromString(string s) nothrow @safe @nogc pure {
  const Nullable!ColorF c = parseColor(s);
  assert(!c.isNull, "invalid color string");
  return c.isNull ? ColorF(0.0f, 0.0f, 0.0f, 0.0f) : c.get;
}

// parseColor / colorFromString: hex and transparent
unittest {
  import std.math : isClose;

  bool nearColor(in ColorF a, in ColorF b) {
    return isClose(a.r, b.r, 1e-5, 1e-5)
      && isClose(a.g, b.g, 1e-5, 1e-5)
      && isClose(a.b, b.b, 1e-5, 1e-5)
      && isClose(a.a, b.a, 1e-5, 1e-5);
  }

  assert(nearColor(colorFromString("transparent"), ColorF(0, 0, 0, 0)));
  assert(nearColor(colorFromString("TRANSPARENT"), ColorF(0, 0, 0, 0)));
  assert(nearColor(colorFromString(" \ttransparent\n "), ColorF(0, 0, 0, 0)));

  assert(nearColor(
    colorFromString("#3aF"),
    ColorF(3 / 15.0f, 10 / 15.0f, 1.0f, 1.0f)
  ));
  assert(nearColor(
    colorFromString(" #3AfC "),
    ColorF(3 / 15.0f, 10 / 15.0f, 1.0f, 12 / 15.0f)
  ));
  assert(nearColor(
    colorFromString("#2b3140"),
    ColorF(0x2b / 255.0f, 0x31 / 255.0f, 0x40 / 255.0f, 1.0f)
  ));
  assert(nearColor(
    colorFromString("#2B314080"),
    ColorF(0x2b / 255.0f, 0x31 / 255.0f, 0x40 / 255.0f, 0x80 / 255.0f)
  ));

  enum ColorF ctfeColor = colorFromString("#2b3140");
  assert(nearColor(
    ctfeColor,
    ColorF(0x2b / 255.0f, 0x31 / 255.0f, 0x40 / 255.0f, 1.0f)
  ));
}

// parseColor: rgb/rgba syntax, clamping, scientific notation, invalid inputs
unittest {
  import std.math : isClose;

  bool nearColor(in ColorF a, in ColorF b) {
    return isClose(a.r, b.r, 1e-5, 1e-5)
      && isClose(a.g, b.g, 1e-5, 1e-5)
      && isClose(a.b, b.b, 1e-5, 1e-5)
      && isClose(a.a, b.a, 1e-5, 1e-5);
  }

  assert(nearColor(
    colorFromString("rgb(43, 49, 64)"),
    ColorF(43 / 255.0f, 49 / 255.0f, 64 / 255.0f, 1.0f)
  ));
  assert(nearColor(
    colorFromString("rgba(43, 49, 64, 0.5)"),
    ColorF(43 / 255.0f, 49 / 255.0f, 64 / 255.0f, 0.5f)
  ));
  assert(nearColor(
    colorFromString("RGB(50%, 100%, 0%)"),
    ColorF(0.5f, 1.0f, 0.0f, 1.0f)
  ));
  assert(nearColor(
    colorFromString("RgBa(100%, 0%, 50%, 50%)"),
    ColorF(1.0f, 0.0f, 0.5f, 0.5f)
  ));
  assert(nearColor(
    colorFromString("rgb(43 49 64)"),
    ColorF(43 / 255.0f, 49 / 255.0f, 64 / 255.0f, 1.0f)
  ));
  assert(nearColor(
    colorFromString("rgb(43 49 64 / 0.25)"),
    ColorF(43 / 255.0f, 49 / 255.0f, 64 / 255.0f, 0.25f)
  ));
  assert(nearColor(
    colorFromString("rgba(100% 50% 0 / 50%)"),
    ColorF(1.0f, 0.5f, 0.0f, 0.5f)
  ));
  assert(nearColor(
    colorFromString("rgba(-10, 300, 100, -0.5)"),
    ColorF(0.0f, 1.0f, 100 / 255.0f, 0.0f)
  ));
  assert(nearColor(
    colorFromString("rgba(150%, -20%, 0%, 2.0)"),
    ColorF(1.0f, 0.0f, 0.0f, 1.0f)
  ));
  assert(nearColor(
    colorFromString("rgb(1e2, 2.5e1, .5e2)"),
    ColorF(100 / 255.0f, 25 / 255.0f, 50 / 255.0f, 1.0f)
  ));

  assert(parseColor("").isNull);
  assert(parseColor("   ").isNull);
  assert(parseColor("#12").isNull);
  assert(parseColor("#12345").isNull);
  assert(parseColor("#1234567").isNull);
  assert(parseColor("#gggggg").isNull);
  assert(parseColor("2b3140").isNull);
  assert(parseColor("rgb (1, 2, 3)").isNull);
  assert(parseColor("rgb(1, 2)").isNull);
  assert(parseColor("rgb(1, 2, 3, 4, 5)").isNull);
  assert(parseColor("rgb(1, 2 3)").isNull);
  assert(parseColor("rgb(10 20, 30)").isNull);
  assert(parseColor("rgb(1, 2, 3 / 0.5)").isNull);
  assert(parseColor("rgb(100%, 50, 0)").isNull);
  assert(parseColor("rgb(1, 2, 3) extra").isNull);
  assert(parseColor("hsl(0, 100%, 50%)").isNull);
  assert(parseColor("rgb(1e500, 0, 0)").isNull);
}

private:

struct ColorToken {
  double value = 0.0;
  bool isPercent = false;
}

bool isAsciiSpace(char c) nothrow @safe @nogc pure {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f';
}

string trimAsciiSpace(string s) nothrow @safe @nogc pure {
  size_t lo = 0;
  size_t hi = s.length;
  while (lo < hi && isAsciiSpace(s[lo])) {
    ++lo;
  }
  while (hi > lo && isAsciiSpace(s[hi - 1])) {
    --hi;
  }
  return s[lo .. hi];
}

char toLowerAscii(char c) nothrow @safe @nogc pure {
  return (c >= 'A' && c <= 'Z') ? cast(char)(c + ('a' - 'A')) : c;
}

bool equalsIgnoreCaseAscii(string a, string b) nothrow @safe @nogc pure {
  if (a.length != b.length) {
    return false;
  }
  foreach (i; 0 .. a.length) {
    if (toLowerAscii(a[i]) != toLowerAscii(b[i])) {
      return false;
    }
  }
  return true;
}

bool startsWithIgnoreCaseAscii(string s, string prefix)
nothrow @safe @nogc pure {
  if (s.length < prefix.length) {
    return false;
  }
  return equalsIgnoreCaseAscii(s[0 .. prefix.length], prefix);
}

int hexDigit(char c) nothrow @safe @nogc pure {
  if (c >= '0' && c <= '9') {
    return c - '0';
  }
  if (c >= 'a' && c <= 'f') {
    return 10 + (c - 'a');
  }
  if (c >= 'A' && c <= 'F') {
    return 10 + (c - 'A');
  }
  return -1;
}

Nullable!ColorF parseHexColor(string hex) nothrow @safe @nogc pure {
  if (hex.length != 3 && hex.length != 4
    && hex.length != 6 && hex.length != 8) {
    return Nullable!ColorF.init;
  }
  int[8] d;
  foreach (i, char c; hex) {
    d[i] = hexDigit(c);
    if (d[i] < 0) {
      return Nullable!ColorF.init;
    }
  }
  if (hex.length <= 4) {
    const float a = hex.length == 4 ? d[3] / 15.0f : 1.0f;
    return Nullable!ColorF(
      ColorF(d[0] / 15.0f, d[1] / 15.0f, d[2] / 15.0f, a)
    );
  }
  const float a = hex.length == 8 ? (d[6] * 16 + d[7]) / 255.0f : 1.0f;
  return Nullable!ColorF(ColorF(
    (d[0] * 16 + d[1]) / 255.0f,
    (d[2] * 16 + d[3]) / 255.0f,
    (d[4] * 16 + d[5]) / 255.0f,
    a
  ));
}

Nullable!int parseAsciiExponent(string s) nothrow @safe @nogc pure {
  if (s.length == 0) {
    return Nullable!int.init;
  }
  size_t i = 0;
  bool neg = false;
  if (s[i] == '+' || s[i] == '-') {
    neg = s[i] == '-';
    ++i;
  }
  if (i >= s.length) {
    return Nullable!int.init;
  }
  int exp = 0;
  while (i < s.length) {
    if (s[i] < '0' || s[i] > '9') {
      return Nullable!int.init;
    }
    if (exp < 10000) {
      exp = exp * 10 + (s[i] - '0');
    }
    ++i;
  }
  return Nullable!int(neg ? -exp : exp);
}

double scalePow10(double val, int exp) nothrow @safe @nogc pure {
  import std.math : isFinite;

  if (val == 0.0 || exp == 0) {
    return val;
  }
  while (exp >= 100 && isFinite(val)) {
    val *= 1e100;
    exp -= 100;
  }
  while (exp <= -100 && val != 0.0) {
    val *= 1e-100;
    exp += 100;
  }
  if (!isFinite(val) || val == 0.0) {
    return val;
  }
  double base = exp > 0 ? 10.0 : 0.1;
  int n = exp > 0 ? exp : -exp;
  while (n > 0) {
    if ((n & 1) != 0) {
      val *= base;
    }
    n >>= 1;
    if (n > 0) {
      base *= base;
    }
  }
  return val;
}

Nullable!double parseAsciiDouble(string s) nothrow @safe @nogc pure {
  import std.math : isFinite;

  if (s.length == 0) {
    return Nullable!double.init;
  }
  size_t i = 0;
  const bool neg = s[i] == '-';
  if (s[i] == '+' || s[i] == '-') {
    ++i;
  }
  double val = 0.0;
  bool hasInt = false;
  while (i < s.length && s[i] >= '0' && s[i] <= '9') {
    val = val * 10.0 + (s[i] - '0');
    hasInt = true;
    ++i;
  }
  int exp = 0;
  bool hasFrac = false;
  if (i < s.length && s[i] == '.') {
    ++i;
    while (i < s.length && s[i] >= '0' && s[i] <= '9') {
      val = val * 10.0 + (s[i] - '0');
      --exp;
      hasFrac = true;
      ++i;
    }
    if (!hasFrac) {
      return Nullable!double.init;
    }
  }
  if (!hasInt && !hasFrac) {
    return Nullable!double.init;
  }
  if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
    const Nullable!int parsedExp = parseAsciiExponent(s[i + 1 .. $]);
    if (parsedExp.isNull) {
      return Nullable!double.init;
    }
    exp += parsedExp.get;
    i = s.length;
  }
  if (i != s.length) {
    return Nullable!double.init;
  }
  const double scaled = scalePow10(val, exp);
  if (!isFinite(scaled)) {
    return Nullable!double.init;
  }
  return Nullable!double(neg ? -scaled : scaled);
}

Nullable!ColorToken parseColorToken(string tok) nothrow @safe @nogc pure {
  if (tok.length == 0) {
    return Nullable!ColorToken.init;
  }
  const bool isPct = tok[$ - 1] == '%';
  const string numStr = isPct ? tok[0 .. $ - 1] : tok;
  const Nullable!double val = parseAsciiDouble(numStr);
  if (val.isNull) {
    return Nullable!ColorToken.init;
  }
  return Nullable!ColorToken(ColorToken(val.get, isPct));
}

float rgbChannelFromToken(ColorToken tok) nothrow @safe @nogc pure {
  if (tok.isPercent) {
    const double v = tok.value < 0.0 ? 0.0
      : (tok.value > 100.0 ? 100.0 : tok.value);
    return cast(float)v / 100.0f;
  }
  const double v = tok.value < 0.0 ? 0.0
    : (tok.value > 255.0 ? 255.0 : tok.value);
  return cast(float)v / 255.0f;
}

float alphaChannelFromToken(ColorToken tok) nothrow @safe @nogc pure {
  if (tok.isPercent) {
    const double v = tok.value < 0.0 ? 0.0
      : (tok.value > 100.0 ? 100.0 : tok.value);
    return cast(float)v / 100.0f;
  }
  const double v = tok.value < 0.0 ? 0.0
    : (tok.value > 1.0 ? 1.0 : tok.value);
  return cast(float)v;
}

Nullable!ColorF parseRgbColor(string inner) nothrow @safe @nogc pure {
  const string s = trimAsciiSpace(inner);
  if (s.length == 0) {
    return Nullable!ColorF.init;
  }
  foreach (char c; s) {
    if (c == ',') {
      return parseCommaRgb(s);
    }
  }
  return parseSpaceRgb(s);
}

Nullable!ColorF parseCommaRgb(string s) nothrow @safe @nogc pure {
  ColorToken[4] toks;
  size_t count = 0;
  size_t start = 0;
  foreach (i, char c; s) {
    if (c == ',') {
      if (count >= 3) {
        return Nullable!ColorF.init;
      }
      const Nullable!ColorToken tok = parseColorToken(
        trimAsciiSpace(s[start .. i])
      );
      if (tok.isNull) {
        return Nullable!ColorF.init;
      }
      toks[count++] = tok.get;
      start = i + 1;
    }
  }
  const Nullable!ColorToken lastTok = parseColorToken(
    trimAsciiSpace(s[start .. $])
  );
  if (lastTok.isNull) {
    return Nullable!ColorF.init;
  }
  toks[count++] = lastTok.get;
  if (count < 3) {
    return Nullable!ColorF.init;
  }
  if (toks[0].isPercent != toks[1].isPercent
    || toks[1].isPercent != toks[2].isPercent) {
    return Nullable!ColorF.init;
  }
  const float a = count == 4 ? alphaChannelFromToken(toks[3]) : 1.0f;
  return Nullable!ColorF(ColorF(
    rgbChannelFromToken(toks[0]),
    rgbChannelFromToken(toks[1]),
    rgbChannelFromToken(toks[2]),
    a
  ));
}

Nullable!(ColorToken[3]) parseThreeSpaceTokens(string s)
nothrow @safe @nogc pure {
  ColorToken[3] rgb;
  size_t count = 0;
  size_t i = 0;
  while (i < s.length) {
    while (i < s.length && isAsciiSpace(s[i])) {
      ++i;
    }
    if (i >= s.length) {
      break;
    }
    const size_t start = i;
    while (i < s.length && !isAsciiSpace(s[i])) {
      ++i;
    }
    if (count >= 3) {
      return Nullable!(ColorToken[3]).init;
    }
    const Nullable!ColorToken tok = parseColorToken(s[start .. i]);
    if (tok.isNull) {
      return Nullable!(ColorToken[3]).init;
    }
    rgb[count++] = tok.get;
  }
  if (count != 3) {
    return Nullable!(ColorToken[3]).init;
  }
  return Nullable!(ColorToken[3])(rgb);
}

Nullable!ColorF parseSpaceRgb(string s) nothrow @safe @nogc pure {
  size_t slashIdx = s.length;
  foreach (i, char c; s) {
    if (c == '/') {
      slashIdx = i;
      break;
    }
  }
  const Nullable!(ColorToken[3]) rgb = parseThreeSpaceTokens(
    trimAsciiSpace(s[0 .. slashIdx])
  );
  if (rgb.isNull) {
    return Nullable!ColorF.init;
  }
  float a = 1.0f;
  if (slashIdx < s.length) {
    const Nullable!ColorToken alphaTok = parseColorToken(
      trimAsciiSpace(s[slashIdx + 1 .. $])
    );
    if (alphaTok.isNull) {
      return Nullable!ColorF.init;
    }
    a = alphaChannelFromToken(alphaTok.get);
  }
  const ColorToken[3] c = rgb.get;
  return Nullable!ColorF(ColorF(
    rgbChannelFromToken(c[0]),
    rgbChannelFromToken(c[1]),
    rgbChannelFromToken(c[2]),
    a
  ));
}
