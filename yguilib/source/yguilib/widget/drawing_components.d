module yguilib.widget.drawing_components;

import yguilib.render : Renderer;
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
}

class TextLabel : Component {
  this(string caption, ColorF color) {
    this.caption = caption;
    this.color = color;
  }
  string font;
  uint fontSize = 16;
  string caption = "TextLabel";
  ColorF color = ColorF(1,1,1,1);
}

class Border : Component {
  // TODO support also dashed non-round
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
