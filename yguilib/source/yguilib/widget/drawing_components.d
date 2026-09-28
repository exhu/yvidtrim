module yguilib.widget.drawing_components;

import yguilib.render : Renderer;
import yguilib.render.font : defaultFontPtSize;
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
  // TODO add font name support when FontManager is implemented
  // empty means default embedded font
  string font;
  // TODO 0 or infinity must fallback to defaultFontPtSize
  float fontSize = defaultFontPtSize;
  string caption = "TextLabel";
  ColorF color = ColorF(1,1,1,1);
  // TODO support line wrapping
  // if multiline is disabled replace '\r\n' with a space
  bool multiline;
  // TODO implement text overflow truncation with "..."
  bool overflowEllipsis = true;
  // TODO
  Alignment alignment = Alignment.left;
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
