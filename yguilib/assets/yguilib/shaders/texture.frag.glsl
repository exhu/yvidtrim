#version 300 es

precision highp float;

uniform sampler2D uTexture;
uniform vec4 uColor;
// 0 straight alpha, 1 premultiplied texture, 2 alpha mask (white * alpha)
uniform int uMode;
in vec2 vTexCoord;
out vec4 fragColor;

void main() {
  vec4 texColor = texture(uTexture, vTexCoord);
  if (uMode == 1) {
    fragColor = texColor * vec4(uColor.rgb * uColor.a, uColor.a);
  } else if (uMode == 2) {
    fragColor = vec4(1.0, 1.0, 1.0, texColor.a * uColor.a);
  } else {
    fragColor = texColor * uColor;
  }
}
