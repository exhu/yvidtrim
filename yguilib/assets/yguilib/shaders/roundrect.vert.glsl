/**
 * Vertex shader for SDF rounded rectangle rendering.
 *
 * Vertex data layout: [worldX, worldY, localX, localY] per vertex
 * (4 floats/vertex, 6 vertices per quad).
 * `aPosition`: Screen/viewport coordinate in logical units.
 * `aLocalPos`: Local coordinate relative to rectangle center in logical units
 *              ranging in (-halfW..+halfW, -halfH..+halfH).
 */
layout(location = 0) in vec2 aPosition;
layout(location = 1) in vec2 aLocalPos;
uniform vec2 uResolution;
out vec2 vLocalPos;

void main() {
  gl_Position = logicToClip(aPosition, uResolution);
  vLocalPos = aLocalPos;
}
