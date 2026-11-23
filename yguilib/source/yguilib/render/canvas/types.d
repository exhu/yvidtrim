/**
 * Value types, enums, paints, and shadow configuration for `Canvas`.
 */
module yguilib.render.canvas.types;

import yguilib.render.font : defaultFontPtSize;
import yguilib.render.render_types : ColorF, PointF;
import yguilib.render.texture : Texture;

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

  /// Determinant of the linear part (`a * d - b * c`).
  float determinant() const nothrow @safe @nogc pure {
    return a * d - b * c;
  }

  /// True when the determinant is finite and its magnitude >= 1e-12.
  bool isInvertible() const nothrow @safe @nogc pure {
    import std.math : abs, isFinite;

    const float det = determinant();
    return isFinite(det) && abs(det) >= 1e-12f;
  }

  /// Inverse transform; returns identity when the matrix is singular.
  Transform2d inverse() const nothrow @safe @nogc pure {
    if (!isInvertible()) {
      return Transform2d.identity();
    }
    const float inv = 1.0f / determinant();
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
    const float det = determinant();
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
  assert(Transform2d.scaling(PointF(2, -3)).determinant() == -6);
  assert(m.isInvertible());
  assert(!Transform2d.scaling(PointF(0, 1)).isInvertible());
  assert(!Transform2d(float.nan, 0, 0, 1, 0, 0).isInvertible());

  assert(isClose(Transform2d.scaling(PointF(2, 3)).maxScale(), 3.0f));
  assert(isClose((r * Transform2d.scaling(PointF(-4, 1))).maxScale(), 4.0f));
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

/**
 * Dash pattern: alternating dash/gap lengths; empty means solid. Holds at
 * most `maxSegments` normalized segments inline, so it is `@nogc` and
 * cheap to copy. Build it with `fromSegments`.
 */
struct LineDash {
  /// Capacity of the normalized (even-length) segment list.
  enum size_t maxSegments = 32;

  /**
   * Builds a dash from `src`: an odd count is duplicated, any negative or
   * non-finite value gives an empty (solid) dash. Deviation from HTML
   * (which has no limit): a normalized length above `maxSegments` also
   * gives a solid dash.
   */
  static LineDash fromSegments(const float[] src) nothrow @safe @nogc {
    import std.math : isFinite;

    foreach (v; src) {
      if (!isFinite(v) || v < 0) {
        return LineDash.init;
      }
    }
    const size_t len = src.length % 2 == 1 ? src.length * 2 : src.length;
    if (len > maxSegments) {
      return LineDash.init;
    }
    LineDash res;
    float sum = 0;
    foreach (i; 0 .. len) {
      res.fSegs[i] = src[i % src.length];
      sum += res.fSegs[i];
    }
    res.fCount = cast(ubyte) len;
    res.fPeriod = sum;
    return res;
  }

  /// The normalized (even-length) dash/gap lengths.
  const(float)[] segments() const return nothrow @safe @nogc {
    return fSegs[0 .. fCount];
  }

  /// True when no dashing applies (empty or zero period).
  bool isSolid() const nothrow @safe @nogc {
    return fCount == 0 || fPeriod <= 0;
  }

  /// Sum of all segment lengths.
  float period() const nothrow @safe @nogc {
    return fPeriod;
  }

private:
  float[maxSegments] fSegs = 0;
  ubyte fCount;
  float fPeriod = 0;
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

// LineDash capacity: odd counts double, overflow gives solid
unittest {
  float[17] odd17 = 1;
  const LineDash d17 = LineDash.fromSegments(odd17[]);
  assert(d17.isSolid() && d17.segments.length == 0);

  float[16] even16;
  foreach (i, ref v; even16) {
    v = i + 1;
  }
  const LineDash d16 = LineDash.fromSegments(even16[]);
  assert(d16.segments == even16[]);
  assert(d16.period() == 136);

  const LineDash d3 = LineDash.fromSegments([1.0f, 2, 3]);
  assert(d3.segments.length == 6);

  float[LineDash.maxSegments] full = 2;
  assert(LineDash.fromSegments(full[]).segments.length == full.length);
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

/// How a `Pattern` repeats outside its `[0, width) x [0, height)` tile.
enum PatternRepeat {
  /// Draw the tile once; transparent outside.
  noRepeat = 0,
  /// Tile horizontally; transparent outside `[0, height)`.
  repeatX = 1,
  /// Tile vertically; transparent outside `[0, width)`.
  repeatY = 2,
  /// Tile in both directions.
  repeat = 3,
}

/// Repeating image paint (`Texture` or `RenderTarget.texture()`).
struct Pattern {
  import std.typecons : Rebindable;

  PatternRepeat repeat = PatternRepeat.repeat;
  /// Pattern pixel space to user space transform.
  Transform2d transform = Transform2d.identity();
  /// Straight-alpha tint color.
  ColorF tint = ColorF(1, 1, 1, 1);

  /// Creates a pattern from `tex` with the given repeat mode.
  static Pattern fromTexture(
    const(Texture) tex,
    PatternRepeat rep
  ) nothrow @safe @nogc {
    Pattern p;
    p.fTexture = tex;
    p.repeat = rep;
    return p;
  }

  /// Pattern texture; null or destroyed texture draws nothing.
  const(Texture) texture() const nothrow @safe @nogc {
    return fTexture.get;
  }

  /// Sets the pattern texture.
  void texture(const(Texture) tex) nothrow @safe @nogc {
    fTexture = tex;
  }

  /// Sets the pattern-to-user transform.
  ref Pattern withTransform(Transform2d xf) return nothrow @safe @nogc {
    transform = xf;
    return this;
  }

  /// Sets the straight-alpha tint color.
  ref Pattern withTint(ColorF c) return nothrow @safe @nogc {
    tint = c;
    return this;
  }

private:
  Rebindable!(const Texture) fTexture;
}

/**
 * Paint for fills and strokes: solid color, gradient, or image pattern.
 * A tagged union: only the member matching `kind()` is stored, and its
 * getter asserts the kind. Build it with the factory functions;
 * `FillStyle.init` is solid opaque black.
 */
struct FillStyle {
  enum Kind {
    color,
    linearGradient,
    radialGradient,
    pattern,
  }

  /// Solid color paint.
  static FillStyle solid(ColorF c) nothrow @safe @nogc {
    FillStyle s;
    s.fKind = Kind.color;
    s.fColor = c;
    return s;
  }

  /// Linear gradient paint.
  static FillStyle fromLinear(in LinearGradient g) nothrow @safe @nogc {
    FillStyle s;
    s.fKind = Kind.linearGradient;
    s.fLinear = g;
    return s;
  }

  /// Radial gradient paint.
  static FillStyle fromRadial(in RadialGradient g) nothrow @safe @nogc {
    FillStyle s;
    s.fKind = Kind.radialGradient;
    s.fRadial = g;
    return s;
  }

  /// Image pattern paint.
  static FillStyle fromPattern(in Pattern p) nothrow @trusted @nogc {
    FillStyle s;
    s.fKind = Kind.pattern;
    // the pattern overlaps non-pointer members: written only here, read
    // only by `pattern()` after the kind check
    s.fPattern = p;
    return s;
  }

  /// Which paint this is.
  Kind kind() const nothrow @safe @nogc {
    return fKind;
  }

  /// Solid color; `kind()` must be `Kind.color`.
  ColorF color() const nothrow @safe @nogc {
    assert(fKind == Kind.color, "FillStyle is not a solid color");
    return fColor;
  }

  /// Linear gradient; `kind()` must be `Kind.linearGradient`.
  ref const(LinearGradient) linear() const return nothrow @safe @nogc {
    assert(fKind == Kind.linearGradient, "FillStyle is not linear");
    return fLinear;
  }

  /// Radial gradient; `kind()` must be `Kind.radialGradient`.
  ref const(RadialGradient) radial() const return nothrow @safe @nogc {
    assert(fKind == Kind.radialGradient, "FillStyle is not radial");
    return fRadial;
  }

  /// Image pattern; `kind()` must be `Kind.pattern`.
  ref const(Pattern) pattern() const return nothrow @trusted @nogc {
    assert(fKind == Kind.pattern, "FillStyle is not a pattern");
    return fPattern;
  }

private:
  Kind fKind = Kind.color;
  union {
    ColorF fColor = ColorF(0, 0, 0, 1);
    LinearGradient fLinear;
    RadialGradient fRadial;
    // holds a texture pointer: accessed only through @trusted functions
    Pattern fPattern;
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

  assert(Pattern.init.texture is null);
  assert(Pattern.init.repeat == PatternRepeat.repeat);
  assert(Pattern.init.transform.isIdentity());
  assert(Pattern.init.tint == ColorF(1, 1, 1, 1));
  const xf = Transform2d.translation(PointF(4, 8));
  const tint = ColorF(1, 0.5f, 0.25f, 0.75f);
  Pattern pat = Pattern.fromTexture(null, PatternRepeat.noRepeat);
  pat.withTransform(xf).withTint(tint);
  assert(pat.texture is null);
  assert(pat.repeat == PatternRepeat.noRepeat);
  assert(pat.transform == xf);
  assert(pat.tint == tint);
  const fp = FillStyle.fromPattern(pat);
  assert(fp.kind == FillStyle.Kind.pattern);
  assert(fp.pattern.texture is null);
  assert(fp.pattern.repeat == PatternRepeat.noRepeat);
  assert(fp.pattern.transform == xf);
  assert(fp.pattern.tint == tint);

  // a copy keeps the active member
  FillStyle cp = fl;
  assert(cp.kind == FillStyle.Kind.linearGradient && cp.linear.p1.x == 10);
  cp = FillStyle.solid(ColorF(0, 1, 0, 1));
  assert(cp.color == ColorF(0, 1, 0, 1));
}

/**
 * Drop shadow of Canvas fills and strokes: the shape's coverage, blurred
 * with a Gaussian of standard deviation `blur / 2` (logic units), tinted
 * with `color` and drawn at `offset` (not transformed) under the shape.
 */
struct Shadow {
  /// Largest Gaussian standard deviation applied, in device pixels.
  enum float maxBlurSigmaPx = 64;

  PointF offset;
  /**
   * Blur amount (logic units, >= 0): the Gaussian sigma is `blur / 2`,
   * i.e. `blur / 2 * scaling` device pixels, clamped to `maxBlurSigmaPx`
   * so huge values cannot stall the GPU. Sigmas over 32 px are blurred at
   * 1/2 resolution, and over `maxBlurSigmaPx` at 1/4 resolution, then
   * upscaled with linear filtering. Downsampled masks are not
   * antialiased, so thin shapes may shimmer slightly at such blurs.
   */
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

/**
 * How a shadow blur runs: the mask is drawn and blurred at 1 /
 * `downsample` of the device resolution with Gaussian sigma `sigma` in
 * those (reduced) pixels.
 */
package(yguilib) struct ShadowBlur {
  float sigma = 0;
  int downsample = 1;
}

/**
 * Shadow blur for a requested sigma of `sigmaPx` device pixels (see
 * `Shadow.blur`): clamped to `Shadow.maxBlurSigmaPx`, at 1/2 resolution
 * over 32 px and at 1/4 over `maxBlurSigmaPx`.
 */
package(yguilib) ShadowBlur shadowBlurFromSigmaPx(float sigmaPx)
nothrow @safe @nogc {
  enum float maxPx = Shadow.maxBlurSigmaPx;
  if (!(sigmaPx > 0)) {
    return ShadowBlur(0, 1);
  }
  if (sigmaPx > maxPx) {
    return ShadowBlur(maxPx / 4, 4);
  }
  if (sigmaPx > maxPx / 2) {
    return ShadowBlur(sigmaPx / 2, 2);
  }
  return ShadowBlur(sigmaPx, 1);
}

unittest {
  assert(shadowBlurFromSigmaPx(0) == ShadowBlur(0, 1));
  assert(shadowBlurFromSigmaPx(float.nan) == ShadowBlur(0, 1));
  assert(shadowBlurFromSigmaPx(10) == ShadowBlur(10, 1));
  assert(shadowBlurFromSigmaPx(32) == ShadowBlur(32, 1));
  assert(shadowBlurFromSigmaPx(48) == ShadowBlur(24, 2));
  assert(shadowBlurFromSigmaPx(64) == ShadowBlur(32, 2));
  assert(shadowBlurFromSigmaPx(65) == ShadowBlur(16, 4));
  assert(shadowBlurFromSigmaPx(float.infinity) == ShadowBlur(16, 4));
  // the effective sigma never exceeds the clamp in device pixels
  foreach (s; [1.0f, 33.0f, 64.0f, 500.0f, 1e9f]) {
    const b = shadowBlurFromSigmaPx(s);
    assert(b.sigma * b.downsample <= Shadow.maxBlurSigmaPx);
  }
}

enum FillRule {
  nonZero,
  evenOdd,
}

/// Font selection of Canvas text: logical point size and registered name.
struct FontSpec {
  float ptSize = defaultFontPtSize;
  /// Registered font name; null or empty selects the default font.
  string name;
}

/// Horizontal text anchor (`start`/`end` depend on `TextDirection`).
enum TextAlign {
  start,
  end,
  left,
  right,
  center,
}

/// Vertical text anchor relative to the font metrics.
enum TextBaseline {
  alphabetic,
  top,
  hanging,
  middle,
  ideographic,
  bottom,
}

enum TextDirection {
  ltr,
  rtl,
}

/// Measured text in logic units; descent is a positive distance.
struct TextMetrics {
  float width = 0;
  float fontAscent = 0;
  float fontDescent = 0;
}

/**
 * Offset from the text anchor point to the top-left corner of the text
 * box (`m.width` by `m.fontAscent + m.fontDescent`), y down.
 *
 * Approximations: hanging baseline is `0.2 * ascent` below the top,
 * ideographic is the box bottom, `middle` is half of the box height.
 */
package(yguilib) PointF textAnchorOffset(
  in TextMetrics m,
  TextAlign textAlign,
  TextBaseline baseline,
  TextDirection dir
) nothrow @safe @nogc pure {
  const float h = m.fontAscent + m.fontDescent;
  float x = 0;
  final switch (textAlign) {
  case TextAlign.left:
    break;
  case TextAlign.right:
    x = -m.width;
    break;
  case TextAlign.center:
    x = -m.width * 0.5f;
    break;
  case TextAlign.start:
    x = dir == TextDirection.ltr ? 0 : -m.width;
    break;
  case TextAlign.end:
    x = dir == TextDirection.ltr ? -m.width : 0;
    break;
  }
  float y = 0;
  final switch (baseline) {
  case TextBaseline.top:
    break;
  case TextBaseline.hanging:
    y = -0.2f * m.fontAscent;
    break;
  case TextBaseline.alphabetic:
    y = -m.fontAscent;
    break;
  case TextBaseline.middle:
    y = -h * 0.5f;
    break;
  case TextBaseline.ideographic:
  case TextBaseline.bottom:
    y = -h;
    break;
  }
  return PointF(x, y);
}

unittest {
  const m = TextMetrics(100, 20, 5);
  alias A = TextAlign;
  alias B = TextBaseline;
  alias D = TextDirection;
  assert(textAnchorOffset(m, A.left, B.top, D.ltr) == PointF(0, 0));
  assert(textAnchorOffset(m, A.right, B.alphabetic, D.ltr)
    == PointF(-100, -20));
  assert(textAnchorOffset(m, A.center, B.middle, D.ltr)
    == PointF(-50, -12.5f));
  assert(textAnchorOffset(m, A.start, B.bottom, D.ltr) == PointF(0, -25));
  assert(textAnchorOffset(m, A.start, B.ideographic, D.rtl)
    == PointF(-100, -25));
  assert(textAnchorOffset(m, A.end, B.hanging, D.ltr) == PointF(-100, -4));
  assert(textAnchorOffset(m, A.end, B.top, D.rtl) == PointF(0, 0));
  assert(textAnchorOffset(TextMetrics.init, A.center, B.middle, D.ltr)
    == PointF(0, 0));
}
