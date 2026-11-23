#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Opaque handle to a decoded image surface. Pixels are always in RGBA32
 * format (byte order R, G, B, A in memory).
 */
typedef struct yguilib_sdl3_image_Surface yguilib_sdl3_image_Surface;

/**
 * Loads and decodes an image file (any format supported by SDL3_image),
 * converting it to RGBA32.
 *
 * @param path Null-terminated UTF-8 file path (NULL returns NULL).
 * @return Surface handle with RGBA32 pixels, or NULL on failure (see
 *   yguilib_sdl3_image_get_error). Free with
 *   yguilib_sdl3_image_destroy_surface.
 */
yguilib_sdl3_image_Surface *yguilib_sdl3_image_load_file(const char *path);

/**
 * Decodes an image from encoded bytes in memory, converting it to RGBA32.
 * The data is not retained after the call returns.
 *
 * @param data Pointer to encoded image data (NULL returns NULL).
 * @param size Size of data in bytes (0 returns NULL).
 * @return Surface handle with RGBA32 pixels, or NULL on failure (see
 *   yguilib_sdl3_image_get_error). Free with
 *   yguilib_sdl3_image_destroy_surface.
 */
yguilib_sdl3_image_Surface *yguilib_sdl3_image_load_mem(
  const void *data,
  size_t size
);

/**
 * Gets the dimensions of a loaded surface.
 *
 * @param surface Surface handle (NULL returns -1).
 * @param w Output pointer for width in pixels (NULL is ignored).
 * @param h Output pointer for height in pixels (NULL is ignored).
 * @return 0 on success, or -1 on error.
 */
int yguilib_sdl3_image_get_surface_size(
  const yguilib_sdl3_image_Surface *surface,
  int *w,
  int *h
);

/**
 * Gets the row pitch of a loaded surface in bytes.
 *
 * @param surface Surface handle (NULL returns 0).
 * @return Pitch in bytes (at least width * 4), or 0 on error.
 */
int yguilib_sdl3_image_get_surface_pitch(
  const yguilib_sdl3_image_Surface *surface
);

/**
 * Gets the raw RGBA32 pixel data of a loaded surface. The pointer stays
 * valid until the surface is destroyed.
 *
 * @param surface Surface handle (NULL returns NULL).
 * @return Pointer to pixel data, or NULL on error.
 */
const void *yguilib_sdl3_image_get_surface_pixels(
  const yguilib_sdl3_image_Surface *surface
);

/**
 * Destroys a surface returned by yguilib_sdl3_image_load_file or
 * yguilib_sdl3_image_load_mem.
 *
 * @param surface Surface handle to destroy (NULL is ignored).
 */
void yguilib_sdl3_image_destroy_surface(
  yguilib_sdl3_image_Surface *surface
);

/**
 * Encodes RGBA32 pixels (byte order R, G, B, A) as a PNG file. The pixels
 * are wrapped without copying.
 *
 * @param rgba Pointer to pixel data (NULL returns -1).
 * @param w Width in pixels (must be > 0).
 * @param h Height in pixels (must be > 0).
 * @param pitch Row pitch in bytes (must be >= w * 4).
 * @param path Null-terminated UTF-8 output file path (NULL returns -1).
 * @return 0 on success, or -1 on failure (see
 *   yguilib_sdl3_image_get_error).
 */
int yguilib_sdl3_image_save_png(
  const void *rgba,
  int w,
  int h,
  int pitch,
  const char *path
);

/**
 * Gets the message of the last error on the calling thread.
 *
 * @return Null-terminated UTF-8 message (never NULL, may be empty). Owned
 *   by SDL; valid until the next SDL call on this thread.
 */
const char *yguilib_sdl3_image_get_error(void);

#ifdef __cplusplus
}
#endif
