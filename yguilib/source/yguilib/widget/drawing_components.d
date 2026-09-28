module yguilib.widget.drawing_components;

import yguilib.render : Renderer;
import yguilib.render.font : Font, defaultFontPtSize;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.widget.component;
import yguilib.widget : Widget;

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

struct FormattedTextLine {
  string text;
  float width = 0.0f;
  float xOffset = 0.0f;
}

string sanitizeSingleLine(string text) {
  import std.array : replace;
  return text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ");
}

string truncateWithEllipsis(
  Renderer r,
  Font font,
  string text,
  float availableWidth
) {
  import std.string : stripRight;
  import std.utf : stride;

  if (availableWidth <= 0.0f || text.length == 0) {
    return "";
  }
  if (r is null || font is null) {
    return text;
  }
  if (r.measureText(text, font).x <= availableWidth) {
    return text;
  }

  const float ellipsisW = r.measureText("...", font).x;
  if (ellipsisW > availableWidth) {
    if (r.measureText("..", font).x <= availableWidth) {
      return "..";
    }
    if (r.measureText(".", font).x <= availableWidth) {
      return ".";
    }
    return "";
  }

  size_t[] boundaries;
  size_t idx = 0;
  while (idx < text.length) {
    boundaries ~= idx;
    idx += stride(text, idx);
  }
  boundaries ~= text.length;

  size_t low = 0;
  size_t high = boundaries.length - 1;
  size_t bestIdx = 0;

  while (low <= high) {
    size_t mid = low + (high - low) / 2;
    size_t byteIdx = boundaries[mid];
    string candidate = text[0 .. byteIdx] ~ "...";
    if (r.measureText(candidate, font).x <= availableWidth) {
      bestIdx = byteIdx;
      low = mid + 1;
    } else {
      if (mid == 0) {
        break;
      }
      high = mid - 1;
    }
  }

  if (bestIdx == 0) {
    return "...";
  }

  string prefix = stripRight(text[0 .. bestIdx]);
  return prefix ~ "...";
}

string[] wrapLine(
  Renderer r,
  Font font,
  string line,
  float availableWidth
) {
  import std.utf : stride;

  if (availableWidth <= 0.0f || r is null || font is null || line.length == 0) {
    return [line];
  }
  if (r.measureText(line, font).x <= availableWidth) {
    return [line];
  }

  string[] words;
  size_t start = 0;
  bool inWord = false;
  foreach (size_t i, dchar c; line) {
    if (c == ' ' || c == '\t') {
      if (inWord) {
        words ~= line[start .. i];
        inWord = false;
      }
    } else {
      if (!inWord) {
        start = i;
        inWord = true;
      }
    }
  }
  if (inWord) {
    words ~= line[start .. $];
  }

  if (words.length == 0) {
    return [line];
  }

  string[] lines;
  string curLine = "";

  void breakLongWord(string word) {
    size_t idx = 0;
    while (idx < word.length) {
      size_t nextStart = idx;
      size_t lastFit = idx;
      while (idx < word.length) {
        size_t charLen = stride(word, idx);
        string chunk = word[nextStart .. idx + charLen];
        if (r.measureText(chunk, font).x <= availableWidth) {
          lastFit = idx + charLen;
          idx += charLen;
        } else {
          break;
        }
      }
      if (lastFit == nextStart) {
        size_t charLen = stride(word, nextStart);
        lastFit = nextStart + charLen;
        idx = lastFit;
      }
      string linePart = word[nextStart .. lastFit];
      if (idx < word.length) {
        lines ~= linePart;
      } else {
        curLine = linePart;
      }
    }
  }

  foreach (word; words) {
    if (curLine.length == 0) {
      if (r.measureText(word, font).x <= availableWidth) {
        curLine = word;
      } else {
        breakLongWord(word);
      }
    } else {
      string candidate = curLine ~ " " ~ word;
      if (r.measureText(candidate, font).x <= availableWidth) {
        curLine = candidate;
      } else {
        lines ~= curLine;
        curLine = "";
        if (r.measureText(word, font).x <= availableWidth) {
          curLine = word;
        } else {
          breakLongWord(word);
        }
      }
    }
  }

  if (curLine.length > 0) {
    lines ~= curLine;
  }

  return lines.length > 0 ? lines : [""];
}

class TextLabel : Component {
  // TODO RTL support
  enum Alignment {
    left,
    center,
    right,
  }

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

  /// Returns caption with '\r\n', '\n', and '\r' replaced with a single space.
  string getSingleLineCaption() const {
    return sanitizeSingleLine(caption);
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
    if (r is null || font is null || caption.length == 0) {
      return [];
    }

    string[] rawLines;
    if (!multiline) {
      string single = sanitizeSingleLine(caption);
      if (overflowEllipsis && availableWidth > 0.0f) {
        single = truncateWithEllipsis(r, font, single, availableWidth);
      }
      rawLines = [single];
    } else {
      import std.string : splitLines;
      string[] paragraphs = splitLines(caption);
      if (paragraphs.length == 0) {
        paragraphs = [""];
      }

      foreach (para; paragraphs) {
        if (availableWidth > 0.0f) {
          rawLines ~= wrapLine(r, font, para, availableWidth);
        } else {
          rawLines ~= para;
        }
      }

      if (availableHeight > 0.0f && rawLines.length > 0) {
        float lineStep = r.toLogic(
          font.lineSkip > 0 ? font.lineSkip : font.height
        );
        if (lineStep <= 0.0f) {
          lineStep = font.size;
        }
        float firstLineH = r.measureText("A", font).y;
        if (firstLineH <= 0.0f) {
          firstLineH = lineStep;
        }

        size_t fitCount = 0;
        for (size_t i = 0; i < rawLines.length; i++) {
          float bottom = cast(float)i * lineStep + firstLineH;
          if (bottom <= availableHeight) {
            fitCount = i + 1;
          } else {
            break;
          }
        }

        if (fitCount < rawLines.length) {
          if (fitCount == 0) {
            rawLines = [];
          } else {
            if (overflowEllipsis) {
              string last = rawLines[fitCount - 1];
              float availW = availableWidth > 0.0f
                ? availableWidth
                : float.infinity;
              if (r.measureText(last ~ "...", font).x <= availW) {
                rawLines[fitCount - 1] = last ~ "...";
              } else {
                rawLines[fitCount - 1] = truncateWithEllipsis(
                  r,
                  font,
                  last,
                  availW
                );
              }
            }
            rawLines = rawLines[0 .. fitCount];
          }
        }
      }
    }

    FormattedTextLine[] result;
    result.reserve(rawLines.length);

    foreach (lineStr; rawLines) {
      const float w = r.measureText(lineStr, font).x;
      float xOff = 0.0f;
      final switch (alignment) {
        case Alignment.left:
          xOff = 0.0f;
          break;
        case Alignment.center:
          xOff = availableWidth > 0.0f ? (availableWidth - w) * 0.5f : 0.0f;
          break;
        case Alignment.right:
          xOff = availableWidth > 0.0f ? availableWidth - w : 0.0f;
          break;
      }
      result ~= FormattedTextLine(lineStr, w, xOff);
    }

    return result;
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
}
