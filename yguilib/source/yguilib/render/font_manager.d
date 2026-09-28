module yguilib.render.font_manager;

package(yguilib):

import std.math.traits : isFinite;
import yguilib.assets : defaultTtfFontData;
import yguilib.render.font : Font, defaultFontPtSize;

private enum FontSourceType {
  memory,
  file,
}

private struct FontSource {
  FontSourceType type;
  const(void)[] memoryData;
  string filePath;
}

private struct FontKey {
  string faceName;
  int sizeMilli;
}

final class FontManager {
  private FontSource[string] registry;
  private Font[FontKey] cache;

  ~this() {
    destroy();
  }

  void destroy() {
    foreach (font; cache) {
      if (font !is null) {
        font.destroy();
      }
    }
    cache.clear();
    registry.clear();
  }

  void registerFont(string fontName, const(void)[] fontData) {
    assert(fontName.length > 0, "fontName must not be empty");
    assert(fontData.length > 0, "fontData must not be empty");
    registry[fontName] = FontSource(
      FontSourceType.memory,
      fontData,
      null
    );
  }

  void registerFont(string fontName, string filePath) {
    assert(fontName.length > 0, "fontName must not be empty");
    assert(filePath.length > 0, "filePath must not be empty");
    registry[fontName] = FontSource(
      FontSourceType.file,
      null,
      filePath
    );
  }

  bool hasFont(string fontName) const {
    if (fontName.length == 0 || fontName == "default") {
      return true;
    }
    return (fontName in registry) !is null;
  }

  Font getFont(
    float ptSize = defaultFontPtSize,
    string fontName = null,
    float totalScale = 1.0f
  ) {
    const float sanitizedSize =
      (isFinite(ptSize) && ptSize > 0.0f) ? ptSize : defaultFontPtSize;
    const string effectiveFace =
      (fontName.length > 0 && fontName != "default") ? fontName : "";
    const int sizeMilli = cast(int)(sanitizedSize * 1000.0f + 0.5f);

    FontKey key = FontKey(effectiveFace, sizeMilli);
    auto p = key in cache;
    if (p !is null && *p !is null) {
      return *p;
    }

    FontSource source;
    if (effectiveFace.length == 0) {
      source = FontSource(
        FontSourceType.memory,
        cast(const(void)[])defaultTtfFontData,
        null
      );
    } else {
      auto reg = effectiveFace in registry;
      if (reg !is null) {
        source = *reg;
      } else {
        source = FontSource(
          FontSourceType.memory,
          cast(const(void)[])defaultTtfFontData,
          null
        );
      }
    }

    Font font;
    if (source.type == FontSourceType.memory) {
      font = new Font(source.memoryData, sanitizedSize, totalScale);
    } else {
      font = new Font(source.filePath, sanitizedSize, totalScale);
    }

    cache[key] = font;
    return font;
  }

  void setScaling(float totalScale) {
    foreach (font; cache) {
      if (font !is null) {
        font.setScale(totalScale);
      }
    }
  }
}

unittest {
  import yguilib.clibs.sdl3;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto fm = new FontManager();
  scope(exit) fm.destroy();

  // Verify default font lookup
  Font f11 = fm.getFont(11.0f);
  assert(f11 !is null);
  assert(f11.size == 11.0f);

  // Requesting the exact same font size reuses the cached instance
  Font f11Again = fm.getFont(11.0f);
  assert(f11 is f11Again);

  // Requesting a different size returns a distinct Font instance
  Font f24 = fm.getFont(24.0f);
  assert(f24 !is null);
  assert(f24.size == 24.0f);
  assert(f24 !is f11);

  // Fallbacks for invalid sizes
  assert(fm.getFont(0.0f).size == defaultFontPtSize);
  assert(fm.getFont(-5.0f).size == defaultFontPtSize);
  assert(fm.getFont(float.nan).size == defaultFontPtSize);
  assert(fm.getFont(float.infinity).size == defaultFontPtSize);

  // Scaling update
  fm.setScaling(2.0f);
  assert(f11.scaledSize == 22.0f);
  assert(f24.scaledSize == 48.0f);
}
