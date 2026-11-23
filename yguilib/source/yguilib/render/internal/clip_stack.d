module yguilib.render.internal.clip_stack;

package(yguilib):

import glad2.gles2;
import std.array : Appender;
import yguilib.render.render_types : RectF, intersectRects;

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

  /// True when no clip rect is pushed.
  bool isEmpty() const {
    return stack[].length == 0;
  }

  /// True when both stacks use the same (allocated) buffer.
  bool sharesStorage(ref ClipStack o) {
    return stack[].ptr !is null && stack[].ptr is o.stack[].ptr;
  }

  /**
   * Re-sets the GL scissor from the top rect, or disables the scissor
   * when the stack is empty (after switching render targets).
   */
  void reapply(int pixelW, int pixelH, float scale) {
    const auto stackData = stack[];
    if (stackData.length == 0) {
      glDisable(GL_SCISSOR_TEST);
    } else {
      applyScissor(stackData[$ - 1], pixelW, pixelH, scale);
    }
  }

  static void applyScissor(
    in RectF rect,
    int pixelW,
    int pixelH,
    float scale
  ) {
    const int[4] box = scissorBox(rect, pixelW, pixelH, scale);
    glEnable(GL_SCISSOR_TEST);
    glScissor(box[0], box[1], box[2], box[3]);
  }

  /// Converts a logical clip rect into a GL scissor box
  /// `[x, y, w, h]` (bottom-left origin) in whole pixels.
  static int[4] scissorBox(
    in RectF rect,
    int pixelW,
    int pixelH,
    float scale
  ) nothrow @safe @nogc {
    import std.algorithm : max, min;
    import std.math : ceil, floor;

    float px = rect.x * scale;
    float py = rect.y * scale;
    float pw = rect.width * scale;
    float ph = rect.height * scale;

    float clampedX = max(0.0f, px);
    float clampedY = max(0.0f, py);
    float clampedRight = min(cast(float)pixelW, px + pw);
    float clampedBottom = min(cast(float)pixelH, py + ph);

    // Snap outward to whole pixels: floor the left/top edges and ceil the
    // right/bottom edges independently. Truncating origin and size
    // separately would pull the right/bottom edge inward by up to ~2 px
    // for fractional rects (e.g. cursor-positioned tooltips).
    const float left = min(floor(clampedX), cast(float)pixelW);
    const float top = min(floor(clampedY), cast(float)pixelH);
    const float right = max(left, ceil(clampedRight));
    const float bottom = max(top, ceil(clampedBottom));

    return [
      cast(int)left,
      cast(int)(pixelH - bottom),
      cast(int)(right - left),
      cast(int)(bottom - top),
    ];
  }

  private Appender!(RectF[]) stack;
}

unittest {
  // Fractional origin and size: right/bottom edges must not shrink.
  // x 10.7 + w 20.6 = right 31.3 -> scissor must cover [10, 32).
  int[4] box = ClipStack.scissorBox(RectF(10.7f, 5.6f, 20.6f, 9.7f),
    100, 50, 1.0f);
  assert(box[0] == 10 && box[2] == 22);
  // y 5.6 + h 9.7 = bottom 15.3 -> rows [5, 16), GL y = 50 - 16.
  assert(box[1] == 34 && box[3] == 11);

  // Integer rect is unchanged.
  box = ClipStack.scissorBox(RectF(10, 5, 20, 10), 100, 50, 1.0f);
  assert(box == [10, 35, 20, 10]);

  // HiDPI scale and clamping to the framebuffer.
  box = ClipStack.scissorBox(RectF(-5, 40, 80, 20), 100, 50, 1.5f);
  assert(box == [0, 0, 100, 0]);

  // Fully outside rect yields an empty box.
  box = ClipStack.scissorBox(RectF(200, 10, 10, 10), 100, 50, 1.0f);
  assert(box[2] == 0);
}
