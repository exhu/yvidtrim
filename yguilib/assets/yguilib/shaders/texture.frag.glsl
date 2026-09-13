#version 300 es

precision mediump float;

uniform sampler2D uTexture;
uniform vec4 uColor;
in vec2 vTexCoord;
out vec4 fragColor;

void main() {
  vec4 texColor = texture(uTexture, vTexCoord);
  fragColor = texColor * uColor;
}
