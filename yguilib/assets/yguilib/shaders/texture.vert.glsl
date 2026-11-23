layout(location = 0) in vec2 aPosition;
layout(location = 1) in vec2 aTexCoord;
uniform vec2 uResolution;
out vec2 vTexCoord;

void main() {
  gl_Position = logicToClip(aPosition, uResolution);
  vTexCoord = aTexCoord;
}
