#version 300 es

precision highp float;

uniform vec4 uColor;
uniform vec2 uHalfSize;   // half-width, half-height of the rect
uniform float uRadius;    // corner radius (clamped to min half-dim)
uniform float uLineWidth; // 0.0 = fill mode, >0 = outline mode
uniform float uDashLen;   // dash length (0.0 = solid)
uniform float uGapLen;    // gap length  (0.0 = solid)
uniform float uPixelSize; // 1.0 / totalScaling — for AA smoothstep

in vec2 vLocalPos;
out vec4 fragColor;

float sdRoundBox(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
  float d = sdRoundBox(vLocalPos, uHalfSize, uRadius);

  float aa = uPixelSize * 1.0;
  float alpha;

  if (uLineWidth > 0.0) {
    // Outline mode: band between d = -lineWidth and d = 0
    float outer = 1.0 - smoothstep(-aa, aa, d);
    float inner = 1.0 - smoothstep(-aa, aa, d + uLineWidth);
    alpha = outer - inner;

    // Dashed mode
    if (uDashLen > 0.0 && uGapLen > 0.0) {
      // Compute perimeter parameter along the border using angle
      float angle = atan(vLocalPos.y, vLocalPos.x);
      float perim = (uHalfSize.x + uHalfSize.y) * 2.0;
      float t = (angle + 3.14159265) / 6.28318530 * perim;
      float period = uDashLen + uGapLen;
      float phase = mod(t, period);
      float dashAlpha = smoothstep(0.0, aa, phase)
        * (1.0 - smoothstep(uDashLen - aa, uDashLen, phase));
      alpha *= dashAlpha;
    }
  } else {
    // Fill mode
    alpha = 1.0 - smoothstep(-aa, aa, d);
  }

  if (alpha <= 0.0) {
    discard;
  }
  fragColor = vec4(uColor.rgb, uColor.a * alpha);
}
