#version 300 es

// Separable 1D Gaussian blur of the alpha channel (radius 3 sigma), using
// linear filtering to fetch two texels per tap. Outputs white with the
// blurred alpha (the composite tints it with the shadow color).

precision highp float;

uniform sampler2D uTexture;
// texture coordinate step of one pixel along the blur axis
uniform vec2 uDirection;
// standard deviation in pixels (> 0)
uniform float uSigma;
// taps are clamped to these texel centers (the pass region)
uniform vec2 uUvMin;
uniform vec2 uUvMax;
in vec2 vTexCoord;
out vec4 fragColor;

float tap(vec2 uv) {
  return texture(uTexture, clamp(uv, uUvMin, uUvMax)).a;
}

void main() {
  int radius = int(ceil(3.0 * uSigma));
  float k = -0.5 / (uSigma * uSigma);
  float sum = tap(vTexCoord);
  float wsum = 1.0;
  for (int i = 1; i <= radius; i += 2) {
    float fi = float(i);
    float w0 = exp(k * fi * fi);
    float w1 = i + 1 <= radius ? exp(k * (fi + 1.0) * (fi + 1.0)) : 0.0;
    float w = w0 + w1;
    vec2 d = uDirection * ((fi * w0 + (fi + 1.0) * w1) / w);
    sum += w * (tap(vTexCoord + d) + tap(vTexCoord - d));
    wsum += 2.0 * w;
  }
  fragColor = vec4(1.0, 1.0, 1.0, sum / wsum);
}
