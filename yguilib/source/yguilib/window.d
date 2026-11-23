module yguilib.window;

import glad2.gles2;
import yguilib.clibs.sdl3;
import yguilib.events : AppEvent;
import yguilib.render : Renderer;
import yguilib.render.render_types : RectF;
import yguilib.widget : Widget, WidgetUpdateScope;

// TODO support minimum width and height based on view's Size component.
class Window {
  this(int width, int height, string title) {
    this.width = width;
    this.height = height;
    this.pixelWidth = width;
    this.pixelHeight = height;
    this.fTitle = title;
  }

  float getDefaultScaling() const {
    if (handle !is null) {
      float scale = yguilib_sdl3_get_window_display_scale(handle);
      if (scale > 0.0f) {
        return scale;
      }
    }
    return 1.0f;
  }

  /**
   * Sets the additional scaling factor above displayScaling (e.g. to support
   * zooming in/out UI for user preferences). Defaults to 1.0.
   */
  void setUnitsScaling(float scaling) {
    customUnitsScaling = scaling;
    if (renderer !is null) {
      renderer.unitsScaling(scaling);
      this.width = renderer.viewportWidth();
      this.height = renderer.viewportHeight();
      updateViewRect();
    }
  }

  /**
   * Gets the additional scaling factor above displayScaling (defaults to 1.0).
   */
  float getUnitsScaling() const {
    if (renderer !is null) {
      return renderer.unitsScaling();
    }
    return customUnitsScaling;
  }

  float getDisplayScaling() const {
    if (renderer !is null) {
      return renderer.displayScaling();
    }
    return getDefaultScaling();
  }

  void setSize(int newWidth, int newHeight) {
    if (handle !is null) {
      yguilib_sdl3_set_window_size(handle, newWidth, newHeight);
      int pw = newWidth;
      int ph = newHeight;
      yguilib_sdl3_get_window_size_in_pixels(handle, &pw, &ph);
      onResize(pw, ph);
    } else {
      onResize(newWidth, newHeight);
    }
  }

  ~this() {
    destroy();
  }

  /// The view widget must have a non-null View component.
  Widget rootWidget;

  @property string title() const {
    return fTitle;
  }

  /**
   * Requests a PNG screenshot of the next rendered frame, saved to `path`
   * on the main thread after rendering and before the buffer swap. A newer
   * request replaces a pending one; an empty `path` cancels it. This does
   * not trigger a render by itself (see `UiSystem.requestScreenshot`).
   */
  void requestScreenshot(string path) {
    import std.logger : tracef;

    tracef("Window.requestScreenshot(%s)", path);
    fPendingScreenshotPath = path;
  }

package(yguilib):
  /// True when a screenshot request is waiting for the next frame.
  bool hasPendingScreenshot() const {
    return fPendingScreenshotPath.length > 0;
  }

  /// Returns the pending screenshot path (empty if none) and clears it.
  string takePendingScreenshotPath() {
    const string path = fPendingScreenshotPath;
    fPendingScreenshotPath = null;
    return path;
  }

  void swapBuffers() {
    if (handle !is null) {
      yguilib_sdl3_gl_swap_window(handle);
    }
  }

  void create() {
    if (handle !is null) {
      return;
    }
    import std.string : toStringz;

    handle = yguilib_sdl3_create_window(fTitle.toStringz, width, height);
    if (handle is null) {
      throw new Exception("Failed to create SDL window: " ~ fTitle);
    }
    glContext = yguilib_sdl3_gl_create_context(handle);
    if (glContext is null) {
      destroy();
      throw new Exception(
        "Failed to create OpenGL ES 3.0 context for window: " ~ title
      );
    }
    // queried after the context: a no-MSAA fallback may recreate the window
    id = yguilib_sdl3_get_window_id(handle);
    makeCurrent();
    if (!gladLoadGLES2(&yguilib_sdl3_gl_get_proc_address)) {
      destroy();
      throw new Exception(
        "Failed to load OpenGL ES functions via glad for window: " ~ title
      );
    }
    clearWithColor(0.15f, 0.15f, 0.18f, 1.0f);
    swapBuffers();

    int pw = width;
    int ph = height;
    yguilib_sdl3_get_window_size_in_pixels(handle, &pw, &ph);
    pixelWidth = pw;
    pixelHeight = ph;

    float defaultScale = getDefaultScaling();
    renderer = new Renderer(pw, ph, defaultScale);
    if (customUnitsScaling != 1.0f) {
      renderer.unitsScaling(customUnitsScaling);
    }
    this.width = renderer.viewportWidth();
    this.height = renderer.viewportHeight();
    updateViewRect();
  }

  void destroy() {
    if (renderer !is null) {
      renderer.destroy();
      renderer = null;
    }
    if (glContext !is null) {
      yguilib_sdl3_gl_destroy_context(glContext);
      glContext = null;
    }
    if (handle !is null) {
      yguilib_sdl3_destroy_window(handle);
      handle = null;
    }
    id = 0;
  }

  void handleWindowEvent(in AppEvent event) {
    if (event.kind == AppEvent.Kind.windowResized) {
      if (event.window.scale > 0.0f &&
          event.window.scale != getDisplayScaling()) {
        onDisplayScaleChanged(event.window.scale);
      }
      onResize(event.window.width, event.window.height);
    } else if (event.kind == AppEvent.Kind.windowExposed) {
      if (event.window.width > 0 && event.window.height > 0 &&
        (event.window.width != pixelWidth ||
          event.window.height != pixelHeight)) {
        onResize(event.window.width, event.window.height);
      }
    } else if (event.kind == AppEvent.Kind.windowDisplayScaleChanged) {
      onDisplayScaleChanged(event.window.scale);
      if (event.window.width > 0 && event.window.height > 0) {
        onResize(event.window.width, event.window.height);
      }
    }
  }

  void startTextInput() {
    if (handle !is null) {
      yguilib_sdl3_start_text_input(handle);
    }
  }

  void stopTextInput() {
    if (handle !is null) {
      yguilib_sdl3_stop_text_input(handle);
    }
  }

  void setTextInputArea(int x, int y, int w, int h, int cursor) {
    if (handle !is null) {
      yguilib_sdl3_Rect rect = yguilib_sdl3_Rect(x, y, w, h);
      yguilib_sdl3_set_text_input_area(handle, &rect, cursor);
    }
  }

  void clearTextInputArea() {
    if (handle !is null) {
      yguilib_sdl3_set_text_input_area(handle, null, 0);
    }
  }

  void setDisplayScaling(float scaling) {
    onDisplayScaleChanged(scaling);
  }

  Renderer renderer;
  uint id;
  int width;
  int height;

private:
  // TODO should it draw widgets?
  void redraw() {
    makeCurrent();
    if (rootWidget !is null && rootWidget.components.background !is null &&
        renderer !is null) {
      renderer.clearFrame(rootWidget.components.background.color);
    } else {
      clearWithColor(0.15f, 0.15f, 0.18f, 1.0f);
    }
    swapBuffers();
  }

  void clearWithColor(float r, float g, float b, float a) {
    if (handle !is null && glContext !is null) {
      glClearColor(r, g, b, a);
      glClear(GL_COLOR_BUFFER_BIT);
    }
  }

  void updateViewRect() {
    if (rootWidget !is null && renderer !is null) {
      const RectF newRect = RectF(
        0,
        0,
        renderer.logicWidth(),
        renderer.logicHeight()
      );
      if (rootWidget.rect != newRect) {
        rootWidget.rect = newRect;
        rootWidget.update(WidgetUpdateScope.all);
      }
    }
  }

  void onResize(int newPixelWidth, int newPixelHeight) {
    this.pixelWidth = newPixelWidth;
    this.pixelHeight = newPixelHeight;
    if (renderer !is null) {
      renderer.viewport(newPixelWidth, newPixelHeight);
      this.width = renderer.viewportWidth();
      this.height = renderer.viewportHeight();
    } else {
      this.width = newPixelWidth;
      this.height = newPixelHeight;
    }
    updateViewRect();
  }

  void makeCurrent() {
    if (handle !is null && glContext !is null) {
      yguilib_sdl3_gl_make_current(handle, glContext);
    }
  }

  void onDisplayScaleChanged(float newScale) {
    if (renderer !is null) {
      renderer.displayScaling(newScale);
      this.width = renderer.viewportWidth();
      this.height = renderer.viewportHeight();
      updateViewRect();
    }
  }


  int pixelWidth;
  int pixelHeight;
  float customUnitsScaling = 1.0f;
  string fTitle;
  string fPendingScreenshotPath;

  yguilib_sdl3_Window* handle;
  yguilib_sdl3_GLContext* glContext;
}

unittest {
  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto window = new Window(320, 240, "test_gl_window");
  assert(window.width == 320);
  assert(window.height == 240);
  assert(window.title == "test_gl_window");
  assert(window.handle is null);

  window.create();
  scope(exit) window.destroy();

  assert(window.handle !is null);
  assert(window.glContext !is null);
  assert(window.id > 0);
  assert(window.renderer !is null);
  assert(window.renderer.viewportWidth() == 320);
  assert(window.renderer.viewportHeight() == 240);

  window.startTextInput();
  window.setTextInputArea(10, 10, 100, 20, 2);
  window.clearTextInputArea();
  window.stopTextInput();

  const float scale = window.getDisplayScaling();
  window.onResize(640, 480);
  assert(window.width == cast(int)(640.0f / scale));
  assert(window.height == cast(int)(480.0f / scale));
  assert(window.renderer.viewportWidth() == window.width);
  assert(window.renderer.viewportHeight() == window.height);

  window.makeCurrent();
  window.swapBuffers();

  assert(window.getDefaultScaling() >= 1.0f);
  assert(window.getUnitsScaling() == 1.0f);

  window.setUnitsScaling(2.0f);
  assert(window.getUnitsScaling() == 2.0f);
  assert(window.width == cast(int)(640.0f / (scale * 2.0f)));
  assert(window.height == cast(int)(480.0f / (scale * 2.0f)));

  window.onDisplayScaleChanged(1.5f);
  // Custom scaling was set to 2.0f, so it retains custom scaling
  assert(window.getUnitsScaling() == 2.0f);
  assert(window.getDisplayScaling() == 1.5f);
  assert(window.width == cast(int)(640.0f / (1.5f * 2.0f)));
  assert(window.height == cast(int)(480.0f / (1.5f * 2.0f)));

  window.redraw();
}
