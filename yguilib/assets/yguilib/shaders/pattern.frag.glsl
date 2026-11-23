#version 300 es

precision highp float;

uniform sampler2D uTexture;
uniform mat3 uInvXf;
uniform vec4 uTint;
// bit 0: repeat X, bit 1: repeat Y (0..3)
uniform int uRepeat;
// 0 straight alpha, 1 premultiplied texture, 2 alpha mask (white * alpha)
uniform int uMode;
// non-zero flips uv.y for GL bottom-up render target textures
uniform int uBottomUp;

in vec2 vPos;
#ifdef MASK
// alpha mask variant: output is scaled by the mask alpha
uniform sampler2D uMask;
in vec2 vMaskUv;
#endif
out vec4 fragColor;

void main() {
  vec2 uv = (uInvXf * vec3(vPos, 1.0)).xy;
  bool outX = (uRepeat & 1) == 0 && (uv.x < 0.0 || uv.x >= 1.0);
  bool outY = (uRepeat & 2) == 0 && (uv.y < 0.0 || uv.y >= 1.0);
  if (outX || outY) {
    fragColor = vec4(0.0);
    return;
  }
  if (uBottomUp != 0) {
    uv.y = 1.0 - uv.y;
  }
  vec4 texColor = texture(uTexture, uv);
  if (uMode == 1) {
    fragColor = texColor * vec4(uTint.rgb * uTint.a, uTint.a);
  } else if (uMode == 2) {
    fragColor = vec4(1.0, 1.0, 1.0, texColor.a * uTint.a);
  } else {
    fragColor = texColor * uTint;
  }
#ifdef MASK
  float m = texture(uMask, vMaskUv).a;
  if (uMode == 1) {
    fragColor *= m;
  } else {
    fragColor.a *= m;
  }
#endif
}
