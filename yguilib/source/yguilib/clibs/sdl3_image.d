/// Bindings to yguilib_sdl3_image C library.
module yguilib.clibs.sdl3_image;

package(yguilib):

struct yguilib_sdl3_image_Surface;

extern(C) nothrow @nogc {
  /// Loads an image file as RGBA32. Returns null on failure or null path.
  /// Free with yguilib_sdl3_image_destroy_surface.
  yguilib_sdl3_image_Surface* yguilib_sdl3_image_load_file(
    const(char)* path
  );

  /// Decodes image bytes as RGBA32; data is not retained after return.
  /// Returns null on failure, null data, or zero size.
  yguilib_sdl3_image_Surface* yguilib_sdl3_image_load_mem(
    const(void)* data,
    size_t size
  );

  /// Gets surface width and height; w/h may be null.
  /// Returns 0 on success or -1 on error (including null surface).
  int yguilib_sdl3_image_get_surface_size(
    const(yguilib_sdl3_image_Surface)* surface,
    int* w,
    int* h
  );

  /// Gets surface row pitch in bytes, or 0 on error (including null surface).
  int yguilib_sdl3_image_get_surface_pitch(
    const(yguilib_sdl3_image_Surface)* surface
  );

  /// Returns borrowed RGBA32 pixels valid until surface is destroyed, or null.
  const(void)* yguilib_sdl3_image_get_surface_pixels(
    const(yguilib_sdl3_image_Surface)* surface
  );

  /// Destroys a surface handle; null is ignored.
  void yguilib_sdl3_image_destroy_surface(
    yguilib_sdl3_image_Surface* surface
  );

  /// Saves RGBA32 pixels to a PNG file; rgba/path must be non-null.
  /// Returns 0 on success or -1 on failure.
  int yguilib_sdl3_image_save_png(
    const(void)* rgba,
    int w,
    int h,
    int pitch,
    const(char)* path
  );

  /// Returns non-null borrowed error string valid until next SDL call.
  const(char)* yguilib_sdl3_image_get_error();
}

unittest {
  yguilib_sdl3_image_destroy_surface(null);
  assert(yguilib_sdl3_image_load_file(null) is null);
  assert(yguilib_sdl3_image_load_mem(null, 0) is null);
  assert(yguilib_sdl3_image_get_surface_size(null, null, null) == -1);
  assert(yguilib_sdl3_image_get_surface_pitch(null) == 0);
  assert(yguilib_sdl3_image_get_surface_pixels(null) is null);
  assert(yguilib_sdl3_image_save_png(null, 0, 0, 0, null) == -1);
  assert(yguilib_sdl3_image_get_error() !is null);
}
