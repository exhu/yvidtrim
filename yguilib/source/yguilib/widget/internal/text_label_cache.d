module yguilib.widget.internal.text_label_cache;

package(yguilib):
import yguilib.render : Renderer;
import yguilib.render.font : Font;
import yguilib.render.render_types : PointF;
import yguilib.widget.internal.layout_text : FormattedTextLine,
  TextAlignment, layoutTextLines, measureTextContentSize;

/// Cached result of text line layout for a TextLabel.
///
/// Key fields mirror TextLabel's formatting parameters plus the
/// available space dimensions. Embed by value inside TextLabel as a
/// package(yguilib) field.
struct TextLayoutCache {
  FormattedTextLine[] lines;
  float width = -1.0f;
  float height = -1.0f;
  string caption;
  float fontSize = -1.0f;
  /// Empty means the default embedded font.
  string font;
  bool multiline;
  bool ellipsis;
  TextAlignment alignment;

  /// Returns true when all key parameters match the stored state.
  bool isValid(
    float availW,
    float availH,
    string cap,
    float fSize,
    string fName,
    bool multi,
    bool ell,
    TextAlignment al
  ) const {
    return lines.length > 0 &&
      width == availW &&
      height == availH &&
      caption == cap &&
      fontSize == fSize &&
      font == fName &&
      multiline == multi &&
      ellipsis == ell &&
      alignment == al;
  }

  /// Stores a freshly computed result along with the key that produced it.
  void store(
    FormattedTextLine[] result,
    float availW,
    float availH,
    string cap,
    float fSize,
    string fName,
    bool multi,
    bool ell,
    TextAlignment al
  ) {
    lines = result;
    width = availW;
    height = availH;
    caption = cap;
    fontSize = fSize;
    font = fName;
    multiline = multi;
    ellipsis = ell;
    alignment = al;
  }
}

/// Cached result of text content-size measurement for a TextLabel.
///
/// Key fields mirror TextLabel's formatting parameters plus the
/// available space dimensions. Embed by value inside TextLabel as a
/// package(yguilib) field.
struct TextContentSizeCache {
  PointF size;
  float availWidth = -1.0f;
  float availHeight = -1.0f;
  string caption;
  float fontSize = -1.0f;
  /// Empty means the default embedded font.
  string font;
  bool multiline;
  bool ellipsis;
  bool valid;

  /// Returns true when all key parameters match the stored state.
  bool isValid(
    float availW,
    float availH,
    string cap,
    float fSize,
    string fName,
    bool multi,
    bool ell
  ) const {
    return valid &&
      availWidth == availW &&
      availHeight == availH &&
      caption == cap &&
      fontSize == fSize &&
      font == fName &&
      multiline == multi &&
      ellipsis == ell;
  }

  /// Stores a freshly computed result along with the key that produced it.
  void store(
    PointF sz,
    float availW,
    float availH,
    string cap,
    float fSize,
    string fName,
    bool multi,
    bool ell
  ) {
    size = sz;
    availWidth = availW;
    availHeight = availH;
    caption = cap;
    fontSize = fSize;
    font = fName;
    multiline = multi;
    ellipsis = ell;
    valid = true;
  }
}

/// Lays out text lines, returning the cached result when all key
/// parameters are unchanged.
///
/// Params:
///   cache          - Cache embedded in the TextLabel (mutable ref).
///   r              - Renderer; must not be null.
///   font           - Resolved font; must not be null.
///   fontName       - Font name key from TextLabel.font (empty = default).
///   caption        - Text to lay out.
///   multiline      - When true, preserves line breaks and word-wraps.
///   overflowEllipsis - When true, truncates overflow with "...".
///   alignment      - Horizontal alignment within the available width.
///   availableWidth - Available horizontal space (0 = unlimited).
///   availableHeight - Available vertical space (0 = unlimited).
FormattedTextLine[] getLayoutLines(
  ref TextLayoutCache cache,
  Renderer r,
  Font font,
  string fontName,
  string caption,
  bool multiline,
  bool overflowEllipsis,
  TextAlignment alignment,
  float availableWidth,
  float availableHeight = 0.0f
) {
  if (r is null || font is null) {
    return [];
  }
  if (cache.isValid(
        availableWidth, availableHeight,
        caption, font.size, fontName,
        multiline, overflowEllipsis, alignment)) {
    return cache.lines;
  }
  auto result = layoutTextLines(
    r, font, caption, multiline, overflowEllipsis,
    alignment, availableWidth, availableHeight
  );
  cache.store(
    result,
    availableWidth, availableHeight,
    caption, font.size, fontName,
    multiline, overflowEllipsis, alignment
  );
  return result;
}

/// Measures the bounding content size for given text layout parameters,
/// returning the cached result when all key parameters are unchanged.
///
/// Params:
///   cache           - Cache embedded in the TextLabel (mutable ref).
///   r               - Renderer; must not be null.
///   font            - Resolved font; must not be null.
///   fontName        - Font name key from TextLabel.font (empty = default).
///   caption         - Text to measure.
///   multiline       - When true, preserves line breaks and word-wraps.
///   overflowEllipsis - When true, truncates overflow with "...".
///   availableWidth  - Available horizontal space (0 = unlimited).
///   availableHeight - Available vertical space (0 = unlimited).
PointF getTextContentSize(
  ref TextContentSizeCache cache,
  Renderer r,
  Font font,
  string fontName,
  string caption,
  bool multiline,
  bool overflowEllipsis,
  float availableWidth = 0.0f,
  float availableHeight = 0.0f
) {
  if (r is null || font is null) {
    return PointF(0.0f, 0.0f);
  }
  if (cache.isValid(
        availableWidth, availableHeight,
        caption, font.size, fontName,
        multiline, overflowEllipsis)) {
    return cache.size;
  }
  const PointF sz = measureTextContentSize(
    r, font, caption, multiline, overflowEllipsis,
    availableWidth, availableHeight
  );
  cache.store(
    sz,
    availableWidth, availableHeight,
    caption, font.size, fontName,
    multiline, overflowEllipsis
  );
  return sz;
}
