# sdl-image ph01: C wrapper and D bindings

Overview: [sdl-image.md](sdl-image.md). Read `AGENTS.md` (wrapper rules)
and `codestyle.md` first.

## Context
- Existing wrappers: `yguilib/yguilib-clibs/yguilib_sdl3_ttf.[c|h]`, with
  tests in `yguilib_sdl3_ttf_test.c` and build rules in
  `yguilib/yguilib-clibs/meson.build`. The D bindings are in
  `yguilib/source/yguilib/clibs/sdl3_ttf.d` (`package(yguilib):`, opaque
  structs, `extern(C)` block).
- `yguilib/meson.build` lists the D sources in `yguilib_src` and the
  dependencies in `yguilib_deps`.
- SDL3_image 3.x needs no `IMG_Init`. Use `IMG_Load`, `IMG_Load_IO`
  (`SDL_IOFromConstMem`, closeio=true) and `IMG_SavePNG`.

## Steps
1. Add `yguilib/yguilib-clibs/yguilib_sdl3_image.h`, documented in the same
   style as `yguilib_sdl3_ttf.h` (each param, return and NULL behaviour):
   ```
   typedef struct yguilib_sdl3_image_Surface yguilib_sdl3_image_Surface;
   yguilib_sdl3_image_Surface *yguilib_sdl3_image_load_file(const char *p);
   yguilib_sdl3_image_Surface *yguilib_sdl3_image_load_mem(
     const void *data, size_t size);
   int yguilib_sdl3_image_get_surface_size(const ... *s, int *w, int *h);
   int yguilib_sdl3_image_get_surface_pitch(const ... *s);
   const void *yguilib_sdl3_image_get_surface_pixels(const ... *s);
   void yguilib_sdl3_image_destroy_surface(... *s);   /* NULL ignored */
   int yguilib_sdl3_image_save_png(const void *rgba, int w, int h,
     int pitch, const char *path);                    /* 0 / -1 */
   const char *yguilib_sdl3_image_get_error(void);    /* SDL_GetError */
   ```
   Loaded surfaces are always converted to `SDL_PIXELFORMAT_RGBA32` (byte
   order R,G,B,A in memory). save_png wraps the pixels with
   `SDL_CreateSurfaceFrom(w, h, SDL_PIXELFORMAT_RGBA32, ...)` without
   copying them.
2. Add `yguilib_sdl3_image.c`, which implements the header. The opaque type
   is just a cast of `SDL_Surface`, or a struct wrapping one.
3. Add `yguilib_sdl3_image_test.c`, which builds a 4x4 pattern with distinct
   RGBA values (including a partial alpha), saves it to a temp path (use
   `SDL_GetPrefPath`-free logic such as `getenv("TMPDIR")` or "/tmp"), reloads
   it from the file and from memory (read the bytes with SDL_LoadFile), and
   compares every pixel. It also checks the failure paths: a missing file,
   NULL args, and size 0.
4. In `yguilib-clibs/meson.build`, add `dep_sdl3_image = dependency(
   'sdl3-image')`, a static lib `yguilib_sdl3_image` with hidden visibility,
   the test `yguilib_sdl3_image`, and `yguilib_sdl3_image_dep`. Add it to
   `yguilib_deps` in `yguilib/meson.build`.
5. Add `yguilib/source/yguilib/clibs/sdl3_image.d` with the bindings
   (camelCase param names, as in sdl3_ttf.d), and register it in
   `yguilib_src`.
6. Update `dub.json` files only if they list C libs or sources explicitly.
   Check them, but they are for IDE use only.

## Verification
`ninja -C _build && meson test -C _build`: `yguilib_sdl3_image` passes.
Lines must be at most 80 chars.
