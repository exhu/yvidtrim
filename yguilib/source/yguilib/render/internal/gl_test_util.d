/** Shared GL test fixture and pixel helpers for Renderer and Canvas tests.

    `GlTestWindow` opens the hidden 320x240 window with a GL context and a
    `Renderer` at display scaling 1. The helpers read back pixels in logic
    coordinates (y down) from the bound framebuffer.
*/
module yguilib.render.internal.gl_test_util;

version (unittest):

package(yguilib):

import glad2.gles2;
import std.math : abs;
import yguilib.clibs.sdl3;
import yguilib.render : Renderer;
import yguilib.render.canvas : Canvas;
import yguilib.render.canvas.path2d : Path2d;
import yguilib.render.render_types : RectF;
import yguilib.window : Window;

/// Width of the `GlTestWindow` viewport in pixels.
enum int testWidth = 320;
/// Height of the `GlTestWindow` viewport in pixels.
enum int testHeight = 240;

/**
 * Hidden 320x240 window with a GL context and a `Renderer`.
 *
 * Declare the teardown in this order, so that open render targets are
 * ended first (an assert in `destroy()` while unwinding a failed assert
 * can make the test runner loop forever):
 * ---
 * auto w = GlTestWindow("test_name");
 * scope(exit) w.destroy();
 * scope(exit) w.endTargets();
 * ---
 * A test that destroys a `RenderTarget` in a `scope(exit)` declares
 * another `scope(exit) w.endTargets();` after it.
 */
struct GlTestWindow {
  @disable this();
  @disable this(this);

  /// Inits SDL, creates the window named `title` and sets the viewport.
  this(string title) {
    yguilib_sdl3_init();
    fWindow = new Window(testWidth, testHeight, title);
    fWindow.create();
    fWindow.setDisplayScaling(1.0f);
    fRenderer = fWindow.renderer;
    fRenderer.viewport(testWidth, testHeight);
  }

  /// The window (for its id in synthesized events).
  Window window() {
    return fWindow;
  }

  /// The window's renderer.
  Renderer renderer() {
    return fRenderer;
  }

  /// The renderer's canvas.
  Canvas canvas() {
    return fRenderer.canvas();
  }

  /// Ends every open render target; safe to call more than once.
  void endTargets() {
    if (fRenderer is null) {
      return;
    }
    while (fRenderer.inTarget()) {
      fRenderer.endTarget();
    }
  }

  /// Destroys the window and quits SDL; safe to call more than once.
  void destroy() {
    if (fWindow is null) {
      return;
    }
    fWindow.destroy();
    fWindow = null;
    fRenderer = null;
    yguilib_sdl3_quit();
  }

private:
  Window fWindow;
  Renderer fRenderer;
}

/// RGBA at logic (x, y) with y down; GL y = 240 - y.
ubyte[4] px(int x, int y) {
  ubyte[4] p;
  glReadPixels(x, testHeight - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p.ptr);
  return p;
}

/// RGBA at logic pixel row `y` (top row 0); GL y = 240 - 1 - y.
ubyte[4] readAt(int x, int y) {
  ubyte[4] p;
  glReadPixels(x, testHeight - 1 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE,
    p.ptr);
  return p;
}

/// True when every rgb channel of `p` is within `tol` of (r, g, b).
bool nearPixel(ubyte[4] p, int r, int g, int b, int tol) {
  return abs(p[0] - r) <= tol && abs(p[1] - g) <= tol
    && abs(p[2] - b) <= tol;
}

/// True when every channel of `p` is within `tol` of (r, g, b, a).
bool nearPixelRgba(ubyte[4] p, int r, int g, int b, int a, int tol) {
  return nearPixel(p, r, g, b, tol) && abs(p[3] - a) <= tol;
}

/// `px(x, y)` rgb is within `tol` of (cr, cg, cb).
bool near(int x, int y, int cr, int cg, int cb, int tol) {
  return nearPixel(px(x, y), cr, cg, cb, tol);
}

/// `px(x, y)` rgb is exactly (cr, cg, cb).
bool isRgb(int x, int y, int cr, int cg, int cb) {
  return near(x, y, cr, cg, cb, 0);
}

/// New path holding the rectangle `rc`.
Path2d rectPath(RectF rc) {
  auto p = new Path2d();
  p.rect(rc);
  return p;
}

/// Pixel bounding box in logic coordinates; empty when `x1 < 0`.
struct PixelBox {
  int x0 = int.max;
  int y0 = int.max;
  int x1 = -1;
  int y1 = -1;

  /// No pixel matched.
  bool empty() const {
    return x1 < 0;
  }
}

/// Bounding box of pixels whose channel `ch` exceeds 60, in a region.
PixelBox bounds(int rx, int ry, int rw, int rh, int ch) {
  auto buf = new ubyte[rw * rh * 4];
  glReadPixels(rx, testHeight - ry - rh, rw, rh, GL_RGBA, GL_UNSIGNED_BYTE,
    buf.ptr);
  PixelBox b;
  foreach (y; 0 .. rh) {
    foreach (x; 0 .. rw) {
      if (buf[((rh - 1 - y) * rw + x) * 4 + ch] > 60) {
        b.x0 = x + rx < b.x0 ? x + rx : b.x0;
        b.y0 = y + ry < b.y0 ? y + ry : b.y0;
        b.x1 = x + rx > b.x1 ? x + rx : b.x1;
        b.y1 = y + ry > b.y1 ? y + ry : b.y1;
      }
    }
  }
  return b;
}

/// `bounds` of the whole 320x240 frame for channel `ch`.
PixelBox frameBounds(int ch) {
  return bounds(0, 0, testWidth, testHeight, ch);
}

/// The whole 320x240 frame as RGBA, GL rows (bottom row first).
ubyte[] grabFrame() {
  auto buf = new ubyte[testWidth * testHeight * 4];
  glReadPixels(0, 0, testWidth, testHeight, GL_RGBA, GL_UNSIGNED_BYTE,
    buf.ptr);
  return buf;
}

/// Channel `c` at logic (x, y) of a `grabFrame()` buffer.
int channelAt(const(ubyte)[] buf, int x, int y, int c) {
  return buf[((testHeight - 1 - y) * testWidth + x) * 4 + c];
}

/// Lit pixel count and horizontal extent; `x1 < 0` when none.
struct LitSpan {
  int count;
  int x0 = int.max;
  int x1 = -1;
}

/// Lit pixels (channel `c` > 60) of a `grabFrame()` buffer.
LitSpan litSpan(const(ubyte)[] buf, int c) {
  LitSpan s;
  foreach (y; 0 .. testHeight) {
    foreach (x; 0 .. testWidth) {
      if (channelAt(buf, x, y, c) > 60) {
        s.count++;
        s.x0 = x < s.x0 ? x : s.x0;
        s.x1 = x > s.x1 ? x : s.x1;
      }
    }
  }
  return s;
}
