/// bindings to yguilib-clib-sdl3_ttf C library
module yguilib.clibs.sdl3_ttf;

struct yguilib_sdl3_ttf_Font;
struct yguilib_sdl3_ttf_Surface;

extern(C) {
  int yguilib_sdl3_ttf_init();
  void yguilib_sdl3_ttf_quit();

  yguilib_sdl3_ttf_Font* yguilib_sdl3_ttf_open_font(
    const(char)* file,
    float ptSize
  );

  yguilib_sdl3_ttf_Font* yguilib_sdl3_ttf_open_font_from_mem(
    const(void)* data,
    size_t size,
    float ptSize
  );

  void yguilib_sdl3_ttf_close_font(yguilib_sdl3_ttf_Font* font);

  int yguilib_sdl3_ttf_get_font_height(const(yguilib_sdl3_ttf_Font)* font);
  int yguilib_sdl3_ttf_get_font_ascent(const(yguilib_sdl3_ttf_Font)* font);
  int yguilib_sdl3_ttf_get_font_descent(const(yguilib_sdl3_ttf_Font)* font);
  int yguilib_sdl3_ttf_get_font_line_skip(const(yguilib_sdl3_ttf_Font)* font);

  int yguilib_sdl3_ttf_get_text_size(
    const(yguilib_sdl3_ttf_Font)* font,
    const(char)* text,
    size_t length,
    int* w,
    int* h
  );

  yguilib_sdl3_ttf_Surface* yguilib_sdl3_ttf_render_text_blended(
    yguilib_sdl3_ttf_Font* font,
    const(char)* text,
    size_t length,
    ubyte r,
    ubyte g,
    ubyte b,
    ubyte a
  );

  int yguilib_sdl3_ttf_get_surface_size(
    const(yguilib_sdl3_ttf_Surface)* surface,
    int* w,
    int* h
  );

  int yguilib_sdl3_ttf_get_surface_pitch(
    const(yguilib_sdl3_ttf_Surface)* surface
  );

  const(void)* yguilib_sdl3_ttf_get_surface_pixels(
    const(yguilib_sdl3_ttf_Surface)* surface
  );

  void yguilib_sdl3_ttf_destroy_surface(yguilib_sdl3_ttf_Surface* surface);
}
