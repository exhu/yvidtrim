/**
 * CPU-side RGBA8 images: load (file or memory) and save as PNG through the
 * private SDL3_image wrapper. Needs no GL context.
 */
module yguilib.render.image;

import yguilib.clibs.sdl3_image;

/**
 * RGBA8 image with straight (non-premultiplied) alpha. Rows are stored
 * top-down with a tight pitch of `width * 4` bytes (bytes R, G, B, A).
 */
final class Image {
  /**
   * Creates a zeroed (fully transparent) image of `width` x `height`
   * pixels. A zero size gives an empty image.
   */
  this(int width, int height) {
    assert(width >= 0 && height >= 0, "image size must not be negative");
    fWidth = width;
    fHeight = height;
    pixels = new ubyte[cast(size_t)width * height * 4];
  }

  /// Width in pixels.
  int width() const {
    return fWidth;
  }

  /// Height in pixels.
  int height() const {
    return fHeight;
  }

  /// True when the image has no pixels.
  bool isEmpty() const {
    return fWidth == 0 || fHeight == 0;
  }

  /// Row pitch in bytes (always `width * 4`).
  int pitch() const {
    return fWidth * 4;
  }

  /**
   * Loads an image file in any format SDL3_image supports.
   *
   * Returns: the image, or null (with an error logged) on failure.
   */
  static Image loadFromFile(string path) {
    import std.logger : errorf;
    import std.string : toStringz;

    if (path.length == 0) {
      errorf("Image.loadFromFile: empty path");
      return null;
    }
    auto surf = yguilib_sdl3_image_load_file(path.toStringz());
    if (surf is null) {
      errorf("Image.loadFromFile(%s) failed: %s", path, lastError());
      return null;
    }
    scope(exit) yguilib_sdl3_image_destroy_surface(surf);
    return imageFromSurface(surf);
  }

  /**
   * Decodes an image from encoded bytes (PNG, JPEG, ...) in memory. The
   * data is not retained.
   *
   * Returns: the image, or null (with an error logged) on failure.
   */
  static Image loadFromMemory(const(void)[] data) {
    import std.logger : errorf;

    if (data.length == 0) {
      errorf("Image.loadFromMemory: empty data");
      return null;
    }
    auto surf = yguilib_sdl3_image_load_mem(data.ptr, data.length);
    if (surf is null) {
      errorf("Image.loadFromMemory failed: %s", lastError());
      return null;
    }
    scope(exit) yguilib_sdl3_image_destroy_surface(surf);
    return imageFromSurface(surf);
  }

  /**
   * Saves the image as a PNG file at `path`.
   *
   * Returns: true on success, false (with an error logged) on failure,
   * including an empty image or path.
   */
  bool savePng(string path) const {
    import std.logger : errorf;
    import std.string : toStringz;

    if (isEmpty() || path.length == 0) {
      errorf("Image.savePng(%s): empty image or path", path);
      return false;
    }
    const int rc = yguilib_sdl3_image_save_png(
      pixels.ptr, fWidth, fHeight, pitch(), path.toStringz()
    );
    if (rc != 0) {
      errorf("Image.savePng(%s) failed: %s", path, lastError());
      return false;
    }
    return true;
  }

  /// Flips the rows in place (top row becomes the bottom row).
  void flipVertical() {
    import std.algorithm.mutation : swapRanges;

    const size_t rowBytes = cast(size_t)pitch();
    foreach (y; 0 .. fHeight / 2) {
      const size_t top = y * rowBytes;
      const size_t bottom = (fHeight - 1 - y) * rowBytes;
      swapRanges(
        pixels[top .. top + rowBytes],
        pixels[bottom .. bottom + rowBytes]
      );
    }
  }

  /// RGBA8 pixel bytes, top-down, pitch `width * 4`.
  ubyte[] pixels;

  invariant {
    assert(pixels.length == cast(size_t)fWidth * fHeight * 4,
      "pixels length must match width * height * 4");
  }

private:
  /// Copies a surface's pixels row by row, honoring its pitch.
  static Image imageFromSurface(const(yguilib_sdl3_image_Surface)* surf) {
    import std.logger : errorf;

    int w = 0;
    int h = 0;
    if (yguilib_sdl3_image_get_surface_size(surf, &w, &h) != 0) {
      errorf("Image: cannot query surface size: %s", lastError());
      return null;
    }
    const int srcPitch = yguilib_sdl3_image_get_surface_pitch(surf);
    const(ubyte)* src =
      cast(const(ubyte)*)yguilib_sdl3_image_get_surface_pixels(surf);
    if (w <= 0 || h <= 0 || src is null || srcPitch < w * 4) {
      errorf("Image: invalid surface (%d x %d, pitch %d)", w, h, srcPitch);
      return null;
    }

    auto img = new Image(w, h);
    const size_t rowBytes = cast(size_t)w * 4;
    foreach (y; 0 .. h) {
      const(ubyte)* row = src + cast(size_t)y * srcPitch;
      img.pixels[y * rowBytes .. (y + 1) * rowBytes] = row[0 .. rowBytes];
    }
    return img;
  }

  static string lastError() {
    import std.string : fromStringz;

    return yguilib_sdl3_image_get_error().fromStringz().idup;
  }

  int fWidth;
  int fHeight;
}

// Zeroed construction and flipVertical row order.
unittest {
  auto img = new Image(2, 3);
  assert(img.width() == 2 && img.height() == 3);
  assert(img.pixels.length == 24);
  foreach (b; img.pixels) {
    assert(b == 0);
  }
  foreach (y; 0 .. 3) {
    img.pixels[y * 8] = cast(ubyte)(10 + y);
  }
  img.flipVertical();
  assert(img.pixels[0] == 12);
  assert(img.pixels[8] == 11);
  assert(img.pixels[16] == 10);

  auto empty = new Image(0, 0);
  assert(empty.isEmpty());
  empty.flipVertical();
}

// PNG save/load round trip through a file and memory.
unittest {
  import std.file : exists, read, remove, tempDir;
  import std.path : buildPath;
  import std.process : thisProcessID;
  import std.conv : to;

  auto img = new Image(3, 2);
  foreach (i; 0 .. img.pixels.length) {
    img.pixels[i] = cast(ubyte)(i * 10 + 5);
  }

  const string path = buildPath(
    tempDir(), "yguilib_image_test_" ~ thisProcessID.to!string ~ ".png"
  );
  assert(img.savePng(path));
  scope(exit) {
    if (exists(path)) {
      remove(path);
    }
  }

  auto loaded = Image.loadFromFile(path);
  assert(loaded !is null);
  assert(loaded.width() == 3 && loaded.height() == 2);
  assert(loaded.pixels == img.pixels);

  auto fromMem = Image.loadFromMemory(read(path));
  assert(fromMem !is null);
  assert(fromMem.pixels == img.pixels);
}

// Failure cases return null/false.
unittest {
  import std.file : tempDir;
  import std.path : buildPath;

  assert(Image.loadFromFile("") is null);
  assert(Image.loadFromFile(
    buildPath(tempDir(), "yguilib_no_such_image_file.png")
  ) is null);
  assert(Image.loadFromMemory(null) is null);
  const ubyte[8] junk = [1, 2, 3, 4, 5, 6, 7, 8];
  assert(Image.loadFromMemory(junk[]) is null);

  assert(!(new Image(0, 0)).savePng(
    buildPath(tempDir(), "yguilib_empty.png")
  ));
  assert(!(new Image(1, 1)).savePng(""));
  assert(!(new Image(1, 1)).savePng(
    buildPath(tempDir(), "no_such_dir_yguilib", "x.png")
  ));
}
