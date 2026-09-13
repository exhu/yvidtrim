#include "yguilib_sdl3_ttf.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

#ifndef FONT_PATH
#define FONT_PATH "yguilib/assets/yguilib/fonts/GoogleSansCode-Regular.ttf"
#endif

int main(void) {
  int init_res = yguilib_sdl3_ttf_init();
  assert(init_res == 0);

  // Invalid parameters
  assert(yguilib_sdl3_ttf_open_font(NULL, 16.0f) == NULL);
  assert(yguilib_sdl3_ttf_open_font("nonexistent_path.ttf", 16.0f) == NULL);
  assert(yguilib_sdl3_ttf_open_font_from_mem(NULL, 0, 16.0f) == NULL);

  // Open font from file
  yguilib_sdl3_ttf_Font *font = yguilib_sdl3_ttf_open_font(
    FONT_PATH,
    16.0f
  );
  assert(font != NULL);

  // Metrics
  int height = yguilib_sdl3_ttf_get_font_height(font);
  int ascent = yguilib_sdl3_ttf_get_font_ascent(font);
  int descent = yguilib_sdl3_ttf_get_font_descent(font);
  int line_skip = yguilib_sdl3_ttf_get_font_line_skip(font);
  assert(height > 0);
  assert(ascent > 0);
  assert(line_skip > 0);
  (void)descent;

  // Text size
  int w = 0;
  int h = 0;
  int size_res = yguilib_sdl3_ttf_get_text_size(font, "Hello", 5, &w, &h);
  assert(size_res == 0);
  assert(w > 0 && h > 0);

  int empty_w = -1;
  int empty_h = -1;
  int empty_res = yguilib_sdl3_ttf_get_text_size(
    font,
    "",
    0,
    &empty_w,
    &empty_h
  );
  assert(empty_res == 0);
  assert(empty_w == 0 && empty_h == 0);

  // Render text blended
  yguilib_sdl3_ttf_Surface *surf = yguilib_sdl3_ttf_render_text_blended(
    font,
    "Hello",
    5,
    255,
    255,
    255,
    255
  );
  assert(surf != NULL);

  int sw = 0;
  int sh = 0;
  int surf_size_res = yguilib_sdl3_ttf_get_surface_size(surf, &sw, &sh);
  assert(surf_size_res == 0);
  assert(sw > 0 && sh > 0);

  int pitch = yguilib_sdl3_ttf_get_surface_pitch(surf);
  assert(pitch >= sw * 4);

  const void *pixels = yguilib_sdl3_ttf_get_surface_pixels(surf);
  assert(pixels != NULL);

  yguilib_sdl3_ttf_destroy_surface(surf);
  yguilib_sdl3_ttf_close_font(font);

  // Open font from memory
  FILE *f = fopen(FONT_PATH, "rb");
  assert(f != NULL);
  fseek(f, 0, SEEK_END);
  long file_size = ftell(f);
  assert(file_size > 0);
  fseek(f, 0, SEEK_SET);

  char *buffer = (char *)malloc((size_t)file_size);
  assert(buffer != NULL);
  size_t read_bytes = fread(buffer, 1, (size_t)file_size, f);
  assert(read_bytes == (size_t)file_size);
  fclose(f);

  yguilib_sdl3_ttf_Font *mem_font = yguilib_sdl3_ttf_open_font_from_mem(
    buffer,
    (size_t)file_size,
    14.0f
  );
  assert(mem_font != NULL);

  int mem_w = 0;
  int mem_h = 0;
  assert(
    yguilib_sdl3_ttf_get_text_size(mem_font, "Test", 4, &mem_w, &mem_h) == 0
  );
  assert(mem_w > 0 && mem_h > 0);

  // In-place dynamic resizing test
  int initial_height = yguilib_sdl3_ttf_get_font_height(mem_font);
  assert(initial_height > 0);
  assert(yguilib_sdl3_ttf_set_font_size(mem_font, 28.0f) == 0);
  int resized_height = yguilib_sdl3_ttf_get_font_height(mem_font);
  assert(resized_height > initial_height);

  int resized_w = 0;
  int resized_h = 0;
  assert(
    yguilib_sdl3_ttf_get_text_size(mem_font, "Test", 4, &resized_w, &resized_h)
      == 0
  );
  assert(resized_w > mem_w && resized_h > mem_h);

  // Invalid parameters
  assert(yguilib_sdl3_ttf_set_font_size(NULL, 16.0f) == -1);
  assert(yguilib_sdl3_ttf_set_font_size(mem_font, -1.0f) == -1);
  assert(yguilib_sdl3_ttf_set_font_size(mem_font, 0.0f) == -1);

  yguilib_sdl3_ttf_close_font(mem_font);
  free(buffer);

  yguilib_sdl3_ttf_quit();
  return 0;
}
