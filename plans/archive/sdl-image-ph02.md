# sdl-image ph02: Image, Texture, drawImage

Overview: [sdl-image.md](sdl-image.md). Read `AGENTS.md` and
`codestyle.md` first.

## Context
- ph01 added `yguilib.clibs.sdl3_image` (bindings for load_file/load_mem,
  surface size/pitch/pixels/destroy, save_png and get_error). Pixels are
  RGBA32 (bytes R,G,B,A).
- `render/internal/text_cache.d` has the private static
  `TextCache.uploadTextPixels(pixels, w, h, pitch)`, which creates a
  GL_RGBA texture with linear filtering and clamp-to-edge, and handles
  `GL_UNPACK_ROW_LENGTH`.
- `render/internal/gl_util.d` holds the shared GL helpers.
- `render/package.d` `Renderer.drawTexture(texId, destRect, color)` calls
  `texPipeline.drawTexture`. `TexturePipeline.drawTexturedQuad(texId,
  TexturedQuad(dest, uv, color), vw, vh)` is in `render/internal/
  pipelines.d` and uses straight alpha blending
  (`GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA`). The UV origin matches the
  top-down upload, as text uploads already do.
- GL pixel tests: see the `unittest` in `render/package.d` after the
  Renderer class (create a `Window(320, 240)`, then `renderer.clearFrame`,
  draw, and `glReadPixels`, where GL y = height - 1 - y).
- Modules are listed in `yguilib_src` in `yguilib/meson.build`.

## Steps
1. Move `uploadTextPixels` into `gl_util.d` as
   `GLuint uploadRgbaTexture(const(void)* pixels, int w, int h, int pitch)`,
   with the same behavior; reset `GL_UNPACK_ROW_LENGTH` to 0 afterwards.
   TextCache then calls it. Keep the existing comments.
2. Add `render/image.d` (module `yguilib.render.image`, public):
   ```
   final class Image {
     this(int width, int height);          // zeroed (transparent)
     int width() const; int height() const;
     ubyte[] pixels;                       // RGBA8, top-down, pitch w*4
     static Image loadFromFile(string path);       // null + log on fail
     static Image loadFromMemory(const(void)[] data);
     bool savePng(string path) const;
     void flipVertical();
   }
   ```
   It copies pixels out of the C surface row by row, honoring pitch, and
   destroys the surface with `scope(exit)`. It logs through std.logger with
   `yguilib_sdl3_image_get_error()`. Use `std.string.toStringz` for paths.
   Unit tests need no GL: a save/load round trip in `std.file.tempDir`, plus
   flipVertical and the failure cases.
3. Add `render/texture.d` (`yguilib.render.texture`, public):
   `final class Texture` with `width`, `height`,
   `package(yguilib) GLuint id`, a `package(yguilib)` constructor taking an
   `Image`, `void update(in Image)` (re-uploads, which may resize), and
   `destroy()` (idempotent). `~this` must not call GL when the GC finalizes
   it, so follow the RAII conventions in ARCHITECTURE.md: check how
   TextTexture and Font handle this and document the rule.
4. In `Renderer`:
   - `Texture createTexture(in Image img)` returns null if the renderer is
     not initialized or the image is null or empty.
   - `void drawImage(Texture t, RectF dest, ColorF tint = ColorF(1,1,1,1))`
   - `void drawImage(Texture t, RectF dest, RectF srcPx, ColorF tint)`,
     where the UV is `srcPx / (t.width, t.height)`.
   Both take logic coordinates for `dest`, as `drawTexture` does. A null
   texture is a no-op.
5. GL unittests in `render/package.d` or `texture.d`: build a 2x2 image
   (red, green / blue, white), draw it to RectF(0,0,100,100) with nearest
   sampling or read at the quadrant centers, and check the colors and
   orientation. Then draw a src sub-rect (only blue), draw with a 50% alpha
   tint over black, and test `update()`.
6. Register `image.d` and `texture.d` in `yguilib_src`.

## Verification
`ninja -C _build && meson test -C _build`. Lines must be at most 80 chars.
