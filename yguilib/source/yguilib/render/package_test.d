/**
 * Renderer GL tests: primitives, scaling, clipping, fonts, text batching,
 * textures and edge cases, drawn in a hidden `GlTestWindow`.
 */
module yguilib.render.package_test;

version (unittest):

import glad2.gles2;
import yguilib.assets : defaultTtfFontData;
import yguilib.events : AppEvent;
import yguilib.render;
import yguilib.render.font : Font, defaultFontPtSize;
import yguilib.render.font_manager : FontManager;
import yguilib.render.image : Image;
import yguilib.render.internal.gl_test_util : GlTestWindow, nearPixel,
  nearPixelRgba, readAt;
import yguilib.render.internal.gl_util : deleteTexture, uploadRgbaTexture;
import yguilib.render.internal.offscreen : OffscreenTarget, SavedTargetState;
import yguilib.render.internal.text_cache : TextRunCache;
import yguilib.render.render_target : RenderTarget;
import yguilib.render.render_types;
import yguilib.render.texture : BorrowedTextureInfo, Texture;

unittest {
  auto w = GlTestWindow("test_renderer");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();
  auto win = w.window();

  auto renderer = w.renderer();
  assert(renderer !is null);

  assert(renderer.viewportWidth() == 320);
  assert(renderer.viewportHeight() == 240);
  assert(renderer.isOnScreen(RectF(10, 10, 100, 100)));
  assert(!renderer.isOnScreen(RectF(700, 10, 100, 100)));

  // 1. Clear canvas red
  renderer.clearFrame(ColorF(1.0f, 0.0f, 0.0f, 1.0f));
  ubyte[4] pixel = readAt(160, 120);
  assert(pixel[0] == 255 && pixel[1] == 0 && pixel[2] == 0 && pixel[3] == 255);

  // 2. Draw filled rect green at (10, 10, 30, 30)
  renderer.drawFillRect(RectF(10, 10, 30, 30), ColorF(0.0f, 1.0f, 0.0f, 1.0f));
  pixel = readAt(20, 20);
  assert(pixel[0] == 0 && pixel[1] == 255 && pixel[2] == 0 && pixel[3] == 255);
  pixel = readAt(100, 100);
  assert(pixel[0] == 255 && pixel[1] == 0 && pixel[2] == 0 && pixel[3] == 255);

  // 3. Alpha blending: draw 50% white over black canvas
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawFillRect(
    RectF(0, 0, 320, 240),
    ColorF(1.0f, 1.0f, 1.0f, 0.5f)
  );
  pixel = readAt(160, 120);
  assert(pixel[0] >= 126 && pixel[0] <= 129);
  assert(pixel[1] >= 126 && pixel[1] <= 129);
  assert(pixel[2] >= 126 && pixel[2] <= 129);

  // 4. Clipping rectangle
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.pushClipRect(RectF(50, 50, 50, 50));
  renderer.drawFillRect(
    RectF(0, 0, 320, 240),
    ColorF(0.0f, 0.0f, 1.0f, 1.0f)
  );
  renderer.popClipRect();

  pixel = readAt(60, 60);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 255 && pixel[3] == 255);
  pixel = readAt(10, 10);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0 && pixel[3] == 255);

  // 5. Draw line and outline rect
  renderer.drawThinLineWithPoints(
    PointF(0.0f, 0.0f),
    PointF(319.0f, 239.0f),
    ColorF(1.0f, 1.0f, 0.0f, 1.0f)
  );
  renderer.drawRect(
    RectF(150, 100, 40, 40),
    ColorF(0.0f, 1.0f, 1.0f, 1.0f)
  );

  assert(glGetError() == GL_NO_ERROR);

  // 6. Test units scaling and pixel conversions
  assert(renderer.defaultScaling() == 1.0f);
  assert(renderer.displayScaling() == 1.0f);
  assert(renderer.unitsScaling() == 1.0f);
  assert(renderer.pixelsFromLogicFloat(10.0f) == 10.0f);
  assert(renderer.logicFromPixelsFloat(10.0f) == 10.0f);

  renderer.unitsScaling(2.0f);
  assert(renderer.unitsScaling() == 2.0f);
  assert(renderer.pixelsFromLogicFloat(10.0f) == 20.0f);
  assert(renderer.logicFromPixelsFloat(20.0f) == 10.0f);
  assert(renderer.pixelsFromLogicFloat(15.0f) == 30.0f);
  assert(renderer.logicFromPixelsFloat(30.0f) == 15.0f);

  PointF lp = PointF(10.0f, 20.0f);
  PointF pp = renderer.pixelsFromLogicPoint(lp);
  assert(pp.x == 20.0f && pp.y == 40.0f);
  PointF backLp = renderer.logicFromPixelsPoint(pp);
  assert(backLp.x == 10.0f && backLp.y == 20.0f);

  RectF lr = RectF(5.0f, 10.0f, 50.0f, 60.0f);
  RectF pr = renderer.pixelsFromLogicRect(lr);
  assert(
    pr.x == 10.0f && pr.y == 20.0f &&
    pr.width == 100.0f && pr.height == 120.0f
  );
  RectF backLr = renderer.logicFromPixelsRect(pr);
  assert(
    backLr.x == 5.0f && backLr.y == 10.0f &&
    backLr.width == 50.0f && backLr.height == 60.0f
  );

  assert(renderer.pixelWidth() == 320);
  assert(renderer.pixelHeight() == 240);
  assert(renderer.viewportWidth() == 160);
  assert(renderer.viewportHeight() == 120);

  // Combined scaling: displayScaling = 2.0f, unitsScaling = 1.5f
  // (effective scale = 3.0f)
  renderer.displayScaling(2.0f);
  renderer.unitsScaling(1.5f);
  assert(renderer.displayScaling() == 2.0f);
  assert(renderer.unitsScaling() == 1.5f);
  assert(renderer.pixelsFromLogicFloat(10.0f) == 30.0f);
  assert(renderer.logicFromPixelsFloat(30.0f) == 10.0f);
  assert(renderer.viewportWidth() == 106);
  assert(renderer.viewportHeight() == 80);

  // 7. Test coordinatesFromEvent
  // Case A: 200% display scale, zoom = 1.0 (1:1 window points to logic)
  renderer.displayScaling(2.0f);
  renderer.unitsScaling(1.0f);
  assert(renderer.defaultScaling() == 2.0f);
  assert(renderer.unitsScaling() == 1.0f);

  AppEvent evMotion = AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(win.id, 100.0f, 50.0f)
  );
  PointF converted = renderer.coordinatesFromEvent(evMotion);
  assert(converted.x == 100.0f);
  assert(converted.y == 50.0f);

  PointF fromFloat = renderer.coordinatesFromCoords(100.0f, 50.0f);
  assert(fromFloat.x == 100.0f);
  assert(fromFloat.y == 50.0f);

  // Case B: 200% display scale, zoom = 2.0 (logic coords halved)
  renderer.unitsScaling(2.0f);
  converted = renderer.coordinatesFromEvent(evMotion);
  assert(converted.x == 50.0f);
  assert(converted.y == 25.0f);

  // Case C: 100% display scale, zoom = 0.5 (logic coords doubled)
  renderer.displayScaling(1.0f);
  renderer.unitsScaling(0.5f);
  converted = renderer.coordinatesFromEvent(evMotion);
  assert(converted.x == 200.0f);
  assert(converted.y == 100.0f);

  // 8. Scaled drawing test: unitsScaling = 2.0
  renderer.displayScaling(1.0f);
  renderer.unitsScaling(2.0f);
  // Drawing rect (0, 0, 160, 120) logic units covers all 320x240 pixels.
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawFillRect(
    RectF(0.0f, 0.0f, 160.0f, 120.0f),
    ColorF(0.0f, 1.0f, 0.0f, 1.0f)
  );
  pixel = readAt(160, 120);
  assert(pixel[0] == 0 && pixel[1] == 255 && pixel[2] == 0 && pixel[3] == 255);
  pixel = readAt(318, 1);
  assert(pixel[0] == 0 && pixel[1] == 255 && pixel[2] == 0 && pixel[3] == 255);

  // 9. Font loading, metrics, text measurement, and rendering tests
  renderer.unitsScaling(1.0f);
  renderer.displayScaling(1.0f);

  Font customFont = Font.fromMemory(
    cast(const(void)[])defaultTtfFontData,
    16.0f,
    1.0f
  );
  scope(exit) customFont.destroy();

  assert(customFont.size == 16.0f);
  assert(customFont.height > 0);
  assert(customFont.ascent > 0);
  assert(customFont.lineSkip > 0);

  PointF mEmpty = renderer.measureTextWithFont("", customFont);
  assert(mEmpty.x == 0.0f && mEmpty.y == 0.0f);

  PointF mShort = renderer.measureTextWithFont("Hi", customFont);
  assert(mShort.x > 0.0f && mShort.y > 0.0f);

  PointF mLong = renderer.measureTextWithFont("Hello World!", customFont);
  assert(mLong.x > mShort.x);

  PointF mBySize = renderer.measureTextWithFontName("Hi", 16.0f, null);
  assert(mBySize.x == mShort.x && mBySize.y == mShort.y);

  // Render text blended in white on black background
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawTextWithFont(
    "ABC",
    PointF(20.0f, 30.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f),
    customFont
  );
  renderer.flush();

  import std.algorithm : min;

  int litCount = 0;
  int checkW = min(cast(int)mLong.x, 50);
  int checkH = min(customFont.height, 30);
  foreach (x; 20 .. 20 + checkW) {
    foreach (y; 30 .. 30 + checkH) {
      pixel = readAt(x, y);
      if (pixel[0] > 100 && pixel[1] > 100 && pixel[2] > 100) {
        litCount++;
      }
    }
  }
  assert(litCount > 0);

  // Render text in green color
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawTextWithFont(
    "ABC",
    PointF(20.0f, 30.0f),
    ColorF(0.0f, 1.0f, 0.0f, 1.0f),
    customFont
  );
  renderer.flush();
  litCount = 0;
  foreach (x; 20 .. 20 + checkW) {
    foreach (y; 30 .. 30 + checkH) {
      pixel = readAt(x, y);
      if (pixel[1] > 100 && pixel[0] == 0 && pixel[2] == 0) {
        litCount++;
      }
    }
  }
  assert(litCount > 0);

  // Render using default font (embedded defaultTtfFontData)
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawTextWithFont(
    "DefaultFont",
    PointF(10.0f, 10.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f),
    null
  );
  assert(renderer.defaultFont() !is null);
  assert(renderer.defaultFont().height > 0);

  // Text clipped outside clip rect
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.pushClipRect(RectF(0.0f, 0.0f, 10.0f, 10.0f));
  renderer.drawTextWithFont(
    "Clipped",
    PointF(50.0f, 50.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f),
    customFont
  );
  renderer.popClipRect();

  // (50..80, 50..70) should have stayed black because it was clipped
  foreach (x; 50 .. 80) {
    foreach (y; 50 .. 70) {
      pixel = readAt(x, y);
      assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);
    }
  }

  // Scaled text drawing test: unitsScaling = 2.0
  renderer.displayScaling(1.0f);
  renderer.unitsScaling(2.0f);
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawTextWithFont(
    "ABC",
    PointF(10.0f, 10.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f),
    null
  );
  renderer.flush();
  litCount = 0;
  foreach (x; 20 .. 80) {
    foreach (y; 20 .. 60) {
      pixel = readAt(x, y);
      if (pixel[0] > 100 && pixel[1] > 100 && pixel[2] > 100) {
        litCount++;
      }
    }
  }
  assert(litCount > 0);
  renderer.unitsScaling(1.0f);

  // Scaled text drawing test: displayScaling = 1.5
  renderer.displayScaling(1.5f);
  renderer.unitsScaling(1.0f);
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawTextWithFont(
    "ABC",
    PointF(35.0f, 45.0f),
    ColorF(1.0f, 1.0f, 1.0f, 1.0f),
    null
  );
  renderer.flush();
  litCount = 0;
  // 35 * 1.5 = 52.5 -> snapped to 53
  // 45 * 1.5 = 67.5 -> snapped to 68
  foreach (x; 53 .. 120) {
    foreach (y; 68 .. 100) {
      pixel = readAt(x, y);
      if (pixel[0] > 100 && pixel[1] > 100 && pixel[2] > 100) {
        litCount++;
      }
    }
  }
  assert(litCount > 0);
  renderer.displayScaling(1.0f);

  // In-place dynamic resizing & unscaled user-space size tests
  Font defaultF = renderer.defaultFont();
  assert(defaultF !is null);
  assert(defaultF.size == defaultFontPtSize);
  assert(defaultF.scaledSize == defaultFontPtSize);
  int initialH = defaultF.height;

  // Scale display: defaultFont instance is preserved and resized in place
  renderer.displayScaling(2.0f);
  assert(renderer.defaultFont() is defaultF);
  assert(defaultF.size == defaultFontPtSize);
  assert(defaultF.scaledSize == defaultFontPtSize * 2.0f);
  assert(defaultF.height > initialH);

  // Scale units: defaultFont instance is preserved and resized in place
  renderer.unitsScaling(1.5f);
  assert(renderer.defaultFont() is defaultF);
  assert(defaultF.size == defaultFontPtSize);
  assert(defaultF.scaledSize == defaultFontPtSize * 3.0f);

  renderer.displayScaling(1.0f);
  renderer.unitsScaling(1.0f);
  assert(defaultF.size == defaultFontPtSize);
  assert(defaultF.scaledSize == defaultFontPtSize);

  // Factory createFont automatically applies renderer's current scaling
  renderer.displayScaling(2.0f);
  Font factoryFont = renderer.createFontFromMemory(
    cast(const(void)[])defaultTtfFontData,
    14.0f
  );
  scope(exit) factoryFont.destroy();
  assert(factoryFont.size == 14.0f);
  assert(factoryFont.scaledSize == 28.0f);
  assert(factoryFont.height > 0);

  // In-place scale() updates raster size while preserving unscaled size
  factoryFont.scale(1.0f);
  assert(factoryFont.size == 14.0f);
  assert(factoryFont.scaledSize == 14.0f);

  // A user-assigned default font is kept and resized on scaling changes
  renderer.defaultFont(factoryFont);
  renderer.unitsScaling(1.5f);
  assert(renderer.defaultFont() is factoryFont);
  assert(factoryFont.scaledSize == 14.0f * 3.0f);
  renderer.unitsScaling(1.0f);
  assert(factoryFont.scaledSize == 28.0f);
  renderer.defaultFont(null);
  assert(renderer.defaultFont() !is factoryFont);

  // A scaling change re-applies the clip scissor (rects in logic units)
  {
    renderer.pushClipRect(RectF(10, 10, 20, 20));
    scope(exit) renderer.popClipRect();
    GLint[4] sb;
    glGetIntegerv(GL_SCISSOR_BOX, sb.ptr);
    assert(sb[0] == 20 && sb[2] == 40);
    renderer.unitsScaling(1.5f);
    glGetIntegerv(GL_SCISSOR_BOX, sb.ptr);
    assert(sb[0] == 30 && sb[2] == 60);
    renderer.unitsScaling(1.0f);
  }

  // Managed fonts via font: distinct instances per size, cached on reuse
  Font f14 = renderer.font(14.0f, null);
  Font f20 = renderer.font(20.0f, null);
  assert(f14 !is null);
  assert(f20 !is null);
  assert(f14.size == 14.0f);
  assert(f20.size == 20.0f);
  assert(renderer.font(14.0f, null) is f14);
  assert(renderer.font(20.0f, null) is f20);
  assert(f14 !is f20);

  renderer.displayScaling(1.0f);
  renderer.unitsScaling(1.0f);

  assert(glGetError() == GL_NO_ERROR);

  // 10. Rounded rectangle drawing tests (fill, outline, dashed, clamping,
  // scaling)
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));

  renderer.drawFillRoundRect(
    RectF(20.0f, 20.0f, 60.0f, 40.0f),
    10.0f,
    ColorF(0.0f, 1.0f, 0.0f, 1.0f)
  );
  pixel = readAt(50, 40);
  assert(pixel[0] == 0 && pixel[1] == 255 && pixel[2] == 0 && pixel[3] == 255);
  pixel = readAt(21, 21);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);
  pixel = readAt(5, 5);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);

  // Test outline mode: draw blue outline at (100, 100, 80, 60), radius 8,
  // line width 4
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawRoundRect(
    RectF(100.0f, 100.0f, 80.0f, 60.0f),
    8.0f,
    4.0f,
    ColorF(0.0f, 0.0f, 1.0f, 1.0f)
  );
  pixel = readAt(140, 130);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);
  pixel = readAt(140, 101);
  assert(pixel[2] > 100);

  // Test dashed mode: draw dashed round rect, verify border has colored pixels
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawRoundRectDashed(
    RectF(50.0f, 50.0f, 100.0f, 60.0f),
    10.0f,
    3.0f,
    DashPattern(8.0f, 6.0f),
    ColorF(1.0f, 1.0f, 0.0f, 1.0f)
  );
  pixel = readAt(100, 80);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);
  int yellowPixels = 0;
  foreach (x; 60 .. 140) {
    pixel = readAt(x, 51);
    if (pixel[0] > 100 && pixel[1] > 100) {
      yellowPixels++;
    }
  }
  assert(yellowPixels > 0);

  // Test radius clamping: radius larger than half dimensions does not crash
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawFillRoundRect(
    RectF(10.0f, 10.0f, 40.0f, 40.0f),
    100.0f, // excess radius clamped to 20
    ColorF(1.0f, 0.0f, 0.0f, 1.0f)
  );
  pixel = readAt(30, 30);
  assert(pixel[0] == 255 && pixel[1] == 0 && pixel[2] == 0 && pixel[3] == 255);

  // Test units scaling with rounded rect
  renderer.unitsScaling(2.0f);
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  // Logic (10, 10, 50, 50) maps to screen (20, 20, 100, 100)
  renderer.drawFillRoundRect(
    RectF(10.0f, 10.0f, 50.0f, 50.0f),
    5.0f,
    ColorF(0.0f, 1.0f, 1.0f, 1.0f)
  );
  pixel = readAt(70, 70);
  assert(pixel[1] == 255 && pixel[2] == 255);
  renderer.unitsScaling(1.0f);

  // 11. drawRect with lineWidth, drawRectDashed, and small drawRoundRectDashed
  // A. drawRectWithWidth with lineWidth = 4 growing inside
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawRectWithWidth(
    RectF(100.0f, 50.0f, 60.0f, 40.0f),
    4.0f,
    ColorF(0.0f, 1.0f, 0.0f, 1.0f)
  );
  assert(readAt(99, 50)[1] == 0);
  assert(readAt(161, 50)[1] == 0);
  assert(readAt(101, 51)[1] == 255);
  assert(readAt(130, 70)[1] == 0);

  // B. drawRectDashed: rect at (50, 50, 100, 60), lw = 3,
  // dashLen = 8, gapLen = 6
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawRectDashed(
    RectF(50.0f, 50.0f, 100.0f, 60.0f),
    3.0f,
    DashPattern(8.0f, 6.0f),
    ColorF(1.0f, 1.0f, 0.0f, 1.0f)
  );
  pixel = readAt(100, 80);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);
  pixel = readAt(48, 50);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0);
  int dashedYellow = 0;
  int dashedBlack = 0;
  foreach (x; 60 .. 140) {
    pixel = readAt(x, 51);
    if (pixel[0] > 100 && pixel[1] > 100) {
      dashedYellow++;
    } else if (pixel[0] == 0 && pixel[1] == 0) {
      dashedBlack++;
    }
  }
  assert(dashedYellow > 0 && dashedBlack > 0);

  // C. Small drawRoundRectDashed: (20, 20, 30, 20), radius 4, lw 2,
  // dash 4, gap 3
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawRoundRectDashed(
    RectF(20.0f, 20.0f, 30.0f, 20.0f),
    4.0f,
    2.0f,
    DashPattern(4.0f, 3.0f),
    ColorF(0.0f, 0.0f, 1.0f, 1.0f)
  );
  assert(readAt(35, 30)[2] == 0);
  int smallBlue = 0;
  foreach (x; 20 .. 50) {
    pixel = readAt(x, 21);
    if (pixel[2] > 100) {
      smallBlue++;
    }
  }
  assert(smallBlue > 0);

  // 12. drawLine* variants: thick solid line and dashed line
  // A. Solid thick line: horizontal from (50, 100) to (150, 100), width = 6
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawLineWithPoints(
    PointF(50.0f, 100.0f),
    PointF(150.0f, 100.0f),
    6.0f,
    ColorF(1.0f, 0.0f, 0.0f, 1.0f)
  );
  pixel = readAt(100, 100);
  assert(pixel[0] == 255 && pixel[1] == 0 && pixel[2] == 0);
  assert(readAt(100, 98)[0] == 255);
  assert(readAt(100, 102)[0] == 255);
  assert(readAt(100, 95)[0] == 0);
  assert(readAt(100, 105)[0] == 0);
  assert(readAt(45, 100)[0] == 0);
  assert(readAt(155, 100)[0] == 0);

  // B. Dashed line: (50, 150) to (200, 150), width = 4, dash = 10, gap = 10
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawLineDashed(
    PointF(50.0f, 150.0f),
    PointF(200.0f, 150.0f),
    4.0f,
    DashPattern(10.0f, 10.0f),
    ColorF(0.0f, 1.0f, 0.0f, 1.0f)
  );
  assert(readAt(55, 150)[1] == 255);
  assert(readAt(65, 150)[1] == 0);
  assert(readAt(75, 150)[1] == 255);

  // C. drawLineDashed alias
  renderer.clearFrame(ColorF(0.0f, 0.0f, 0.0f, 1.0f));
  renderer.drawLineDashed(
    PointF(50.0f, 150.0f),
    PointF(200.0f, 150.0f),
    4.0f,
    DashPattern(10.0f, 10.0f),
    ColorF(0.0f, 0.0f, 1.0f, 1.0f)
  );
  assert(readAt(55, 150)[2] == 255);
  assert(readAt(65, 150)[2] == 0);

  // D. Degenerate and zero/negative width edge cases
  renderer.drawLineWithPoints(
    PointF(10, 10), PointF(10, 10), 5.0f, ColorF(1, 1, 1, 1)
  );
  renderer.drawLineWithPoints(
    PointF(10, 10), PointF(50, 50), 0.0f, ColorF(1, 1, 1, 1)
  );
  renderer.drawLineWithPoints(
    PointF(10, 10), PointF(50, 50), -2.0f, ColorF(1, 1, 1, 1)
  );

  assert(glGetError() == GL_NO_ERROR);
}

// Verifies createTexture, drawImage, drawImageRegion, tint and update.
unittest {
  auto w = GlTestWindow("test_renderer_image");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  auto renderer = w.renderer();

  // 2x2: red, green / blue, white (top-down rows).
  auto img = new Image(2, 2);
  img.pixels[] = [
    255, 0, 0, 255,  0, 255, 0, 255,
    0, 0, 255, 255,  255, 255, 255, 255,
  ];

  assert(renderer.createTexture(null) is null);
  assert(renderer.createTexture(new Image(0, 0)) is null);
  Texture tex = renderer.createTexture(img);
  assert(tex !is null && tex.isValid());
  scope(exit) tex.destroy();
  assert(tex.width() == 2 && tex.height() == 2);

  bool near(ubyte[4] px, int r, int g, int b) {
    // Linear filtering bleeds a few levels from neighboring texels.
    return nearPixel(px, r, g, b, 8);
  }

  const ColorF opaque = ColorF(1, 1, 1, 1);

  // 1. Whole image: colors and orientation at quadrant centers.
  renderer.clearFrame(ColorF(0, 0, 0, 1));
  renderer.drawImage(tex, RectF(0, 0, 100, 100), opaque);
  assert(near(readAt(25, 25), 255, 0, 0));
  assert(near(readAt(75, 25), 0, 255, 0));
  assert(near(readAt(25, 75), 0, 0, 255));
  assert(near(readAt(75, 75), 255, 255, 255));
  // Outside dest stays black.
  assert(near(readAt(150, 150), 0, 0, 0));

  // 2. Source sub-rect: only the blue texel.
  renderer.clearFrame(ColorF(0, 0, 0, 1));
  renderer.drawImageRegion(
    tex, RectF(0, 0, 100, 100), RectF(0, 1, 1, 1), opaque
  );
  assert(near(readAt(50, 50), 0, 0, 255));
  assert(near(readAt(10, 90), 0, 0, 255));

  // 3. 50% alpha tint over black.
  renderer.clearFrame(ColorF(0, 0, 0, 1));
  renderer.drawImage(tex, RectF(0, 0, 100, 100), ColorF(1, 1, 1, 0.5f));
  assert(near(readAt(25, 25), 128, 0, 0));
  assert(near(readAt(75, 75), 128, 128, 128));

  // 4. update() re-uploads and resizes.
  auto green = new Image(1, 1);
  green.pixels[] = [0, 255, 0, 255];
  tex.update(green);
  assert(tex.width() == 1 && tex.height() == 1);
  renderer.clearFrame(ColorF(0, 0, 0, 1));
  renderer.drawImage(tex, RectF(0, 0, 100, 100), opaque);
  assert(near(readAt(25, 25), 0, 255, 0));
  assert(near(readAt(75, 75), 0, 255, 0));

  // 5. Null and destroyed textures are no-ops; destroy is idempotent.
  renderer.clearFrame(ColorF(0, 0, 0, 1));
  renderer.drawImage(null, RectF(0, 0, 100, 100), opaque);
  tex.destroy();
  tex.destroy();
  assert(!tex.isValid() && tex.width() == 0);
  renderer.drawImage(tex, RectF(0, 0, 100, 100), opaque);
  assert(near(readAt(50, 50), 0, 0, 0));

  assert(glGetError() == GL_NO_ERROR);
}

// Verifies the blend on a transparent target (alpha a, not a * a) and
// that premultiplied + bottom-up textures draw like straight ones.
unittest {
  auto w = GlTestWindow("test_renderer_blend_premultiplied");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  auto renderer = w.renderer();

  bool near4(ubyte[4] px, int r, int g, int b, int a) {
    return nearPixelRgba(px, r, g, b, a, 3);
  }

  // Offscreen RGBA target cleared to transparent.
  OffscreenTarget fb;
  scope(exit) fb.destroy();
  const GLuint curFbo = renderer.currentFramebuffer();
  // over the GL size limit (or not positive): rejected, nothing allocated
  assert(!fb.ensureSize(fb.maxSize() + 1, 1, curFbo));
  assert(!fb.ensureSize(0, 10, curFbo));
  assert(fb.fbo == 0 && fb.width == 0);
  assert(fb.ensureSize(320, 240, curFbo));
  const SavedTargetState saved = SavedTargetState.capture();
  fb.bindRegion(320, 240, true);

  // 1. Semi-transparent over transparent: premultiplied (128, 0, 0, 128).
  renderer.drawFillRect(RectF(0, 0, 50, 50), ColorF(1, 0, 0, 0.5f));
  assert(near4(readAt(25, 25), 128, 0, 0, 128));
  // Opaque results are unchanged.
  renderer.drawFillRect(RectF(60, 0, 50, 50), ColorF(0, 1, 0, 1));
  assert(near4(readAt(85, 25), 0, 255, 0, 255));
  renderer.drawFillRect(RectF(60, 0, 50, 50), ColorF(1, 0, 0, 0.5f));
  assert(near4(readAt(85, 25), 128, 128, 0, 255));
  assert(near4(readAt(200, 200), 0, 0, 0, 0));

  // 2. Straight top-down image and its premultiplied bottom-up twin.
  // 2x2: red a=128, green / blue, white a=64 (top-down rows).
  auto img = new Image(2, 2);
  img.pixels[] = [
    255, 0, 0, 128,  0, 255, 0, 255,
    0, 0, 255, 255,  255, 255, 255, 64,
  ];
  Texture straight = renderer.createTexture(img);
  scope(exit) straight.destroy();
  assert(!straight.premultiplied() && !straight.bottomUp());
  assert(!straight.borrowed());

  // Bottom row first, rgb multiplied by alpha.
  ubyte[16] pre = [
    0, 0, 255, 255,  64, 64, 64, 64,
    128, 0, 0, 128,  0, 255, 0, 255,
  ];
  BorrowedTextureInfo info;
  info.id = uploadRgbaTexture(pre.ptr, 2, 2, 8);
  info.width = 2;
  info.height = 2;
  info.premultiplied = true;
  info.bottomUp = true;
  scope(exit) deleteTexture(info.id);
  Texture borrowed = Texture.borrowedFromInfo(info);
  scope(exit) borrowed.releaseBorrowed();

  // uv of a bottom-up texture is flipped.
  const RectF uvAll = Renderer.textureUv(borrowed, RectF(0, 0, 2, 2));
  assert(uvAll == RectF(0, 1, 1, -1));
  const RectF uvPlain = Renderer.textureUv(straight, RectF(0, 1, 1, 1));
  assert(uvPlain == RectF(0, 0.5f, 0.5f, 0.5f));

  const int[2][4] centers = [[25, 25], [75, 25], [25, 75], [75, 75]];
  void compareAt(ColorF tint, ColorF clear) {
    renderer.clearFrame(clear);
    renderer.drawImage(straight, RectF(0, 0, 100, 100), tint);
    renderer.drawImage(borrowed, RectF(100, 0, 100, 100), tint);
    foreach (c; centers) {
      const ubyte[4] a = readAt(c[0], c[1]);
      const ubyte[4] b = readAt(c[0] + 100, c[1]);
      assert(near4(b, a[0], a[1], a[2], a[3]));
    }
  }

  const ColorF opaque = ColorF(1, 1, 1, 1);
  const ColorF halfTint = ColorF(1, 0.5f, 1, 0.5f);
  compareAt(opaque, ColorF(0, 0, 0, 0));
  compareAt(halfTint, ColorF(0, 0, 0, 0));
  // Over transparent the straight red texel gives premultiplied alpha.
  compareAt(opaque, ColorF(0, 0, 0, 0));
  assert(near4(readAt(25, 25), 128, 0, 0, 128));
  compareAt(opaque, ColorF(0.2f, 0.4f, 0.6f, 1));
  compareAt(halfTint, ColorF(0.2f, 0.4f, 0.6f, 1));

  // 3. Region of a bottom-up texture uses top-left source pixels: blue.
  renderer.clearFrame(ColorF(0, 0, 0, 1));
  renderer.drawImageRegion(
    borrowed, RectF(0, 0, 100, 100), RectF(0, 1, 1, 1), opaque
  );
  assert(near4(readAt(50, 50), 0, 0, 255, 255));

  saved.restore();
  assert(glGetError() == GL_NO_ERROR);
}

// Verifies readPixels/captureFrame orientation, clamping and empty rects.
unittest {
  auto w = GlTestWindow("test_renderer_read_pixels");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  auto renderer = w.renderer();

  renderer.clearFrame(ColorF(0, 0, 0, 1));
  renderer.drawFillRect(RectF(0, 0, 10, 10), ColorF(1, 0, 0, 1));

  Image frame = renderer.captureFrame();
  assert(frame !is null);
  assert(frame.width() == 320 && frame.height() == 240);
  // Top-left pixel is red: rows are top-down.
  assert(frame.pixels[0 .. 4] == [255, 0, 0, 255]);
  // Bottom-right pixel is black.
  assert(frame.pixels[$ - 4 .. $] == [0, 0, 0, 255]);

  // Sub-rect straddling the red square's corner, clamped at the origin.
  Image part = renderer.readPixels(-5, -5, 20, 20);
  assert(part !is null);
  assert(part.width() == 15 && part.height() == 15);
  assert(part.pixels[0 .. 4] == [255, 0, 0, 255]);
  const size_t offs = cast(size_t)(12 * part.width() + 12) * 4;
  assert(part.pixels[offs .. offs + 4] == [0, 0, 0, 255]);

  // Rect at the bottom-right edge is clamped to the viewport.
  Image edge = renderer.readPixels(310, 230, 50, 50);
  assert(edge !is null);
  assert(edge.width() == 10 && edge.height() == 10);

  // Empty or fully outside rects give null.
  assert(renderer.readPixels(0, 0, 0, 10) is null);
  assert(renderer.readPixels(400, 0, 10, 10) is null);
  assert(renderer.readPixels(0, -20, 10, 10) is null);

  assert(glGetError() == GL_NO_ERROR);
}

// Destroyed fonts take their text runs with them (review 2.4).
unittest {
  import yguilib.render.font : invalidFontId;

  auto w = GlTestWindow("test_renderer_font_textures");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  auto r = w.renderer();
  FontManager fm = r.fontManagerRef();
  TextRunCache tc = r.textCacheRef();
  assert(fm.scaledCount() == 0);

  // Fill the scaled cache up to the flush threshold.
  ulong[] ids;
  foreach (i; 0 .. 64) {
    Font f = r.fontAtScale(10.0f, null, 1.0f + i / 8.0f);
    assert(r.textRunFor(f, "x", 0) !is null);
    ids ~= f.id;
  }
  assert(fm.scaledCount() == 64);
  foreach (id; ids) {
    assert(tc.countForFont(id) == 1);
  }
  const size_t texts = tc.length;

  // One more scaled font evicts the oldest subset (16) and its textures.
  Font next = r.fontAtScale(10.0f, null, 12.0f);
  assert(fm.scaledCount() == 49);
  size_t evicted = 0;
  foreach (id; ids) {
    const size_t cnt = tc.countForFont(id);
    if (cnt == 0) {
      evicted++;
    } else {
      assert(cnt == 1);
    }
  }
  assert(evicted == 16);
  assert(tc.length == texts - 16);
  assert(r.textRunFor(next, "x", 0) !is null);

  // Re-registering a face drops the textures of its fonts.
  const(void)[] data = cast(const(void)[])defaultTtfFontData;
  r.registerFontFromMemory("Foo", data);
  Font foo = r.font(12.0f, "Foo");
  const ulong fooId = foo.id;
  assert(r.textRunFor(foo, "foo", 0) !is null);
  assert(r.textRunFor(foo, "foo", 2) !is null);
  assert(tc.countForFont(fooId) == 2);
  r.registerFontFromMemory("Foo", data);
  assert(tc.countForFont(fooId) == 0);
  assert(foo.id == invalidFontId);
  assert(r.font(12.0f, "Foo").id != fooId);
}

// Glyph quads match the blended whole-string bitmap, and 600 distinct
// strings in one frame all draw from one atlas texture.
unittest {
  import std.conv : to;
  import yguilib.clibs.sdl3_ttf;

  auto w = GlTestWindow("test_renderer_text_oracle");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  auto r = w.renderer();
  Font f = r.fontAtScale(14.0f, null, 1.0f);
  const string text = "Hello, Ag";
  const ColorF white = ColorF(1, 1, 1, 1);

  r.clearFrame(ColorF(0, 0, 0, 1));
  r.drawTextWithFont(text, PointF(10, 10), white, f);
  Image glyphs = r.readPixels(0, 0, 160, 60);
  assert(glyphs !is null);

  auto surf = yguilib_sdl3_ttf_render_text_blended(
    f.handle, text.ptr, text.length, 255, 255, 255, 255
  );
  assert(surf !is null);
  scope(exit) yguilib_sdl3_ttf_destroy_surface(surf);
  int sw = 0;
  int sh = 0;
  yguilib_sdl3_ttf_get_surface_size(surf, &sw, &sh);
  GLuint tex = uploadRgbaTexture(
    yguilib_sdl3_ttf_get_surface_pixels(surf), sw, sh,
    yguilib_sdl3_ttf_get_surface_pitch(surf)
  );
  scope(exit) deleteTexture(tex);
  r.clearFrame(ColorF(0, 0, 0, 1));
  r.drawTexture(tex, RectF(10, 10, sw, sh), white);
  Image whole = r.readPixels(0, 0, 160, 60);
  assert(whole !is null);

  int maxDiff = 0;
  int lit = 0;
  foreach (i; 0 .. glyphs.pixels.length) {
    const int d = glyphs.pixels[i] > whole.pixels[i]
      ? glyphs.pixels[i] - whole.pixels[i]
      : whole.pixels[i] - glyphs.pixels[i];
    maxDiff = d > maxDiff ? d : maxDiff;
    lit += (i % 4 == 0 && glyphs.pixels[i] > 60) ? 1 : 0;
  }
  assert(lit > 50);
  assert(maxDiff <= 2, "max channel difference " ~ maxDiff.to!string);

  // 600 distinct strings in one frame, at most one atlas growth, no per-string
  // textures.
  r.clearFrame(ColorF(0, 0, 0, 1));
  GLuint curAtlasTex = r.glyphAtlasTexture();
  assert(curAtlasTex != 0);
  int atlasChanges = 0;
  foreach (i; 0 .. 600) {
    const string s = "str" ~ i.to!string;
    assert(r.textRunFor(f, s, 0) !is null);
    r.drawTextWithFont(s, PointF(i % 20 * 15, i / 20 * 7), white, f);
    const GLuint texNow = r.glyphAtlasTexture();
    assert(texNow != 0);
    if (texNow != curAtlasTex) {
      ++atlasChanges;
      curAtlasTex = texNow;
    }
  }
  assert(atlasChanges <= 1);
  assert(r.glyphAtlasSize() >= 512);
  assert(glGetError() == GL_NO_ERROR);
}

// Multi-font, multi-size, multi-color consecutive text calls share 1 flush.
unittest {
  auto w = GlTestWindow("test_renderer_text_batch_multi");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  auto r = w.renderer();
  r.registerFontFromMemory("Alt", cast(const(void)[])defaultTtfFontData);
  Font f1 = r.font(11.0f, null);
  Font f2 = r.font(18.0f, null);
  Font f3 = r.font(24.0f, "Alt");

  r.clearFrame(ColorF(0, 0, 0, 1));
  r.resetTextBatchStats();

  r.drawTextWithFont("Red", PointF(10, 10), ColorF(1, 0, 0, 1), f1);
  r.drawTextWithFont("Green", PointF(10, 40), ColorF(0, 1, 0, 1), f2);
  r.drawTextWithFont("Blue", PointF(10, 80), ColorF(0, 0, 1, 1), f3);
  assert(r.textBatchStats().flushes == 0);

  r.flush();
  assert(r.textBatchStats().flushes == 1);
  assert(r.textBatchStats().flushedQuads > 0);

  int countChannel(int x0, int y0, int bw, int bh, int ch) {
    Image part = r.readPixels(x0, y0, bw, bh);
    assert(part !is null);
    int n = 0;
    for (size_t i = 0; i < part.pixels.length; i += 4) {
      if (part.pixels[i + ch] > 120
          && part.pixels[i + ((ch + 1) % 3)] < 20
          && part.pixels[i + ((ch + 2) % 3)] < 20) {
        ++n;
      }
    }
    return n;
  }

  assert(countChannel(10, 10, 80, 25, 0) > 0);
  assert(countChannel(10, 40, 100, 35, 1) > 0);
  assert(countChannel(10, 80, 100, 40, 2) > 0);
  assert(glGetError() == GL_NO_ERROR);
}

// Interleaved non-text draws auto-flush and preserve z-order.
unittest {
  auto w = GlTestWindow("test_renderer_text_batch_zorder");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  auto r = w.renderer();
  Font f = r.font(18.0f, null);
  r.clearFrame(ColorF(0, 0, 0, 1));
  r.resetTextBatchStats();

  r.drawTextWithFont("HHHH", PointF(10, 20), ColorF(1, 1, 1, 1), f);
  assert(r.textBatchStats().flushes == 0);

  r.drawFillRect(RectF(10, 20, 100, 35), ColorF(1, 0, 0, 1));
  assert(r.textBatchStats().flushes == 1);

  r.drawTextWithFont("IIII", PointF(10, 20), ColorF(0, 1, 0, 1), f);
  assert(r.textBatchStats().flushes == 1);

  r.flush();
  assert(r.textBatchStats().flushes == 2);

  Image part = r.readPixels(10, 20, 100, 35);
  assert(part !is null);
  int greenOnTop = 0;
  int whiteLeaked = 0;
  for (size_t i = 0; i < part.pixels.length; i += 4) {
    if (part.pixels[i + 1] > 150 && part.pixels[i] < 100) {
      ++greenOnTop;
    }
    if (part.pixels[i] > 180 && part.pixels[i + 2] > 180) {
      ++whiteLeaked;
    }
  }
  assert(greenOnTop > 0);
  assert(whiteLeaked == 0);
  assert(glGetError() == GL_NO_ERROR);
}

// Scissor changes flush; redundant identical clip rects do not.
unittest {
  auto w = GlTestWindow("test_renderer_text_batch_scissor");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  auto r = w.renderer();
  r.clearFrame(ColorF(0, 0, 0, 1));
  r.resetTextBatchStats();

  r.pushClipRect(RectF(0, 0, 200, 200));
  r.drawTextWithFont("A", PointF(10, 10), ColorF(1, 1, 1, 1), null);
  assert(r.textBatchStats().flushes == 0);

  // Intersects to (0, 0, 200, 200): identical scissor box, no flush.
  r.pushClipRect(RectF(0, 0, 250, 250));
  r.drawTextWithFont("B", PointF(30, 10), ColorF(1, 1, 1, 1), null);
  assert(r.textBatchStats().flushes == 0);

  // Popping back to (0, 0, 200, 200) keeps the same scissor box, no flush.
  r.popClipRect();
  r.drawTextWithFont("C", PointF(50, 10), ColorF(1, 1, 1, 1), null);
  assert(r.textBatchStats().flushes == 0);

  // Narrower clip changes the scissor box and flushes prior queued text.
  r.pushClipRect(RectF(10, 10, 100, 100));
  assert(r.textBatchStats().flushes == 1);
  r.drawTextWithFont("D", PointF(20, 40), ColorF(1, 1, 1, 1), null);

  // Popping back to (0, 0, 200, 200) changes the scissor box and flushes.
  r.popClipRect();
  assert(r.textBatchStats().flushes == 2);
  r.drawTextWithFont("E", PointF(70, 10), ColorF(1, 1, 1, 1), null);

  // Final pop disables scissor and flushes.
  r.popClipRect();
  assert(r.textBatchStats().flushes == 3);
  assert(glGetError() == GL_NO_ERROR);
}

// Mid-batch atlas growth and clear flush queued labels before reallocating.
unittest {
  import std.conv : to;

  auto w = GlTestWindow("test_renderer_text_batch_atlas_reset");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  auto r = w.renderer();
  Font smallF = r.font(16.0f, null);
  Font bigF = r.font(64.0f, null);

  // Trigger initial atlas allocation, then test mid-batch growth.
  r.clearFrame(ColorF(0, 0, 0, 1));
  r.drawTextWithFont("Init", PointF(0, 0), ColorF(0, 0, 0, 1), smallF);
  r.flush();

  r.clearFrame(ColorF(0, 0, 0, 1));
  r.resetTextBatchStats();
  const int oldAtlasSize = r.glyphAtlasSize();

  r.drawTextWithFont("ABC", PointF(10, 10), ColorF(1, 1, 1, 1), smallF);
  assert(r.textBatchStats().flushes == 0);

  // Fill 512x512 atlas until it grows (or clear if already at max size).
  bool grew = false;
  foreach (i; 0 .. 40) {
    const string s = "G" ~ i.to!string ~ "WXYZQMRK";
    r.drawTextWithFont(s, PointF(10, 90), ColorF(0, 1, 0, 1), bigF);
    if (r.glyphAtlasSize() > oldAtlasSize) {
      grew = true;
      break;
    }
  }
  if (!grew) {
    r.textCacheRef().atlas().clear();
  }
  assert(r.textBatchStats().flushes >= 1);

  Image topImg = r.readPixels(10, 10, 60, 30);
  assert(topImg !is null);
  int whiteLit = 0;
  for (size_t i = 0; i < topImg.pixels.length; i += 4) {
    if (topImg.pixels[i] > 120
        && topImg.pixels[i + 1] > 120
        && topImg.pixels[i + 2] > 120) {
      ++whiteLit;
    }
  }
  assert(whiteLit > 0);

  // Explicit mid-batch atlas clear also flushes queued labels intact.
  r.clearFrame(ColorF(0, 0, 0, 1));
  r.resetTextBatchStats();
  r.drawTextWithFont("DEF", PointF(10, 10), ColorF(1, 1, 1, 1), smallF);
  assert(r.textBatchStats().flushes == 0);
  r.textCacheRef().atlas().clear();
  assert(r.textBatchStats().flushes == 1);
  Image clearImg = r.readPixels(10, 10, 60, 30);
  assert(clearImg !is null);
  int clearLit = 0;
  for (size_t i = 0; i < clearImg.pixels.length; i += 4) {
    if (clearImg.pixels[i] > 120 && clearImg.pixels[i + 1] > 120) {
      ++clearLit;
    }
  }
  assert(clearLit > 0);
  assert(glGetError() == GL_NO_ERROR);
}

// beginTarget/endTarget and readPixels/captureFrame auto-flush.
unittest {
  auto w = GlTestWindow("test_renderer_text_batch_targets");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  auto r = w.renderer();
  RenderTarget rt = r.createRenderTarget(160, 120, false);
  assert(rt !is null);
  scope(exit) rt.destroy();
  scope(exit) w.endTargets();

  Font f = r.font(16.0f, null);
  r.clearFrame(ColorF(0, 0, 0, 1));
  r.resetTextBatchStats();

  r.drawTextWithFont("Main", PointF(10, 10), ColorF(1, 1, 1, 1), f);
  assert(r.textBatchStats().flushes == 0);

  r.beginTarget(rt, true);
  assert(r.textBatchStats().flushes == 1);
  r.drawTextWithFont("RT1", PointF(10, 10), ColorF(0, 1, 0, 1), f);
  assert(r.textBatchStats().flushes == 1);

  Image rtCap = r.captureFrame();
  assert(rtCap !is null);
  assert(r.textBatchStats().flushes == 2);
  int rtGreen = 0;
  for (size_t i = 0; i < rtCap.pixels.length; i += 4) {
    if (rtCap.pixels[i + 1] > 120) {
      ++rtGreen;
    }
  }
  assert(rtGreen > 0);

  r.drawTextWithFont("RT2", PointF(10, 40), ColorF(0, 0, 1, 1), f);
  assert(r.textBatchStats().flushes == 2);

  r.endTarget();
  assert(r.textBatchStats().flushes == 3);

  Image mainPart = r.readPixels(10, 10, 80, 30);
  assert(mainPart !is null);
  int mainWhite = 0;
  for (size_t i = 0; i < mainPart.pixels.length; i += 4) {
    if (mainPart.pixels[i] > 120
        && mainPart.pixels[i + 1] > 120
        && mainPart.pixels[i + 2] > 120) {
      ++mainWhite;
    }
  }
  assert(mainWhite > 0);

  r.clearFrame(ColorF(0, 0, 0, 1));
  r.drawImage(rt.texture(), RectF(0, 0, 160, 120), ColorF(1, 1, 1, 1));
  Image comp = r.readPixels(0, 0, 160, 120);
  assert(comp !is null);
  int compBlue = 0;
  for (size_t i = 0; i < comp.pixels.length; i += 4) {
    if (comp.pixels[i + 2] > 120 && comp.pixels[i + 1] < 20) {
      ++compBlue;
    }
  }
  assert(compBlue > 0);
  assert(glGetError() == GL_NO_ERROR);
}

// Steady-state batched text frames allocate zero GC memory.
unittest {
  import core.memory : GC;

  auto w = GlTestWindow("test_renderer_text_batch_zero_gc");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  auto r = w.renderer();
  Font f1 = r.font(12.0f, null);
  Font f2 = r.font(18.0f, null);

  void drawBatchedFrame() {
    r.clearFrame(ColorF(0, 0, 0, 1));
    r.drawTextWithFont("Label One", PointF(10, 10), ColorF(1, 1, 1, 1), f1);
    r.drawTextWithFont("Label Two", PointF(10, 35), ColorF(1, 0, 0, 1), f2);
    r.drawTextWithFont("Label Three", PointF(10, 65), ColorF(0, 1, 0, 1), f1);
    r.drawTextWithFont("Label Four", PointF(10, 90), ColorF(0, 0, 1, 1), f2);
    r.flush();
  }

  foreach (_; 0 .. 5) {
    drawBatchedFrame();
  }

  GC.collect();
  const before = GC.stats();
  foreach (_; 0 .. 50) {
    drawBatchedFrame();
  }
  const after = GC.stats();
  assert(after.allocatedInCurrentThread == before.allocatedInCurrentThread);
  assert(glGetError() == GL_NO_ERROR);
}

// Edge cases: oversized targets, NaN dashes/rects, viewport() with active clip.
unittest {
  import yguilib.render.internal.clip_stack : ClipStack;

  auto w = GlTestWindow("test_renderer_edge_cases");
  scope(exit) w.destroy();
  scope(exit) w.endTargets();

  auto r = w.renderer();

  // 1. Huge or above-limit RenderTarget sizes are rejected cleanly.
  const int limit = r.maxTargetSizeForTest();
  assert(r.createRenderTarget(1e30f, 10, false) is null);
  assert(r.createRenderTarget(10, 1e30f, true) is null);
  assert(r.createRenderTarget(cast(float)limit + 1.0f, 10, false) is null);

  RenderTarget rt = r.createRenderTarget(16, 16, false);
  assert(rt !is null && rt.isValid());
  scope(exit) rt.destroy();
  scope(exit) w.endTargets();
  assert(!r.resizeRenderTarget(rt, 1e30f, 16));
  assert(!r.resizeRenderTarget(rt, cast(float)limit + 1.0f, 16));
  assert(rt.pixelWidth() == 16 && rt.pixelHeight() == 16);

  // 2. NaN dashes and rects are no-ops without GL errors.
  r.clearFrame(ColorF(0, 0, 0, 1));
  r.drawLineDashed(
    PointF(0, 0), PointF(50, 50), float.nan, DashPattern(4, 4),
    ColorF(1, 1, 1, 1)
  );
  r.drawLineDashed(
    PointF(float.nan, 0), PointF(50, 50), 2, DashPattern(4, 4),
    ColorF(1, 1, 1, 1)
  );
  r.drawLineDashed(
    PointF(0, 10), PointF(100, 10), 2, DashPattern(float.nan, 4),
    ColorF(1, 1, 1, 1)
  );
  r.drawRectWithWidth(
    RectF(float.nan, 0, 20, 20), 2, ColorF(1, 1, 1, 1)
  );
  r.drawRectWithWidth(
    RectF(10, 10, 20, 20), float.nan, ColorF(1, 1, 1, 1)
  );
  r.drawFillRoundRect(
    RectF(10, 10, float.nan, 20), 4, ColorF(1, 1, 1, 1)
  );
  r.drawFillRoundRect(
    RectF(10, 10, 20, 20), float.nan, ColorF(1, 1, 1, 1)
  );
  assert(glGetError() == GL_NO_ERROR);

  // 3. viewport() updates active clip scissor and rejects active targets.
  r.pushClipRect(RectF(10, 20, 30, 40));
  r.viewport(200, 150);
  GLint[4] sb;
  glGetIntegerv(GL_SCISSOR_BOX, sb.ptr);
  assert(sb == ClipStack.scissorBox(RectF(10, 20, 30, 40), 200, 150, 1.0f));
  r.popClipRect();
  r.viewport(320, 240);

  version (assert) {
    import core.exception : AssertError;
    import std.exception : assertThrown;

    r.beginTarget(rt, true);
    assertThrown!AssertError(r.viewport(100, 100));
    r.endTarget();
  }

  assert(glGetError() == GL_NO_ERROR);
}
