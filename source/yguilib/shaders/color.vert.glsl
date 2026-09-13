#version 300 es

layout(location = 0) in vec2 aPosition;
uniform vec2 uResolution;

void main() {
  vec2 zeroToOne = aPosition / uResolution;
  vec2 zeroToTwo = zeroToOne * 2.0;
  vec2 clipSpace = vec2(zeroToTwo.x - 1.0, 1.0 - zeroToTwo.y);
  gl_Position = vec4(clipSpace, 0.0, 1.0);
}
