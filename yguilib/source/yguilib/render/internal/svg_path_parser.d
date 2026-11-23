/**
 * Zero-allocation W3C SVG path data string parser (`parseSvgPathInto`).
 */
module yguilib.render.internal.svg_path_parser;

import std.math : abs, atan2, cos, isFinite, PI, sin, sqrt;
import std.typecons : nullable, Nullable;
import yguilib.render.canvas.path2d : Path2d, SvgArcParams;
import yguilib.render.render_types : PointF;

package(yguilib):

/**
 * Parses W3C SVG path data string `d` and appends its commands into `path`.
 * Stops immediately on the first syntax error, preserving already-emitted
 * commands, and returns `false` (`true` on success).
 */
bool parseSvgPathInto(Path2d path, string d) nothrow @safe {
  assert(path !is null);
  SvgScanner sc = SvgScanner(d, 0);
  SvgState st;
  sc.skipWsp();
  while (!sc.atEnd()) {
    const char cmd = sc.src[sc.pos];
    if (!st.hasInitialCmd && cmd != 'M' && cmd != 'm') {
      return false;
    }
    sc.pos += 1;
    if (!dispatchCommand(path, sc, st, cmd)) {
      return false;
    }
    sc.skipWsp();
  }
  return true;
}

private:

struct SvgState {
  PointF cur = PointF(0, 0);
  PointF start = PointF(0, 0);
  bool hasInitialCmd = false;
  char prevCmd = 0;
  PointF lastCubicCp = PointF(0, 0);
  PointF lastQuadCp = PointF(0, 0);
}

struct SvgScanner {
  string src;
  size_t pos;

  bool atEnd() const nothrow @safe @nogc pure {
    return pos >= src.length;
  }

  static bool isWsp(char c) nothrow @safe @nogc pure {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f';
  }

  static bool isDigit(char c) nothrow @safe @nogc pure {
    return c >= '0' && c <= '9';
  }

  void skipWsp() nothrow @safe @nogc pure {
    while (pos < src.length && isWsp(src[pos])) {
      pos += 1;
    }
  }

  /// Skips whitespace and at most one comma; returns `true` if a comma was hit.
  bool skipCommaWsp() nothrow @safe @nogc pure {
    skipWsp();
    if (pos < src.length && src[pos] == ',') {
      pos += 1;
      skipWsp();
      return true;
    }
    return false;
  }

  bool canStartNumber() const nothrow @safe @nogc pure {
    if (pos >= src.length) {
      return false;
    }
    const char c = src[pos];
    return isDigit(c) || c == '+' || c == '-' || c == '.';
  }

  Nullable!bool readFlag() nothrow @safe @nogc pure {
    if (pos >= src.length) {
      return Nullable!bool.init;
    }
    const char c = src[pos];
    if (c == '0') {
      pos += 1;
      return nullable(false);
    }
    if (c == '1') {
      pos += 1;
      return nullable(true);
    }
    return Nullable!bool.init;
  }

  Nullable!float readNumber() nothrow @safe @nogc pure {
    if (pos >= src.length) {
      return Nullable!float.init;
    }
    const bool neg = parseSign();
    ulong mantissa = 0;
    int exp10 = 0;
    if (!parseSignificand(mantissa, exp10)) {
      return Nullable!float.init;
    }
    if (!parseExponent(exp10)) {
      return Nullable!float.init;
    }
    return buildFloat(neg, mantissa, exp10);
  }

  bool parseSign() nothrow @safe @nogc pure {
    if (src[pos] == '-') {
      pos += 1;
      return true;
    }
    if (src[pos] == '+') {
      pos += 1;
    }
    return false;
  }

  bool parseSignificand(
    ref ulong mantissa,
    ref int exp10
  ) nothrow @safe @nogc pure {
    enum ulong maxMantissa = 1_000_000_000_000_000_000UL;
    bool hasDigits = false;
    while (pos < src.length && isDigit(src[pos])) {
      hasDigits = true;
      const uint d = src[pos] - '0';
      if (mantissa <= maxMantissa) {
        mantissa = mantissa * 10 + d;
      } else {
        exp10 += 1;
      }
      pos += 1;
    }
    if (pos < src.length && src[pos] == '.') {
      pos += 1;
      while (pos < src.length && isDigit(src[pos])) {
        hasDigits = true;
        const uint d = src[pos] - '0';
        if (mantissa <= maxMantissa) {
          mantissa = mantissa * 10 + d;
          exp10 -= 1;
        }
        pos += 1;
      }
    }
    return hasDigits;
  }

  bool parseExponent(ref int exp10) nothrow @safe @nogc pure {
    if (pos >= src.length || (src[pos] != 'e' && src[pos] != 'E')) {
      return true;
    }
    pos += 1;
    if (pos >= src.length) {
      return false;
    }
    const bool expNeg = parseSign();
    if (pos >= src.length || !isDigit(src[pos])) {
      return false;
    }
    int expVal = 0;
    while (pos < src.length && isDigit(src[pos])) {
      if (expVal < 100_000) {
        expVal = expVal * 10 + (src[pos] - '0');
      }
      pos += 1;
    }
    exp10 += expNeg ? -expVal : expVal;
    return true;
  }
}

double pow10(int e) nothrow @safe @nogc pure {
  double res = 1.0;
  double base = 10.0;
  int n = e;
  while (n > 0) {
    if (n & 1) {
      res *= base;
    }
    n >>= 1;
    if (n > 0) {
      base *= base;
    }
  }
  return res;
}

Nullable!float buildFloat(
  bool neg,
  ulong mantissa,
  int exp10
) nothrow @safe @nogc pure {
  if (mantissa == 0) {
    return nullable(0.0f);
  }
  if (exp10 > 308) {
    return Nullable!float.init;
  }
  double val = cast(double) mantissa;
  if (exp10 < -340) {
    val = 0.0;
  } else if (exp10 > 0) {
    val *= pow10(exp10);
  } else if (exp10 < 0) {
    const int k = -exp10;
    if (k > 308) {
      val = (val / pow10(300)) / pow10(k - 300);
    } else {
      val /= pow10(k);
    }
  }
  const float f = cast(float)(neg ? -val : val);
  if (!isFinite(f)) {
    return Nullable!float.init;
  }
  return Nullable!float(f);
}

Nullable!PointF readPoint(ref SvgScanner sc) nothrow @safe @nogc pure {
  const x = sc.readNumber();
  if (x.isNull) {
    return Nullable!PointF.init;
  }
  sc.skipCommaWsp();
  const y = sc.readNumber();
  if (y.isNull) {
    return Nullable!PointF.init;
  }
  return nullable(PointF(x.get, y.get));
}

PointF resolvePoint(
  PointF raw,
  PointF cur,
  bool rel
) nothrow @safe @nogc pure {
  return rel ? PointF(cur.x + raw.x, cur.y + raw.y) : raw;
}

bool continueArgs(ref SvgScanner sc, bool first) nothrow @safe @nogc pure {
  if (first) {
    sc.skipWsp();
    return true;
  }
  const bool hadComma = sc.skipCommaWsp();
  return hadComma || sc.canStartNumber();
}

bool dispatchCommand(
  Path2d path,
  ref SvgScanner sc,
  ref SvgState st,
  char cmd
) nothrow @safe {
  switch (cmd) {
  case 'M':
  case 'm':
    return parseMoveTo(path, sc, st, cmd);
  case 'Z':
  case 'z':
    path.closePath();
    st.cur = st.start;
    st.prevCmd = cmd;
    return true;
  case 'L':
  case 'l':
    return parseLineTo(path, sc, st, cmd);
  case 'H':
  case 'h':
    return parseHorizTo(path, sc, st, cmd);
  case 'V':
  case 'v':
    return parseVertTo(path, sc, st, cmd);
  case 'C':
  case 'c':
    return parseCubicTo(path, sc, st, cmd);
  case 'S':
  case 's':
    return parseSmoothCubicTo(path, sc, st, cmd);
  case 'Q':
  case 'q':
    return parseQuadTo(path, sc, st, cmd);
  case 'T':
  case 't':
    return parseSmoothQuadTo(path, sc, st, cmd);
  case 'A':
  case 'a':
    return parseArcCmd(path, sc, st, cmd);
  default:
    return false;
  }
}

bool parseMoveTo(
  Path2d path,
  ref SvgScanner sc,
  ref SvgState st,
  char cmd
) nothrow @safe {
  const bool rel = cmd == 'm';
  bool first = true;
  while (continueArgs(sc, first)) {
    const pt = readPoint(sc);
    if (pt.isNull) {
      return false;
    }
    const bool useRel = rel && st.hasInitialCmd;
    const PointF dst = resolvePoint(pt.get, st.cur, useRel);
    if (first) {
      path.moveTo(dst);
      st.start = dst;
      st.hasInitialCmd = true;
      st.prevCmd = cmd;
      first = false;
    } else {
      path.lineTo(dst);
      st.prevCmd = rel ? 'l' : 'L';
    }
    st.cur = dst;
  }
  return !first;
}

bool parseLineTo(
  Path2d path,
  ref SvgScanner sc,
  ref SvgState st,
  char cmd
) nothrow @safe {
  const bool rel = cmd == 'l';
  bool first = true;
  while (continueArgs(sc, first)) {
    const pt = readPoint(sc);
    if (pt.isNull) {
      return false;
    }
    const PointF dst = resolvePoint(pt.get, st.cur, rel);
    path.lineTo(dst);
    st.cur = dst;
    st.prevCmd = cmd;
    first = false;
  }
  return !first;
}

bool parseHorizTo(
  Path2d path,
  ref SvgScanner sc,
  ref SvgState st,
  char cmd
) nothrow @safe {
  const bool rel = cmd == 'h';
  bool first = true;
  while (continueArgs(sc, first)) {
    const x = sc.readNumber();
    if (x.isNull) {
      return false;
    }
    const PointF dst = PointF(rel ? st.cur.x + x.get : x.get, st.cur.y);
    path.lineTo(dst);
    st.cur = dst;
    st.prevCmd = cmd;
    first = false;
  }
  return !first;
}

bool parseVertTo(
  Path2d path,
  ref SvgScanner sc,
  ref SvgState st,
  char cmd
) nothrow @safe {
  const bool rel = cmd == 'v';
  bool first = true;
  while (continueArgs(sc, first)) {
    const y = sc.readNumber();
    if (y.isNull) {
      return false;
    }
    const PointF dst = PointF(st.cur.x, rel ? st.cur.y + y.get : y.get);
    path.lineTo(dst);
    st.cur = dst;
    st.prevCmd = cmd;
    first = false;
  }
  return !first;
}

bool parseCubicTo(
  Path2d path,
  ref SvgScanner sc,
  ref SvgState st,
  char cmd
) nothrow @safe {
  const bool rel = cmd == 'c';
  bool first = true;
  while (continueArgs(sc, first)) {
    const p1 = readPoint(sc);
    if (p1.isNull) {
      return false;
    }
    sc.skipCommaWsp();
    const p2 = readPoint(sc);
    if (p2.isNull) {
      return false;
    }
    sc.skipCommaWsp();
    const p3 = readPoint(sc);
    if (p3.isNull) {
      return false;
    }
    const PointF cp1 = resolvePoint(p1.get, st.cur, rel);
    const PointF cp2 = resolvePoint(p2.get, st.cur, rel);
    const PointF dst = resolvePoint(p3.get, st.cur, rel);
    path.bezierCurveTo(cp1, cp2, dst);
    st.lastCubicCp = cp2;
    st.cur = dst;
    st.prevCmd = cmd;
    first = false;
  }
  return !first;
}

bool parseSmoothCubicTo(
  Path2d path,
  ref SvgScanner sc,
  ref SvgState st,
  char cmd
) nothrow @safe {
  const bool rel = cmd == 's';
  bool first = true;
  while (continueArgs(sc, first)) {
    const p2 = readPoint(sc);
    if (p2.isNull) {
      return false;
    }
    sc.skipCommaWsp();
    const p3 = readPoint(sc);
    if (p3.isNull) {
      return false;
    }
    const bool reflect = st.prevCmd == 'C' || st.prevCmd == 'c'
      || st.prevCmd == 'S' || st.prevCmd == 's';
    const PointF cp1 = reflect
      ? PointF(2 * st.cur.x - st.lastCubicCp.x, 2 * st.cur.y - st.lastCubicCp.y)
      : st.cur;
    const PointF cp2 = resolvePoint(p2.get, st.cur, rel);
    const PointF dst = resolvePoint(p3.get, st.cur, rel);
    path.bezierCurveTo(cp1, cp2, dst);
    st.lastCubicCp = cp2;
    st.cur = dst;
    st.prevCmd = cmd;
    first = false;
  }
  return !first;
}

bool parseQuadTo(
  Path2d path,
  ref SvgScanner sc,
  ref SvgState st,
  char cmd
) nothrow @safe {
  const bool rel = cmd == 'q';
  bool first = true;
  while (continueArgs(sc, first)) {
    const p1 = readPoint(sc);
    if (p1.isNull) {
      return false;
    }
    sc.skipCommaWsp();
    const p2 = readPoint(sc);
    if (p2.isNull) {
      return false;
    }
    const PointF cp = resolvePoint(p1.get, st.cur, rel);
    const PointF dst = resolvePoint(p2.get, st.cur, rel);
    path.quadraticCurveTo(cp, dst);
    st.lastQuadCp = cp;
    st.cur = dst;
    st.prevCmd = cmd;
    first = false;
  }
  return !first;
}

bool parseSmoothQuadTo(
  Path2d path,
  ref SvgScanner sc,
  ref SvgState st,
  char cmd
) nothrow @safe {
  const bool rel = cmd == 't';
  bool first = true;
  while (continueArgs(sc, first)) {
    const p2 = readPoint(sc);
    if (p2.isNull) {
      return false;
    }
    const bool reflect = st.prevCmd == 'Q' || st.prevCmd == 'q'
      || st.prevCmd == 'T' || st.prevCmd == 't';
    const PointF cp = reflect
      ? PointF(2 * st.cur.x - st.lastQuadCp.x, 2 * st.cur.y - st.lastQuadCp.y)
      : st.cur;
    const PointF dst = resolvePoint(p2.get, st.cur, rel);
    path.quadraticCurveTo(cp, dst);
    st.lastQuadCp = cp;
    st.cur = dst;
    st.prevCmd = cmd;
    first = false;
  }
  return !first;
}

struct SvgArcArgs {
  float rx;
  float ry;
  float xAxisRotDeg;
  bool largeArc;
  bool sweep;
  PointF end;
}

Nullable!SvgArcArgs readArcArgs(ref SvgScanner sc) nothrow @safe @nogc pure {
  const rx = sc.readNumber();
  if (rx.isNull) {
    return Nullable!SvgArcArgs.init;
  }
  sc.skipCommaWsp();
  const ry = sc.readNumber();
  if (ry.isNull) {
    return Nullable!SvgArcArgs.init;
  }
  sc.skipCommaWsp();
  const rot = sc.readNumber();
  if (rot.isNull) {
    return Nullable!SvgArcArgs.init;
  }
  sc.skipCommaWsp();
  const largeArc = sc.readFlag();
  if (largeArc.isNull) {
    return Nullable!SvgArcArgs.init;
  }
  sc.skipCommaWsp();
  const sweep = sc.readFlag();
  if (sweep.isNull) {
    return Nullable!SvgArcArgs.init;
  }
  sc.skipCommaWsp();
  const endPt = readPoint(sc);
  if (endPt.isNull) {
    return Nullable!SvgArcArgs.init;
  }
  return nullable(SvgArcArgs(
    rx.get, ry.get, rot.get, largeArc.get, sweep.get, endPt.get
  ));
}

void emitSvgArc(
  Path2d path,
  PointF cur,
  in SvgArcArgs a
) nothrow @safe {
  if (a.end.x == cur.x && a.end.y == cur.y) {
    return;
  }
  if (a.rx == 0 || a.ry == 0) {
    path.lineTo(a.end);
    return;
  }
  double rxAbs = abs(cast(double) a.rx);
  double ryAbs = abs(cast(double) a.ry);
  const double phi = cast(double) a.xAxisRotDeg * (PI / 180.0);
  const double cosPhi = cos(phi);
  const double sinPhi = sin(phi);
  const double dx2 = (cast(double) cur.x - cast(double) a.end.x) * 0.5;
  const double dy2 = (cast(double) cur.y - cast(double) a.end.y) * 0.5;
  const double x1p = cosPhi * dx2 + sinPhi * dy2;
  const double y1p = -sinPhi * dx2 + cosPhi * dy2;
  const double x1p2 = x1p * x1p;
  const double y1p2 = y1p * y1p;
  double rx2 = rxAbs * rxAbs;
  double ry2 = ryAbs * ryAbs;
  const double lambda = x1p2 / rx2 + y1p2 / ry2;
  if (lambda > 1.0) {
    const double s = sqrt(lambda);
    rxAbs *= s;
    ryAbs *= s;
    rx2 = rxAbs * rxAbs;
    ry2 = ryAbs * ryAbs;
  }
  const double den = rx2 * y1p2 + ry2 * x1p2;
  double radicand = den > 0.0 ? (rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2) / den : 0;
  if (radicand < 0.0) {
    radicand = 0.0;
  }
  const double coef = (a.largeArc == a.sweep ? -1.0 : 1.0) * sqrt(radicand);
  const double cxp = coef * ((rxAbs * y1p) / ryAbs);
  const double cyp = coef * (-(ryAbs * x1p) / rxAbs);
  const double mx = (cast(double) cur.x + cast(double) a.end.x) * 0.5;
  const double my = (cast(double) cur.y + cast(double) a.end.y) * 0.5;
  const double cx = cosPhi * cxp - sinPhi * cyp + mx;
  const double cy = sinPhi * cxp + cosPhi * cyp + my;
  const double ux = (x1p - cxp) / rxAbs;
  const double uy = (y1p - cyp) / ryAbs;
  const double vx = (-x1p - cxp) / rxAbs;
  const double vy = (-y1p - cyp) / ryAbs;
  const double theta1 = atan2(uy, ux);
  double dtheta = atan2(ux * vy - uy * vx, ux * vx + uy * vy);
  if (!a.sweep && dtheta > 0.0) {
    dtheta -= 2.0 * PI;
  } else if (a.sweep && dtheta < 0.0) {
    dtheta += 2.0 * PI;
  }
  path.appendSvgArc(SvgArcParams(
    PointF(cast(float) cx, cast(float) cy),
    PointF(cast(float) rxAbs, cast(float) ryAbs),
    cast(float) phi, cast(float) theta1, cast(float) dtheta, a.end
  ));
}

bool parseArcCmd(
  Path2d path,
  ref SvgScanner sc,
  ref SvgState st,
  char cmd
) nothrow @safe {
  const bool rel = cmd == 'a';
  bool first = true;
  while (continueArgs(sc, first)) {
    const args = readArcArgs(sc);
    if (args.isNull) {
      return false;
    }
    SvgArcArgs resolved = args.get;
    resolved.end = resolvePoint(resolved.end, st.cur, rel);
    emitSvgArc(path, st.cur, resolved);
    st.cur = resolved.end;
    st.prevCmd = cmd;
    first = false;
  }
  return !first;
}

// Empty, whitespace-only, and basic M/L/H/V/Z commands
unittest {
  import yguilib.render.canvas.path2d : PathVerb;

  auto p = Path2d.fromSvgPath("");
  assert(p.isEmpty());
  assert(p.addSvgPath("   \t\n\r\f  "));
  assert(p.isEmpty());

  p = Path2d.fromSvgPath("M 10 20 L 30 40 H 50 V 60 Z");
  assert(p.verbs == [
    PathVerb.moveTo, PathVerb.lineTo, PathVerb.lineTo,
    PathVerb.lineTo, PathVerb.close
  ]);
  assert(p.points == [
    PointF(10, 20), PointF(30, 40), PointF(50, 40), PointF(50, 60)
  ]);

  // Relative m as first command is absolute; subsequent implicit pairs are l
  p.clear();
  assert(p.addSvgPath("m 10 20 5 -5 h 10 v -10 l 2 3 z"));
  assert(p.verbs == [
    PathVerb.moveTo, PathVerb.lineTo, PathVerb.lineTo,
    PathVerb.lineTo, PathVerb.lineTo, PathVerb.close
  ]);
  assert(p.points == [
    PointF(10, 20), PointF(15, 15), PointF(25, 15),
    PointF(25, 5), PointF(27, 8)
  ]);

  // Implicit L after M, and m after z uses subpath start
  p.clear();
  assert(p.addSvgPath("M 10 20 30 40 z m 5 5"));
  assert(p.verbs == [
    PathVerb.moveTo, PathVerb.lineTo, PathVerb.close, PathVerb.moveTo
  ]);
  assert(p.points == [PointF(10, 20), PointF(30, 40), PointF(15, 25)]);
}

// Curves C/c/S/s/Q/q/T/t and smooth reflections
unittest {
  import yguilib.render.canvas.path2d : PathVerb;

  auto p = new Path2d();
  assert(p.addSvgPath("M 0 0 C 10 20 30 40 50 60 S 70 80 90 100"));
  assert(p.verbs == [PathVerb.moveTo, PathVerb.cubicTo, PathVerb.cubicTo]);
  // Reflected cp1 of S: 2*(50,60) - (30,40) = (70,80)
  assert(p.points == [
    PointF(0, 0),
    PointF(10, 20), PointF(30, 40), PointF(50, 60),
    PointF(70, 80), PointF(70, 80), PointF(90, 100)
  ]);

  // S not preceded by C/c/S/s uses current point as cp1; relative s & c
  p.clear();
  assert(p.addSvgPath("M 10 10 s 20 0 30 10 c 1 2 3 4 5 6"));
  assert(p.points == [
    PointF(10, 10),
    PointF(10, 10), PointF(30, 10), PointF(40, 20),
    PointF(41, 22), PointF(43, 24), PointF(45, 26)
  ]);

  // Quadratic Q/q and smooth T/t reflection + non-Q fallback
  p.clear();
  assert(p.addSvgPath("M 0 0 Q 10 20 30 0 T 60 0 t 10 5"));
  assert(p.verbs == [
    PathVerb.moveTo, PathVerb.quadTo, PathVerb.quadTo, PathVerb.quadTo
  ]);
  // T cp: 2*(30,0) - (10,20) = (50,-20); t cp: 2*(60,0) - (50,-20) = (70,20)
  assert(p.points == [
    PointF(0, 0),
    PointF(10, 20), PointF(30, 0),
    PointF(50, -20), PointF(60, 0),
    PointF(70, 20), PointF(70, 5)
  ]);

  p.clear();
  assert(p.addSvgPath("M 5 5 T 15 15"));
  assert(p.points == [PointF(5, 5), PointF(5, 5), PointF(15, 15)]);
}

// Compact syntax, scientific notation, commas, and error handling
unittest {
  import std.math : isClose;
  import yguilib.render.canvas.path2d : PathVerb;

  auto p = new Path2d();
  assert(p.addSvgPath("M10-20L.5.5l1.2.3M1e-2-3e+1l+1.5E2-.25"));
  assert(p.points.length == 5);
  assert(p.points[0] == PointF(10, -20));
  assert(p.points[1] == PointF(0.5f, 0.5f));
  assert(isClose(p.points[2].x, 1.7f, 1e-5));
  assert(isClose(p.points[2].y, 0.8f, 1e-5));
  assert(isClose(p.points[3].x, 0.01f, 1e-5));
  assert(p.points[3].y == -30.0f);
  assert(isClose(p.points[4].x, 150.01f, 1e-5));
  assert(p.points[4].y == -30.25f);

  // Compact arc flags (0120 -> largeArc=0, sweep=1, x=20)
  p.clear();
  assert(p.addSvgPath("M 0 0 A 10 10 0 0120 0"));
  assert(p.verbs.length >= 2 && p.points[$ - 1] == PointF(20, 0));

  // Syntax errors stop immediately and keep partial commands
  p.clear();
  assert(!p.addSvgPath("L 10 20")); // must start with M/m
  assert(p.isEmpty());

  assert(!p.addSvgPath("M 10,, 20"));
  assert(!p.addSvgPath("M,10 20"));
  assert(!p.addSvgPath("M 10 20, L 30 40"));
  assert(!p.addSvgPath("M 10 20,"));
  assert(!p.addSvgPath("M 10")); // missing y
  assert(!p.addSvgPath("M 10 20 X 30 40"));
  assert(!p.addSvgPath("M 10 20 A 10 10 0 2 1 30 40")); // bad flag
  assert(!p.addSvgPath("M 1e999 0")); // overflow
  p.clear();
  assert(!p.addSvgPath("M 10 20 L 30 40 bad"));
  // Partial valid prefix M 10 20 L 30 40 was retained
  assert(p.verbs == [PathVerb.moveTo, PathVerb.lineTo]);
  assert(p.points == [PointF(10, 20), PointF(30, 40)]);
}

// Arc parameterization: all 4 (largeArc, sweep) cases, rotation, degenerates
unittest {
  import std.math : isClose;
  import yguilib.render.canvas.path2d : PathVerb;

  bool near(PointF a, PointF b) {
    return isClose(a.x, b.x, 1e-3, 1e-3) && isClose(a.y, b.y, 1e-3, 1e-3);
  }

  // Circle of radius 10 from (10, 0) to (0, 10):
  // (0,1): short CW through (7.07, 7.07) -> 1 cubic
  // (1,1): long CW (270 deg) -> 3 cubics
  // (0,0): short CCW (wait: (10,0)->(0,10) short is CW, so (0,0) is
  //   center (10,10), goes through (0, 0)? Wait: check midpoint & length)
  auto p01 = Path2d.fromSvgPath("M 10 0 A 10 10 0 0 1 0 10");
  assert(p01.verbs == [PathVerb.moveTo, PathVerb.cubicTo]);
  assert(p01.points[$ - 1] == PointF(0, 10));
  const b01 = p01.bounds();
  assert(b01.x >= -0.01f && b01.y >= -0.01f);

  auto p11 = Path2d.fromSvgPath("M 10 0 A 10 10 0 1 1 0 10");
  assert(p11.verbs.length == 4); // moveTo + 3 cubics (270 deg)
  assert(p11.points[$ - 1] == PointF(0, 10));
  assert(p11.bounds().x > -1.0f && p11.bounds().width > 15.0f);

  auto p00 = Path2d.fromSvgPath("M 10 0 A 10 10 0 0 0 0 10");
  assert(p00.verbs == [PathVerb.moveTo, PathVerb.cubicTo]);
  assert(p00.points[$ - 1] == PointF(0, 10));
  // Center is (10, 10), curve goes near (3, 3) -> bounds inside [0, 10]
  assert(p00.bounds().x >= -0.01f && p00.bounds().y >= -0.01f);

  auto p10 = Path2d.fromSvgPath("M 10 0 A 10 10 0 1 0 0 10");
  assert(p10.verbs.length == 4);
  assert(p10.points[$ - 1] == PointF(0, 10));
  assert(p10.bounds().x < -5.0f && p10.bounds().y < -5.0f);

  // Rotated and upscaled radii (chord length 100, rx=10, ry=5 -> scaled up)
  auto pRot = Path2d.fromSvgPath("M 0 0 a 10 5 35 0 1 100 0");
  assert(pRot.verbs.length >= 2);
  assert(near(pRot.points[$ - 1], PointF(100, 0)));

  // Zero radius -> lineTo; coincident endpoint -> skipped
  auto pDeg = Path2d.fromSvgPath(
    "M 10 20 A 0 10 0 0 1 30 40 A 10 10 0 0 1 30 40"
  );
  assert(pDeg.verbs == [PathVerb.moveTo, PathVerb.lineTo]);
  assert(pDeg.points == [PointF(10, 20), PointF(30, 40)]);
}

// Gamepad bumper and body SVG strings from gamepad-canvas-by-gemini.html
unittest {
  import yguilib.render.canvas.path2d : PathVerb;

  auto leftBumper = Path2d.fromSvgPath(
    "M 155 112 C 165 88, 225 88, 235 106 Z"
  );
  assert(leftBumper.verbs == [
    PathVerb.moveTo, PathVerb.cubicTo, PathVerb.close
  ]);
  assert(leftBumper.points == [
    PointF(155, 112), PointF(165, 88), PointF(225, 88), PointF(235, 106)
  ]);

  auto rightBumper = Path2d.fromSvgPath(
    "M 365 106 C 375 88, 435 88, 445 112 Z"
  );
  assert(rightBumper.verbs == [
    PathVerb.moveTo, PathVerb.cubicTo, PathVerb.close
  ]);

  auto body = new Path2d();
  const bool ok = body.addSvgPath(
    "M 190 105 L 410 105 "
    ~ "C 455 105, 485 135, 500 200 "
    ~ "C 515 265, 505 320, 465 325 "
    ~ "C 435 328, 415 295, 395 260 "
    ~ "C 385 242, 370 235, 350 235 "
    ~ "L 250 235 "
    ~ "C 230 235, 215 242, 205 260 "
    ~ "C 185 295, 165 328, 135 325 "
    ~ "C 95 320, 85 265, 100 200 "
    ~ "C 115 135, 145 105, 190 105 Z"
  );
  assert(ok);
  assert(body.verbs == [
    PathVerb.moveTo, PathVerb.lineTo,
    PathVerb.cubicTo, PathVerb.cubicTo, PathVerb.cubicTo, PathVerb.cubicTo,
    PathVerb.lineTo,
    PathVerb.cubicTo, PathVerb.cubicTo, PathVerb.cubicTo, PathVerb.cubicTo,
    PathVerb.close
  ]);
  assert(body.points[0] == PointF(190, 105));
  assert(body.points[$ - 1] == PointF(190, 105));
}
