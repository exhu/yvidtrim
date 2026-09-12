module yguilib.window;
import yguilib.clibs.sdl3;
import glad2.gles2;
import yguilib.render;
import yguilib.widget;

class Window {
  this(int w, int h, string title) {
    this.w = w;
    this.h = h;
    this.title = title;
  }

  int w;
  int h;
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

    handle = yguilib_sdl3_create_window(title.toStringz, w, h);
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

    renderer = new Renderer(w, h);
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
  assert(window.w == 320);
  assert(window.h == 240);
  assert(window.title == "test_gl_window");
  assert(window.handle is null);

  window.create();
  scope(exit) window.destroy();

  assert(window.handle !is null);
  assert(window.glContext !is null);
  assert(window.id > 0);

  window.makeCurrent();
  window.swapBuffers();
}
