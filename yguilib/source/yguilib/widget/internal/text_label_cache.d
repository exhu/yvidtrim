module yguilib.widget.internal.text_label_cache;

package(yguilib):
import yguilib.render : Renderer;
import yguilib.render.font : Font;
import yguilib.render.render_types : PointF;
import yguilib.widget.internal.layout_text : FormattedTextLine,
  TextAlignment, TextLayoutParams, layoutTextLines, measureTextContentSize;

/// Shared cache key for text layout and content-size caches.
struct TextLayoutKey {
  float availWidth = -1.0f;
  float availHeight = -1.0f;
  string caption;
  ulong fontId = 0;
  float fontScaledSize = -1.0f;
  bool multiline;
  bool ellipsis;
  TextAlignment alignment = TextAlignment.left;

  ref TextLayoutKey withSize(float availW, float availH) return {
    availWidth = availW;
    availHeight = availH;
    return this;
  }

  ref TextLayoutKey withCaption(string cap) return {
    caption = cap;
    return this;
  }

  ref TextLayoutKey withFont(const Font f) return {
    fontId = f !is null ? f.id : 0;
    fontScaledSize = f !is null ? f.scaledSize : -1.0f;
    return this;
  }

  ref TextLayoutKey withMultiline(bool multi) return {
    multiline = multi;
    return this;
  }

  ref TextLayoutKey withEllipsis(bool ell) return {
    ellipsis = ell;
    return this;
  }

  ref TextLayoutKey withAlignment(TextAlignment al) return {
    alignment = al;
    return this;
  }

  TextLayoutParams toLayoutParams() const {
    TextLayoutParams p;
    p.withCaption(caption)
      .withMultiline(multiline)
      .withEllipsis(ellipsis)
      .withAlignment(alignment)
      .withAvailableSize(availWidth, availHeight);
    return p;
  }
}

/// Cached result of text line layout for a TextLabel.
///
/// Key fields mirror TextLabel's formatting parameters plus the
/// available space dimensions. Embed by value inside TextLabel as a
/// package(yguilib) field.
struct TextLayoutCache {
  FormattedTextLine[] lines;
  TextLayoutKey key;
  bool valid;

  /// Returns true when all key parameters match the stored state.
  bool isValid(in TextLayoutKey k) const {
    return valid && key == k;
  }

  /// Stores a freshly computed result along with the key that produced it.
  void store(FormattedTextLine[] result, in TextLayoutKey k) {
    lines = result;
    key = k;
    valid = true;
  }
}

/// Cached result of text content-size measurement for a TextLabel.
///
/// Key fields mirror TextLabel's formatting parameters plus the
/// available space dimensions. Embed by value inside TextLabel as a
/// package(yguilib) field.
struct TextContentSizeCache {
  PointF size;
  TextLayoutKey key;
  bool valid;

  /// Returns true when all key parameters match the stored state.
  bool isValid(in TextLayoutKey k) const {
    return valid && key == k;
  }

  /// Stores a freshly computed result along with the key that produced it.
  void store(PointF sz, in TextLayoutKey k) {
    size = sz;
    key = k;
    valid = true;
  }
}

/// Lays out text lines, returning the cached result when all key
/// parameters are unchanged.
///
/// Params:
///   cache - Cache embedded in the TextLabel (mutable ref).
///   r     - Renderer; must not be null.
///   font  - Resolved font; must not be null.
///   key   - Layout key (including font id/scaledSize and available bounds).
const(FormattedTextLine)[] layoutLines(
  ref TextLayoutCache cache,
  Renderer r,
  Font font,
  in TextLayoutKey key
) {
  assert(r !is null);
  assert(font !is null);
  if (cache.isValid(key)) {
    return cache.lines;
  }
  auto result = layoutTextLines(r, font, key.toLayoutParams());
  cache.store(result, key);
  return result;
}

/// Measures the bounding content size for given text layout parameters,
/// returning the cached result when all key parameters are unchanged.
///
/// Params:
///   cache - Cache embedded in the TextLabel (mutable ref).
///   r     - Renderer; must not be null.
///   font  - Resolved font; must not be null.
///   key   - Layout key (including font id/scaledSize and available bounds).
PointF textContentSize(
  ref TextContentSizeCache cache,
  Renderer r,
  Font font,
  in TextLayoutKey key
) {
  assert(r !is null);
  assert(font !is null);
  if (cache.isValid(key)) {
    return cache.size;
  }
  const PointF sz = measureTextContentSize(r, font, key.toLayoutParams());
  cache.store(sz, key);
  return sz;
}

unittest {
  import yguilib.clibs.sdl3 : yguilib_sdl3_init, yguilib_sdl3_quit;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_text_label_cache");
  win.create();
  scope(exit) win.destroy();

  auto r = new Renderer(320, 240, 1.0f);
  scope(exit) r.destroy();

  auto font1 = r.font(14.0f, null);
  assert(font1 !is null);

  // Empty result ([] from tiny height) still caches with valid = true
  TextLayoutCache layoutCache;
  TextLayoutKey emptyKey;
  emptyKey.withSize(200.0f, 1.0f)
    .withCaption("Line 1")
    .withFont(font1)
    .withMultiline(true)
    .withEllipsis(true)
    .withAlignment(TextAlignment.left);

  auto emptyLines = layoutLines(layoutCache, r, font1, emptyKey);
  assert(emptyLines.length == 0);
  assert(layoutCache.valid);
  assert(layoutCache.isValid(emptyKey));

  // Subsequent call hits cache without recomputing
  auto emptyLines2 = layoutLines(layoutCache, r, font1, emptyKey);
  assert(emptyLines2.length == 0);

  // Changing font.id invalidates cache
  auto font2 = r.font(18.0f, null);
  assert(font2 !is null && font2.id != font1.id);
  TextLayoutKey keyFont2 = emptyKey;
  keyFont2.withFont(font2);
  assert(!layoutCache.isValid(keyFont2));

  // Changing scale (font.scaledSize) invalidates cache even at same ptSize
  auto rHiDpi = new Renderer(320, 240, 2.0f);
  scope(exit) rHiDpi.destroy();
  auto fontHiDpi = rHiDpi.font(14.0f, null);
  assert(fontHiDpi !is null);
  TextLayoutKey keyHiDpi = emptyKey;
  keyHiDpi.withFont(fontHiDpi);
  assert(!layoutCache.isValid(keyHiDpi));

  // TextContentSizeCache hit/miss and font invalidation
  TextContentSizeCache sizeCache;
  TextLayoutKey szKey;
  szKey.withSize(0.0f, 0.0f)
    .withCaption("Hello")
    .withFont(font1);
  const PointF s1 = textContentSize(sizeCache, r, font1, szKey);
  assert(s1.x > 0.0f && sizeCache.valid);
  const PointF s2 = textContentSize(sizeCache, r, font1, szKey);
  assert(s2 == s1);
  TextLayoutKey szKeyHiDpi = szKey;
  szKeyHiDpi.withFont(fontHiDpi);
  assert(!sizeCache.isValid(szKeyHiDpi));
}
