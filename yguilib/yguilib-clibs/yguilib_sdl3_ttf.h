#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct yguilib_sdl3_ttf_Font yguilib_sdl3_ttf_Font;
typedef struct yguilib_sdl3_ttf_Surface yguilib_sdl3_ttf_Surface;

/**
 * Initializes the SDL3_ttf subsystem.
 *
 * @return 0 on success, or -1 on initialization failure.
 */
int yguilib_sdl3_ttf_init(void);

/**
 * Cleans up and shuts down the SDL3_ttf subsystem.
 */
void yguilib_sdl3_ttf_quit(void);

/**
 * Gets the message of the last SDL error on the calling thread.
 *
 * @return Null-terminated error message (may be empty). Valid until the
 *         next SDL call on this thread.
 */
const char *yguilib_sdl3_ttf_get_error(void);

/**
 * Opens a font from a file path.
 *
 * @param file Null-terminated UTF-8 file path.
 * @param pt_size Point size of the font.
 * @return Pointer to font handle, or NULL on failure.
 */
yguilib_sdl3_ttf_Font *yguilib_sdl3_ttf_open_font(
  const char *file,
  float pt_size
);

/**
 * Opens a font from memory data.
 *
 * The caller must keep @p data alive and unmodified until
 * yguilib_sdl3_ttf_close_font is called, because SDL3_ttf reads from the
 * borrowed buffer on demand without copying it.
 *
 * @param data Pointer to font file data in memory (NULL returns NULL).
 * @param size Size of font data in bytes (0 returns NULL).
 * @param pt_size Point size of the font.
 * @return Pointer to font handle, or NULL on failure.
 */
yguilib_sdl3_ttf_Font *yguilib_sdl3_ttf_open_font_from_mem(
  const void *data,
  size_t size,
  float pt_size
);

/**
 * Closes an opened font handle.
 *
 * @param font Font handle to close (NULL is ignored).
 */
void yguilib_sdl3_ttf_close_font(yguilib_sdl3_ttf_Font *font);

/**
 * Dynamically updates the point size of an opened font.
 *
 * @param font Font handle.
 * @param pt_size New point size in points (scaled for rendering resolution).
 * @return 0 on success, or -1 on error.
 */
int yguilib_sdl3_ttf_set_font_size(
  yguilib_sdl3_ttf_Font *font,
  float pt_size
);

/**
 * Sets the outline width of a font (0 disables the outline).
 *
 * @param font Font handle.
 * @param outline Outline width in pixels (must be >= 0).
 * @return 0 on success, or -1 on error.
 */
int yguilib_sdl3_ttf_set_font_outline(
  yguilib_sdl3_ttf_Font *font,
  int outline
);

/**
 * Gets the outline width of a font in pixels.
 *
 * @param font Font handle (must not be NULL).
 * @return Outline width in pixels, or 0 on error.
 */
int yguilib_sdl3_ttf_get_font_outline(const yguilib_sdl3_ttf_Font *font);

/**
 * Gets the total font height in pixels.
 *
 * @param font Font handle (must not be NULL).
 * @return Height in pixels, or 0 on error.
 */
int yguilib_sdl3_ttf_get_font_height(const yguilib_sdl3_ttf_Font *font);

/**
 * Gets the font ascent in pixels.
 *
 * @param font Font handle (must not be NULL).
 * @return Ascent in pixels, or 0 on error.
 */
int yguilib_sdl3_ttf_get_font_ascent(const yguilib_sdl3_ttf_Font *font);

/**
 * Gets the font descent in pixels.
 *
 * @param font Font handle (must not be NULL).
 * @return Descent in pixels, or 0 on error.
 */
int yguilib_sdl3_ttf_get_font_descent(const yguilib_sdl3_ttf_Font *font);

/**
 * Gets the recommended line spacing in pixels.
 *
 * @param font Font handle (must not be NULL).
 * @return Line skip in pixels, or 0 on error.
 */
int yguilib_sdl3_ttf_get_font_line_skip(const yguilib_sdl3_ttf_Font *font);

/**
 * Measures the pixel width and height of a text string.
 *
 * @param font Font handle.
 * @param text UTF-8 text string.
 * @param length Byte length of text.
 * @param w Output pointer for width in pixels.
 * @param h Output pointer for height in pixels.
 * @return 0 on success, or -1 on failure.
 */
int yguilib_sdl3_ttf_get_text_size(
  const yguilib_sdl3_ttf_Font *font,
  const char *text,
  size_t length,
  int *w,
  int *h
);

/**
 * Renders UTF-8 text at high quality to a newly allocated 32-bit RGBA surface.
 *
 * @param font Font handle.
 * @param text UTF-8 text string.
 * @param length Byte length of text.
 * @param r Red component (0-255).
 * @param g Green component (0-255).
 * @param b Blue component (0-255).
 * @param a Alpha component (0-255).
 * @return Surface handle with RGBA32 pixels, or NULL on error.
 */
yguilib_sdl3_ttf_Surface *yguilib_sdl3_ttf_render_text_blended(
  yguilib_sdl3_ttf_Font *font,
  const char *text,
  size_t length,
  uint8_t r,
  uint8_t g,
  uint8_t b,
  uint8_t a
);

/** One positioned glyph copy operation produced by layout_text. */
typedef struct yguilib_sdl3_ttf_GlyphQuad {
  uint32_t glyph_index;
  /** Area within the glyph image (see render_glyph) to draw. */
  int src_x;
  int src_y;
  int src_w;
  int src_h;
  /** Destination in pixels, relative to the text top-left. */
  int dst_x;
  int dst_y;
  int dst_w;
  int dst_h;
} yguilib_sdl3_ttf_GlyphQuad;

/**
 * Lays out (shapes) text and returns per-glyph copy operations. Only glyph
 * copies are reported (no underline/strikethrough fills). The font outline
 * set with yguilib_sdl3_ttf_set_font_outline is included in the layout and
 * in the glyph images.
 *
 * @param font Font handle.
 * @param text UTF-8 text string.
 * @param length Byte length of text.
 * @param out Output array of quads (may be NULL when cap is 0).
 * @param cap Capacity of out in quads.
 * @param w Output pointer for text area width (may be NULL).
 * @param h Output pointer for text area height (may be NULL).
 * @return Total glyph count (call again with a bigger buffer if > cap),
 *         0 for empty text, or -1 on error.
 */
int yguilib_sdl3_ttf_layout_text(
  yguilib_sdl3_ttf_Font *font,
  const char *text,
  size_t length,
  yguilib_sdl3_ttf_GlyphQuad *out,
  int cap,
  int *w,
  int *h
);

/**
 * Renders the glyph image for a glyph index to a newly allocated RGBA32
 * surface (same format as render_text_blended). Includes the font outline.
 * Free with yguilib_sdl3_ttf_destroy_surface.
 *
 * @param font Font handle.
 * @param glyph_index Glyph index from layout_text.
 * @return Surface handle with RGBA32 pixels, or NULL on error.
 */
yguilib_sdl3_ttf_Surface *yguilib_sdl3_ttf_render_glyph(
  yguilib_sdl3_ttf_Font *font,
  uint32_t glyph_index
);

/**
 * Gets the dimensions of a rendered surface.
 *
 * @param surface Surface handle.
 * @param w Output pointer for width.
 * @param h Output pointer for height.
 * @return 0 on success, or -1 on error.
 */
int yguilib_sdl3_ttf_get_surface_size(
  const yguilib_sdl3_ttf_Surface *surface,
  int *w,
  int *h
);

/**
 * Gets the row pitch of a rendered surface in bytes.
 *
 * @param surface Surface handle.
 * @return Pitch in bytes, or 0 on error.
 */
int yguilib_sdl3_ttf_get_surface_pitch(
  const yguilib_sdl3_ttf_Surface *surface
);

/**
 * Gets the raw RGBA32 pixel data of a rendered surface.
 *
 * @param surface Surface handle.
 * @return Pointer to pixel data, or NULL on error.
 */
const void *yguilib_sdl3_ttf_get_surface_pixels(
  const yguilib_sdl3_ttf_Surface *surface
);

/**
 * Destroys a surface allocated by yguilib_sdl3_ttf_render_text_blended or
 * yguilib_sdl3_ttf_render_glyph.
 *
 * @param surface Surface handle to destroy (NULL is ignored).
 */
void yguilib_sdl3_ttf_destroy_surface(yguilib_sdl3_ttf_Surface *surface);

#ifdef __cplusplus
}
#endif
