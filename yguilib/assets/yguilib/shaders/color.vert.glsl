layout(location = 0) in vec2 aPosition;
uniform vec2 uResolution;

void main() {
  gl_Position = logicToClip(aPosition, uResolution);
}
