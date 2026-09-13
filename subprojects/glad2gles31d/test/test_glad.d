module test_glad;
import glad2.gles2;
import glad2.khrplatform;

void main() {
  assert(GL_VERTEX_SHADER == 0x8B31);
  assert(GL_FRAGMENT_SHADER == 0x8B30);
  assert(GL_NO_ERROR == 0);
}
