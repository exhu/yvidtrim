module yguilib.widget.internal.layout_text;

package(yguilib):
import std.algorithm.comparison : max;
import std.array : replace;
import std.string : splitLines, stripRight;
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

/// Normalizes newlines ('\r\n', '\r', '\n') to spaces.
string sanitizeSingleLine(string text) {
  return text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ");
}

/// Truncates text with ellipsis ("...", "..", ".") if exceeding availableWidth.
string truncateWithEllipsis(
  Renderer r,
  Font font,
  string text,
  float availableWidth
) {
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
    const size_t mid = low + (high - low) / 2;
    const size_t byteIdx = boundaries[mid];
    const string candidate = text[0 .. byteIdx] ~ "...";
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

  const string prefix = stripRight(text[0 .. bestIdx]);
  return prefix ~ "...";
}

/// Breaks a single line of text into wrapped lines fitting availableWidth.
string[] wrapLine(
  Renderer r,
  Font font,
  string line,
  float availableWidth
) {
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
    size_t wIdx = 0;
    while (wIdx < word.length) {
      const size_t nextStart = wIdx;
      size_t lastFit = wIdx;
      while (wIdx < word.length) {
        const size_t charLen = stride(word, wIdx);
        const string chunk = word[nextStart .. wIdx + charLen];
        if (r.measureText(chunk, font).x <= availableWidth) {
          lastFit = wIdx + charLen;
          wIdx += charLen;
        } else {
          break;
        }
      }
      if (lastFit == nextStart) {
        const size_t charLen = stride(word, nextStart);
        lastFit = nextStart + charLen;
        wIdx = lastFit;
      }
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
      if (r.measureText(word, font).x <= availableWidth) {
        curLine = word;
      } else {
        breakLongWord(word);
      }
    } else {
      const string candidate = curLine ~ " " ~ word;
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

/// Returns the vertical distance between consecutive text lines in logic units.
float getLineStep(Renderer r, Font font) {
  if (r is null || font is null) {
    return 0.0f;
  }
  float step = r.toLogic(font.lineSkip > 0 ? font.lineSkip : font.height);
  if (step <= 0.0f) {
    step = font.size;
  }
  return step;
}

/// Returns the height of the first line of text in logic units.
float getFirstLineHeight(Renderer r, Font font, float lineStep) {
  if (r is null || font is null) {
    return 0.0f;
  }
  const float firstLineH = r.measureText("A", font).y;
  return firstLineH > 0.0f ? firstLineH : lineStep;
}

/// Lays out lines of text with wrapping, truncation, and alignment offsets.
FormattedTextLine[] layoutTextLines(
  Renderer r,
  Font font,
  string caption,
  bool multiline,
  bool overflowEllipsis,
  TextAlignment alignment,
  float availableWidth,
  float availableHeight = 0.0f
) {
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
      const float lineStep = getLineStep(r, font);
      const float firstLineH = getFirstLineHeight(r, font, lineStep);

      size_t fitCount = 0;
      for (size_t i = 0; i < rawLines.length; i++) {
        const float bottom = cast(float)i * lineStep + firstLineH;
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
            const string last = rawLines[fitCount - 1];
            const float availW = availableWidth > 0.0f
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
      case TextAlignment.left:
        xOff = 0.0f;
        break;
      case TextAlignment.center:
        xOff = availableWidth > 0.0f ? (availableWidth - w) * 0.5f : 0.0f;
        break;
      case TextAlignment.right:
        xOff = availableWidth > 0.0f ? availableWidth - w : 0.0f;
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
  string caption,
  bool multiline,
  bool overflowEllipsis,
  float availableWidth = 0.0f,
  float availableHeight = 0.0f
) {
  if (r is null || font is null || caption.length == 0) {
    return PointF(0.0f, 0.0f);
  }

  const FormattedTextLine[] lines = layoutTextLines(
    r,
    font,
    caption,
    multiline,
    overflowEllipsis,
    TextAlignment.left,
    availableWidth,
    availableHeight
  );

  if (lines.length == 0) {
    return PointF(0.0f, 0.0f);
  }

  float maxW = 0.0f;
  foreach (const ref line; lines) {
    if (line.width > maxW) {
      maxW = line.width;
    }
  }

  const float lineStep = getLineStep(r, font);
  const float firstLineH = getFirstLineHeight(r, font, lineStep);

  const float totalH = lines.length > 1
    ? (cast(float)(lines.length - 1)) * lineStep + firstLineH
    : firstLineH;

  return PointF(max(0.0f, maxW), max(0.0f, totalH));
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

  auto r = new Renderer(320, 240);
  scope(exit) r.destroy();

  auto font = r.getDefaultFont();
  assert(font !is null);

  // Single line without overflow
  auto lines1 = layoutTextLines(
    r, font, "Hello", false, true, TextAlignment.left, 200.0f, 100.0f
  );
  assert(lines1.length == 1);
  assert(lines1[0].text == "Hello");
  assert(lines1[0].xOffset == 0.0f);

  // Single line with newlines when multiline is false
  auto linesNewlines = layoutTextLines(
    r, font, "Hello\r\nWorld", false, true, TextAlignment.left, 200.0f, 100.0f
  );
  assert(linesNewlines.length == 1);
  assert(linesNewlines[0].text == "Hello World");

  // Single line with overflowEllipsis == true
  const float fullW = r.measureText("Long text that should overflow", font).x;
  auto linesOverflow = layoutTextLines(
    r, font, "Long text that should overflow", false, true,
    TextAlignment.left, fullW * 0.5f, 100.0f
  );
  assert(linesOverflow.length == 1);
  assert(linesOverflow[0].text.length >= 3);
  assert(linesOverflow[0].text[$ - 3 .. $] == "...");
  assert(linesOverflow[0].width <= fullW * 0.5f);

  // Single line with overflowEllipsis == false
  auto linesNoEllipsis = layoutTextLines(
    r, font, "Long text that should overflow", false, false,
    TextAlignment.left, fullW * 0.5f, 100.0f
  );
  assert(linesNoEllipsis.length == 1);
  assert(linesNoEllipsis[0].text == "Long text that should overflow");

  // Alignment: left, center, right
  auto linesCenter = layoutTextLines(
    r, font, "Centered", false, true, TextAlignment.center, 200.0f, 100.0f
  );
  assert(linesCenter.length == 1);
  const float expectedCenter = (200.0f - linesCenter[0].width) * 0.5f;
  assert(linesCenter[0].xOffset == expectedCenter);

  auto linesRight = layoutTextLines(
    r, font, "Right", false, true, TextAlignment.right, 200.0f, 100.0f
  );
  assert(linesRight.length == 1);
  const float expectedRight = 200.0f - linesRight[0].width;
  assert(linesRight[0].xOffset == expectedRight);

  // Multiline: explicit breaks
  auto linesMulti = layoutTextLines(
    r, font, "Line 1\nLine 2\r\nLine 3", true, true, TextAlignment.left,
    200.0f, 100.0f
  );
  assert(linesMulti.length == 3);
  assert(linesMulti[0].text == "Line 1");
  assert(linesMulti[1].text == "Line 2");
  assert(linesMulti[2].text == "Line 3");

  // Multiline: word wrapping
  const float wrapW = r.measureText("Word one word two", font).x + 5.0f;
  auto linesWrap = layoutTextLines(
    r, font, "Word one word two word three word four", true, true,
    TextAlignment.left, wrapW, 500.0f
  );
  assert(linesWrap.length >= 2);
  foreach (const ref l; linesWrap) {
    assert(l.width <= wrapW);
  }

  // Multiline: vertical truncation with overflowEllipsis == true
  const float lineStep = getLineStep(r, font);
  const float firstLineH = getFirstLineHeight(r, font, lineStep);
  const float limitH = lineStep + firstLineH + 2.0f;
  auto linesVertTrunc = layoutTextLines(
    r, font, "Line 1\nLine 2\r\nLine 3", true, true, TextAlignment.left,
    200.0f, limitH
  );
  assert(linesVertTrunc.length == 2);
  assert(linesVertTrunc[1].text[$ - 3 .. $] == "...");

  // Multiline: vertical truncation with overflowEllipsis == false
  auto linesVertNoTrunc = layoutTextLines(
    r, font, "Line 1\nLine 2\r\nLine 3", true, false, TextAlignment.left,
    200.0f, limitH
  );
  assert(linesVertNoTrunc.length == 2);
  assert(linesVertNoTrunc[1].text == "Line 2");

  // measureTextContentSize tests
  const PointF sizeSingle = measureTextContentSize(
    r, font, "Hello World", false, false
  );
  assert(sizeSingle.x == r.measureText("Hello World", font).x);
  assert(sizeSingle.y == firstLineH);

  // measureTextContentSize with ellipsis
  const PointF sizeTrunc = measureTextContentSize(
    r, font, "Long text that should overflow", false, true, fullW * 0.5f
  );
  assert(sizeTrunc.x <= fullW * 0.5f);
  assert(sizeTrunc.y == firstLineH);

  // measureTextContentSize with multiline wrapping
  const PointF sizeMultiWrap = measureTextContentSize(
    r, font, "Word one word two word three word four", true, true, wrapW
  );
  assert(sizeMultiWrap.x <= wrapW);
  assert(sizeMultiWrap.y > firstLineH);
}
