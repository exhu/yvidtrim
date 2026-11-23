#include "yguilib_sdl3_image.h"

#include <SDL3/SDL.h>
#include <SDL3_image/SDL_image.h>

/** Converts a loaded surface to RGBA32 and frees the source. */
static yguilib_sdl3_image_Surface *to_rgba32(SDL_Surface *loaded) {
  if (!loaded) {
    return NULL;
  }
  if (loaded->format == SDL_PIXELFORMAT_RGBA32) {
    return (yguilib_sdl3_image_Surface *)loaded;
  }
  SDL_Surface *converted = SDL_ConvertSurface(
    loaded,
    SDL_PIXELFORMAT_RGBA32
  );
  SDL_DestroySurface(loaded);
  return (yguilib_sdl3_image_Surface *)converted;
}

yguilib_sdl3_image_Surface *yguilib_sdl3_image_load_file(const char *path) {
  if (!path) {
    SDL_InvalidParamError("path");
    return NULL;
  }
  return to_rgba32(IMG_Load(path));
}

yguilib_sdl3_image_Surface *yguilib_sdl3_image_load_mem(
  const void *data,
  size_t size
) {
  if (!data) {
    SDL_InvalidParamError("data");
    return NULL;
  }
  if (size == 0) {
    SDL_InvalidParamError("size");
    return NULL;
  }
  SDL_IOStream *io = SDL_IOFromConstMem(data, size);
  if (!io) {
    return NULL;
  }
  return to_rgba32(IMG_Load_IO(io, true));
}

int yguilib_sdl3_image_get_surface_size(
  const yguilib_sdl3_image_Surface *surface,
  int *w,
  int *h
) {
  if (!surface) {
    return -1;
  }
  const SDL_Surface *surf = (const SDL_Surface *)surface;
  if (w) {
    *w = surf->w;
  }
  if (h) {
    *h = surf->h;
  }
  return 0;
}

int yguilib_sdl3_image_get_surface_pitch(
  const yguilib_sdl3_image_Surface *surface
) {
  if (!surface) {
    return 0;
  }
  return ((const SDL_Surface *)surface)->pitch;
}

const void *yguilib_sdl3_image_get_surface_pixels(
  const yguilib_sdl3_image_Surface *surface
) {
  if (!surface) {
    return NULL;
  }
  return ((const SDL_Surface *)surface)->pixels;
}

void yguilib_sdl3_image_destroy_surface(
  yguilib_sdl3_image_Surface *surface
) {
  if (surface) {
    SDL_DestroySurface((SDL_Surface *)surface);
  }
}

int yguilib_sdl3_image_save_png(
  const void *rgba,
  int w,
  int h,
  int pitch,
  const char *path
) {
  if (!rgba || !path) {
    SDL_InvalidParamError(!rgba ? "rgba" : "path");
    return -1;
  }
  if (w <= 0 || h <= 0 || pitch < w * 4) {
    SDL_SetError("yguilib_sdl3_image_save_png: invalid size or pitch");
    return -1;
  }
  /* SDL does not write to the pixels when encoding; cast is safe. */
  SDL_Surface *surf = SDL_CreateSurfaceFrom(
    w,
    h,
    SDL_PIXELFORMAT_RGBA32,
    (void *)rgba,
    pitch
  );
  if (!surf) {
    return -1;
  }
  const bool ok = IMG_SavePNG(surf, path);
  SDL_DestroySurface(surf);
  return ok ? 0 : -1;
}

const char *yguilib_sdl3_image_get_error(void) {
  return SDL_GetError();
}
