/// Bindings to yguilib_sdl3_ttf C library.
module yguilib.clibs.sdl3_ttf;

package(yguilib):

struct yguilib_sdl3_ttf_Font;
struct yguilib_sdl3_ttf_Surface;

/// One positioned glyph copy op (matches the C struct layout).
extern(C) struct yguilib_sdl3_ttf_GlyphQuad {
  uint glyphIndex;
  int srcX, srcY, srcW, srcH;
  int dstX, dstY, dstW, dstH;
}

static assert(yguilib_sdl3_ttf_GlyphQuad.sizeof == 36);
static assert(yguilib_sdl3_ttf_GlyphQuad.dstH.offsetof == 32);

extern(C) nothrow @nogc {
  /// Initializes SDL3_ttf. Returns 0 on success or -1 on failure.
  int yguilib_sdl3_ttf_init();

  /// Shuts down SDL3_ttf.
  void yguilib_sdl3_ttf_quit();

  /// Returns non-null borrowed error string valid until next SDL call.
  const(char)* yguilib_sdl3_ttf_get_error();

  /// Opens a font file. Returns null on failure or null file.
  /// Free with yguilib_sdl3_ttf_close_font.
  yguilib_sdl3_ttf_Font* yguilib_sdl3_ttf_open_font(
    const(char)* file,
    float ptSize
  );

  /// Opens a font from memory; data must stay alive and unmodified until
  /// yguilib_sdl3_ttf_close_font. Returns null on failure, null data, or
  /// zero size.
  yguilib_sdl3_ttf_Font* yguilib_sdl3_ttf_open_font_from_mem(
    const(void)* data,
    size_t size,
    float ptSize
  );

  /// Closes a font handle; null is ignored.
  void yguilib_sdl3_ttf_close_font(yguilib_sdl3_ttf_Font* font);

  /// Updates font point size; font must be non-null. Returns 0 or -1.
  int yguilib_sdl3_ttf_set_font_size(
    yguilib_sdl3_ttf_Font* font,
    float ptSize
  );

  /// Sets font outline width (>= 0); font must be non-null. Returns 0 or -1.
  int yguilib_sdl3_ttf_set_font_outline(
    yguilib_sdl3_ttf_Font* font,
    int outline
  );

  /// Gets font outline width in pixels, or 0 on error; font must be non-null.
  int yguilib_sdl3_ttf_get_font_outline(const(yguilib_sdl3_ttf_Font)* font);

  /// Gets total font height in pixels, or 0 on error; font must be non-null.
  int yguilib_sdl3_ttf_get_font_height(const(yguilib_sdl3_ttf_Font)* font);

  /// Gets font ascent in pixels, or 0 on error; font must be non-null.
  int yguilib_sdl3_ttf_get_font_ascent(const(yguilib_sdl3_ttf_Font)* font);

  /// Gets font descent in pixels, or 0 on error; font must be non-null.
  int yguilib_sdl3_ttf_get_font_descent(const(yguilib_sdl3_ttf_Font)* font);

  /// Gets font line skip in pixels, or 0 on error; font must be non-null.
  int yguilib_sdl3_ttf_get_font_line_skip(const(yguilib_sdl3_ttf_Font)* font);

  /// Measures UTF-8 text; font and text must be non-null, w/h may be null.
  /// Returns 0 on success or -1 on failure.
  int yguilib_sdl3_ttf_get_text_size(
    const(yguilib_sdl3_ttf_Font)* font,
    const(char)* text,
    size_t length,
    int* w,
    int* h
  );

  /// Renders UTF-8 text to an RGBA32 surface; font and text must be non-null.
  /// Returns null on error. Free with yguilib_sdl3_ttf_destroy_surface.
  yguilib_sdl3_ttf_Surface* yguilib_sdl3_ttf_render_text_blended(
    yguilib_sdl3_ttf_Font* font,
    const(char)* text,
    size_t length,
    ubyte r,
    ubyte g,
    ubyte b,
    ubyte a
  );

  /// Shapes UTF-8 text into glyph quads; font and text must be non-null.
  /// output may be null when cap is 0; w and h may be null.
  /// Returns total glyph count, 0 for empty text, or -1 on error.
  int yguilib_sdl3_ttf_layout_text(
    yguilib_sdl3_ttf_Font* font,
    const(char)* text,
    size_t length,
    yguilib_sdl3_ttf_GlyphQuad* output,
    int cap,
    int* w,
    int* h
  );

  /// Renders one glyph index to an RGBA32 surface; font must be non-null.
  /// Returns null on error. Free with yguilib_sdl3_ttf_destroy_surface.
  yguilib_sdl3_ttf_Surface* yguilib_sdl3_ttf_render_glyph(
    yguilib_sdl3_ttf_Font* font,
    uint glyphIndex
  );

  /// Gets surface width and height; w/h may be null.
  /// Returns 0 on success or -1 on error (including null surface).
  int yguilib_sdl3_ttf_get_surface_size(
    const(yguilib_sdl3_ttf_Surface)* surface,
    int* w,
    int* h
  );

  /// Gets surface row pitch in bytes, or 0 on error (including null surface).
  int yguilib_sdl3_ttf_get_surface_pitch(
    const(yguilib_sdl3_ttf_Surface)* surface
  );

  /// Returns borrowed RGBA32 pixels valid until surface is destroyed, or null.
  const(void)* yguilib_sdl3_ttf_get_surface_pixels(
    const(yguilib_sdl3_ttf_Surface)* surface
  );

  /// Destroys a surface handle; null is ignored.
  void yguilib_sdl3_ttf_destroy_surface(yguilib_sdl3_ttf_Surface* surface);
}

unittest {
  yguilib_sdl3_ttf_close_font(null);
  yguilib_sdl3_ttf_destroy_surface(null);
  assert(yguilib_sdl3_ttf_get_surface_size(null, null, null) == -1);
  assert(yguilib_sdl3_ttf_get_surface_pitch(null) == 0);
  assert(yguilib_sdl3_ttf_get_surface_pixels(null) is null);
  assert(yguilib_sdl3_ttf_get_error() !is null);
}
