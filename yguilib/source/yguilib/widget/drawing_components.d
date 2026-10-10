module yguilib.widget.drawing_components;

import yguilib.render : Renderer;
import yguilib.render.font : Font, defaultFontPtSize;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.widget.component;
import yguilib.widget : Widget;
package(yguilib) import yguilib.widget.internal.layout_text : FormattedTextLine,
  TextAlignment, sanitizeSingleLine;

class Background : Component {
  enum Style {
    rect,
    round,
    none,
  }

  this(ColorF color, Style style = Style.rect, float cornerRadius = 15.0f) {
    this.color = color;
    this.style = style;
    this.cornerRadius = cornerRadius;
  }

  Background withCornerRadius(float r) {
    this.cornerRadius = r;
    return this;
  }

  static Background rect(ColorF color) {
    return new Background(color, Style.rect);
  }

  static Background round(ColorF color, float cornerRadius = 15.0f) {
    return new Background(color, Style.round, cornerRadius);
  }

  ColorF color;
  Style style;
  float cornerRadius = 15.0f;
}

class TextLabel : Component {
  // TODO RTL support
  alias Alignment = TextAlignment;

  this(string caption, ColorF color = ColorF(1, 1, 1, 1)) {
    this.caption = caption;
    this.color = color;
  }

  TextLabel withFontSize(float pt) {
    this.fontSize = pt;
    return this;
  }

  TextLabel withAlignment(Alignment align_) {
    this.alignment = align_;
    return this;
  }

  TextLabel withMultiline(bool multi = true) {
    this.multiline = multi;
    return this;
  }

  TextLabel withEllipsis(bool ellipsis = true) {
    this.overflowEllipsis = ellipsis;
    return this;
  }

  TextLabel withFont(string fontName) {
    this.font = fontName;
    return this;
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

package(yguilib):
  import yguilib.widget.internal.text_label_cache :
    TextLayoutCache, TextContentSizeCache;
  /// Cached text formatting used by the paint system.
  TextLayoutCache layoutCache;
  /// Cached measured content size used by the layout system.
  TextContentSizeCache contentSizeCache;
}

class Border : Component {
  enum Style {
    rect,
    dashed,
    round,
    roundDashed,
    none,
  }

  this(ColorF color, float width = 2.0f, Style style = Style.rect) {
    this.color = color;
    this.width = width;
    this.style = style;
  }

  Border withCornerRadius(float r) {
    this.cornerRadius = r;
    return this;
  }

  Border withDashes(float dashLen, float gap) {
    this.dashLen = dashLen;
    this.gap = gap;
    return this;
  }

  static Border rect(ColorF color, float width = 1.0f) {
    return new Border(color, width, Style.rect);
  }

  static Border round(
    ColorF color,
    float cornerRadius = 10.0f,
    float width = 1.0f
  ) {
    auto b = new Border(color, width, Style.round);
    b.cornerRadius = cornerRadius;
    return b;
  }

  static Border dashed(
    ColorF color,
    float width = 1.0f,
    float dashLen = 5.0f,
    float gap = 2.0f
  ) {
    auto b = new Border(color, width, Style.dashed);
    b.dashLen = dashLen;
    b.gap = gap;
    return b;
  }

  static Border roundDashed(
    ColorF color,
    float cornerRadius = 10.0f,
    float width = 1.0f
  ) {
    auto b = new Border(color, width, Style.roundDashed);
    b.cornerRadius = cornerRadius;
    return b;
  }

  ColorF color;
  Style style;
  /// pixels
  float width = 2.0f;
  float dashLen = 5.0f;
  float gap = 2.0f;
  float cornerRadius = 10.0f;
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
  import yguilib.widget.internal.text_label_cache : getLayoutLines;
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
  auto lines1 = getLayoutLines(
    tl1.layoutCache, r, font, tl1.font,
    tl1.caption, tl1.multiline, tl1.overflowEllipsis,
    tl1.alignment, 200.0f, 100.0f
  );
  assert(lines1.length == 1);
  assert(lines1[0].text == "Hello");
  assert(lines1[0].xOffset == 0.0f);

  // Single line with newlines when multiline is false
  auto tlNewlines = new TextLabel("Hello\r\nWorld", ColorF(1, 1, 1, 1));
  auto linesNewlines = getLayoutLines(
    tlNewlines.layoutCache, r, font, tlNewlines.font,
    tlNewlines.caption, tlNewlines.multiline, tlNewlines.overflowEllipsis,
    tlNewlines.alignment, 200.0f, 100.0f
  );
  assert(linesNewlines.length == 1);
  assert(linesNewlines[0].text == "Hello World");

  // Single line with overflowEllipsis == true
  const float fullW = r.measureText("Long text that should overflow", font).x;
  auto tlOverflow = new TextLabel(
    "Long text that should overflow",
    ColorF(1, 1, 1, 1)
  );
  auto linesOverflow = getLayoutLines(
    tlOverflow.layoutCache, r, font, tlOverflow.font,
    tlOverflow.caption, tlOverflow.multiline, tlOverflow.overflowEllipsis,
    tlOverflow.alignment, fullW * 0.5f, 100.0f
  );
  assert(linesOverflow.length == 1);
  assert(linesOverflow[0].text.length >= 3);
  assert(linesOverflow[0].text[$ - 3 .. $] == "...");
  assert(linesOverflow[0].width <= fullW * 0.5f);

  // Single line with overflowEllipsis == false
  tlOverflow.overflowEllipsis = false;
  auto linesNoEllipsis = getLayoutLines(
    tlOverflow.layoutCache, r, font, tlOverflow.font,
    tlOverflow.caption, tlOverflow.multiline, tlOverflow.overflowEllipsis,
    tlOverflow.alignment, fullW * 0.5f, 100.0f
  );
  assert(linesNoEllipsis.length == 1);
  assert(linesNoEllipsis[0].text == "Long text that should overflow");

  // Alignment: left, center, right
  auto tlAlign = new TextLabel("Centered", ColorF(1, 1, 1, 1));
  tlAlign.alignment = TextLabel.Alignment.center;
  auto linesCenter = getLayoutLines(
    tlAlign.layoutCache, r, font, tlAlign.font,
    tlAlign.caption, tlAlign.multiline, tlAlign.overflowEllipsis,
    tlAlign.alignment, 200.0f, 100.0f
  );
  assert(linesCenter.length == 1);
  const float expectedCenter = (200.0f - linesCenter[0].width) * 0.5f;
  assert(linesCenter[0].xOffset == expectedCenter);

  tlAlign.alignment = TextLabel.Alignment.right;
  auto linesRight = getLayoutLines(
    tlAlign.layoutCache, r, font, tlAlign.font,
    tlAlign.caption, tlAlign.multiline, tlAlign.overflowEllipsis,
    tlAlign.alignment, 200.0f, 100.0f
  );
  assert(linesRight.length == 1);
  const float expectedRight = 200.0f - linesRight[0].width;
  assert(linesRight[0].xOffset == expectedRight);

  // Multiline: explicit breaks
  auto tlMulti = new TextLabel("Line 1\nLine 2\r\nLine 3", ColorF(1, 1, 1, 1));
  tlMulti.multiline = true;
  auto linesMulti = getLayoutLines(
    tlMulti.layoutCache, r, font, tlMulti.font,
    tlMulti.caption, tlMulti.multiline, tlMulti.overflowEllipsis,
    tlMulti.alignment, 200.0f, 100.0f
  );
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
  auto linesWrap = getLayoutLines(
    tlWrap.layoutCache, r, font, tlWrap.font,
    tlWrap.caption, tlWrap.multiline, tlWrap.overflowEllipsis,
    tlWrap.alignment, wrapW, 500.0f
  );
  assert(linesWrap.length >= 2);
  foreach (const ref l; linesWrap) {
    assert(l.width <= wrapW);
  }

  // Multiline: vertical truncation with overflowEllipsis == true
  float lineStep = r.toLogic(font.lineSkip > 0 ? font.lineSkip : font.height);
  float firstLineH = r.measureText("A", font).y;
  // Fit exactly 2 lines
  float limitH = lineStep + firstLineH + 2.0f;
  auto linesVertTrunc = getLayoutLines(
    tlMulti.layoutCache, r, font, tlMulti.font,
    tlMulti.caption, tlMulti.multiline, tlMulti.overflowEllipsis,
    tlMulti.alignment, 200.0f, limitH
  );
  assert(linesVertTrunc.length == 2);
  assert(linesVertTrunc[1].text[$ - 3 .. $] == "...");

  // Multiline: vertical truncation with overflowEllipsis == false
  tlMulti.overflowEllipsis = false;
  auto linesVertNoTrunc = getLayoutLines(
    tlMulti.layoutCache, r, font, tlMulti.font,
    tlMulti.caption, tlMulti.multiline, tlMulti.overflowEllipsis,
    tlMulti.alignment, 200.0f, limitH
  );
  assert(linesVertNoTrunc.length == 2);
  assert(linesVertNoTrunc[1].text == "Line 2");

  // Test layoutLines caching
  auto tlCache = new TextLabel("Cached line", ColorF(1, 1, 1, 1));
  auto linesC1 = getLayoutLines(
    tlCache.layoutCache, r, font, tlCache.font,
    tlCache.caption, tlCache.multiline, tlCache.overflowEllipsis,
    tlCache.alignment, 200.0f, 100.0f
  );
  auto linesC2 = getLayoutLines(
    tlCache.layoutCache, r, font, tlCache.font,
    tlCache.caption, tlCache.multiline, tlCache.overflowEllipsis,
    tlCache.alignment, 200.0f, 100.0f
  );
  assert(linesC1.ptr == linesC2.ptr);

  // Changing caption invalidates cache
  tlCache.caption = "Updated line";
  auto linesC3 = getLayoutLines(
    tlCache.layoutCache, r, font, tlCache.font,
    tlCache.caption, tlCache.multiline, tlCache.overflowEllipsis,
    tlCache.alignment, 200.0f, 100.0f
  );
  assert(linesC3.length == 1);
  assert(linesC3[0].text == "Updated line");
  assert(linesC3.ptr != linesC1.ptr);
}

unittest {
  // Test Background builder & factories
  auto bgRound = Background.round(ColorF(1, 0, 0, 1), 8.0f);
  assert(bgRound.style == Background.Style.round);
  assert(bgRound.cornerRadius == 8.0f);

  auto bgRect = Background.rect(ColorF(0, 1, 0, 1))
    .withCornerRadius(4.0f);
  assert(bgRect.style == Background.Style.rect);
  assert(bgRect.cornerRadius == 4.0f);

  // Test Border builder & factories
  auto bRound = Border.round(ColorF(0, 0, 1, 1), 6.0f, 2.0f);
  assert(bRound.style == Border.Style.round);
  assert(bRound.cornerRadius == 6.0f);
  assert(bRound.width == 2.0f);

  auto bDashed = Border.dashed(ColorF(1, 1, 0, 1), 1.5f, 6.0f, 3.0f);
  assert(bDashed.style == Border.Style.dashed);
  assert(bDashed.dashLen == 6.0f);
  assert(bDashed.gap == 3.0f);

  // Test TextLabel builder
  auto tl = new TextLabel("Title", ColorF(1, 1, 1, 1))
    .withFontSize(16.0f)
    .withAlignment(TextLabel.Alignment.center)
    .withMultiline(true)
    .withEllipsis(false);
  assert(tl.caption == "Title");
  assert(tl.fontSize == 16.0f);
  assert(tl.alignment == TextLabel.Alignment.center);
  assert(tl.multiline);
  assert(!tl.overflowEllipsis);
}
