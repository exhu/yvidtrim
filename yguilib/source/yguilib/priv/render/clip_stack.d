module yguilib.priv.render.clip_stack;

import glad2.gles2;
import std.algorithm : max, min;
import std.array : Appender;
import yguilib.render_types : RectF, intersectRects;

struct ClipStack {
  void push(
    RectF rect,
    float vw,
    float vh,
    int pixelW,
    int pixelH,
    float scale
  ) {
    const auto stackData = stack[];
    RectF active;
    if (stackData.length == 0) {
      active = RectF(0, 0, vw, vh);
    } else {
      active = stackData[$ - 1];
    }
    RectF clipped = intersectRects(active, rect);
    stack ~= clipped;
    applyScissor(clipped, pixelW, pixelH, scale);
  }

  void pop(int pixelW, int pixelH, float scale) {
    auto stackData = stack[];
    if (stackData.length == 0) {
      return;
    }
    stack.shrinkTo(stackData.length - 1);
    stackData = stack[];
    if (stackData.length == 0) {
      glDisable(GL_SCISSOR_TEST);
    } else {
      applyScissor(stackData[$ - 1], pixelW, pixelH, scale);
    }
  }

  void set(RectF rect, int pixelW, int pixelH, float scale) {
    stack.clear();
    stack ~= rect;
    applyScissor(rect, pixelW, pixelH, scale);
  }

  void reset() {
    stack.clear();
    glDisable(GL_SCISSOR_TEST);
  }

  void clear() {
    stack.clear();
  }

  static void applyScissor(
    in RectF rect,
    int pixelW,
    int pixelH,
    float scale
  ) {
    float px = rect.x * scale;
    float py = rect.y * scale;
    float pw = rect.width * scale;
    float ph = rect.height * scale;

    float clampedX = max(0.0f, px);
    float clampedY = max(0.0f, py);
    float clampedRight = min(cast(float)pixelW, px + pw);
    float clampedBottom = min(cast(float)pixelH, py + ph);

    float w = clampedRight - clampedX;
    float h = clampedBottom - clampedY;
    if (w < 0.0f) {
      w = 0.0f;
    }
    if (h < 0.0f) {
      h = 0.0f;
    }

    int glX = cast(int)clampedX;
    int glY = cast(int)(pixelH - (clampedY + h));
    int glW = cast(int)w;
    int glH = cast(int)h;

    glEnable(GL_SCISSOR_TEST);
    glScissor(glX, glY, glW, glH);
  }

  private Appender!(RectF[]) stack;
}
