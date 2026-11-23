#include "yguilib_sdl3_image.h"

#include <SDL3/SDL.h>
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PAT_W 4
#define PAT_H 4

/** Fills a 4x4 RGBA pattern with distinct values, some partial alpha. */
static void fill_pattern(uint8_t *px) {
  for (int y = 0; y < PAT_H; ++y) {
    for (int x = 0; x < PAT_W; ++x) {
      uint8_t *p = px + (y * PAT_W + x) * 4;
      p[0] = (uint8_t)(x * 60 + 10);
      p[1] = (uint8_t)(y * 60 + 20);
      p[2] = (uint8_t)((x + y) * 25 + 5);
      p[3] = (uint8_t)((x == 1 && y == 2) ? 128 : 255 - x * 10 - y);
    }
  }
}

/** Asserts that a surface matches the reference pattern exactly. */
static void check_surface(
  const yguilib_sdl3_image_Surface *surf,
  const uint8_t *ref
) {
  assert(surf != NULL);
  int w = 0;
  int h = 0;
  assert(yguilib_sdl3_image_get_surface_size(surf, &w, &h) == 0);
  assert(w == PAT_W && h == PAT_H);
  const int pitch = yguilib_sdl3_image_get_surface_pitch(surf);
  assert(pitch >= PAT_W * 4);
  const uint8_t *px = yguilib_sdl3_image_get_surface_pixels(surf);
  assert(px != NULL);
  for (int y = 0; y < PAT_H; ++y) {
    const int cmp = memcmp(px + y * pitch, ref + y * PAT_W * 4, PAT_W * 4);
    assert(cmp == 0);
    (void)cmp;
  }
}

static void check_failures(const uint8_t *ref) {
  assert(yguilib_sdl3_image_load_file(NULL) == NULL);
  assert(yguilib_sdl3_image_load_file("/nonexistent/none.png") == NULL);
  assert(yguilib_sdl3_image_get_error() != NULL);
  assert(yguilib_sdl3_image_load_mem(NULL, 10) == NULL);
  assert(yguilib_sdl3_image_load_mem(ref, 0) == NULL);
  assert(yguilib_sdl3_image_load_mem(ref, 16) == NULL);

  assert(yguilib_sdl3_image_save_png(NULL, 4, 4, 16, "/tmp/x.png") == -1);
  assert(yguilib_sdl3_image_save_png(ref, 4, 4, 16, NULL) == -1);
  assert(yguilib_sdl3_image_save_png(ref, 0, 4, 16, "/tmp/x.png") == -1);
  assert(yguilib_sdl3_image_save_png(ref, 4, 4, 8, "/tmp/x.png") == -1);

  int w = -1;
  assert(yguilib_sdl3_image_get_surface_size(NULL, &w, NULL) == -1);
  assert(w == -1);
  assert(yguilib_sdl3_image_get_surface_pitch(NULL) == 0);
  assert(yguilib_sdl3_image_get_surface_pixels(NULL) == NULL);
  yguilib_sdl3_image_destroy_surface(NULL);
  (void)w;
}

int main(void) {
  uint8_t ref[PAT_W * PAT_H * 4];
  fill_pattern(ref);

  check_failures(ref);

  const char *tmp_dir = getenv("TMPDIR");
  if (!tmp_dir || !tmp_dir[0]) {
    tmp_dir = "/tmp";
  }
  char path[1024];
  const int n = snprintf(
    path,
    sizeof(path),
    "%s/yguilib_sdl3_image_test.png",
    tmp_dir
  );
  assert(n > 0 && (size_t)n < sizeof(path));
  (void)n;

  // Save, then reload from file
  const int save_res = yguilib_sdl3_image_save_png(
    ref,
    PAT_W,
    PAT_H,
    PAT_W * 4,
    path
  );
  if (save_res != 0) {
    fprintf(stderr, "save_png: %s\n", yguilib_sdl3_image_get_error());
  }
  assert(save_res == 0);

  yguilib_sdl3_image_Surface *from_file = yguilib_sdl3_image_load_file(
    path
  );
  check_surface(from_file, ref);
  yguilib_sdl3_image_destroy_surface(from_file);

  // Reload from memory
  size_t size = 0;
  void *bytes = SDL_LoadFile(path, &size);
  assert(bytes != NULL && size > 0);
  yguilib_sdl3_image_Surface *from_mem = yguilib_sdl3_image_load_mem(
    bytes,
    size
  );
  check_surface(from_mem, ref);
  yguilib_sdl3_image_destroy_surface(from_mem);
  SDL_free(bytes);

  remove(path);
  printf("yguilib_sdl3_image tests passed\n");
  return 0;
}
