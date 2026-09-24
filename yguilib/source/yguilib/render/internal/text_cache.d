module yguilib.render.internal.text_cache;

package(yguilib):

import glad2.gles2;
import yguilib.clibs.sdl3_ttf;
import yguilib.render.font : Font;

struct TextTexture {
  GLuint textureId = 0;
  int width = 0;
  int height = 0;

  bool isValid() const {
    return textureId != 0;
  }

  void destroy() {
    if (textureId != 0) {
      glDeleteTextures(1, &textureId);
      textureId = 0;
    }
    width = 0;
    height = 0;
  }
}

private struct TextCacheKey {
  void* fontHandle;
  float ptSize;
  string text;
}

final class TextCache {
  enum size_t maxCacheEntries = 512;

  ~this() {
    clear();
  }

  void clear() {
    foreach (key, tex; cache) {
      tex.destroy();
    }
    cache.clear();
  }

  TextTexture getOrCreate(Font font, string text) {
    if (font is null || font.handle is null || text.length == 0) {
      return TextTexture();
    }

    TextCacheKey key = TextCacheKey(font.handle, font.scaledSize, text);
    auto p = key in cache;
    if (p !is null) {
      return *p;
    }

    if (cache.length >= maxCacheEntries) {
      clear();
    }

    TextTexture tex = createTextTexture(font, text);
    if (tex.isValid()) {
      cache[key] = tex;
    }
    return tex;
  }

  static TextTexture createTextTexture(Font font, string text) {
    if (font is null || font.handle is null || text.length == 0) {
      return TextTexture();
    }

    auto surf = yguilib_sdl3_ttf_render_text_blended(
      font.handle,
      text.ptr,
      text.length,
      255,
      255,
      255,
      255
    );
    if (surf is null) {
      return TextTexture();
    }
    scope(exit) yguilib_sdl3_ttf_destroy_surface(surf);

    int w = 0;
    int h = 0;
    yguilib_sdl3_ttf_get_surface_size(surf, &w, &h);
    int pitch = yguilib_sdl3_ttf_get_surface_pitch(surf);
    const void* pixels = yguilib_sdl3_ttf_get_surface_pixels(surf);
    if (w <= 0 || h <= 0 || pixels is null) {
      return TextTexture();
    }

    GLuint texId;
    glGenTextures(1, &texId);
    glBindTexture(GL_TEXTURE_2D, texId);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    if (pitch != w * 4) {
      glPixelStorei(GL_UNPACK_ROW_LENGTH, pitch / 4);
    }
    glTexImage2D(
      GL_TEXTURE_2D,
      0,
      GL_RGBA,
      w,
      h,
      0,
      GL_RGBA,
      GL_UNSIGNED_BYTE,
      pixels
    );
    if (pitch != w * 4) {
      glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    }
    glBindTexture(GL_TEXTURE_2D, 0);

    return TextTexture(texId, w, h);
  }

  private TextTexture[TextCacheKey] cache;
}
