/**
 * Vertex shader for gradient paint: passes the logic position through so
 * the fragment shader can evaluate the gradient per pixel.
 */
layout(location = 0) in vec2 aPosition;
uniform vec2 uResolution;
out vec2 vPos;

void main() {
  gl_Position = logicToClip(aPosition, uResolution);
  vPos = aPosition;
}
