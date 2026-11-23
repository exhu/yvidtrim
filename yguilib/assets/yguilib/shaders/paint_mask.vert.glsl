/**
 * Vertex shader for gradient and pattern paint modulated by an alpha mask
 * (e.g. glyph bitmaps): (x, y) logic position and (u, v) mask coordinate.
 */
layout(location = 0) in vec2 aPosition;
layout(location = 1) in vec2 aMaskUv;
uniform vec2 uResolution;
out vec2 vPos;
out vec2 vMaskUv;

void main() {
  gl_Position = logicToClip(aPosition, uResolution);
  vPos = aPosition;
  vMaskUv = aMaskUv;
}
