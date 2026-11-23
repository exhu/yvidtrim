#version 300 es

/**
 * Gradient paint (HTML canvas semantics, pad spread).
 *
 * `uKind`: 0 linear (`uP0` -> `uP1`), 1 radial (circle `uP0`, `uR0` to
 * circle `uP1`, `uR1`). `uInvXf` maps logic coordinates to gradient user
 * space. Stops are sorted by offset; colors are non-premultiplied and are
 * interpolated in premultiplied alpha. Output is non-premultiplied for the
 * SRC_ALPHA / ONE_MINUS_SRC_ALPHA blend func.
 */
precision highp float;

const int maxStops = 8;

uniform int uKind;
uniform mat3 uInvXf;
uniform vec2 uP0;
uniform vec2 uP1;
uniform float uR0;
uniform float uR1;
uniform vec4 uStopColors[maxStops];
uniform float uStopOffsets[maxStops];
uniform int uStopCount;

in vec2 vPos;
out vec4 fragColor;

/**
 * Linear gradient parameter of `p`: projection onto `uP0` -> `uP1`.
 * Returns a negative `.y` when the gradient is degenerate (draw nothing).
 */
vec2 linearT(vec2 p) {
  vec2 d = uP1 - uP0;
  float dd = dot(d, d);
  if (dd <= 0.0) {
    return vec2(0.0, -1.0);
  }
  return vec2(dot(p - uP0, d) / dd, 1.0);
}

/**
 * Two-circle (conical) radial gradient parameter of `p`, canvas spec:
 * circles c(w) = c0 + w * (c1 - c0) with radius r(w) = r0 + w * (r1 - r0).
 * Finds the largest w with r(w) >= 0 such that p lies on circle c(w), i.e.
 * |p - c0 - w * cd|^2 = (r0 + w * dr)^2, which is the quadratic
 * a * w^2 - 2 * b * w + c = 0 with a = cd.cd - dr^2,
 * b = pd.cd + r0 * dr, c = pd.pd - r0^2 (pd = p - c0).
 * Returns a negative `.y` when there is no such w (draw nothing).
 */
vec2 radialT(vec2 p) {
  vec2 cd = uP1 - uP0;
  vec2 pd = p - uP0;
  float dr = uR1 - uR0;
  float a = dot(cd, cd) - dr * dr;
  float b = dot(pd, cd) + uR0 * dr;
  float c = dot(pd, pd) - uR0 * uR0;
  const vec2 none = vec2(0.0, -1.0);
  if (abs(a) < 1e-6) {
    // linear case: -2 * b * w + c = 0
    if (abs(b) < 1e-6) {
      return none;
    }
    float w = c / (2.0 * b);
    return uR0 + w * dr >= 0.0 ? vec2(w, 1.0) : none;
  }
  float disc = b * b - a * c;
  if (disc < 0.0) {
    return none;
  }
  float s = sqrt(disc);
  float w1 = (b + s) / a;
  float w2 = (b - s) / a;
  float hi = max(w1, w2);
  float lo = min(w1, w2);
  if (uR0 + hi * dr >= 0.0) {
    return vec2(hi, 1.0);
  }
  if (uR0 + lo * dr >= 0.0) {
    return vec2(lo, 1.0);
  }
  return none;
}

vec4 premul(vec4 c) {
  return vec4(c.rgb * c.a, c.a);
}

/// Premultiplied stop color at `t` in [0, 1] (pad outside the stops).
vec4 stopColor(float t) {
  vec4 col = premul(uStopColors[0]);
  for (int i = 1; i < maxStops; ++i) {
    if (i >= uStopCount) {
      break;
    }
    float o0 = uStopOffsets[i - 1];
    float o1 = uStopOffsets[i];
    if (t < o0) {
      break;
    }
    vec4 c1 = premul(uStopColors[i]);
    if (t >= o1) {
      col = c1;
    } else {
      float f = (t - o0) / max(o1 - o0, 1e-6);
      col = mix(premul(uStopColors[i - 1]), c1, f);
    }
  }
  return col;
}

void main() {
  if (uStopCount <= 0) {
    discard;
  }
  vec2 p = (uInvXf * vec3(vPos, 1.0)).xy;
  vec2 tv = uKind == 0 ? linearT(p) : radialT(p);
  if (tv.y < 0.0) {
    discard;
  }
  vec4 c = stopColor(clamp(tv.x, 0.0, 1.0));
  if (c.a <= 0.0) {
    discard;
  }
  fragColor = vec4(c.rgb / c.a, c.a);
}
