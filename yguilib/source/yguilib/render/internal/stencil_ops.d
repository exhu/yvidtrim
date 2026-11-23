/**
 * Stencil, color mask and cull state for the Canvas stencil-then-cover
 * passes. Bit layout (see plans/canvas.md):
 * bit 7 is the clip mask (1 = inside the clip, valid while a clip is
 * active); bits 0..6 hold the fill winding, the evenOdd parity (bit 0) or
 * the stroke "drawn once" marker and are always 0 after a Canvas call.
 */
module yguilib.render.internal.stencil_ops;

package(yguilib):

import glad2.gles2;
import yguilib.render.canvas : FillRule;

/// Stencil bit 7: inside the current Canvas clip.
enum uint clipBit = 0x80;
/// Stencil bits 0..6: per-call winding / parity / marker.
enum uint lowBits = 0x7F;

/// Winding pass for nonZero: front faces increment, back faces decrement.
void beginWindingNonZero() {
  glEnable(GL_STENCIL_TEST);
  glDisable(GL_CULL_FACE);
  glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
  glStencilMask(lowBits);
  glStencilFunc(GL_ALWAYS, 0, 0xFF);
  glStencilOpSeparate(GL_FRONT, GL_KEEP, GL_KEEP, GL_INCR_WRAP);
  glStencilOpSeparate(GL_BACK, GL_KEEP, GL_KEEP, GL_DECR_WRAP);
}

/// Winding pass for evenOdd: every covering triangle flips bit 0.
void beginWindingEvenOdd() {
  glEnable(GL_STENCIL_TEST);
  glDisable(GL_CULL_FACE);
  glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
  glStencilMask(0x01);
  glStencilFunc(GL_ALWAYS, 0, 0xFF);
  glStencilOp(GL_KEEP, GL_KEEP, GL_INVERT);
}

/// Winding pass for `rule`.
void beginWinding(FillRule rule) {
  final switch (rule) {
  case FillRule.nonZero:
    beginWindingNonZero();
    break;
  case FillRule.evenOdd:
    beginWindingEvenOdd();
    break;
  }
}

/**
 * Cover pass: draws color where the winding test (and the clip bit when
 * `clipActive`) passes; zeroes the low bits wherever the cover touches.
 */
void beginCover(FillRule rule, bool clipActive) {
  glEnable(GL_STENCIL_TEST);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  glStencilMask(lowBits);
  glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO);
  final switch (rule) {
  case FillRule.nonZero:
    // passes when ref < (stencil & mask): low bits non-zero
    if (clipActive) {
      glStencilFunc(GL_LESS, clipBit, 0xFF);
    } else {
      glStencilFunc(GL_LESS, 0, lowBits);
    }
    break;
  case FillRule.evenOdd:
    if (clipActive) {
      glStencilFunc(GL_EQUAL, clipBit | 0x01, clipBit | 0x01);
    } else {
      glStencilFunc(GL_EQUAL, 0x01, 0x01);
    }
    break;
  }
}

/// Stroke pass: each pixel is drawn once, then marked in the low bits.
void beginStrokeOnce(bool clipActive) {
  glEnable(GL_STENCIL_TEST);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  glStencilMask(lowBits);
  if (clipActive) {
    glStencilFunc(GL_EQUAL, clipBit, 0xFF);
  } else {
    glStencilFunc(GL_EQUAL, 0, lowBits);
  }
  glStencilOp(GL_KEEP, GL_KEEP, GL_INCR);
}

/**
 * Plain draw limited to the clip bit when `clipActive` (stencil writes
 * off); without a clip the stencil test is disabled.
 */
void beginClipTest(bool clipActive) {
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  if (!clipActive) {
    glDisable(GL_STENCIL_TEST);
    return;
  }
  glEnable(GL_STENCIL_TEST);
  glStencilMask(0);
  glStencilFunc(GL_EQUAL, clipBit, clipBit);
  glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
}

/// Zeroes the low bits under the drawn geometry without drawing color.
void beginResetLow() {
  glEnable(GL_STENCIL_TEST);
  glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
  glStencilMask(lowBits);
  glStencilFunc(GL_ALWAYS, 0, 0xFF);
  glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO);
}

/**
 * Clip intersection over the full viewport: clears bit 7 where the
 * point is outside the path just written to the low bits by the winding
 * pass for `rule`.
 */
void beginClipIntersect(FillRule rule) {
  glEnable(GL_STENCIL_TEST);
  glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
  glStencilMask(clipBit);
  glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);
  final switch (rule) {
  case FillRule.nonZero:
    glStencilFunc(GL_EQUAL, 0, lowBits);
    break;
  case FillRule.evenOdd:
    glStencilFunc(GL_EQUAL, 0, 0x01);
    break;
  }
}

/// Restores the default state: no stencil test, all writes enabled.
void endStencil() {
  glDisable(GL_STENCIL_TEST);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  glStencilMask(0xFF);
  glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
}
