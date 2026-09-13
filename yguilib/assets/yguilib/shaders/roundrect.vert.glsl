/**
 * Vertex shader for SDF rounded rectangle rendering.
 *
 * Vertex data layout: [worldX, worldY, localX, localY] per vertex (4 floats/vertex, 6 vertices per quad).
 * `aPosition`: Screen/viewport coordinate in logical units.
 * `aLocalPos`: Local coordinate relative to rectangle center in logical units
 *              ranging in (-halfW..+halfW, -halfH..+halfH).
 */
#version 300 es

layout(location = 0) in vec2 aPosition;
layout(location = 1) in vec2 aLocalPos;
uniform vec2 uResolution;
out vec2 vLocalPos;

void main() {
  vec2 zeroToOne = aPosition / uResolution;
  vec2 zeroToTwo = zeroToOne * 2.0;
  vec2 clipSpace = vec2(zeroToTwo.x - 1.0, 1.0 - zeroToTwo.y);
  gl_Position = vec4(clipSpace, 0.0, 1.0);
  vLocalPos = aLocalPos;
}
