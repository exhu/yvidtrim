module yguilib.widget.internal.layout_text;

package(yguilib):
import std.array : replace;
import std.string : indexOfAny, splitLines, stripRight;
import std.utf : stride;

import yguilib.render : Renderer;
import yguilib.render.font : Font;
import yguilib.render.render_types : PointF;

/// A formatted single line of text with measured width and horizontal offset.
struct FormattedTextLine {
  string text;
  float width = 0.0f;
  float xOffset = 0.0f;
}

/// Horizontal text alignment options.
enum TextAlignment {
  left,
  center,
  right,
}

/// Parameters for `layoutTextLines` and `measureTextContentSize`.
struct TextLayoutParams {
  string caption;
  bool multiline;
  bool overflowEllipsis;
  TextAlignment alignment = TextAlignment.left;
  float availableWidth = 0.0f;
  float availableHeight = 0.0f;

  ref TextLayoutParams withCaption(string caption) return {
    this.caption = caption;
    return this;
  }

  ref TextLayoutParams withMultiline(bool multiline) return {
    this.multiline = multiline;
    return this;
  }

  ref TextLayoutParams withEllipsis(bool overflowEllipsis) return {
    this.overflowEllipsis = overflowEllipsis;
    return this;
  }

  ref TextLayoutParams withAlignment(TextAlignment alignment) return {
    this.alignment = alignment;
    return this;
  }

  ref TextLayoutParams withAvailableSize(float width, float height) return {
    this.availableWidth = width;
    this.availableHeight = height;
    return this;
  }
}

/// Normalizes newlines ('\r\n', '\r', '\n') to spaces.
string sanitizeSingleLine(string text) {
  if (text.indexOfAny("\r\n") < 0) {
    return text;
  }
  return text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ");
}

/// Truncates text with ellipsis ("...", "..", ".") if exceeding availableWidth.
string truncateWithEllipsis(
  Renderer r,
  Font font,
  string text,
  float availableWidth
) {
  return truncateWithEllipsisImpl(r, font, text, availableWidth, false);
}

/// Truncates text and always appends ellipsis ("...", "..", ".") even if
/// `text` alone fits within `availableWidth`.
string truncateForceEllipsis(
  Renderer r,
  Font font,
  string text,
  float availableWidth
) {
  return truncateWithEllipsisImpl(r, font, text, availableWidth, true);
}

/// Breaks a single line of text into wrapped lines fitting availableWidth.
string[] wrapLine(
  Renderer r,
  Font font,
  string line,
  float availableWidth
) {
  if (!(availableWidth > 0.0f) || r is null || font is null ||
      line.length == 0) {
    return [line];
  }
  if (r.measureTextWithFont(line, font).x <= availableWidth) {
    return [line];
  }

  size_t indentEnd = 0;
  while (indentEnd < line.length &&
      (line[indentEnd] == ' ' || line[indentEnd] == '\t')) {
    indentEnd++;
  }
  if (indentEnd == line.length) {
    return [line];
  }
  const string leadingIndent = line[0 .. indentEnd];

  string[] words;
  size_t start = indentEnd;
  bool inWord = false;
  for (size_t i = indentEnd; i < line.length;) {
    const size_t charLen = stride(line, i);
    const char ch = line[i];
    if (ch == ' ' || ch == '\t') {
      if (inWord) {
        words ~= line[start .. i];
        inWord = false;
      }
    } else if (!inWord) {
      start = i;
      inWord = true;
    }
    i += charLen;
  }
  if (inWord) {
    words ~= line[start .. $];
  }

  if (words.length == 0) {
    return [line];
  }
  if (leadingIndent.length > 0) {
    words[0] = leadingIndent ~ words[0];
  }

  string[] lines;
  string curLine = "";

  void breakLongWord(string word) {
    size_t wIdx = 0;
    while (wIdx < word.length) {
      const size_t nextStart = wIdx;
      size_t low = nextStart;
      size_t high = word.length;
      size_t lastFit = nextStart;

      while (low < high) {
        size_t mid = low + (high - low + 1) / 2;
        while (mid > low && (word[mid] & 0xC0) == 0x80) {
          mid--;
        }
        if (mid == low) {
          mid = high;
        }
        if (r.measureTextWithFont(word[nextStart .. mid], font).x <=
            availableWidth) {
          lastFit = mid;
          low = mid;
        } else {
          high = mid - 1;
          while (high > low && (word[high] & 0xC0) == 0x80) {
            high--;
          }
        }
      }

      if (lastFit == nextStart) {
        lastFit = nextStart + stride(word, nextStart);
      }
      wIdx = lastFit;
      const string linePart = word[nextStart .. lastFit];
      if (wIdx < word.length) {
        lines ~= linePart;
      } else {
        curLine = linePart;
      }
    }
  }

  foreach (word; words) {
    if (curLine.length == 0) {
      if (r.measureTextWithFont(word, font).x <= availableWidth) {
        curLine = word;
      } else {
        breakLongWord(word);
      }
    } else {
      const string candidate = curLine ~ " " ~ word;
      if (r.measureTextWithFont(candidate, font).x <= availableWidth) {
        curLine = candidate;
      } else {
        lines ~= curLine;
        curLine = "";
        if (r.measureTextWithFont(word, font).x <= availableWidth) {
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

/// Returns the vertical distance between consecutive text lines in logic units.
float lineStepFromFont(Renderer r, Font font) {
  if (r is null || font is null) {
    return 0.0f;
  }
  float step = r.logicFromPixelsFloat(
    font.lineSkip > 0 ? font.lineSkip : font.height
  );
  if (step <= 0.0f) {
    step = font.size;
  }
  return step;
}

/// Returns the height of the first line of text in logic units.
float firstLineHeightFromFont(Renderer r, Font font, float lineStep) {
  if (r is null || font is null) {
    return 0.0f;
  }
  const float firstLineH = r.measureTextWithFont("A", font).y;
  return firstLineH > 0.0f ? firstLineH : lineStep;
}

/// Lays out lines of text with wrapping, truncation, and alignment offsets.
FormattedTextLine[] layoutTextLines(
  Renderer r,
  Font font,
  in TextLayoutParams params
) {
  if (r is null || font is null || params.caption.length == 0) {
    return [];
  }

  string[] rawLines = buildRawLines(r, font, params);

  FormattedTextLine[] result;
  result.reserve(rawLines.length);
  foreach (lineStr; rawLines) {
    const float w = r.measureTextWithFont(lineStr, font).x;
    float xOff = 0.0f;
    final switch (params.alignment) {
      case TextAlignment.left:
        xOff = 0.0f;
        break;
      case TextAlignment.center:
        xOff = params.availableWidth > 0.0f
          ? (params.availableWidth - w) * 0.5f : 0.0f;
        break;
      case TextAlignment.right:
        xOff = params.availableWidth > 0.0f
          ? params.availableWidth - w : 0.0f;
        break;
    }
    result ~= FormattedTextLine(lineStr, w, xOff);
  }
  return result;
}

/// Measures the bounding content size for given text layout parameters.
PointF measureTextContentSize(
  Renderer r,
  Font font,
  in TextLayoutParams params
) {
  if (r is null || font is null || params.caption.length == 0) {
    return PointF(0.0f, 0.0f);
  }

  const string[] rawLines = buildRawLines(r, font, params);
  if (rawLines.length == 0) {
    return PointF(0.0f, 0.0f);
  }

  float maxW = 0.0f;
  foreach (lineStr; rawLines) {
    const float w = r.measureTextWithFont(lineStr, font).x;
    if (w > maxW) {
      maxW = w;
    }
  }

  const float lineStep = lineStepFromFont(r, font);
  const float firstLineH = firstLineHeightFromFont(r, font, lineStep);

  const float totalH = rawLines.length > 1
    ? (cast(float)(rawLines.length - 1)) * lineStep + firstLineH
    : firstLineH;

  import std.algorithm.comparison : max;
  return PointF(max(0.0f, maxW), max(0.0f, totalH));
}

private:

string truncateWithEllipsisImpl(
  Renderer r,
  Font font,
  string text,
  float availableWidth,
  bool forceEllipsis
) {
  if (!(availableWidth > 0.0f) || text.length == 0) {
    return "";
  }
  if (r is null || font is null) {
    return text;
  }
  if (!forceEllipsis &&
      r.measureTextWithFont(text, font).x <= availableWidth) {
    return text;
  }

  const float ellipsisW = r.measureTextWithFont("...", font).x;
  if (ellipsisW > availableWidth) {
    if (r.measureTextWithFont("..", font).x <= availableWidth) {
      return "..";
    }
    if (r.measureTextWithFont(".", font).x <= availableWidth) {
      return ".";
    }
    return "";
  }

  char[256] stackBuf = void;
  bool fitsWithEllipsis(size_t byteIdx) {
    const size_t totalLen = byteIdx + 3;
    if (totalLen <= stackBuf.length) {
      stackBuf[0 .. byteIdx] = text[0 .. byteIdx];
      stackBuf[byteIdx .. totalLen] = "...";
      return r.measureTextWithFont(
        cast(string)stackBuf[0 .. totalLen], font
      ).x <= availableWidth;
    }
    return r.measureTextWithFont(
      text[0 .. byteIdx] ~ "...", font
    ).x <= availableWidth;
  }

  size_t low = 0;
  size_t high = text.length;
  size_t bestIdx = 0;

  while (low < high) {
    size_t mid = low + (high - low + 1) / 2;
    while (mid > low && (text[mid] & 0xC0) == 0x80) {
      mid--;
    }
    if (mid == low) {
      mid = high;
    }
    if (fitsWithEllipsis(mid)) {
      bestIdx = mid;
      low = mid;
    } else {
      high = mid - 1;
      while (high > low && (text[high] & 0xC0) == 0x80) {
        high--;
      }
    }
  }

  if (bestIdx == 0) {
    return "...";
  }

  const string prefix = stripRight(text[0 .. bestIdx]);
  return prefix ~ "...";
}

string[] buildRawLines(
  Renderer r,
  Font font,
  in TextLayoutParams params
) {
  if (!params.multiline) {
    string single = sanitizeSingleLine(params.caption);
    if (params.overflowEllipsis && params.availableWidth > 0.0f) {
      single = truncateWithEllipsis(r, font, single, params.availableWidth);
    }
    return [single];
  }

  string[] paragraphs = splitLines(params.caption);
  if (paragraphs.length == 0) {
    paragraphs = [""];
  }
  string[] rawLines;
  foreach (para; paragraphs) {
    if (params.availableWidth > 0.0f) {
      rawLines ~= wrapLine(r, font, para, params.availableWidth);
    } else {
      rawLines ~= para;
    }
  }
  if (!(params.availableHeight > 0.0f) || rawLines.length == 0) {
    return rawLines;
  }

  const float lineStep = lineStepFromFont(r, font);
  const float firstLineH = firstLineHeightFromFont(r, font, lineStep);
  size_t fitCount = 0;
  for (size_t i = 0; i < rawLines.length; i++) {
    if (cast(float)i * lineStep + firstLineH <= params.availableHeight) {
      fitCount = i + 1;
    } else {
      break;
    }
  }
  if (fitCount >= rawLines.length) {
    return rawLines;
  }
  if (fitCount == 0) {
    return [];
  }
  if (params.overflowEllipsis) {
    const string last = rawLines[fitCount - 1];
    if (!(params.availableWidth > 0.0f)) {
      rawLines[fitCount - 1] = last ~ "...";
    } else if (r.measureTextWithFont(last ~ "...", font).x <=
        params.availableWidth) {
      rawLines[fitCount - 1] = last ~ "...";
    } else {
      rawLines[fitCount - 1] = truncateForceEllipsis(
        r, font, last, params.availableWidth
      );
    }
  }
  return rawLines[0 .. fitCount];
}

unittest {
  assert(sanitizeSingleLine("Hello\r\nWorld") == "Hello World");
  assert(sanitizeSingleLine("Line1\nLine2\rLine3") == "Line1 Line2 Line3");
  assert(sanitizeSingleLine("SingleLine") == "SingleLine");

  import yguilib.clibs.sdl3 : yguilib_sdl3_init, yguilib_sdl3_quit;
  import yguilib.window : Window;

  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_layout_text");
  win.create();
  scope(exit) win.destroy();

  auto r = new Renderer(320, 240, 1.0f);
  scope(exit) r.destroy();

  auto font = r.defaultFont();
  assert(font !is null);

  TextLayoutParams makeParams(
    string cap,
    bool multi,
    bool ell,
    TextAlignment al,
    float w,
    float h
  ) {
    TextLayoutParams p;
    p.withCaption(cap)
      .withMultiline(multi)
      .withEllipsis(ell)
      .withAlignment(al)
      .withAvailableSize(w, h);
    return p;
  }

  // Single line without overflow
  auto lines1 = layoutTextLines(
    r, font,
    makeParams("Hello", false, true, TextAlignment.left, 200.0f, 100.0f)
  );
  assert(lines1.length == 1);
  assert(lines1[0].text == "Hello");
  assert(lines1[0].xOffset == 0.0f);

  // Single line with newlines when multiline is false
  auto linesNewlines = layoutTextLines(
    r, font,
    makeParams(
      "Hello\r\nWorld", false, true, TextAlignment.left, 200.0f, 100.0f
    )
  );
  assert(linesNewlines.length == 1);
  assert(linesNewlines[0].text == "Hello World");

  // Single line with overflowEllipsis == true
  const float fullW = r.measureTextWithFont(
    "Long text that should overflow", font
  ).x;
  auto linesOverflow = layoutTextLines(
    r, font,
    makeParams(
      "Long text that should overflow", false, true,
      TextAlignment.left, fullW * 0.5f, 100.0f
    )
  );
  assert(linesOverflow.length == 1);
  assert(linesOverflow[0].text.length >= 3);
  assert(linesOverflow[0].text[$ - 3 .. $] == "...");
  assert(linesOverflow[0].width <= fullW * 0.5f);

  // Single line with overflowEllipsis == false
  auto linesNoEllipsis = layoutTextLines(
    r, font,
    makeParams(
      "Long text that should overflow", false, false,
      TextAlignment.left, fullW * 0.5f, 100.0f
    )
  );
  assert(linesNoEllipsis.length == 1);
  assert(linesNoEllipsis[0].text == "Long text that should overflow");

  // Alignment: left, center, right
  auto linesCenter = layoutTextLines(
    r, font,
    makeParams("Centered", false, true, TextAlignment.center, 200.0f, 100.0f)
  );
  assert(linesCenter.length == 1);
  const float expectedCenter = (200.0f - linesCenter[0].width) * 0.5f;
  assert(linesCenter[0].xOffset == expectedCenter);

  auto linesRight = layoutTextLines(
    r, font,
    makeParams("Right", false, true, TextAlignment.right, 200.0f, 100.0f)
  );
  assert(linesRight.length == 1);
  const float expectedRight = 200.0f - linesRight[0].width;
  assert(linesRight[0].xOffset == expectedRight);

  // Multiline: explicit breaks
  auto linesMulti = layoutTextLines(
    r, font,
    makeParams(
      "Line 1\nLine 2\r\nLine 3", true, true,
      TextAlignment.left, 200.0f, 100.0f
    )
  );
  assert(linesMulti.length == 3);
  assert(linesMulti[0].text == "Line 1");
  assert(linesMulti[1].text == "Line 2");
  assert(linesMulti[2].text == "Line 3");

  // Multiline: word wrapping
  const float wrapW = r.measureTextWithFont("Word one word two", font).x + 5.0f;
  auto linesWrap = layoutTextLines(
    r, font,
    makeParams(
      "Word one word two word three word four", true, true,
      TextAlignment.left, wrapW, 500.0f
    )
  );
  assert(linesWrap.length >= 2);
  foreach (const ref l; linesWrap) {
    assert(l.width <= wrapW);
  }

  // Multiline: vertical truncation with overflowEllipsis == true
  const float lineStep = lineStepFromFont(r, font);
  const float firstLineH = firstLineHeightFromFont(r, font, lineStep);
  const float limitH = lineStep + firstLineH + 2.0f;
  auto linesVertTrunc = layoutTextLines(
    r, font,
    makeParams(
      "Line 1\nLine 2\r\nLine 3", true, true,
      TextAlignment.left, 200.0f, limitH
    )
  );
  assert(linesVertTrunc.length == 2);
  assert(linesVertTrunc[1].text[$ - 3 .. $] == "...");

  // Multiline: vertical overflow when last visible line is near availW
  const float nearW = r.measureTextWithFont("Line 2", font).x + 1.0f;
  auto linesNearTrunc = layoutTextLines(
    r, font,
    makeParams(
      "Line 1\nLine 2\nLine 3", true, true,
      TextAlignment.left, nearW, limitH
    )
  );
  assert(linesNearTrunc.length == 2);
  assert(linesNearTrunc[1].text.length >= 3);
  assert(linesNearTrunc[1].text[$ - 3 .. $] == "...");
  assert(linesNearTrunc[1].width <= nearW);

  // Multiline: vertical truncation with overflowEllipsis == false
  auto linesVertNoTrunc = layoutTextLines(
    r, font,
    makeParams(
      "Line 1\nLine 2\r\nLine 3", true, false,
      TextAlignment.left, 200.0f, limitH
    )
  );
  assert(linesVertNoTrunc.length == 2);
  assert(linesVertNoTrunc[1].text == "Line 2");

  // NaN width guards
  assert(truncateWithEllipsis(r, font, "Hello", float.nan) == "");
  assert(wrapLine(r, font, "Hello", float.nan) == ["Hello"]);

  // Leading indentation & whitespace-only lines preserved in wrapLine
  const float narrowW = r.measureTextWithFont("  hello", font).x + 2.0f;
  auto indented = wrapLine(r, font, "  hello world", narrowW);
  assert(indented.length >= 2);
  assert(indented[0][0 .. 2] == "  ");
  assert(wrapLine(r, font, "    ", 10.0f) == ["    "]);

  // UTF-8 multibyte truncation & long-word breaking
  const string utf8 = "Привет мир тест";
  const float utf8HalfW = r.measureTextWithFont(utf8, font).x * 0.5f;
  const string utf8Trunc = truncateWithEllipsis(r, font, utf8, utf8HalfW);
  assert(utf8Trunc.length >= 3 && utf8Trunc[$ - 3 .. $] == "...");
  import std.utf : validate;
  validate(utf8Trunc);
  auto utf8Broken = wrapLine(r, font, "ПриветМирДлинноеСлово", utf8HalfW);
  assert(utf8Broken.length >= 2);
  foreach (part; utf8Broken) {
    validate(part);
  }

  // measureTextContentSize tests
  const PointF sizeSingle = measureTextContentSize(
    r, font,
    makeParams("Hello World", false, false, TextAlignment.left, 0.0f, 0.0f)
  );
  assert(sizeSingle.x == r.measureTextWithFont("Hello World", font).x);
  assert(sizeSingle.y == firstLineH);

  // measureTextContentSize with ellipsis
  const PointF sizeTrunc = measureTextContentSize(
    r, font,
    makeParams(
      "Long text that should overflow", false, true,
      TextAlignment.left, fullW * 0.5f, 0.0f
    )
  );
  assert(sizeTrunc.x <= fullW * 0.5f);
  assert(sizeTrunc.y == firstLineH);

  // measureTextContentSize with multiline wrapping
  const PointF sizeMultiWrap = measureTextContentSize(
    r, font,
    makeParams(
      "Word one word two word three word four", true, true,
      TextAlignment.left, wrapW, 0.0f
    )
  );
  assert(sizeMultiWrap.x <= wrapW);
  assert(sizeMultiWrap.y > firstLineH);
}
