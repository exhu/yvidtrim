/// 2d drawing api similar to HTML canvas 2d api or svg, but reduced in
/// features, simplified, uses float, int and other efficient types.
/// https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial
module yguilib.render.canvas;
import yguilib.render.render_types;

// TODO declare missing types that only used with Canvas here

final class Path2d {
  // TODO similar to Canvas web API Path2D, but do not use text strings,
  // use already existing renderer types, or add new, use float type for coords and values
  // that expect fractional, use int for integers.

}

enum LineCap {
  butt,
  round,
  square,
}

enum LineJoin {
  round,
  bevel,
  miter,
}

struct LineDash {
  // TODO
}

struct LinearGradient {
  // TODO
}

struct RadialGradient {
  // TODO
}

struct Pattern {
  // TODO image, postpone for now until we support loading images
}

struct FillStyle {
  // TODO support color, gradient, pattern
}

// TODO if there's difference, introduce separate type StrokeStyle
alias StrokeStyle = FillStyle;

struct Shadow {
  // TODO offset, blur, color
}

enum FillRule {
  nonZero,
  evenOdd,
}

/// canvas context
final class Canvas {
// TODO make it work with current Renderer
// do not replicate standalone path functions, like ctx.arc or ctx.beginPath,
// the user is expected to use Path2d instead to draw paths

  void clearRect(RectF rect);
  void fillStyle(FillStyle style);
  void strokeStyle(StrokeStyle style);
  void lineWidth(float w);
  void lineCap(LineCap cap);
  void lineJoin(LineJoin join);
  void miterLimit(float miter);
  // TODO introduce LineDash type
  void lineDash(LineDash dash);
  LineDash lineDash();
  void lineDashOffset(float offset);
  void fillRule(FillRule rule);

  void fill(Path2d path);
  void stroke(Path2d path);

  // push state
  void save();
  // pop state
  void restore();

  void translate(PointF offset);
  void rotate(float radians);
  /// supports negative for axis mirroring
  void scale(PointF factor);
  /// to the identity matrix
  void resetTransform();

  /// sets clipping mask; use save() and then restore() to undo clipping.
  void clip(Path2d path);
  void clipFillRule(FillRule rule);

  // Text/font-related functions are omitted for now.
}
