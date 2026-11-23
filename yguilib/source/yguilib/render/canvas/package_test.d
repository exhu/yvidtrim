/** Canvas GL tests: fills, strokes, clips, gradients, shadows, images,
    patterns and text, drawn in a hidden `GlTestWindow`.
*/
module yguilib.render.canvas.package_test;

version (unittest):

import glad2.gles2;
import yguilib.render.canvas;
import yguilib.render.canvas.path2d : Path2d;
import yguilib.render.canvas.types;
import yguilib.render.font : defaultFontPtSize;
import yguilib.render.internal.gl_test_util;
import yguilib.render.render_types;
import yguilib.render.texture : Texture;

// Canvas GL rendering (stencil-then-cover, transforms, strokes, clips)
unittest {
  import std.math : PI, cos, sin;

  auto w = GlTestWindow("test_canvas");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto r = w.renderer();
  auto cv = w.canvas();
  assert(cv !is null);

  GLint stencilBits = 0;
  glGetIntegerv(GL_STENCIL_BITS, &stencilBits);
  assert(stencilBits >= 8);

  const black = ColorF(0, 0, 0, 1);
  const red = ColorF(1, 0, 0, 1);
  const green = FillStyle.solid(ColorF(0, 1, 0, 1));
  const blue = FillStyle.solid(ColorF(0, 0, 1, 1));
  auto full = rectPath(RectF(0, 0, 320, 240));

  // 1. rect fill
  r.clearFrame(red);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(20, 20, 60, 40)));
  assert(isRgb(50, 40, 0, 255, 0));
  assert(isRgb(150, 150, 255, 0, 0));

  // 2. self-intersecting star: nonZero fills the center, evenOdd not
  auto star = new Path2d();
  foreach (k; 0 .. 5) {
    const float a = cast(float)(-PI / 2 + k * 4 * PI / 5);
    const PointF pt = PointF(160 + 80 * cos(a), 120 + 80 * sin(a));
    if (k == 0) {
      star.moveTo(pt);
    } else {
      star.lineTo(pt);
    }
  }
  star.closePath();
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.fill(star);
  assert(isRgb(160, 120, 0, 255, 0));
  assert(isRgb(160, 60, 0, 255, 0));
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.fillRule(FillRule.evenOdd);
  cv.fill(star);
  assert(isRgb(160, 120, 0, 0, 0));
  assert(isRgb(160, 60, 0, 255, 0));
  cv.fillRule(FillRule.nonZero);

  // 3. transforms and save/restore
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.save();
  cv.translate(PointF(100, 50));
  cv.rotate(cast(float)(PI / 4));
  cv.fill(rectPath(RectF(-10, -10, 20, 20)));
  cv.restore();
  assert(cv.transform().isIdentity());
  assert(isRgb(100, 50, 0, 255, 0));
  assert(isRgb(112, 50, 0, 255, 0)); // inside the rotated diamond only
  assert(isRgb(108, 42, 0, 0, 0)); // unrotated corner area
  cv.save();
  cv.scale(PointF(2, 3));
  cv.fill(rectPath(RectF(10, 10, 10, 10))); // -> (20, 30, 20, 30)
  assert(!cv.transform().isIdentity());
  cv.restore();
  assert(isRgb(30, 45, 0, 255, 0));
  assert(isRgb(15, 45, 0, 0, 0));
  assert(isRgb(30, 65, 0, 0, 0));
  cv.restore(); // empty stack: no-op
  cv.fill(rectPath(RectF(200, 200, 10, 10)));
  assert(isRgb(205, 205, 0, 255, 0));

  // 4. self-overlapping stroke is painted once
  r.clearFrame(black);
  auto cross = new Path2d();
  cross.moveTo(PointF(50, 50));
  cross.lineTo(PointF(200, 200));
  cross.lineTo(PointF(200, 50));
  cross.lineTo(PointF(50, 200));
  cv.strokeStyle(FillStyle.solid(ColorF(1, 1, 1, 0.5f)));
  cv.lineWidth(10);
  cv.stroke(cross);
  const ov = px(125, 125);
  assert(ov[0] >= 125 && ov[0] <= 131);
  const single = px(80, 80);
  assert(single[0] >= 125 && single[0] <= 131);

  // 5. dashes: [20, 20] along y = 100 from x = 20
  r.clearFrame(black);
  cv.strokeStyle(FillStyle.solid(ColorF(1, 1, 1, 1)));
  cv.lineWidth(6);
  cv.lineDash(LineDash.fromSegments([20.0f, 20]));
  assert(cv.lineDash().segments == [20.0f, 20]);
  auto line = new Path2d();
  line.moveTo(PointF(20, 100));
  line.lineTo(PointF(220, 100));
  cv.stroke(line);
  assert(isRgb(30, 100, 255, 255, 255));
  assert(isRgb(50, 100, 0, 0, 0));
  assert(isRgb(70, 100, 255, 255, 255));
  assert(isRgb(30, 110, 0, 0, 0));
  cv.lineDash(LineDash.init);
  cv.lineWidth(1);

  // 6. circle clip; restore() removes it
  r.clearFrame(black);
  auto circle = new Path2d();
  circle.arc(PointF(160, 120), 60, 0, cast(float)(2 * PI), false);
  cv.fillStyle(blue);
  cv.save();
  cv.clip(circle);
  cv.fill(full);
  assert(isRgb(160, 120, 0, 0, 255));
  assert(isRgb(5, 5, 0, 0, 0));
  assert(isRgb(315, 235, 0, 0, 0));
  assert(isRgb(160, 50, 0, 0, 0));
  cv.restore();
  cv.fillStyle(green);
  cv.fill(full);
  assert(isRgb(5, 5, 0, 255, 0));
  assert(isRgb(160, 120, 0, 255, 0));

  // 7. nested clips intersect; restoring one level keeps the outer clip
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.save();
  cv.clip(rectPath(RectF(20, 20, 100, 100)));
  cv.save();
  cv.clip(rectPath(RectF(70, 70, 100, 100)));
  cv.fill(full);
  assert(isRgb(90, 90, 0, 255, 0));
  assert(isRgb(40, 40, 0, 0, 0));
  assert(isRgb(150, 150, 0, 0, 0));
  cv.restore();
  cv.fillStyle(blue);
  cv.fill(full);
  assert(isRgb(40, 40, 0, 0, 255));
  assert(isRgb(150, 150, 0, 0, 0));
  // 8. Renderer draws ignore the Canvas clip
  r.drawFillRect(RectF(0, 0, 320, 240), ColorF(1, 0, 0, 1));
  assert(isRgb(150, 150, 255, 0, 0));
  assert(isRgb(5, 5, 255, 0, 0));
  cv.restore();

  // evenOdd clip with the star excludes its center
  r.clearFrame(black);
  cv.save();
  cv.clipFillRule(FillRule.evenOdd);
  cv.clip(star);
  cv.fillStyle(green);
  cv.fill(full);
  assert(isRgb(160, 120, 0, 0, 0));
  assert(isRgb(160, 60, 0, 255, 0));
  assert(isRgb(5, 5, 0, 0, 0));
  cv.restore();
  assert(cv.clipFillRule() == FillRule.nonZero);

  // 9. Renderer scissor limits Canvas fills
  r.clearFrame(black);
  cv.fillStyle(green);
  r.pushClipRect(RectF(50, 50, 50, 50));
  cv.fill(full);
  r.popClipRect();
  assert(isRgb(60, 60, 0, 255, 0));
  assert(isRgb(10, 10, 0, 0, 0));
  assert(isRgb(150, 150, 0, 0, 0));

  // 10. clearRect overwrites with transparent black
  r.clearFrame(ColorF(1, 1, 1, 1));
  cv.clearRect(RectF(10, 10, 50, 50));
  assert(isRgb(30, 30, 0, 0, 0));
  assert(isRgb(100, 100, 255, 255, 255));
  // and the next Renderer draw blends again
  r.drawFillRect(RectF(0, 0, 320, 240), ColorF(1, 1, 1, 0.5f));
  const half = px(100, 100);
  assert(half[0] == 255);

  // clearFrame resets the Canvas state
  cv.save();
  cv.translate(PointF(5, 5));
  cv.clip(rectPath(RectF(0, 0, 1, 1)));
  r.clearFrame(black);
  assert(cv.transform().isIdentity());
  assert(cv.fillStyle().color == ColorF(0, 0, 0, 1));
  cv.fillStyle(green);
  cv.fill(full);
  assert(isRgb(100, 100, 0, 255, 0));

  assert(glGetError() == GL_NO_ERROR);
}

// Canvas gradients (linear, multi-stop, radial, transformed, stroke)
unittest {
  auto w = GlTestWindow("test_canvas_gradients");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto r = w.renderer();
  auto cv = w.canvas();

  const black = ColorF(0, 0, 0, 1);
  const red = ColorF(1, 0, 0, 1);
  const green = ColorF(0, 1, 0, 1);
  const blue = ColorF(0, 0, 1, 1);

  LinearGradient rb;
  rb.p0 = PointF(0, 0);
  rb.p1 = PointF(200, 0);
  rb.addColorStop(0, red).addColorStop(1, blue);

  // 1. linear red -> blue across a 200-wide rect
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromLinear(rb));
  cv.fill(rectPath(RectF(0, 0, 200, 50)));
  assert(near(10, 25, 242, 0, 13, 6));
  assert(near(190, 25, 13, 0, 242, 6));
  assert(near(100, 25, 128, 0, 128, 4));
  assert(near(250, 25, 0, 0, 0, 0)); // outside the rect

  // 2. three stops: the middle stop's color shows at offset 0.5
  LinearGradient rgb;
  rgb.p0 = PointF(0, 0);
  rgb.p1 = PointF(200, 0);
  rgb.addColorStop(0, red).addColorStop(0.5f, green).addColorStop(1, blue);
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromLinear(rgb));
  cv.fill(rectPath(RectF(0, 0, 200, 50)));
  assert(near(100, 25, 0, 255, 0, 3));
  assert(near(50, 25, 128, 128, 0, 4));

  // degenerate linear gradient (p0 == p1) draws nothing
  LinearGradient flat;
  flat.addColorStop(0, red);
  cv.fillStyle(FillStyle.fromLinear(flat));
  cv.fill(rectPath(RectF(0, 0, 200, 50)));
  assert(near(100, 25, 0, 255, 0, 3));

  // 3. radial: center is the first stop, near r1 the last, padded outside
  RadialGradient rad;
  rad.c0 = PointF(160, 120);
  rad.c1 = PointF(160, 120);
  rad.r0 = 0;
  rad.r1 = 50;
  rad.addColorStop(0, red).addColorStop(1, blue);
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromRadial(rad));
  cv.fill(rectPath(RectF(0, 0, 320, 240)));
  assert(near(160, 120, 255, 0, 0, 6));
  assert(near(205, 120, 25, 0, 230, 8));
  assert(near(160, 165, 25, 0, 230, 8));
  assert(near(240, 120, 0, 0, 255, 0));
  assert(near(5, 5, 0, 0, 255, 0));

  // 4. gradient follows the transform at the time of the fill
  r.clearFrame(black);
  cv.save();
  cv.translate(PointF(100, 0));
  cv.fillStyle(FillStyle.fromLinear(rb));
  cv.fill(rectPath(RectF(0, 0, 200, 50)));
  cv.restore();
  assert(near(110, 25, 242, 0, 13, 6));
  assert(near(290, 25, 13, 0, 242, 6));
  assert(near(200, 25, 128, 0, 128, 4));
  assert(near(50, 25, 0, 0, 0, 0));

  // 5. gradient stroke
  LinearGradient sg;
  sg.p0 = PointF(20, 0);
  sg.p1 = PointF(220, 0);
  sg.addColorStop(0, red).addColorStop(1, blue);
  r.clearFrame(black);
  cv.strokeStyle(FillStyle.fromLinear(sg));
  cv.lineWidth(10);
  auto line = new Path2d();
  line.moveTo(PointF(20, 150));
  line.lineTo(PointF(220, 150));
  cv.stroke(line);
  assert(near(30, 150, 242, 0, 13, 6));
  assert(near(210, 150, 13, 0, 242, 6));
  assert(near(120, 150, 128, 0, 128, 4));
  assert(near(120, 170, 0, 0, 0, 0));

  assert(glGetError() == GL_NO_ERROR);
}

// Canvas shadows (offscreen mask, blur, clip, scissor and state restore)
unittest {
  auto w = GlTestWindow("test_canvas_shadows");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto r = w.renderer();
  auto cv = w.canvas();

  const black = ColorF(0, 0, 0, 1);
  const green = FillStyle.solid(ColorF(0, 1, 0, 1));
  // right angle at the top-left: catches flipped shadow textures
  auto tri = new Path2d();
  tri.moveTo(PointF(50, 50));
  tri.lineTo(PointF(110, 50));
  tri.lineTo(PointF(50, 90));
  tri.closePath();

  // 1. invisible shadow (alpha 0) takes no FBO path, same pixels
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.fill(tri);
  ubyte[] plain = new ubyte[320 * 240 * 4];
  glReadPixels(0, 0, 320, 240, GL_RGBA, GL_UNSIGNED_BYTE, plain.ptr);
  Shadow hidden;
  hidden.offset = PointF(10, 10);
  hidden.blur = 4;
  cv.shadow(hidden);
  assert(!cv.shadow().isVisible());
  r.clearFrame(black); // resets the shadow too
  assert(cv.shadow().blur == 0);
  cv.shadow(hidden);
  cv.fillStyle(green);
  cv.fill(tri);
  ubyte[] same = new ubyte[320 * 240 * 4];
  glReadPixels(0, 0, 320, 240, GL_RGBA, GL_UNSIGNED_BYTE, same.ptr);
  assert(plain == same);
  assert(r.offscreenTargetRef(0).fbo == 0);

  // 2. hard shadow (blur 0) at offset (10, 10) under the shape
  Shadow hard;
  hard.offset = PointF(10, 10);
  hard.color = ColorF(1, 0, 0, 1);
  r.clearFrame(black);
  cv.save();
  cv.shadow(hard);
  assert(cv.shadow().isVisible());
  cv.fillStyle(green);
  cv.fill(tri);
  cv.restore();
  assert(!cv.shadow().isVisible());
  assert(r.offscreenTargetRef(0).fbo != 0);
  assert(isRgb(55, 55, 0, 255, 0)); // shape over the shadow
  assert(isRgb(65, 65, 0, 255, 0));
  assert(isRgb(115, 62, 255, 0, 0)); // shadow outside the shape
  assert(isRgb(62, 98, 255, 0, 0));
  assert(isRgb(115, 95, 0, 0, 0));
  assert(isRgb(45, 45, 0, 0, 0));
  // 2b. shadow alpha = shadow color alpha * paint alpha
  bool near(int v, int expected) {
    return v >= expected - 3 && v <= expected + 3;
  }

  r.clearFrame(black);
  cv.shadow(hard);
  cv.fillStyle(FillStyle.solid(ColorF(0, 1, 0, 0.5f)));
  cv.fill(tri);
  // shadow only: red at 0.5 over black
  auto halfShadow = px(115, 62);
  assert(near(halfShadow[0], 128) && halfShadow[1] == 0);
  // overlap: 0.5 green over the 0.5 red shadow
  auto overlap = px(65, 65);
  assert(near(overlap[0], 64) && near(overlap[1], 128));
  // gradient paint fading to transparent: the shadow fades the same way
  r.clearFrame(black);
  cv.shadow(hard);
  LinearGradient fade;
  fade.p0 = PointF(100, 0);
  fade.p1 = PointF(200, 0);
  fade.addColorStop(0, ColorF(0, 1, 0, 1));
  fade.addColorStop(1, ColorF(0, 1, 0, 0));
  cv.fillStyle(FillStyle.fromLinear(fade));
  cv.fill(rectPath(RectF(100, 100, 100, 40)));
  // below the shape (y 140..150) only the shadow shows
  const sLeft = px(112, 145)[0];
  const sMid = px(160, 145)[0];
  const sRight = px(205, 145)[0];
  assert(sLeft > 200 && near(sMid, 128) && sRight < 20);
  cv.shadow(Shadow.init);

  // invalid shadows are ignored
  Shadow bad = hard;
  bad.blur = -1;
  cv.shadow(bad);
  assert(!cv.shadow().isVisible());

  // 3. blur 8 (sigma 4 px): partial alpha falling off outward
  Shadow soft;
  soft.blur = 8;
  soft.color = ColorF(1, 0, 0, 1);
  r.clearFrame(black);
  cv.shadow(soft);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(100, 80, 80, 60)));
  const edge = px(181, 110);
  assert(edge[0] > 0 && edge[0] < 255 && edge[1] == 0);
  foreach (x; 181 .. 196) {
    assert(px(x, 110)[0] >= px(x + 1, 110)[0]);
  }
  assert(px(181, 110)[0] > px(186, 110)[0]);
  assert(px(196, 110)[0] <= 2);
  assert(isRgb(178, 110, 0, 255, 0));

  // 4. shadow on a stroke
  r.clearFrame(black);
  cv.shadow(hard);
  cv.strokeStyle(FillStyle.solid(ColorF(0, 0, 1, 1)));
  cv.lineWidth(6);
  auto line = new Path2d();
  line.moveTo(PointF(20, 200));
  line.lineTo(PointF(120, 200));
  cv.stroke(line);
  assert(isRgb(60, 200, 0, 0, 255));
  assert(isRgb(60, 210, 255, 0, 0));
  assert(isRgb(60, 190, 0, 0, 0));

  // 5. Canvas clip applies; scissor and viewport are restored
  r.clearFrame(black);
  r.pushClipRect(RectF(0, 0, 200, 200));
  GLint[4] boxBefore;
  glGetIntegerv(GL_SCISSOR_BOX, boxBefore.ptr);
  GLint[4] vpBefore;
  glGetIntegerv(GL_VIEWPORT, vpBefore.ptr);
  cv.save();
  cv.clip(rectPath(RectF(0, 0, 160, 240)));
  cv.shadow(hard);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(140, 50, 40, 40)));
  cv.restore();
  assert(isRgb(155, 95, 255, 0, 0)); // shadow inside the clip
  assert(isRgb(165, 95, 0, 0, 0)); // shadow outside the clip
  assert(isRgb(150, 70, 0, 255, 0));
  GLint[4] boxAfter;
  glGetIntegerv(GL_SCISSOR_BOX, boxAfter.ptr);
  GLint[4] vpAfter;
  glGetIntegerv(GL_VIEWPORT, vpAfter.ptr);
  assert(boxAfter == boxBefore && vpAfter == vpBefore);
  assert(glIsEnabled(GL_SCISSOR_TEST) == GL_TRUE);
  GLint fbo = -1;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fbo);
  assert(fbo == 0);
  r.drawFillRect(RectF(0, 0, 320, 240), ColorF(0, 0, 1, 1));
  r.popClipRect();
  assert(isRgb(5, 5, 0, 0, 255));
  assert(isRgb(210, 210, 0, 0, 0));
  assert(isRgb(250, 100, 0, 0, 0));

  // the shadow is limited by the Renderer scissor too
  r.clearFrame(black);
  r.pushClipRect(RectF(0, 0, 100, 240));
  cv.shadow(hard);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(60, 50, 40, 40)));
  r.popClipRect();
  assert(isRgb(95, 95, 255, 0, 0));
  assert(isRgb(105, 95, 0, 0, 0));

  // 6. a huge blur is clamped to sigma 64 px (blurred at 1/4 resolution):
  // it finishes, falls off like sigma 64 and stays within the clamped box
  // (pad 3 * 16 + 1 = 49 quarter pixels: right edge at 4 * (15 + 49))
  Shadow huge;
  huge.blur = 1000;
  huge.color = ColorF(1, 0, 0, 1);
  r.clearFrame(black);
  cv.shadow(huge);
  cv.fillStyle(green);
  // a half plane (right edge x = 60) far beyond the viewport elsewhere
  cv.fill(rectPath(RectF(-1000, -1000, 1060, 2240)));
  cv.shadow(Shadow.init);
  assert(isRgb(30, 120, 0, 255, 0));
  // 10 px out: about 0.44 alpha; 64 px (1 sigma) out: about 0.16
  assert(px(70, 120)[0] > 80 && px(70, 120)[1] == 0);
  const oneSigma = px(124, 120)[0];
  assert(oneSigma > 20 && oneSigma < 70);
  foreach (x; 256 .. 320) {
    assert(px(x, 120)[0] == 0);
  }

  // 7. offscreen targets that cannot hold the box: no shadow, the shape
  // still draws
  r.offscreenTargetRef(0).destroy();
  r.offscreenTargetRef(0).limitMaxSize(8);
  assert(!r.offscreenTargetRef(0).ensureSize(9, 9));
  r.clearFrame(black);
  cv.shadow(hard);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(100, 80, 40, 40)));
  assert(isRgb(120, 100, 0, 255, 0));
  assert(isRgb(145, 125, 0, 0, 0));
  GLint fboAfter = -1;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fboAfter);
  assert(fboAfter == 0);
  // destroy() forgets the limit: the shadow is back
  r.offscreenTargetRef(0).destroy();
  r.clearFrame(black);
  cv.shadow(hard);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(100, 80, 40, 40)));
  assert(isRgb(145, 125, 255, 0, 0));
  cv.shadow(Shadow.init);

  assert(glGetError() == GL_NO_ERROR);
}

// Canvas.drawImage (transform, clip, src region, tint, shadow, targets)
unittest {
  import std.math : PI;
  import yguilib.render.image : Image;
  import yguilib.render.render_target : RenderTarget;

  auto w = GlTestWindow("test_canvas_draw_image");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto r = w.renderer();
  auto cv = w.canvas();
  const ColorF black = ColorF(0, 0, 0, 1);
  const ColorF white = ColorF(1, 1, 1, 1);

  // 80x40 image, left half `left`, right half `right` (RGBA8)
  Image twoColor(ubyte[4] left, ubyte[4] right) {
    auto img = new Image(80, 40);
    foreach (y; 0 .. 40) {
      foreach (x; 0 .. 80) {
        const size_t i = (y * 80 + x) * 4;
        img.pixels[i .. i + 4] = x < 40 ? left : right;
      }
    }
    return img;
  }

  Texture tex = r.createTexture(twoColor([255, 0, 0, 255],
    [0, 0, 255, 255]));
  scope(exit) tex.destroy();
  assert(tex !is null && !tex.premultiplied() && !tex.bottomUp());
  const RectF dest = RectF(20, 20, 80, 40);

  // 1. untransformed: same pixels as Renderer.drawImage
  r.clearFrame(black);
  r.drawImage(tex, dest, white);
  Image expected = r.captureFrame();
  r.clearFrame(black);
  cv.drawImage(tex, dest);
  Image actual = r.captureFrame();
  assert(expected !is null && actual !is null);
  assert(expected.pixels == actual.pixels);
  assert(isRgb(30, 40, 255, 0, 0) && isRgb(90, 40, 0, 0, 255));
  assert(isRgb(10, 40, 0, 0, 0) && isRgb(30, 65, 0, 0, 0));

  // 2. rotate 90 degrees: local (x, y) -> (200 - y, 20 + x)
  r.clearFrame(black);
  cv.save();
  cv.translate(PointF(200, 20));
  cv.rotate(PI / 2);
  cv.drawImage(tex, RectF(0, 0, 80, 40));
  cv.restore();
  assert(isRgb(180, 30, 255, 0, 0) && isRgb(180, 55, 255, 0, 0));
  assert(isRgb(180, 65, 0, 0, 255) && isRgb(165, 95, 0, 0, 255));
  assert(isRgb(205, 40, 0, 0, 0) && isRgb(155, 40, 0, 0, 0));
  assert(isRgb(180, 105, 0, 0, 0));

  // 3. the Canvas clip limits the image
  r.clearFrame(black);
  cv.save();
  auto clipPath = new Path2d();
  clipPath.rect(RectF(0, 0, 40, 240));
  cv.clip(clipPath);
  cv.drawImage(tex, dest);
  cv.restore();
  assert(isRgb(30, 40, 255, 0, 0));
  assert(isRgb(50, 40, 0, 0, 0) && isRgb(90, 40, 0, 0, 0));
  // ... a circle clip too
  r.clearFrame(black);
  cv.save();
  auto circle = new Path2d();
  circle.arc(PointF(60, 40), 15, 0, 2 * PI, false);
  cv.clip(circle);
  cv.drawImage(tex, dest);
  cv.restore();
  assert(isRgb(50, 40, 255, 0, 0) && isRgb(70, 40, 0, 0, 255));
  assert(isRgb(60, 22, 0, 0, 0) && isRgb(30, 40, 0, 0, 0));
  assert(isRgb(90, 40, 0, 0, 0));

  // 4. a src region picks the right half, stretched to dest
  r.clearFrame(black);
  cv.drawImageRegion(tex, RectF(40, 0, 40, 40), dest);
  assert(isRgb(22, 40, 0, 0, 255) && isRgb(98, 40, 0, 0, 255));
  assert(isRgb(60, 40, 0, 0, 255));

  // 5. tint alpha halves the result
  r.clearFrame(black);
  cv.drawImageTinted(tex, dest, ColorF(1, 1, 1, 0.5f));
  assert(near(30, 40, 128, 0, 0, 2) && near(90, 40, 0, 0, 128, 2));
  // invalid input draws nothing
  r.clearFrame(black);
  cv.drawImage(null, dest);
  cv.drawImageTinted(tex, dest, ColorF(1, 1, 1, 0));
  cv.drawImage(tex, RectF(20, 20, 0, 40));
  cv.drawImage(tex, RectF(20, float.nan, 80, 40));
  cv.drawImageRegion(tex, RectF(0, 0, -5, 40), dest);
  assert(isRgb(30, 40, 0, 0, 0) && isRgb(90, 40, 0, 0, 0));

  // 6. hard shadow in the image shape; none under transparent pixels
  Texture half = r.createTexture(twoColor([0, 255, 0, 255],
    [0, 0, 0, 0]));
  scope(exit) half.destroy();
  Shadow hard;
  hard.offset = PointF(10, 10);
  hard.color = ColorF(1, 0, 0, 1);
  r.clearFrame(black);
  cv.shadow(hard);
  cv.drawImage(half, RectF(100, 100, 80, 40));
  assert(isRgb(105, 105, 0, 255, 0) && isRgb(135, 135, 0, 255, 0));
  assert(isRgb(145, 120, 255, 0, 0) && isRgb(120, 145, 255, 0, 0));
  assert(isRgb(160, 130, 0, 0, 0) && isRgb(175, 145, 0, 0, 0));
  assert(isRgb(105, 145, 0, 0, 0));
  // shadow alpha = shadow color alpha * image alpha * tint alpha
  r.clearFrame(black); // also resets the Canvas state
  cv.shadow(hard);
  cv.drawImageTinted(half, RectF(100, 100, 80, 40),
    ColorF(1, 1, 1, 0.5f));
  assert(near(145, 120, 128, 0, 0, 3));
  cv.shadow(Shadow.init);

  // 7. a render target texture is upright with the drawn colors
  RenderTarget rt = r.createRenderTarget(80, 40, false);
  assert(rt !is null);
  scope(exit) rt.destroy();
  // On a failed assert close open targets before destroying them (an
  // assert in destroy() while unwinding loops the test runner forever).
  scope(exit) w.endTargets();
  r.beginTarget(rt, true);
  r.drawFillRect(RectF(0, 0, 80, 20), ColorF(1, 0, 0, 1));
  r.drawFillRect(RectF(0, 20, 80, 20), ColorF(0, 0, 1, 0.5f));
  r.endTarget();
  r.clearFrame(black);
  cv.drawImage(rt.texture(), RectF(200, 150, 80, 40));
  assert(isRgb(240, 160, 255, 0, 0));
  assert(near(240, 180, 0, 0, 128, 2));
  // ... and through a transform + tint
  r.clearFrame(black);
  cv.save();
  cv.translate(PointF(100, 0));
  cv.drawImageTinted(rt.texture(), RectF(100, 150, 80, 40),
    ColorF(1, 1, 1, 0.5f));
  cv.restore();
  assert(near(240, 160, 128, 0, 0, 2));
  assert(near(240, 180, 0, 0, 64, 2));

  assert(glGetError() == GL_NO_ERROR);
}

// Canvas patterns (repeat modes, transforms, tints, strokes, clips, shadows)
unittest {
  import std.math : PI;
  import yguilib.render.image : Image;
  import yguilib.render.render_target : RenderTarget;

  auto w = GlTestWindow("test_canvas_patterns");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto r = w.renderer();
  auto cv = w.canvas();
  const ColorF black = ColorF(0, 0, 0, 1);

  // 20x20 4-quadrant texture: TL red, TR green, BL blue, BR white
  auto quadImg = new Image(20, 20);
  foreach (y; 0 .. 20) {
    foreach (x; 0 .. 20) {
      const size_t i = (y * 20 + x) * 4;
      ubyte[4] c;
      if (y < 10) {
        c = x < 10 ? [255, 0, 0, 255] : [0, 255, 0, 255];
      } else {
        c = x < 10 ? [0, 0, 255, 255] : [255, 255, 255, 255];
      }
      quadImg.pixels[i .. i + 4] = c;
    }
  }
  Texture tex = r.createTexture(quadImg);
  assert(tex !is null);
  scope(exit) tex.destroy();

  auto box = rectPath(RectF(0, 0, 100, 60));

  // 1. repeat: tiles across 100x60 rect
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.repeat)
  ));
  cv.fill(box);
  // tile (0, 0)
  assert(isRgb(5, 5, 255, 0, 0) && isRgb(15, 5, 0, 255, 0));
  assert(isRgb(5, 15, 0, 0, 255) && isRgb(15, 15, 255, 255, 255));
  // tile (1, 0)
  assert(isRgb(25, 5, 255, 0, 0) && isRgb(35, 5, 0, 255, 0));
  assert(isRgb(25, 15, 0, 0, 255) && isRgb(35, 15, 255, 255, 255));
  // tile (0, 1)
  assert(isRgb(5, 25, 255, 0, 0) && isRgb(15, 35, 255, 255, 255));
  // tile (3, 2)
  assert(isRgb(65, 45, 255, 0, 0) && isRgb(75, 45, 0, 255, 0));
  assert(isRgb(65, 55, 0, 0, 255) && isRgb(75, 55, 255, 255, 255));
  // outside rect
  assert(isRgb(120, 30, 0, 0, 0) && isRgb(50, 80, 0, 0, 0));

  // 2. repeatX: tiles horizontally for y in [0, 20), background for y >= 20
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.repeatX)
  ));
  cv.fill(box);
  assert(isRgb(5, 5, 255, 0, 0) && isRgb(25, 5, 255, 0, 0));
  assert(isRgb(75, 15, 255, 255, 255));
  assert(isRgb(5, 25, 0, 0, 0) && isRgb(65, 45, 0, 0, 0));

  // 3. repeatY: tiles vertically for x in [0, 20), background for x >= 20
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.repeatY)
  ));
  cv.fill(box);
  assert(isRgb(5, 5, 255, 0, 0) && isRgb(5, 25, 255, 0, 0));
  assert(isRgb(15, 55, 255, 255, 255));
  assert(isRgb(25, 5, 0, 0, 0) && isRgb(65, 45, 0, 0, 0));

  // 4. noRepeat: draws once in [0, 20) x [0, 20); stencil bits stay clean
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.noRepeat)
  ));
  cv.fill(box);
  assert(isRgb(5, 5, 255, 0, 0) && isRgb(15, 5, 0, 255, 0));
  assert(isRgb(5, 15, 0, 0, 255) && isRgb(15, 15, 255, 255, 255));
  assert(isRgb(25, 5, 0, 0, 0) && isRgb(5, 25, 0, 0, 0));
  assert(isRgb(65, 45, 0, 0, 0));
  // subsequent fill over the whole area works (stencil low bits zeroed)
  cv.fillStyle(FillStyle.solid(ColorF(0, 1, 0, 1)));
  cv.fill(box);
  assert(isRgb(5, 5, 0, 255, 0) && isRgb(25, 5, 0, 255, 0));
  assert(isRgb(65, 45, 0, 255, 0));

  // 5. Pattern.transform: translation, 90-deg rotation, 2x scaling, combined
  r.clearFrame(black);
  Pattern trPat = Pattern.fromTexture(tex, PatternRepeat.repeat);
  trPat.withTransform(Transform2d.translation(PointF(10, 5)));
  cv.fillStyle(FillStyle.fromPattern(trPat));
  cv.fill(box);
  assert(isRgb(15, 10, 255, 0, 0) && isRgb(25, 10, 0, 255, 0));
  assert(isRgb(15, 20, 0, 0, 255) && isRgb(25, 20, 255, 255, 255));

  r.clearFrame(black);
  Pattern rotPat = Pattern.fromTexture(tex, PatternRepeat.repeat);
  rotPat.withTransform(Transform2d.rotation(cast(float)(PI / 2)));
  cv.fillStyle(FillStyle.fromPattern(rotPat));
  cv.fill(box);
  // (u, v) -> pattern (v, -u mod 20)
  assert(isRgb(5, 5, 0, 0, 255) && isRgb(15, 5, 255, 0, 0));
  assert(isRgb(5, 15, 255, 255, 255) && isRgb(15, 15, 0, 255, 0));

  r.clearFrame(black);
  Pattern scPat = Pattern.fromTexture(tex, PatternRepeat.repeat);
  scPat.withTransform(Transform2d.scaling(PointF(2, 2)));
  cv.fillStyle(FillStyle.fromPattern(scPat));
  cv.fill(box);
  assert(isRgb(10, 10, 255, 0, 0) && isRgb(30, 10, 0, 255, 0));
  assert(isRgb(10, 30, 0, 0, 255) && isRgb(30, 30, 255, 255, 255));

  r.clearFrame(black);
  cv.save();
  cv.translate(PointF(40, 20));
  Pattern combPat = Pattern.fromTexture(tex, PatternRepeat.repeat);
  combPat.withTransform(Transform2d.translation(PointF(10, 0)));
  cv.fillStyle(FillStyle.fromPattern(combPat));
  cv.fill(rectPath(RectF(0, 0, 60, 40)));
  cv.restore();
  assert(isRgb(55, 25, 255, 0, 0) && isRgb(65, 25, 0, 255, 0));
  assert(isRgb(45, 25, 0, 255, 0) && isRgb(30, 25, 0, 0, 0));

  // 6. Pattern.tint: half alpha and color tinting
  r.clearFrame(black);
  Pattern halfPat = Pattern.fromTexture(tex, PatternRepeat.repeat);
  halfPat.withTint(ColorF(1, 1, 1, 0.5f));
  cv.fillStyle(FillStyle.fromPattern(halfPat));
  cv.fill(box);
  assert(near(5, 5, 128, 0, 0, 3) && near(15, 15, 128, 128, 128, 3));

  r.clearFrame(black);
  Pattern tintPat = Pattern.fromTexture(tex, PatternRepeat.repeat);
  tintPat.withTint(ColorF(1, 0, 0.5f, 1));
  cv.fillStyle(FillStyle.fromPattern(tintPat));
  cv.fill(box);
  assert(near(15, 15, 255, 0, 128, 3) && near(15, 5, 0, 0, 0, 2));

  // 7. Pattern stroke: thick line, self-overlapping cross, dashed stroke
  r.clearFrame(black);
  cv.strokeStyle(FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.repeat)
  ));
  cv.lineWidth(10);
  auto hline = new Path2d();
  hline.moveTo(PointF(0, 5));
  hline.lineTo(PointF(60, 5));
  cv.stroke(hline);
  assert(isRgb(5, 5, 255, 0, 0) && isRgb(15, 5, 0, 255, 0));
  assert(isRgb(25, 5, 255, 0, 0) && isRgb(35, 5, 0, 255, 0));
  assert(isRgb(5, 20, 0, 0, 0));

  r.clearFrame(black);
  auto cross = new Path2d();
  cross.moveTo(PointF(50, 50));
  cross.lineTo(PointF(200, 200));
  cross.lineTo(PointF(200, 50));
  cross.lineTo(PointF(50, 200));
  cv.strokeStyle(FillStyle.fromPattern(halfPat));
  cv.lineWidth(10);
  cv.stroke(cross);
  // (125, 125) and (85, 85) both fall in TL red (5, 5) mod 20
  assert(near(125, 125, 128, 0, 0, 3));
  assert(near(85, 85, 128, 0, 0, 3));

  r.clearFrame(black);
  cv.strokeStyle(FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.repeat)
  ));
  cv.lineWidth(8);
  cv.lineDash(LineDash.fromSegments([20.0f, 20]));
  auto dline = new Path2d();
  dline.moveTo(PointF(0, 5));
  dline.lineTo(PointF(80, 5));
  cv.stroke(dline);
  assert(isRgb(5, 5, 255, 0, 0) && isRgb(15, 5, 0, 255, 0));
  assert(isRgb(25, 5, 0, 0, 0) && isRgb(35, 5, 0, 0, 0));
  assert(isRgb(45, 5, 255, 0, 0) && isRgb(55, 5, 0, 255, 0));
  cv.lineDash(LineDash.init);
  cv.lineWidth(1);

  // 8. clip() limits pattern fill; save()/restore() preserves styles
  r.clearFrame(black);
  const FillStyle patStyle = FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.repeat)
  );
  cv.save();
  cv.fillStyle(patStyle);
  cv.strokeStyle(patStyle);
  cv.clip(rectPath(RectF(0, 0, 30, 30)));
  cv.fill(box);
  assert(isRgb(5, 5, 255, 0, 0) && isRgb(25, 5, 255, 0, 0));
  assert(isRgb(45, 5, 0, 0, 0) && isRgb(5, 45, 0, 0, 0));
  cv.save();
  cv.fillStyle(FillStyle.solid(ColorF(0, 0, 1, 1)));
  cv.strokeStyle(FillStyle.solid(ColorF(0, 1, 0, 1)));
  cv.restore();
  assert(cv.fillStyle().kind == FillStyle.Kind.pattern);
  assert(cv.fillStyle().pattern.texture is tex);
  assert(cv.strokeStyle().kind == FillStyle.Kind.pattern);
  assert(cv.strokeStyle().pattern.texture is tex);
  cv.restore();
  assert(cv.fillStyle().kind == FillStyle.Kind.color);

  // 9. Pattern shadow: half-transparent texture, noRepeat, tint.a scaling
  auto halfImg = new Image(20, 20);
  foreach (y; 0 .. 20) {
    foreach (x; 0 .. 20) {
      const size_t i = (y * 20 + x) * 4;
      halfImg.pixels[i .. i + 4] =
        x < 10 ? [0, 255, 0, 255] : [0, 0, 0, 0];
    }
  }
  Texture halfTex = r.createTexture(halfImg);
  assert(halfTex !is null);
  scope(exit) halfTex.destroy();

  Shadow hard;
  hard.offset = PointF(10, 10);
  hard.color = ColorF(1, 0, 0, 1);

  r.clearFrame(black);
  cv.shadow(hard);
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(halfTex, PatternRepeat.repeat)
  ));
  cv.fill(rectPath(RectF(20, 20, 40, 20)));
  assert(isRgb(25, 25, 0, 255, 0));
  assert(isRgb(35, 35, 255, 0, 0) && isRgb(35, 45, 255, 0, 0));
  assert(isRgb(45, 45, 0, 0, 0) && isRgb(55, 45, 255, 0, 0));

  r.clearFrame(black);
  cv.shadow(hard);
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(halfTex, PatternRepeat.noRepeat)
  ));
  cv.fill(rectPath(RectF(0, 0, 60, 40)));
  assert(isRgb(5, 5, 0, 255, 0));
  assert(isRgb(15, 15, 255, 0, 0) && isRgb(15, 25, 255, 0, 0));
  assert(isRgb(35, 25, 0, 0, 0));

  r.clearFrame(black);
  cv.shadow(hard);
  Pattern halfAlphaPat = Pattern.fromTexture(halfTex, PatternRepeat.noRepeat);
  halfAlphaPat.withTint(ColorF(1, 1, 1, 0.5f));
  cv.fillStyle(FillStyle.fromPattern(halfAlphaPat));
  cv.fill(rectPath(RectF(0, 0, 60, 40)));
  assert(near(15, 25, 128, 0, 0, 3));
  cv.shadow(Shadow.init);

  // 10. RenderTarget.texture() as a Pattern: upright and tiled cleanly
  RenderTarget rt = r.createRenderTarget(20, 20, false);
  assert(rt !is null);
  scope(exit) rt.destroy();
  scope(exit) w.endTargets();
  r.beginTarget(rt, true);
  r.drawFillRect(RectF(0, 0, 20, 10), ColorF(1, 0, 0, 1));
  r.drawFillRect(RectF(0, 10, 20, 10), ColorF(0, 0, 1, 0.5f));
  r.endTarget();

  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(rt.texture(), PatternRepeat.repeat)
  ));
  cv.fill(rectPath(RectF(0, 0, 60, 40)));
  assert(isRgb(10, 5, 255, 0, 0) && near(10, 15, 0, 0, 128, 2));
  assert(isRgb(50, 25, 255, 0, 0) && near(50, 35, 0, 0, 128, 2));

  // 11. Invalid patterns draw nothing
  r.clearFrame(black);
  cv.fillStyle(
    FillStyle.fromPattern(Pattern.fromTexture(null, PatternRepeat.repeat))
  );
  cv.fill(box);

  Texture dead = r.createTexture(quadImg);
  assert(dead !is null);
  dead.destroy();
  cv.fillStyle(
    FillStyle.fromPattern(Pattern.fromTexture(dead, PatternRepeat.repeat))
  );
  cv.fill(box);

  Pattern zeroA = Pattern.fromTexture(tex, PatternRepeat.repeat);
  zeroA.withTint(ColorF(1, 1, 1, 0));
  cv.fillStyle(FillStyle.fromPattern(zeroA));
  cv.fill(box);

  Pattern singular = Pattern.fromTexture(tex, PatternRepeat.repeat);
  singular.withTransform(Transform2d.scaling(PointF(0, 1)));
  cv.fillStyle(FillStyle.fromPattern(singular));
  cv.fill(box);

  cv.save();
  cv.scale(PointF(0, 1));
  cv.fillStyle(
    FillStyle.fromPattern(Pattern.fromTexture(tex, PatternRepeat.repeat))
  );
  cv.fill(box);
  cv.restore();

  assert(isRgb(5, 5, 0, 0, 0) && isRgb(15, 15, 0, 0, 0));
  assert(isRgb(50, 30, 0, 0, 0));

  assert(glGetError() == GL_NO_ERROR);
}

// Canvas text state and measureText
unittest {
  import std.math : isClose;

  auto w = GlTestWindow("test_canvas_text_state");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto cv = w.canvas();

  assert(cv.fontSpec.ptSize == defaultFontPtSize);
  assert(cv.textAlign == TextAlign.start);
  assert(cv.textBaseline == TextBaseline.alphabetic);
  assert(cv.direction == TextDirection.ltr);

  cv.fontSpec = FontSpec(20, null);
  cv.textAlign = TextAlign.center;
  cv.textBaseline = TextBaseline.middle;
  cv.direction = TextDirection.rtl;
  cv.save();
  cv.fontSpec = FontSpec(30, null);
  cv.textAlign = TextAlign.end;
  cv.textBaseline = TextBaseline.top;
  cv.direction = TextDirection.ltr;
  assert(cv.fontSpec.ptSize == 30);
  cv.restore();
  assert(cv.fontSpec.ptSize == 20);
  assert(cv.textAlign == TextAlign.center);
  assert(cv.textBaseline == TextBaseline.middle);
  assert(cv.direction == TextDirection.rtl);

  // invalid sizes are ignored
  cv.fontSpec = FontSpec(0, null);
  cv.fontSpec = FontSpec(-3, null);
  cv.fontSpec = FontSpec(float.nan, null);
  cv.fontSpec = FontSpec(float.infinity, null);
  assert(cv.fontSpec.ptSize == 20);

  const e = cv.measureText("");
  assert(e.width == 0 && e.fontAscent == 0 && e.fontDescent == 0);
  const m = cv.measureText("Hello");
  assert(m.width > 0 && m.fontAscent > 0 && m.fontDescent >= 0);
  cv.fontSpec = FontSpec(40, null);
  const m2 = cv.measureText("Hello");
  assert(m2.width > m.width && m2.fontAscent > m.fontAscent);

  // under a transform scale metrics stay in user units (not scaled)
  cv.save();
  cv.scale(PointF(2, 2));
  const m3 = cv.measureText("Hello");
  cv.restore();
  assert(isClose(m3.width, m2.width, 0.05f));
  assert(isClose(m3.fontAscent, m2.fontAscent, 0.05f));
  // a degenerate transform still measures at the display scale
  cv.save();
  cv.scale(PointF(0, 1));
  const m4 = cv.measureText("Hello");
  cv.restore();
  assert(m4.width == m2.width && m4.fontAscent == m2.fontAscent);
}

// Canvas.fillText (position, transform, clip, shadow, maxWidth, no-ops)
unittest {
  import std.math : PI;

  auto w = GlTestWindow("test_canvas_fill_text");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto r = w.renderer();
  auto cv = w.canvas();

  const black = ColorF(0, 0, 0, 1);
  const white = FillStyle.solid(ColorF(1, 1, 1, 1));
  // clearFrame resets the canvas state, so set the font after it
  void clear() {
    r.clearFrame(black);
    cv.fontSpec = FontSpec(24, null);
    cv.textBaseline = TextBaseline.top;
  }
  cv.textBaseline = TextBaseline.top;

  // 1. plain text: box starts at the anchor, width follows measureText
  clear();
  cv.fillStyle(white);
  cv.fillText("Hello", PointF(40, 50));
  const base = frameBounds(0);
  const mw = cv.measureText("Hello").width; // state set by clear()
  assert(!base.empty);
  assert(base.x0 >= 38 && base.x0 <= 46);
  assert(base.y0 >= 50 && base.y0 <= 60);
  assert(base.x1 - base.x0 + 1 <= cast(int)mw + 2);
  assert(base.x1 - base.x0 + 1 >= cast(int)mw - 10);
  const baseW = base.x1 - base.x0 + 1;
  const baseH = base.y1 - base.y0 + 1;

  // 2. translation moves the box rigidly
  clear();
  cv.fillStyle(white);
  cv.save();
  cv.translate(PointF(100, 60));
  cv.fillText("Hello", PointF(40, 50));
  cv.restore();
  const tr = frameBounds(0);
  assert(tr.x0 == base.x0 + 100 && tr.y0 == base.y0 + 60);
  assert(tr.x1 - tr.x0 == base.x1 - base.x0);

  // 3. rotation by 90 degrees swaps width and height
  clear();
  cv.fillStyle(white);
  cv.save();
  cv.translate(PointF(160, 40));
  cv.rotate(cast(float)(PI / 2));
  cv.fillText("Hello", PointF(0, 0));
  cv.restore();
  const rot = frameBounds(0);
  assert(!rot.empty);
  const rotW = rot.x1 - rot.x0 + 1;
  const rotH = rot.y1 - rot.y0 + 1;
  assert(rotW >= baseH - 3 && rotW <= baseH + 3);
  assert(rotH >= baseW - 3 && rotH <= baseW + 3);
  // clockwise rotation: text extends to the left of x = 160 and down
  assert(rot.x1 <= 162 && rot.y0 >= 38);

  // 4. a scale transform enlarges the bitmap crisply
  clear();
  cv.fillStyle(white);
  cv.save();
  cv.scale(PointF(2, 2));
  cv.fillText("Hello", PointF(20, 20));
  cv.restore();
  const sc = frameBounds(0);
  const scW = sc.x1 - sc.x0 + 1;
  assert(scW >= 2 * baseW - 6 && scW <= 2 * baseW + 6);

  // 5. clip limits the text
  clear();
  cv.fillStyle(white);
  cv.save();
  auto clipRc = new Path2d();
  clipRc.rect(RectF(0, 0, 60, 240));
  cv.clip(clipRc);
  cv.fillText("Hello", PointF(40, 50));
  cv.restore();
  const cl = frameBounds(0);
  assert(!cl.empty && cl.x1 < 60);

  // 6. solid color tint
  clear();
  cv.fillStyle(FillStyle.solid(ColorF(0, 0, 1, 1)));
  cv.fillText("Hello", PointF(40, 50));
  assert(frameBounds(0).empty);
  assert(frameBounds(2).x0 == base.x0);

  // 7. hard shadow: a copy offset by (60, 50) in the shadow color
  clear();
  Shadow sh;
  sh.offset = PointF(60, 50);
  sh.color = ColorF(1, 0, 0, 1);
  cv.shadow(sh);
  cv.fillStyle(FillStyle.solid(ColorF(0, 1, 0, 1)));
  cv.fillText("Hello", PointF(40, 50));
  cv.shadow(Shadow.init);
  const sg = frameBounds(1);
  const sr = frameBounds(0);
  assert(!sg.empty && !sr.empty);
  assert(sr.x1 == sg.x1 + 60 && sr.y1 == sg.y1 + 50);

  // 8. maxWidth squeezes about the anchor; narrower text is untouched
  clear();
  cv.fillStyle(white);
  cv.fillTextWithMaxWidth("Hello", PointF(40, 50), mw * 0.5f);
  const mx = frameBounds(0);
  const mxW = mx.x1 - mx.x0 + 1;
  assert(mx.x0 >= 38 && mx.x0 <= 46);
  assert(mxW >= baseW / 2 - 4 && mxW <= baseW / 2 + 4);
  clear();
  cv.fillStyle(white);
  cv.fillTextWithMaxWidth("Hello", PointF(40, 50), 1000);
  const wide = frameBounds(0);
  assert(wide == base);

  // 9. no-ops
  clear();
  cv.fillStyle(white);
  cv.fillText("", PointF(40, 50));
  cv.fillText("Hello", PointF(float.nan, 50));
  cv.fillText("Hello", PointF(40, float.infinity));
  cv.fillTextWithMaxWidth("Hello", PointF(40, 50), 0);
  cv.fillTextWithMaxWidth("Hello", PointF(40, 50), -5);
  cv.fillTextWithMaxWidth("Hello", PointF(40, 50), float.nan);
  cv.fillTextWithMaxWidth("Hello", PointF(40, 50), float.infinity);
  cv.fillStyle(FillStyle.solid(ColorF(1, 1, 1, 0)));
  cv.fillText("Hello", PointF(40, 50));
  LinearGradient lg;
  lg.p1 = PointF(100, 0);
  lg.stops.add(0, ColorF(1, 1, 1, 0));
  lg.stops.add(1, ColorF(1, 1, 1, 0));
  cv.fillStyle(FillStyle.fromLinear(lg));
  cv.fillText("Hello", PointF(40, 50));
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(null, PatternRepeat.repeat)
  ));
  cv.fillText("Hello", PointF(40, 50));
  cv.fillStyle(white);
  cv.save();
  cv.scale(PointF(0, 1));
  cv.fillText("Hello", PointF(40, 50));
  cv.restore();
  assert(frameBounds(0).empty);
}

// Canvas.fillText with gradient and pattern fills (alpha mask variants)
unittest {
  import yguilib.render.image : Image;

  auto w = GlTestWindow("test_canvas_fill_text_paint");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto r = w.renderer();
  auto cv = w.canvas();

  const black = ColorF(0, 0, 0, 1);
  void clear() {
    r.clearFrame(black);
    cv.fontSpec = FontSpec(40, null);
    cv.textBaseline = TextBaseline.top;
  }

  clear();
  cv.fillStyle(FillStyle.solid(ColorF(1, 1, 1, 1)));
  cv.fillText("Hello", PointF(40, 50));
  const base = frameBounds(0);
  assert(!base.empty);

  // 1. linear gradient red (left) to blue (right) across the text
  clear();
  LinearGradient lg;
  lg.p0 = PointF(40, 0);
  lg.p1 = PointF(40 + (base.x1 - base.x0), 0);
  lg.stops.add(0, ColorF(1, 0, 0, 1));
  lg.stops.add(1, ColorF(0, 0, 1, 1));
  cv.fillStyle(FillStyle.fromLinear(lg));
  cv.fillText("Hello", PointF(40, 50));
  const red = frameBounds(0);
  const blue = frameBounds(2);
  assert(!red.empty && !blue.empty);
  assert(frameBounds(1).empty);
  assert(red.x0 < blue.x0 - 10 && red.x1 < blue.x1);
  assert(red.x0 <= base.x0 + 2 && blue.x1 >= base.x1 - 2);

  // 2. radial gradient also paints through the glyph mask
  clear();
  RadialGradient rg;
  rg.c0 = PointF(40, 70);
  rg.c1 = PointF(40, 70);
  rg.r0 = 0;
  rg.r1 = 200;
  rg.stops.add(0, ColorF(0, 1, 0, 1));
  rg.stops.add(1, ColorF(0, 1, 0, 1));
  cv.fillStyle(FillStyle.fromRadial(rg));
  cv.fillText("Hello", PointF(40, 50));
  const gr = frameBounds(1);
  assert(!gr.empty && gr.x0 >= base.x0 - 1 && gr.x1 <= base.x1 + 1);
  assert(frameBounds(0).empty && frameBounds(2).empty);

  // 3. pattern: red left of x = 80, green right of it
  auto img = new Image(320, 1);
  foreach (x; 0 .. 320) {
    const ubyte[4] c = x < 80 ? [255, 0, 0, 255] : [0, 255, 0, 255];
    img.pixels[x * 4 .. x * 4 + 4] = c;
  }
  Texture tex = r.createTexture(img);
  assert(tex !is null);
  scope(exit) tex.destroy();
  clear();
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.repeatY)
  ));
  cv.fillText("Hello", PointF(40, 50));
  const pr = frameBounds(0);
  const pg = frameBounds(1);
  assert(!pr.empty && !pg.empty && frameBounds(2).empty);
  assert(pr.x1 < 80 && pg.x0 >= 78 && pr.x0 <= base.x0 + 2);
  assert(pg.x1 >= base.x1 - 2);

  // 4. pattern under a translate transform moves with it
  clear();
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(tex, PatternRepeat.repeatY)
  ));
  cv.save();
  cv.translate(PointF(100, 0));
  cv.fillText("Hello", PointF(40, 50));
  cv.restore();
  const tr = frameBounds(0);
  assert(!tr.empty && tr.x0 >= base.x0 + 98 && tr.x1 < 180);

  // 5. gradient shadow follows the glyph alpha
  clear();
  Shadow sh;
  sh.offset = PointF(0, 80);
  sh.color = ColorF(1, 0, 0, 1);
  cv.shadow(sh);
  cv.fillStyle(FillStyle.fromRadial(rg));
  cv.fillText("Hello", PointF(40, 50));
  cv.shadow(Shadow.init);
  assert(!frameBounds(0).empty && !frameBounds(1).empty);

  // 6. invisible styles draw nothing
  clear();
  LinearGradient clear0;
  clear0.p1 = PointF(100, 0);
  clear0.stops.add(0, ColorF(1, 1, 1, 0));
  clear0.stops.add(1, ColorF(1, 1, 1, 0));
  cv.fillStyle(FillStyle.fromLinear(clear0));
  cv.fillText("Hello", PointF(40, 50));
  Pattern ghost = Pattern.fromTexture(tex, PatternRepeat.repeat);
  ghost.tint = ColorF(1, 1, 1, 0);
  cv.fillStyle(FillStyle.fromPattern(ghost));
  cv.fillText("Hello", PointF(40, 50));
  cv.fillStyle(FillStyle.fromPattern(
    Pattern.fromTexture(null, PatternRepeat.repeat)
  ));
  cv.fillText("Hello", PointF(40, 50));
  assert(frameBounds(0).empty && frameBounds(1).empty && frameBounds(2).empty);
  assert(glGetError() == GL_NO_ERROR);
}

// Canvas.strokeText (outline ring, paint kinds, no-ops)
unittest {
  auto w = GlTestWindow("test_canvas_stroke_text");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto r = w.renderer();
  auto cv = w.canvas();

  ubyte[] buf;
  void grab() {
    buf = grabFrame();
  }
  int ch(int x, int y, int c) {
    return channelAt(buf, x, y, c);
  }

  const black = ColorF(0, 0, 0, 1);
  void clear() {
    r.clearFrame(black);
    cv.fontSpec = FontSpec(100, null);
    cv.textBaseline = TextBaseline.top;
    cv.lineWidth(4);
  }

  // 1. ring: glyph "O" has a hole at its center; stroke wider than fill
  clear();
  cv.fillStyle(FillStyle.solid(ColorF(1, 1, 1, 1)));
  cv.fillText("O", PointF(100, 40));
  grab();
  const fill = litSpan(buf, 0);
  assert(fill.count > 0);

  clear();
  cv.strokeStyle(FillStyle.solid(ColorF(1, 0, 0, 1)));
  cv.strokeText("O", PointF(100, 40));
  grab();
  const st = litSpan(buf, 0);
  assert(st.count > 0);
  assert(st.x1 - st.x0 > fill.x1 - fill.x0);
  assert(st.x0 < fill.x0 && st.x1 > fill.x1);
  const cx = (st.x0 + st.x1) / 2;
  bool centerLit = false;
  foreach (y; 40 .. 160) {
    if (ch(cx, y, 0) > 60) {
      centerLit = true;
    }
  }
  // the vertical line through the center crosses ring top and bottom
  // but its middle (glyph center) is empty
  assert(centerLit);
  assert(ch(cx, 40 + 50, 0) < 30);
  assert(ch(cx, 40 + 50, 1) < 30);

  // 2. wider lineWidth draws more pixels
  cv.lineWidth(8);
  cv.strokeText("O", PointF(100, 40));
  grab();
  assert(litSpan(buf, 0).count > st.count);

  // 3. gradient stroke paints through the ring mask
  clear();
  auto lg = LinearGradient(PointF(0, 0), PointF(320, 0));
  lg.addColorStop(0, ColorF(0, 1, 0, 1));
  lg.addColorStop(1, ColorF(0, 1, 0, 1));
  cv.strokeStyle(FillStyle.fromLinear(lg));
  cv.strokeText("O", PointF(100, 40));
  grab();
  assert(litSpan(buf, 1).count > 0);
  assert(ch(cx, 40 + 50, 1) < 30);

  // 4. maxWidth squeezes
  clear();
  cv.strokeStyle(FillStyle.solid(ColorF(1, 0, 0, 1)));
  cv.strokeTextWithMaxWidth("OOOO", PointF(20, 40), 60);
  grab();
  const mx = litSpan(buf, 0);
  assert(mx.count > 0);
  assert(mx.x1 - mx.x0 <= 60 + 2 * 8);

  // 5. no-ops
  clear();
  cv.strokeStyle(FillStyle.solid(ColorF(1, 0, 0, 1)));
  cv.strokeText("", PointF(100, 40));
  cv.strokeText("O", PointF(float.nan, 40));
  cv.strokeTextWithMaxWidth("O", PointF(100, 40), 0);
  cv.strokeTextWithMaxWidth("O", PointF(100, 40), float.nan);
  cv.strokeStyle(FillStyle.solid(ColorF(1, 0, 0, 0)));
  cv.strokeText("O", PointF(100, 40));
  grab();
  assert(litSpan(buf, 0).count == 0);
}

// dashed stroke: transform, shadow, and a warmed-up loop without GC growth
unittest {
  import core.memory : GC;

  auto w = GlTestWindow("test_canvas_dash_gc");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto r = w.renderer();
  auto cv = w.canvas();

  const black = ColorF(0, 0, 0, 1);
  auto line = new Path2d();
  line.moveTo(PointF(0, 0));
  line.lineTo(PointF(100, 0));

  // translated dashed line with a hard shadow 20 px below: the shadow
  // pass sees the same transformed geometry
  r.clearFrame(black);
  cv.strokeStyle(FillStyle.solid(ColorF(1, 1, 1, 1)));
  cv.lineWidth(6);
  cv.lineDash(LineDash.fromSegments([20.0f, 20]));
  Shadow s;
  s.offset = PointF(0, 20);
  s.color = ColorF(0, 1, 0, 1);
  cv.shadow(s);
  cv.translate(PointF(20, 100));
  cv.stroke(line);
  cv.resetTransform();
  cv.shadow(Shadow.init);
  assert(isRgb(30, 100, 255, 255, 255) && isRgb(50, 100, 0, 0, 0));
  assert(isRgb(70, 100, 255, 255, 255));
  assert(isRgb(30, 120, 0, 255, 0) && isRgb(50, 120, 0, 0, 0));
  assert(isRgb(70, 120, 0, 255, 0));

  const float[3] segs = [7, 3, 2];
  void frame() {
    cv.lineDash(LineDash.fromSegments(segs[]));
    const LineDash d = cv.lineDash();
    assert(d.segments.length == 6);
    cv.lineDashOffset(1);
    cv.stroke(line);
  }

  frame();
  frame();
  GC.collect();
  const before = GC.stats();
  foreach (_; 0 .. 100) {
    frame();
  }
  const after = GC.stats();
  cv.lineDash(LineDash.init);
  cv.lineDashOffset(0);
  assert(after.allocatedInCurrentThread == before.allocatedInCurrentThread);
  assert(
    after.usedSize + after.freeSize <= before.usedSize + before.freeSize
  );
}

// nested clips inside and across a render target pass; clip, save and
// target passes do not allocate after a warm-up
unittest {
  import core.memory : GC;
  import yguilib.render.render_target : RenderTarget;

  auto w = GlTestWindow("test_canvas_clip_state");
  scope(exit) w.destroy();
  auto r = w.renderer();
  auto cv = w.canvas();
  RenderTarget rt = r.createRenderTarget(320, 240, false);
  assert(rt !is null);
  scope(exit) rt.destroy();
  RenderTarget rt2 = r.createRenderTarget(320, 240, false);
  assert(rt2 !is null);
  scope(exit) rt2.destroy();
  scope(exit) w.endTargets();

  const black = ColorF(0, 0, 0, 1);
  const green = FillStyle.solid(ColorF(0, 1, 0, 1));
  const blue = FillStyle.solid(ColorF(0, 0, 1, 1));
  auto full = rectPath(RectF(0, 0, 320, 240));
  auto outer = rectPath(RectF(20, 20, 100, 100));
  auto inner = rectPath(RectF(70, 70, 100, 100));
  auto small = rectPath(RectF(0, 0, 40, 40));

  // nested save/clip/clip/restore/restore inside a target pass
  void nested() {
    cv.fillStyle(green);
    cv.save();
    cv.clip(outer);
    cv.save();
    cv.clip(inner);
    cv.fill(full);
    assert(isRgb(90, 90, 0, 255, 0));
    assert(isRgb(40, 40, 0, 0, 0) && isRgb(150, 150, 0, 0, 0));
    cv.restore();
    cv.fillStyle(blue);
    cv.fill(full);
    assert(isRgb(40, 40, 0, 0, 255) && isRgb(150, 150, 0, 0, 0));
    cv.restore();
    cv.fillStyle(green);
    cv.fill(full);
    assert(isRgb(150, 150, 0, 255, 0) && isRgb(5, 5, 0, 255, 0));
  }

  r.clearFrame(black);
  r.beginTarget(rt, true);
  nested();
  r.endTarget();

  // across a target boundary: the outer clips stay on the window, the
  // target starts unclipped and its clips are gone after endTarget
  r.clearFrame(black);
  cv.save();
  cv.clip(outer);
  cv.save();
  cv.clip(inner);
  r.beginTarget(rt, true);
  cv.fillStyle(blue);
  cv.fill(full);
  assert(isRgb(5, 5, 0, 0, 255));
  cv.save();
  cv.clip(small);
  cv.fillStyle(green);
  cv.fill(full);
  assert(isRgb(10, 10, 0, 255, 0) && isRgb(100, 100, 0, 0, 255));
  r.endTarget();
  cv.fillStyle(green);
  cv.fill(full);
  assert(isRgb(90, 90, 0, 255, 0));
  assert(isRgb(40, 40, 0, 0, 0) && isRgb(10, 10, 0, 0, 0));
  cv.restore();
  cv.fillStyle(blue);
  cv.fill(full);
  assert(isRgb(40, 40, 0, 0, 255) && isRgb(150, 150, 0, 0, 0));
  cv.restore();
  cv.fillStyle(blue);
  cv.fill(full);
  assert(isRgb(150, 150, 0, 0, 255) && isRgb(5, 5, 0, 0, 255));

  // a nested pass while the outer pass has clips
  r.clearFrame(black);
  r.beginTarget(rt, true);
  cv.save();
  cv.clip(small);
  r.beginTarget(rt2, true);
  nested();
  r.endTarget();
  cv.fillStyle(green);
  cv.fill(full);
  assert(isRgb(10, 10, 0, 255, 0) && isRgb(100, 100, 0, 0, 0));
  cv.restore();
  r.endTarget();

  // save; clip; fill; restore does not grow the GC heap
  void clipLoop() {
    cv.save();
    cv.clip(small);
    cv.fill(full);
    cv.restore();
  }

  r.clearFrame(black);
  clipLoop();
  clipLoop();
  GC.collect();
  auto before = GC.stats();
  foreach (_; 0 .. 100) {
    clipLoop();
  }
  auto after = GC.stats();
  assert(after.allocatedInCurrentThread == before.allocatedInCurrentThread);
  assert(
    after.usedSize + after.freeSize <= before.usedSize + before.freeSize
  );

  // repeated target passes (with Canvas and Renderer clips inside) do
  // not grow the GC heap either
  void targetPass() {
    cv.save();
    cv.clip(outer);
    r.beginTarget(rt, false);
    r.pushClipRect(RectF(0, 0, 50, 50));
    clipLoop();
    r.popClipRect();
    r.endTarget();
    cv.restore();
  }

  targetPass();
  targetPass();
  GC.collect();
  before = GC.stats();
  foreach (_; 0 .. 50) {
    targetPass();
  }
  after = GC.stats();
  assert(after.allocatedInCurrentThread == before.allocatedInCurrentThread);
  assert(
    after.usedSize + after.freeSize <= before.usedSize + before.freeSize
  );
  assert(glGetError() == GL_NO_ERROR);
}

// arcTo on an empty path draws no cap dot; textAlign center uses the
// measureText advance (identity and scaled transforms)
unittest {
  auto w = GlTestWindow("test_canvas_arcto_text_align");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto r = w.renderer();
  auto cv = w.canvas();
  const black = ColorF(0, 0, 0, 1);
  const white = FillStyle.solid(ColorF(1, 1, 1, 1));

  // arcTo without a current point only moves: nothing to stroke
  r.clearFrame(black);
  auto p = new Path2d();
  p.arcTo(PointF(100, 100), PointF(200, 150), 20);
  cv.strokeStyle(white);
  cv.lineWidth(20);
  cv.lineCap(LineCap.round);
  cv.stroke(p);
  assert(frameBounds(0).empty);
  // a following lineTo strokes from p1
  p.lineTo(PointF(150, 100));
  cv.stroke(p);
  const line = frameBounds(0);
  assert(!line.empty && line.x0 >= 88 && line.x0 <= 92);

  // the centered text box is the left-aligned one shifted by half the
  // advance width: the right-aligned shift, which equals the measureText
  // width under the same transform (both rasterize the font at that
  // scale, so their hinted advances agree).
  void checkCenter(float scale) {
    auto drawAt(TextAlign a) {
      r.clearFrame(black);
      cv.fontSpec = FontSpec(24, null);
      cv.textBaseline = TextBaseline.top;
      cv.textAlign(a);
      cv.fillStyle(white);
      cv.save();
      cv.scale(PointF(scale, scale));
      cv.fillText("Hello", PointF(160 / scale, 60 / scale));
      cv.restore();
      return frameBounds(0);
    }

    import std.math : abs;

    const left = drawAt(TextAlign.left);
    const center = drawAt(TextAlign.center);
    const right = drawAt(TextAlign.right);
    assert(!left.empty && !center.empty && !right.empty);
    cv.fontSpec = FontSpec(24, null);
    cv.save();
    cv.scale(PointF(scale, scale));
    const float measured = cv.measureText("Hello").width * scale;
    cv.restore();
    const float advance = left.x0 - right.x0;
    const float half = measured / 2;
    assert(abs(advance - measured) <= 1);
    const float dx0 = center.x0 - (left.x0 - half);
    const float dx1 = center.x1 - (left.x1 - half);
    assert(abs(dx0) <= 1 && abs(dx1) <= 1);
  }

  checkCenter(1.0f);
  checkCenter(1.5f);
  assert(glGetError() == GL_NO_ERROR);
}

// GL state caches: VBO growth then sub-data uploads, the program and
// gradient stop caches, and the shadow box limited by the scissor clip
unittest {
  import std.math : PI, abs, cos, sin;
  import yguilib.render.render_target : RenderTarget;

  auto w = GlTestWindow("test_canvas_gl_state_cache");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto r = w.renderer();
  auto cv = w.canvas();

  const black = ColorF(0, 0, 0, 1);
  const red = ColorF(1, 0, 0, 1);
  const blue = ColorF(0, 0, 1, 1);
  const green = FillStyle.solid(ColorF(0, 1, 0, 1));

  // 1. a large path grows the VBO, a small one then fits (sub-data)
  auto circle = new Path2d();
  enum int segs = 3000;
  foreach (k; 0 .. segs) {
    const float a = cast(float)(2 * PI * k / segs);
    const PointF pt = PointF(160 + 80 * cos(a), 120 + 80 * sin(a));
    if (k == 0) {
      circle.moveTo(pt);
    } else {
      circle.lineTo(pt);
    }
  }
  circle.closePath();
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.fill(circle);
  const size_t grown = r.colorPipelineRef().mesh.va.capacity;
  assert(grown >= segs * 3 * 2 * float.sizeof);
  assert(isRgb(160, 120, 0, 255, 0));
  assert(isRgb(160, 50, 0, 255, 0));
  assert(isRgb(160, 30, 0, 0, 0));
  assert(isRgb(10, 10, 0, 0, 0));
  r.clearFrame(black); // resets the fill style too
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(20, 20, 30, 30)));
  assert(r.colorPipelineRef().mesh.va.capacity == grown);
  assert(isRgb(35, 35, 0, 255, 0));
  assert(isRgb(160, 120, 0, 0, 0));
  assert(isRgb(60, 35, 0, 0, 0));

  // the tracked program is the GL program
  GLint prog = -1;
  glGetIntegerv(GL_CURRENT_PROGRAM, &prog);
  assert(cast(GLuint)prog == r.programTrackerRef().current());

  // 2. gradient, solid, the same gradient, another one, the first again
  LinearGradient rb;
  rb.p0 = PointF(0, 0);
  rb.p1 = PointF(200, 0);
  rb.addColorStop(0, red).addColorStop(1, blue);
  LinearGradient gr;
  gr.p0 = PointF(0, 0);
  gr.p1 = PointF(200, 0);
  gr.addColorStop(0, ColorF(0, 1, 0, 1)).addColorStop(1, red);
  void fillRb() {
    r.clearFrame(black);
    cv.fillStyle(FillStyle.fromLinear(rb));
    cv.fill(rectPath(RectF(0, 0, 200, 50)));
    assert(near(10, 25, 242, 0, 13, 6));
    assert(near(190, 25, 13, 0, 242, 6));
  }
  fillRb();
  r.clearFrame(black);
  cv.fillStyle(green);
  cv.fill(rectPath(RectF(0, 0, 200, 50)));
  assert(isRgb(100, 25, 0, 255, 0));
  fillRb();
  r.clearFrame(black);
  cv.fillStyle(FillStyle.fromLinear(gr));
  cv.fill(rectPath(RectF(0, 0, 200, 50)));
  assert(near(10, 25, 13, 242, 0, 6));
  assert(near(190, 25, 242, 13, 0, 6));
  fillRb();
  // a target pass starts a new epoch: the stops are uploaded again
  const uint epoch = r.programTrackerRef().epoch();
  RenderTarget rt = r.createRenderTarget(40, 30, false);
  assert(rt !is null);
  scope(exit) rt.destroy();
  scope(exit) w.endTargets();
  r.beginTarget(rt, true);
  cv.fillStyle(FillStyle.fromLinear(gr));
  cv.fill(rectPath(RectF(0, 0, 40, 30)));
  r.endTarget();
  assert(r.programTrackerRef().epoch() != epoch);
  fillRb();
  assert(r.gradientPipelineRef().locs.stopsEpoch()
    == r.programTrackerRef().epoch());

  // 3. a blurred shadow inside a scissor clip: same pixels as unclipped
  // in the visible area, nothing outside, a smaller mask box
  Shadow soft;
  soft.blur = 8;
  soft.offset = PointF(5, 5);
  soft.color = red;
  const RectF shape = RectF(40, 60, 200, 100);
  const RectF clip = RectF(150, 0, 60, 240);
  r.offscreenTargetRef(0).destroy();
  r.offscreenTargetRef(1).destroy();
  r.clearFrame(black);
  r.pushClipRect(clip);
  cv.shadow(soft);
  cv.fillStyle(green);
  cv.fill(rectPath(shape));
  cv.shadow(Shadow.init);
  r.popClipRect();
  const int clippedWidth = r.offscreenTargetRef(0).width;
  const ubyte[] clipped = grabFrame();
  r.offscreenTargetRef(0).destroy();
  r.offscreenTargetRef(1).destroy();
  r.clearFrame(black);
  cv.shadow(soft);
  cv.fillStyle(green);
  cv.fill(rectPath(shape));
  cv.shadow(Shadow.init);
  const int fullWidth = r.offscreenTargetRef(0).width;
  const ubyte[] full = grabFrame();
  // box: shape 200 wide + 2 * pad (13) vs visible 60 + 2 * pad
  assert(fullWidth >= 226 && clippedWidth < 100);
  // the blurred edge below the shape is lit in the visible area
  assert(channelAt(full, 180, 165, 0) > 60);
  foreach (y; 0 .. testHeight) {
    foreach (x; 0 .. testWidth) {
      const bool inside = x >= 150 && x < 210;
      foreach (c; 0 .. 3) {
        const int a = channelAt(clipped, x, y, c);
        if (inside) {
          assert(abs(a - channelAt(full, x, y, c)) <= 1);
        } else {
          assert(a == 0);
        }
      }
    }
  }
  // an empty visible area skips the shadow pass (no target allocated)
  r.offscreenTargetRef(0).destroy();
  r.clearFrame(black);
  r.pushClipRect(RectF(400, 0, 10, 10));
  cv.shadow(soft);
  cv.fillStyle(green);
  cv.fill(rectPath(shape));
  cv.shadow(Shadow.init);
  r.popClipRect();
  assert(r.offscreenTargetRef(0).fbo == 0);

  assert(glGetError() == GL_NO_ERROR);
}

// Convex fill fast path (review 3.3): fan drawn once, no stencil
unittest {
  import std.math : PI, cos, sin;

  auto w = GlTestWindow("test_canvas_convex");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto r = w.renderer();
  auto cv = w.canvas();
  const black = ColorF(0, 0, 0, 1);
  const half = FillStyle.solid(ColorF(1, 1, 1, 0.5f));

  // no pixel is blended twice (> ~128) and at least `minFull` are fully
  // covered; the window may be multisampled, so curved or slanted edges
  // can be partly covered (`exact` false). With `exact` (pixel-aligned
  // edges) every pixel is 0 or ~128.
  void assertSingleBlend(int minFull, bool exact) {
    const ubyte[] buf = grabFrame();
    int full = 0;
    foreach (y; 0 .. testHeight) {
      foreach (x; 0 .. testWidth) {
        const int v = channelAt(buf, x, y, 0);
        const bool once = v >= 126 && v <= 129;
        assert(v <= 129 && (!exact || v == 0 || once));
        full += once ? 1 : 0;
      }
    }
    assert(full >= minFull);
  }

  auto circle = new Path2d();
  circle.arc(PointF(160, 120), 60, 0, cast(float)(2 * PI), false);
  circle.closePath();
  auto rr = new Path2d();
  rr.roundRect(RectF(30, 40, 250, 150), 30);
  Path2d[3] shapes = [rectPath(RectF(20, 30, 200, 120)), circle, rr];
  foreach (rule; [FillRule.nonZero, FillRule.evenOdd]) {
    foreach (i, shape; shapes) {
      r.clearFrame(black);
      cv.fillRule(rule);
      cv.fillStyle(half);
      const before = cv.pathStats();
      cv.fill(shape);
      const after = cv.pathStats();
      assert(after.convexFills == before.convexFills + 1);
      assert(after.stencilFills == before.stencilFills);
      // the rect has pixel-aligned edges
      assertSingleBlend(10_000, i == 0);
    }
  }
  // a transformed rect stays convex
  r.clearFrame(black);
  cv.fillStyle(half);
  cv.translate(PointF(160, 120));
  cv.rotate(0.3f);
  cv.scale(PointF(-1.5f, 1));
  const s0 = cv.pathStats();
  cv.fill(rectPath(RectF(-40, -30, 80, 60)));
  assert(cv.pathStats().convexFills == s0.convexFills + 1);
  assertSingleBlend(4000, false);
  assert(near(160, 120, 128, 128, 128, 1));

  // the concave star uses the stencil path and is still correct
  auto star = new Path2d();
  foreach (k; 0 .. 5) {
    const float a = cast(float)(-PI / 2 + k * 4 * PI / 5);
    const PointF pt = PointF(160 + 80 * cos(a), 120 + 80 * sin(a));
    if (k == 0) {
      star.moveTo(pt);
    } else {
      star.lineTo(pt);
    }
  }
  star.closePath();
  r.clearFrame(black);
  cv.fillStyle(half);
  const s1 = cv.pathStats();
  cv.fill(star);
  assert(cv.pathStats().stencilFills == s1.stencilFills + 1);
  assert(cv.pathStats().convexFills == s1.convexFills);
  assertSingleBlend(1000, false);
  assert(near(160, 120, 128, 128, 128, 1));
  r.clearFrame(black);
  cv.fillStyle(half);
  cv.fillRule(FillRule.evenOdd);
  cv.fill(star);
  assert(isRgb(160, 120, 0, 0, 0));
  assert(near(160, 60, 128, 128, 128, 1));
  cv.fillRule(FillRule.nonZero);

  // a Canvas clip forces the stencil path
  r.clearFrame(black);
  cv.fillStyle(half);
  cv.save();
  cv.clip(rectPath(RectF(0, 0, 100, 240)));
  const s2 = cv.pathStats();
  cv.fill(rectPath(RectF(50, 50, 100, 100)));
  cv.restore();
  assert(cv.pathStats().stencilFills == s2.stencilFills + 1);
  assert(near(75, 100, 128, 128, 128, 1));
  assert(isRgb(125, 100, 0, 0, 0));

  // with a shadow, the shape still blends once over the shadow
  r.clearFrame(black);
  Shadow sh;
  sh.offset = PointF(100, 0);
  sh.color = ColorF(0, 0, 1, 1);
  cv.shadow(sh);
  cv.fillStyle(half);
  cv.fill(rectPath(RectF(20, 20, 60, 60)));
  cv.shadow(Shadow.init);
  assert(near(50, 50, 128, 128, 128, 1));
  assert(near(150, 50, 0, 0, 128, 1));
  assert(glGetError() == GL_NO_ERROR);
}

// clearRect as a scissored glClear (review 3.3)
unittest {
  auto w = GlTestWindow("test_canvas_clear_rect");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto r = w.renderer();
  auto cv = w.canvas();
  const green = ColorF(0, 1, 0, 1);
  auto all = rectPath(RectF(0, 0, 320, 240));

  // clearRect(rc) under translate(dy) * scale(2, 1.5), optionally under a
  // Canvas clip of the whole viewport
  void clearScaled(RectF rc, float dy, bool viaClip) {
    r.clearFrame(green);
    cv.save();
    if (viaClip) {
      cv.clip(all);
    }
    cv.translate(PointF(10, dy));
    cv.scale(PointF(2, 1.5f));
    cv.clearRect(rc);
    cv.restore();
  }

  // fractional edges: rows whose centers are in [27.7, 42.7), cols
  // [20, 60)
  const s0 = cv.pathStats();
  clearScaled(RectF(5, 5, 20, 10), 20.2f, false);
  const s1 = cv.pathStats();
  assert(s1.scissorClears == s0.scissorClears + 1);
  assert(s1.stencilFills == s0.stencilFills);
  assert(nearPixel(readAt(20, 28), 0, 0, 0, 0));
  assert(nearPixel(readAt(59, 42), 0, 0, 0, 0));
  assert(nearPixel(readAt(19, 30), 0, 255, 0, 0));
  assert(nearPixel(readAt(60, 30), 0, 255, 0, 0));
  assert(nearPixel(readAt(30, 27), 0, 255, 0, 0));
  assert(nearPixel(readAt(30, 43), 0, 255, 0, 0));
  assert(readAt(30, 35)[3] == 0);

  // a Canvas clip takes the stencil path: the same pixels (pixel-aligned
  // edges, as the window may be multisampled: rows 29..43)
  const RectF aligned = RectF(5, 6, 20, 10);
  clearScaled(aligned, 20, false);
  const ubyte[] fast = grabFrame();
  assert(nearPixel(readAt(20, 29), 0, 0, 0, 0));
  assert(nearPixel(readAt(20, 44), 0, 255, 0, 0));
  const s1b = cv.pathStats();
  clearScaled(aligned, 20, true);
  const s2 = cv.pathStats();
  assert(s2.scissorClears == s1b.scissorClears);
  assert(s2.stencilFills == s1b.stencilFills + 1);
  assert(grabFrame() == fast);

  // mirrored scale: same rect from the other side
  r.clearFrame(green);
  cv.translate(PointF(100, 0));
  cv.scale(PointF(-1, 1));
  cv.clearRect(RectF(10, 10, 20, 20)); // -> x 70..90
  cv.resetTransform();
  assert(cv.pathStats().scissorClears == s2.scissorClears + 1);
  assert(nearPixel(readAt(70, 10), 0, 0, 0, 0));
  assert(nearPixel(readAt(89, 29), 0, 0, 0, 0));
  assert(nearPixel(readAt(69, 20), 0, 255, 0, 0));
  assert(nearPixel(readAt(90, 20), 0, 255, 0, 0));

  // rotation takes the stencil path
  r.clearFrame(green);
  cv.translate(PointF(160, 120));
  cv.rotate(0.5f);
  const s3 = cv.pathStats();
  cv.clearRect(RectF(-20, -20, 40, 40));
  cv.resetTransform();
  assert(cv.pathStats().stencilFills == s3.stencilFills + 1);
  assert(cv.pathStats().scissorClears == s3.scissorClears);
  assert(nearPixel(readAt(160, 120), 0, 0, 0, 0));
  assert(nearPixel(readAt(160, 90), 0, 255, 0, 0));

  // the Renderer scissor limits the clear and is restored afterwards
  r.clearFrame(green);
  r.pushClipRect(RectF(0, 0, 40, 240));
  cv.clearRect(RectF(20, 20, 40, 20));
  assert(nearPixel(readAt(25, 30), 0, 0, 0, 0));
  assert(nearPixel(readAt(45, 30), 0, 255, 0, 0));
  r.drawFillRect(RectF(0, 100, 320, 10), ColorF(1, 0, 0, 1));
  r.popClipRect();
  assert(nearPixel(readAt(20, 105), 255, 0, 0, 0));
  assert(nearPixel(readAt(60, 105), 0, 255, 0, 0));
  // no scissor left behind
  r.drawFillRect(RectF(0, 200, 320, 10), ColorF(1, 0, 0, 1));
  assert(nearPixel(readAt(300, 205), 255, 0, 0, 0));
  // inside a render target (tracked state checked by targetState)
  auto rt = r.createRenderTarget(32, 32, false);
  assert(rt !is null);
  scope(exit) rt.destroy();
  scope(exit) w.endTargets();
  r.beginTarget(rt, false);
  r.clearFrame(green);
  cv.clearRect(RectF(0, 0, 16, 32));
  assert(nearPixel(readAt(4, 4), 0, 0, 0, 0));
  r.endTarget();
  assert(glGetError() == GL_NO_ERROR);
}

// glyph atlas: a rotated glyph shows no neighbouring atlas content; a
// multi-glyph gradient fill with a shadow shadows every glyph; direction
// and maxWidth anchor through the glyph path
unittest {
  import std.math : PI, abs, cos, sin;

  auto w = GlTestWindow("test_canvas_text_atlas");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto r = w.renderer();
  auto cv = w.canvas();

  const black = ColorF(0, 0, 0, 1);
  const white = FillStyle.solid(ColorF(1, 1, 1, 1));
  void clear() {
    r.clearFrame(black);
    cv.fontSpec = FontSpec(48, null);
    cv.textBaseline = TextBaseline.top;
  }

  // 1. "W" cached first, then a rotated "I": lit pixels stay near the
  // rotated I box (checked in the glyph's unrotated frame)
  clear();
  cv.fillStyle(white);
  cv.fillText("W", PointF(40, 50));
  clear();
  cv.fillStyle(white);
  cv.fillText("I", PointF(150, 80));
  const ib = frameBounds(0);
  assert(!ib.empty);
  const float cx = 0.5f * (ib.x0 + ib.x1 + 1);
  const float cy = 0.5f * (ib.y0 + ib.y1 + 1);
  const float ang = cast(float)(PI / 6);
  clear();
  cv.fillStyle(white);
  cv.save();
  cv.translate(PointF(cx, cy));
  cv.rotate(ang);
  cv.translate(PointF(-cx, -cy));
  cv.fillText("I", PointF(150, 80));
  cv.restore();
  const buf = grabFrame();
  int lit;
  foreach (y; 0 .. testHeight) {
    foreach (x; 0 .. testWidth) {
      if (channelAt(buf, x, y, 0) <= 20) {
        continue;
      }
      lit++;
      const float dx = x + 0.5f - cx;
      const float dy = y + 0.5f - cy;
      const float ux = dx * cos(ang) + dy * sin(ang);
      const float uy = -dx * sin(ang) + dy * cos(ang);
      assert(abs(ux) <= 0.5f * (ib.x1 - ib.x0 + 1) + 3);
      assert(abs(uy) <= 0.5f * (ib.y1 - ib.y0 + 1) + 3);
    }
  }
  assert(lit > 20);

  // 2. several glyphs, gradient fill and shadow in one call
  int runs(int ch) {
    const b = grabFrame();
    int n;
    bool inRun;
    foreach (x; 0 .. testWidth) {
      bool any;
      foreach (y; 0 .. testHeight) {
        any = any || channelAt(b, x, y, ch) > 60;
      }
      n += (any && !inRun) ? 1 : 0;
      inRun = any;
    }
    return n;
  }

  clear();
  LinearGradient lg;
  lg.p0 = PointF(20, 0);
  lg.p1 = PointF(140, 0);
  lg.stops.add(0, ColorF(1, 0, 0, 1));
  lg.stops.add(1, ColorF(0, 0, 1, 1));
  cv.fillStyle(FillStyle.fromLinear(lg));
  Shadow sh;
  sh.offset = PointF(0, 100);
  sh.color = ColorF(0, 1, 0, 1);
  cv.shadow(sh);
  cv.fillText("I I I", PointF(20, 20));
  cv.shadow(Shadow.init);
  assert(runs(1) == 3);
  const gs = frameBounds(1);
  const fill = frameBounds(0);
  const fillB = frameBounds(2);
  assert(!gs.empty && !fill.empty && !fillB.empty);
  assert(gs.y0 >= fill.y0 + 95);
  assert(abs(gs.x0 - fill.x0) <= 2 && abs(gs.x1 - fillB.x1) <= 2);

  // 3. direction: rtl start aligns to the right edge, like end in ltr
  clear();
  cv.fillStyle(white);
  cv.textAlign(TextAlign.start);
  cv.direction = TextDirection.rtl;
  cv.fillText("Hello", PointF(200, 50));
  const rtl = frameBounds(0);
  clear();
  cv.fillStyle(white);
  cv.textAlign(TextAlign.end);
  cv.direction = TextDirection.ltr;
  cv.fillText("Hello", PointF(200, 50));
  const ltrEnd = frameBounds(0);
  assert(!rtl.empty && rtl == ltrEnd && rtl.x1 <= 202);
  cv.direction = TextDirection.ltr;
  cv.textAlign(TextAlign.start);

  // 4. maxWidth squeezes all glyph quads about the anchor
  clear();
  cv.fillStyle(white);
  cv.fillText("Hello", PointF(40, 50));
  const full = frameBounds(0);
  clear();
  cv.fillStyle(white);
  cv.fillTextWithMaxWidth("Hello", PointF(40, 50), 40);
  const sq = frameBounds(0);
  assert(abs(sq.y0 - full.y0) <= 1 && abs(sq.y1 - full.y1) <= 1);
  assert(sq.y0 == full.y0 && sq.y1 == full.y1);
  assert(glGetError() == GL_NO_ERROR);
}

// Path2d.fromSvgPath GL rendering (cubic curve + SVG arc, fill + stroke)
unittest {
  auto w = GlTestWindow("test_canvas_svg_path");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto r = w.renderer();
  auto cv = w.canvas();

  const black = ColorF(0, 0, 0, 1);
  auto shape = Path2d.fromSvgPath(
    "M 60 120 C 60 60, 140 60, 140 120 "
    ~ "A 60 60 0 0 1 260 120 L 260 200 L 60 200 Z"
  );
  assert(!shape.isEmpty());

  r.clearFrame(black);
  cv.fillStyle(FillStyle.solidFromString("#2b3140"));
  cv.strokeStyle(StrokeStyle.solidFromString("#ef4444"));
  cv.lineWidth(6);
  cv.fill(shape);
  cv.stroke(shape);

  // Fill interior (#2b3140 -> 43, 49, 64)
  assert(isRgb(100, 100, 43, 49, 64));
  assert(isRgb(200, 90, 43, 49, 64));
  assert(isRgb(160, 160, 43, 49, 64));
  // Stroke on cubic peak (100, 75), arc peak (200, 60), bottom (160, 200)
  assert(isRgb(100, 75, 239, 68, 68));
  assert(isRgb(200, 60, 239, 68, 68));
  assert(isRgb(160, 200, 239, 68, 68));
  // Outside background
  assert(isRgb(20, 20, 0, 0, 0));
  assert(isRgb(100, 50, 0, 0, 0));
  assert(isRgb(200, 40, 0, 0, 0));
  assert(glGetError() == GL_NO_ERROR);
}
