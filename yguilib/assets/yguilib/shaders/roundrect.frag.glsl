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

/**
 * Computes the perimeter arc-length parameter `t` along the outer border
 * of the rounded rectangle, starting at the top-left edge junction and
 * running clockwise.
 *
 * Coordinate system of vLocalPos:
 *   Center is (0, 0).
 *   x: -halfW (left) to +halfW (right)
 *   y: -halfH (top) to +halfH (bottom)
 *
 * Perimeter breakdown:
 *   - 4 straight edge segments of lengths:
 *       top/bottom: 2.0 * (halfW - r)
 *       left/right: 2.0 * (halfH - r)
 *   - 4 corner circular arcs of length: 0.5 * PI * r each
 */
float perimArcLength(vec2 p, vec2 hs, float r) {
  vec2 b = max(hs - vec2(r), vec2(0.0));
  float pi = 3.14159265359;

  float sideW = 2.0 * b.x;
  float sideH = 2.0 * b.y;
  float arc = 0.5 * pi * r;

  // Cumulative starting offsets for each perimeter segment (clockwise):
  // Seg 0: Top edge                [0, sideW)
  // Seg 1: Top-right corner arc    [sideW, sideW + arc)
  // Seg 2: Right edge              [sideW + arc, sideW + arc + sideH)
  // Seg 3: Bottom-right corner arc [sideW + arc + sideH, sideW + 2*arc + sideH)
  // Seg 4: Bottom edge             [..., 2*sideW + 2*arc + sideH)
  // Seg 5: Bottom-left corner arc  [..., 2*sideW + 3*arc + sideH)
  // Seg 6: Left edge               [..., 2*sideW + 3*arc + 2*sideH)
  // Seg 7: Top-left corner arc     [..., 2*sideW + 4*arc + 2*sideH)
  float oTopEdge = 0.0;
  float oRightArc = oTopEdge + sideW;
  float oRightEdge = oRightArc + arc;
  float oBotArc = oRightEdge + sideH;
  float oBotEdge = oBotArc + arc;
  float oLeftArc = oBotEdge + sideW;
  float oLeftEdge = oLeftArc + arc;
  float oTopArc = oLeftEdge + sideH;
  float totalPerim = oTopArc + arc;

  vec2 c = clamp(p, -b, b);
  vec2 d = p - c;

  bool inCorner = (abs(p.x) > b.x) && (abs(p.y) > b.y);

  float t = 0.0;
  if (inCorner && r > 0.0) {
    if (d.x > 0.0 && d.y < 0.0) {
      // Top-right corner: from -Y (up) clockwise to +X (right)
      float angle = atan(d.x, -d.y);
      t = oRightArc + angle * r;
    } else if (d.x > 0.0 && d.y > 0.0) {
      // Bottom-right corner: from +X (right) clockwise to +Y (down)
      float angle = atan(d.y, d.x);
      t = oBotArc + angle * r;
    } else if (d.x < 0.0 && d.y > 0.0) {
      // Bottom-left corner: from +Y (down) clockwise to -X (left)
      float angle = atan(-d.x, d.y);
      t = oLeftArc + angle * r;
    } else {
      // Top-left corner: from -X (left) clockwise to -Y (up)
      float angle = atan(-d.y, -d.x);
      t = oTopArc + angle * r;
    }
  } else {
    if (abs(p.x) * hs.y <= abs(p.y) * hs.x) {
      if (p.y < 0.0) {
        // Top edge: left to right
        t = oTopEdge + clamp(p.x + b.x, 0.0, sideW);
      } else {
        // Bottom edge: right to left
        t = oBotEdge + clamp(b.x - p.x, 0.0, sideW);
      }
    } else {
      if (p.x > 0.0) {
        // Right edge: top to bottom
        t = oRightEdge + clamp(p.y + b.y, 0.0, sideH);
      } else {
        // Left edge: bottom to top
        t = oLeftEdge + clamp(b.y - p.y, 0.0, sideH);
      }
    }
  }

  return mod(t, max(totalPerim, 0.0001));
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
      // Compute perimeter parameter along the border using arc length
      float t = perimArcLength(vLocalPos, uHalfSize, uRadius);
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
