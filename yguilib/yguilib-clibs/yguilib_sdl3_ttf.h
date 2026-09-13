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
 * @param data Pointer to font file data in memory.
 * @param size Size of font data in bytes.
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
 * @param font Font handle to close.
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
 * Gets the total font height in pixels.
 *
 * @param font Font handle.
 * @return Height in pixels, or 0 on error.
 */
int yguilib_sdl3_ttf_get_font_height(const yguilib_sdl3_ttf_Font *font);

/**
 * Gets the font ascent in pixels.
 *
 * @param font Font handle.
 * @return Ascent in pixels, or 0 on error.
 */
int yguilib_sdl3_ttf_get_font_ascent(const yguilib_sdl3_ttf_Font *font);

/**
 * Gets the font descent in pixels.
 *
 * @param font Font handle.
 * @return Descent in pixels, or 0 on error.
 */
int yguilib_sdl3_ttf_get_font_descent(const yguilib_sdl3_ttf_Font *font);

/**
 * Gets the recommended line spacing in pixels.
 *
 * @param font Font handle.
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
 * Destroys a surface allocated by yguilib_sdl3_ttf_render_text_blended.
 *
 * @param surface Surface handle to destroy.
 */
void yguilib_sdl3_ttf_destroy_surface(yguilib_sdl3_ttf_Surface *surface);

#ifdef __cplusplus
}
#endif
