module yguilib.widget.drawing_components;

import yguilib.render : Renderer;
import yguilib.render.font : Font, defaultFontPtSize;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.widget.component;
import yguilib.widget : Widget;
package(yguilib) import yguilib.widget.internal.layout_text : FormattedTextLine,
  TextAlignment, layoutTextLines, sanitizeSingleLine;

class Background : Component {
  enum Style {
    rect,
    round,
    none,
  }
  this(ColorF color, Style style = Style.rect) {
    this.color = color;
    this.style = style;
  }
  ColorF color;
  Style style;
  float cornerRadius = 15.0;
}

class TextLabel : Component {
  // TODO RTL support
  alias Alignment = TextAlignment;

  this(string caption, ColorF color) {
    this.caption = caption;
    this.color = color;
  }
  // empty means default embedded font
  string font;
  // 0 or infinity must fallback to defaultFontPtSize
  float fontSize = defaultFontPtSize;
  string caption = "TextLabel";
  ColorF color = ColorF(1, 1, 1, 1);
  /// When true, enables line wrapping and preserves explicit line breaks.
  /// When false, newlines ('\r\n', '\n', '\r') are replaced with spaces.
  bool multiline;
  /// When true, truncates overflowing text with "...".
  bool overflowEllipsis = true;
  /// Horizontal alignment of text within the content area.
  Alignment alignment = Alignment.left;

  /// Cached text formatting to avoid repeating line splitting, wrapping,
  /// ellipsis truncation, and string measurements when parameters
  /// are unchanged.
  package(yguilib) FormattedTextLine[] cachedLines;
  package(yguilib) float cachedWidth = -1.0f;
  package(yguilib) float cachedHeight = -1.0f;
  package(yguilib) string cachedCaption;
  package(yguilib) float cachedFontSize = -1.0f;
  package(yguilib) string cachedFont;
  package(yguilib) bool cachedMultiline;
  package(yguilib) bool cachedEllipsis;
  package(yguilib) Alignment cachedAlignment;

  // Cached measured content size
  package(yguilib) PointF cachedContentSize;
  package(yguilib) float cachedContentAvailWidth = -1.0f;
  package(yguilib) float cachedContentAvailHeight = -1.0f;
  package(yguilib) string cachedContentCaption;
  package(yguilib) float cachedContentFontSize = -1.0f;
  package(yguilib) string cachedContentFont;
  package(yguilib) bool cachedContentMultiline;
  package(yguilib) bool cachedContentEllipsis;
  package(yguilib) bool hasCachedContentSize;

  /// Returns caption with '\r\n', '\n', and '\r' replaced with a single space.
  string getSingleLineCaption() const {
    return sanitizeSingleLine(caption);
  }

  FormattedTextLine[] layoutLines(
    Renderer r,
    float availableWidth,
    float availableHeight = 0.0f
  ) {
    if (r is null) {
      return [];
    }
    Font f = r.getFont(fontSize, this.font);
    return layoutLines(r, f, availableWidth, availableHeight);
  }

  FormattedTextLine[] layoutLines(
    Renderer r,
    Font font,
    float availableWidth,
    float availableHeight = 0.0f
  ) {
    if (cachedLines.length > 0 &&
        availableWidth == cachedWidth &&
        availableHeight == cachedHeight &&
        caption == cachedCaption &&
        fontSize == cachedFontSize &&
        this.font == cachedFont &&
        multiline == cachedMultiline &&
        overflowEllipsis == cachedEllipsis &&
        alignment == cachedAlignment) {
      return cachedLines;
    }

    cachedLines = layoutTextLines(
      r,
      font,
      caption,
      multiline,
      overflowEllipsis,
      alignment,
      availableWidth,
      availableHeight
    );
    cachedWidth = availableWidth;
    cachedHeight = availableHeight;
    cachedCaption = caption;
    cachedFontSize = fontSize;
    cachedFont = this.font;
    cachedMultiline = multiline;
    cachedEllipsis = overflowEllipsis;
    cachedAlignment = alignment;

    return cachedLines;
  }

  FormattedTextLine[] layoutLines(
    Renderer r,
    float availableWidth,
    float availableHeight = 0.0f
  ) const {
    if (r is null) {
      return [];
    }
    Font f = r.getFont(fontSize, this.font);
    return layoutLines(r, f, availableWidth, availableHeight);
  }

  FormattedTextLine[] layoutLines(
    Renderer r,
    Font font,
    float availableWidth,
    float availableHeight = 0.0f
  ) const {
    return layoutTextLines(
      r,
      font,
      caption,
      multiline,
      overflowEllipsis,
      alignment,
      availableWidth,
      availableHeight
    );
  }
}

class Border : Component {
  enum Style {
    rect,
    dashed,
    round,
    roundDashed,
    none,
  }
  this(ColorF color, Style style = Style.rect) {
    this.color = color;
    this.style = style;
  }
  ColorF color;
  Style style;
  /// pixels
  float width = 2.0;
  float dashLen = 5.0;
  float gap = 2.0;
  float cornerRadius = 10.0;
}

class CustomDraw : Component {
  void delegate(in Renderer r, in Widget w) drawFunc;
}

unittest {
  // Test sanitizeSingleLine
  assert(sanitizeSingleLine("Hello\r\nWorld") == "Hello World");
  assert(sanitizeSingleLine("Line1\nLine2\rLine3") == "Line1 Line2 Line3");
  assert(sanitizeSingleLine("SingleLine") == "SingleLine");

  import yguilib.clibs.sdl3 : yguilib_sdl3_init, yguilib_sdl3_quit;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_drawing_components");
  win.create();
  scope(exit) win.destroy();

  auto r = new Renderer(320, 240);
  scope(exit) r.destroy();

  auto font = r.getDefaultFont();
  assert(font !is null);

  // Single line without overflow
  auto tl1 = new TextLabel("Hello", ColorF(1, 1, 1, 1));
  auto lines1 = tl1.layoutLines(r, 200.0f, 100.0f);
  assert(lines1.length == 1);
  assert(lines1[0].text == "Hello");
  assert(lines1[0].xOffset == 0.0f);

  // Single line with newlines when multiline is false
  auto tlNewlines = new TextLabel("Hello\r\nWorld", ColorF(1, 1, 1, 1));
  auto linesNewlines = tlNewlines.layoutLines(r, 200.0f, 100.0f);
  assert(linesNewlines.length == 1);
  assert(linesNewlines[0].text == "Hello World");

  // Single line with overflowEllipsis == true
  const float fullW = r.measureText("Long text that should overflow", font).x;
  auto tlOverflow = new TextLabel(
    "Long text that should overflow",
    ColorF(1, 1, 1, 1)
  );
  auto linesOverflow = tlOverflow.layoutLines(r, fullW * 0.5f, 100.0f);
  assert(linesOverflow.length == 1);
  assert(linesOverflow[0].text.length >= 3);
  assert(linesOverflow[0].text[$ - 3 .. $] == "...");
  assert(linesOverflow[0].width <= fullW * 0.5f);

  // Single line with overflowEllipsis == false
  tlOverflow.overflowEllipsis = false;
  auto linesNoEllipsis = tlOverflow.layoutLines(r, fullW * 0.5f, 100.0f);
  assert(linesNoEllipsis.length == 1);
  assert(linesNoEllipsis[0].text == "Long text that should overflow");

  // Alignment: left, center, right
  auto tlAlign = new TextLabel("Centered", ColorF(1, 1, 1, 1));
  tlAlign.alignment = TextLabel.Alignment.center;
  auto linesCenter = tlAlign.layoutLines(r, 200.0f, 100.0f);
  assert(linesCenter.length == 1);
  const float expectedCenter = (200.0f - linesCenter[0].width) * 0.5f;
  assert(linesCenter[0].xOffset == expectedCenter);

  tlAlign.alignment = TextLabel.Alignment.right;
  auto linesRight = tlAlign.layoutLines(r, 200.0f, 100.0f);
  assert(linesRight.length == 1);
  const float expectedRight = 200.0f - linesRight[0].width;
  assert(linesRight[0].xOffset == expectedRight);

  // Multiline: explicit breaks
  auto tlMulti = new TextLabel("Line 1\nLine 2\r\nLine 3", ColorF(1, 1, 1, 1));
  tlMulti.multiline = true;
  auto linesMulti = tlMulti.layoutLines(r, 200.0f, 100.0f);
  assert(linesMulti.length == 3);
  assert(linesMulti[0].text == "Line 1");
  assert(linesMulti[1].text == "Line 2");
  assert(linesMulti[2].text == "Line 3");

  // Multiline: word wrapping
  auto tlWrap = new TextLabel(
    "Word one word two word three word four",
    ColorF(1, 1, 1, 1)
  );
  tlWrap.multiline = true;
  const float wrapW = r.measureText("Word one word two", font).x + 5.0f;
  auto linesWrap = tlWrap.layoutLines(r, wrapW, 500.0f);
  assert(linesWrap.length >= 2);
  foreach (const ref l; linesWrap) {
    assert(l.width <= wrapW);
  }

  // Multiline: vertical truncation with overflowEllipsis == true
  float lineStep = r.toLogic(font.lineSkip > 0 ? font.lineSkip : font.height);
  float firstLineH = r.measureText("A", font).y;
  // Fit exactly 2 lines
  float limitH = lineStep + firstLineH + 2.0f;
  auto linesVertTrunc = tlMulti.layoutLines(r, 200.0f, limitH);
  assert(linesVertTrunc.length == 2);
  assert(linesVertTrunc[1].text[$ - 3 .. $] == "...");

  // Multiline: vertical truncation with overflowEllipsis == false
  tlMulti.overflowEllipsis = false;
  auto linesVertNoTrunc = tlMulti.layoutLines(r, 200.0f, limitH);
  assert(linesVertNoTrunc.length == 2);
  assert(linesVertNoTrunc[1].text == "Line 2");

  // Test layoutLines caching
  auto tlCache = new TextLabel("Cached line", ColorF(1, 1, 1, 1));
  auto linesC1 = tlCache.layoutLines(r, 200.0f, 100.0f);
  auto linesC2 = tlCache.layoutLines(r, 200.0f, 100.0f);
  assert(linesC1.ptr == linesC2.ptr);

  // Changing caption invalidates cache
  tlCache.caption = "Updated line";
  auto linesC3 = tlCache.layoutLines(r, 200.0f, 100.0f);
  assert(linesC3.length == 1);
  assert(linesC3[0].text == "Updated line");
  assert(linesC3.ptr != linesC1.ptr);
}

