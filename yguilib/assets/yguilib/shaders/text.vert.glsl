layout(location = 0) in vec2 aPosition;
layout(location = 1) in vec2 aTexCoord;
layout(location = 2) in vec4 aColor;
uniform vec2 uResolution;
out vec2 vTexCoord;
out vec4 vColor;

void main() {
  gl_Position = logicToClip(aPosition, uResolution);
  vTexCoord = aTexCoord;
  vColor = aColor;
}
