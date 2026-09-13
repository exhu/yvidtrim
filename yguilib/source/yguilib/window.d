module yguilib.window;
import yguilib.clibs.sdl3;
import glad2.gles2;
import yguilib.render;
import yguilib.widget;

class Window {
  this(int width, int height, string title) {
    this.width = width;
    this.height = height;
    this.pixelWidth = width;
    this.pixelHeight = height;
    this.title = title;
  }

  int width;
  int height;
  int pixelWidth;
  int pixelHeight;
  float customUnitsScaling = 1.0f;
  string title;

  Widget view;

  yguilib_sdl3_Window* handle;
  yguilib_sdl3_GLContext* glContext;
  uint id;

  void create() {
    if (handle !is null) {
      return;
    }
    import std.string : toStringz;

    handle = yguilib_sdl3_create_window(title.toStringz, width, height);
    if (handle is null) {
      throw new Exception("Failed to create SDL window: " ~ title);
    }
    id = yguilib_sdl3_get_window_id(handle);
    glContext = yguilib_sdl3_gl_create_context(handle);
    if (glContext is null) {
      destroy();
      throw new Exception(
        "Failed to create OpenGL ES 3.0 context for window: " ~ title
      );
    }
    makeCurrent();
    if (!gladLoadGLES2(&yguilib_sdl3_gl_get_proc_address)) {
      destroy();
      throw new Exception(
        "Failed to load OpenGL ES functions via glad for window: " ~ title
      );
    }
    clear();
    swapBuffers();

    int pw = width;
    int ph = height;
    yguilib_sdl3_get_window_size_in_pixels(handle, &pw, &ph);
    pixelWidth = pw;
    pixelHeight = ph;

    float defaultScale = getDefaultScaling();
    renderer = new Renderer(pw, ph, defaultScale);
    if (customUnitsScaling != 1.0f) {
      renderer.setUnitsScaling(customUnitsScaling);
    }
    this.width = renderer.getViewportWidth();
    this.height = renderer.getViewportHeight();
    updateViewRect();
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
      renderer.setUnitsScaling(scaling);
      this.width = renderer.getViewportWidth();
      this.height = renderer.getViewportHeight();
      updateViewRect();
    }
  }

  /**
   * Gets the additional scaling factor above displayScaling (defaults to 1.0).
   */
  float getUnitsScaling() const {
    if (renderer !is null) {
      return renderer.getUnitsScaling();
    }
    return customUnitsScaling;
  }

  float getDisplayScaling() const {
    if (renderer !is null) {
      return renderer.getDisplayScaling();
    }
    return getDefaultScaling();
  }

  void onDisplayScaleChanged(float newScale) {
    if (renderer !is null) {
      renderer.setDisplayScaling(newScale);
      this.width = renderer.getViewportWidth();
      this.height = renderer.getViewportHeight();
      updateViewRect();
    }
  }

  void redraw() {
    makeCurrent();
    if (view !is null && view.components.background !is null &&
        renderer !is null) {
      renderer.clearCanvas(view.components.background.color);
    } else {
      clear();
    }
    swapBuffers();
  }

  private void updateViewRect() {
    if (view !is null && renderer !is null) {
      view.rect = RectF(
        0,
        0,
        renderer.getLogicWidth(),
        renderer.getLogicHeight()
      );
    }
  }

  void onResize(int newPixelWidth, int newPixelHeight) {
    this.pixelWidth = newPixelWidth;
    this.pixelHeight = newPixelHeight;
    if (renderer !is null) {
      renderer.setViewport(newPixelWidth, newPixelHeight);
      this.width = renderer.getViewportWidth();
      this.height = renderer.getViewportHeight();
    } else {
      this.width = newPixelWidth;
      this.height = newPixelHeight;
    }
    updateViewRect();
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

  void clear(
    float r = 0.15f,
    float g = 0.15f,
    float b = 0.18f,
    float a = 1.0f
  ) {
    if (handle !is null && glContext !is null) {
      glClearColor(r, g, b, a);
      glClear(GL_COLOR_BUFFER_BIT);
    }
  }

  void destroy() {
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

  void swapBuffers() {
    if (handle !is null) {
      yguilib_sdl3_gl_swap_window(handle);
    }
  }

  void makeCurrent() {
    if (handle !is null && glContext !is null) {
      yguilib_sdl3_gl_make_current(handle, glContext);
    }
  }

  ~this() {
    destroy();
  }

  Renderer renderer;
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
  assert(window.renderer.getViewportWidth() == 320);
  assert(window.renderer.getViewportHeight() == 240);

  window.onResize(640, 480);
  assert(window.width == 640);
  assert(window.height == 480);
  assert(window.renderer.getViewportWidth() == 640);
  assert(window.renderer.getViewportHeight() == 480);

  window.makeCurrent();
  window.swapBuffers();

  assert(window.getDefaultScaling() >= 1.0f);
  assert(window.getUnitsScaling() == 1.0f);

  window.setUnitsScaling(2.0f);
  assert(window.getUnitsScaling() == 2.0f);
  assert(window.width == 320);
  assert(window.height == 240);

  window.onDisplayScaleChanged(1.5f);
  // Custom scaling was set to 2.0f, so it retains custom scaling
  assert(window.getUnitsScaling() == 2.0f);
  assert(window.getDisplayScaling() == 1.5f);
  assert(window.width == 213);
  assert(window.height == 160);

  window.redraw();
}
