/**
 * Renderer scissor clip stack (`Renderer.pushClipRect`): nested logic
 * rects, each intersected with its parent, applied as the GL scissor box
 * snapped outward to whole pixels. The stack owns the scissor: the test
 * is enabled exactly while it is not empty, and `appliedBox()` tracks
 * the box without GL queries.
 */
module yguilib.render.internal.clip_stack;

package(yguilib):

import glad2.gles2;
import std.array : Appender;
import yguilib.render.render_types : RectF, intersectRects;

struct ClipStack {
  /**
   * Pushes `rect` (logic units) intersected with the top rect, or with
   * the viewport (`pixelW` x `pixelH` pixels at `scale` pixels per logic
   * unit) when empty, and applies it as the scissor.
   */
  void push(RectF rect, int pixelW, int pixelH, float scale) {
    const bool wasEnabled = !isEmpty();
    const RectF clipped = nextPushedRect(rect, pixelW, pixelH, scale);
    stack ~= clipped;
    applyScissorIfChanged(clipped, pixelW, pixelH, scale, wasEnabled);
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
      applyScissorIfChanged(stackData[$ - 1], pixelW, pixelH, scale, true);
    }
  }

  void set(RectF rect, int pixelW, int pixelH, float scale) {
    const bool wasEnabled = !isEmpty();
    stack.clear();
    stack ~= rect;
    applyScissorIfChanged(rect, pixelW, pixelH, scale, wasEnabled);
  }

  void reset() {
    if (isEmpty()) {
      return;
    }
    stack.clear();
    glDisable(GL_SCISSOR_TEST);
  }

  void clear() {
    stack.clear();
  }

  /// True when `push(rect, ...)` would enable or change the GL scissor box.
  bool wouldPushChangeScissor(
    in RectF rect,
    int pixelW,
    int pixelH,
    float scale
  ) const {
    const RectF clipped = nextPushedRect(rect, pixelW, pixelH, scale);
    const int[4] box = scissorBox(clipped, pixelW, pixelH, scale);
    return isEmpty() || box != fAppliedBox;
  }

  /// True when `pop(...)` would disable or change the GL scissor box.
  bool wouldPopChangeScissor(int pixelW, int pixelH, float scale) const {
    const auto stackData = stack[];
    if (stackData.length == 0) {
      return false;
    }
    if (stackData.length == 1) {
      return true;
    }
    const int[4] box = scissorBox(stackData[$ - 2], pixelW, pixelH, scale);
    return box != fAppliedBox;
  }

  /// True when `set(rect, ...)` would enable or change the GL scissor box.
  bool wouldSetChangeScissor(
    in RectF rect,
    int pixelW,
    int pixelH,
    float scale
  ) const {
    const int[4] box = scissorBox(rect, pixelW, pixelH, scale);
    return isEmpty() || box != fAppliedBox;
  }

  /// True when `reset()` would disable an active GL scissor test.
  bool wouldResetChangeScissor() const {
    return !isEmpty();
  }

  /// True when no clip rect is pushed.
  bool isEmpty() const {
    return stack[].length == 0;
  }

  /// Innermost clip rect in logic units; the stack must not be empty.
  RectF top() const {
    assert(!isEmpty());
    return stack[][$ - 1];
  }

  /**
   * GL scissor box (`[x, y, w, h]`, see `scissorBox`) last set by this
   * stack; the GL scissor test is enabled exactly while the stack is not
   * empty (as long as the stack owns the scissor, see `Renderer`).
   */
  int[4] appliedBox() const {
    return fAppliedBox;
  }

  /**
   * `glClear(mask)` limited to the GL box `box` (`[x, y, w, h]`, see
   * `scissorBox`) intersected with the applied scissor when the stack is
   * not empty; the scissor state is restored afterwards. An empty
   * intersection clears nothing.
   */
  void clearBox(in int[4] box, GLbitfield mask) {
    import std.algorithm : max, min;

    int x0 = box[0];
    int y0 = box[1];
    int x1 = box[0] + box[2];
    int y1 = box[1] + box[3];
    const bool clipped = !isEmpty();
    if (clipped) {
      const int[4] a = fAppliedBox;
      x0 = max(x0, a[0]);
      y0 = max(y0, a[1]);
      x1 = min(x1, a[0] + a[2]);
      y1 = min(y1, a[1] + a[3]);
    }
    if (x1 <= x0 || y1 <= y0) {
      return;
    }
    if (!clipped) {
      glEnable(GL_SCISSOR_TEST);
    }
    glScissor(x0, y0, x1 - x0, y1 - y0);
    glClear(mask);
    if (clipped) {
      glScissor(fAppliedBox[0], fAppliedBox[1], fAppliedBox[2],
        fAppliedBox[3]);
    } else {
      glDisable(GL_SCISSOR_TEST);
    }
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

  void applyScissor(
    in RectF rect,
    int pixelW,
    int pixelH,
    float scale
  ) {
    const int[4] box = scissorBox(rect, pixelW, pixelH, scale);
    glEnable(GL_SCISSOR_TEST);
    glScissor(box[0], box[1], box[2], box[3]);
    fAppliedBox = box;
  }

  /// Logic units of `pixels` at `scale` (as `Renderer.logicWidth`).
  static float logicFromPixels(int pixels, float scale)
    nothrow @safe @nogc pure {
    return scale > 0.0f ? cast(float)pixels / scale : cast(float)pixels;
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
    import std.math : ceil, floor, isFinite;

    if (!isFinite(rect.x) || !isFinite(rect.y)
        || !isFinite(rect.width) || !isFinite(rect.height)
        || !isFinite(scale)) {
      return [0, 0, 0, 0];
    }

    const float px = rect.x * scale;
    const float py = rect.y * scale;
    const float pw = rect.width * scale;
    const float ph = rect.height * scale;

    const float clampedX = max(0.0f, px);
    const float clampedY = max(0.0f, py);
    const float clampedRight = min(cast(float)pixelW, px + pw);
    const float clampedBottom = min(cast(float)pixelH, py + ph);

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

private:
  RectF nextPushedRect(
    in RectF rect,
    int pixelW,
    int pixelH,
    float scale
  ) const {
    const auto stackData = stack[];
    const RectF active = stackData.length == 0
      ? RectF(0, 0, logicFromPixels(pixelW, scale),
        logicFromPixels(pixelH, scale))
      : stackData[$ - 1];
    return intersectRects(active, rect);
  }

  void applyScissorIfChanged(
    in RectF rect,
    int pixelW,
    int pixelH,
    float scale,
    bool wasEnabled
  ) {
    const int[4] box = scissorBox(rect, pixelW, pixelH, scale);
    if (wasEnabled && box == fAppliedBox) {
      return;
    }
    glEnable(GL_SCISSOR_TEST);
    glScissor(box[0], box[1], box[2], box[3]);
    fAppliedBox = box;
  }

  Appender!(RectF[]) stack;
  int[4] fAppliedBox;
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

// Verifies would*ChangeScissor queries and redundant GL call skipping.
unittest {
  import yguilib.render.internal.gl_test_util : GlTestWindow, testHeight,
    testWidth;

  auto w = GlTestWindow("test_clip_stack_queries");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  ClipStack cs;
  const int pw = testWidth;
  const int ph = testHeight;
  const float scale = 1.0f;

  assert(!cs.wouldPopChangeScissor(pw, ph, scale));
  assert(!cs.wouldResetChangeScissor());
  assert(cs.wouldPushChangeScissor(RectF(10, 10, 100, 80), pw, ph, scale));
  assert(cs.wouldSetChangeScissor(RectF(10, 10, 100, 80), pw, ph, scale));

  cs.push(RectF(10, 10, 100, 80), pw, ph, scale);
  assert(!cs.isEmpty());
  assert(cs.wouldResetChangeScissor());
  assert(cs.wouldPopChangeScissor(pw, ph, scale));

  // Identical or looser nested clip keeps the same intersected scissor box.
  assert(!cs.wouldPushChangeScissor(RectF(0, 0, 200, 200), pw, ph, scale));
  assert(!cs.wouldSetChangeScissor(RectF(10, 10, 100, 80), pw, ph, scale));
  assert(cs.wouldPushChangeScissor(RectF(20, 20, 50, 40), pw, ph, scale));
  assert(cs.wouldSetChangeScissor(RectF(20, 20, 50, 40), pw, ph, scale));

  // Push identical intersected box: pop does not change scissor.
  cs.push(RectF(0, 0, 200, 200), pw, ph, scale);
  assert(!cs.wouldPopChangeScissor(pw, ph, scale));
  assert(cs.appliedBox() == ClipStack.scissorBox(
    RectF(10, 10, 100, 80), pw, ph, scale
  ));

  // Push narrower box: pop does change scissor back to parent.
  cs.push(RectF(20, 20, 50, 40), pw, ph, scale);
  assert(cs.wouldPopChangeScissor(pw, ph, scale));
  assert(cs.appliedBox() == ClipStack.scissorBox(
    RectF(20, 20, 50, 40), pw, ph, scale
  ));

  cs.pop(pw, ph, scale);
  assert(cs.appliedBox() == ClipStack.scissorBox(
    RectF(10, 10, 100, 80), pw, ph, scale
  ));
  cs.pop(pw, ph, scale);
  assert(cs.appliedBox() == ClipStack.scissorBox(
    RectF(10, 10, 100, 80), pw, ph, scale
  ));
  assert(cs.wouldPopChangeScissor(pw, ph, scale));
  cs.pop(pw, ph, scale);
  assert(cs.isEmpty());
  assert(!glIsEnabled(GL_SCISSOR_TEST));

  // Pushing the same rect again after becoming empty must re-enable scissor.
  assert(cs.wouldPushChangeScissor(RectF(10, 10, 100, 80), pw, ph, scale));
  assert(cs.wouldSetChangeScissor(RectF(10, 10, 100, 80), pw, ph, scale));
  cs.set(RectF(10, 10, 100, 80), pw, ph, scale);
  assert(glIsEnabled(GL_SCISSOR_TEST));
  assert(!cs.wouldSetChangeScissor(RectF(10, 10, 100, 80), pw, ph, scale));
  cs.set(RectF(10, 10, 100, 80), pw, ph, scale);
  assert(glIsEnabled(GL_SCISSOR_TEST));
  assert(cs.wouldResetChangeScissor());
  cs.reset();
  assert(!glIsEnabled(GL_SCISSOR_TEST));
  assert(!cs.wouldResetChangeScissor());
}
