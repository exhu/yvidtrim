/// bindings to yguilib-clib-sdl3_image C library
module yguilib.clibs.sdl3_image;

package(yguilib):

struct yguilib_sdl3_image_Surface;

extern(C) {
  yguilib_sdl3_image_Surface* yguilib_sdl3_image_load_file(
    const(char)* path
  );

  yguilib_sdl3_image_Surface* yguilib_sdl3_image_load_mem(
    const(void)* data,
    size_t size
  );

  int yguilib_sdl3_image_get_surface_size(
    const(yguilib_sdl3_image_Surface)* surface,
    int* w,
    int* h
  );

  int yguilib_sdl3_image_get_surface_pitch(
    const(yguilib_sdl3_image_Surface)* surface
  );

  const(void)* yguilib_sdl3_image_get_surface_pixels(
    const(yguilib_sdl3_image_Surface)* surface
  );

  void yguilib_sdl3_image_destroy_surface(
    yguilib_sdl3_image_Surface* surface
  );

  int yguilib_sdl3_image_save_png(
    const(void)* rgba,
    int w,
    int h,
    int pitch,
    const(char)* path
  );

  const(char)* yguilib_sdl3_image_get_error();
}
