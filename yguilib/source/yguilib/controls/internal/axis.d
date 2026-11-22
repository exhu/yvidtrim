module yguilib.controls.internal.axis;

import yguilib.render.render_types : PointF, RectF;
import yguilib.widget.layout_components : Dimension, FlexDirection, Size,
  SizingMode;

package(yguilib):

/// Axis projection helper mapping main/cross layout operations to X/Y.
struct Axis {
  bool isRow = true;

  /// Creates an `Axis` from a `FlexDirection`.
  static Axis of(FlexDirection d) nothrow @safe @nogc {
    return Axis(d == FlexDirection.row);
  }

  /// Returns `p`'s coordinate along the main axis.
  float mainCoord(PointF p) const nothrow @safe @nogc {
    return isRow ? p.x : p.y;
  }

  /// Returns `p`'s coordinate along the cross axis.
  float crossCoord(PointF p) const nothrow @safe @nogc {
    return isRow ? p.y : p.x;
  }

  /// Returns `r`'s position along the main axis.
  float mainPos(RectF r) const nothrow @safe @nogc {
    return isRow ? r.x : r.y;
  }

  /// Returns `r`'s position along the cross axis.
  float crossPos(RectF r) const nothrow @safe @nogc {
    return isRow ? r.y : r.x;
  }

  /// Returns `r`'s extent along the main axis.
  float mainSize(RectF r) const nothrow @safe @nogc {
    return isRow ? r.width : r.height;
  }

  /// Returns `r`'s extent along the cross axis.
  float crossSize(RectF r) const nothrow @safe @nogc {
    return isRow ? r.height : r.width;
  }

  /// Constructs a `PointF` from main and cross coordinates.
  PointF makePoint(float main, float cross) const nothrow @safe @nogc {
    return isRow ? PointF(main, cross) : PointF(cross, main);
  }

  /// Returns a copy of `p` with its main-axis coordinate replaced by `main`.
  PointF withMainCoord(PointF p, float main) const nothrow @safe @nogc {
    return isRow ? PointF(main, p.y) : PointF(p.x, main);
  }

  /// Creates a `Size` with `fraction(1.0f)` on main axis and `auto_` on cross.
  Size fillMain() const {
    auto sz = new Size();
    if (isRow) {
      sz.width = Dimension(1.0f, SizingMode.fraction);
    } else {
      sz.height = Dimension(1.0f, SizingMode.fraction);
    }
    return sz;
  }

  /// Sets the cross-axis dimension of `sz` to `fixed(crossLen)`.
  void setFixedCrossSize(Size sz, float crossLen) const {
    assert(sz !is null, "sz must not be null");
    if (isRow) {
      sz.height = Dimension(crossLen, SizingMode.fixed);
    } else {
      sz.width = Dimension(crossLen, SizingMode.fixed);
    }
  }

  /// Creates a `Size` filling the main axis with fixed `crossLen` on cross.
  Size fillMainFixedCross(float crossLen) const {
    auto sz = fillMain();
    setFixedCrossSize(sz, crossLen);
    return sz;
  }

  /// Returns the decrement arrow glyph for this axis.
  string decArrow() const nothrow @safe @nogc {
    return isRow ? "<" : "^";
  }

  /// Returns the increment arrow glyph for this axis.
  string incArrow() const nothrow @safe @nogc {
    return isRow ? ">" : "v";
  }
}

unittest {
  const Axis row = Axis.of(FlexDirection.row);
  assert(row.isRow);
  const PointF p = PointF(12.0f, 34.0f);
  const RectF r = RectF(10.0f, 20.0f, 100.0f, 50.0f);

  assert(row.mainCoord(p) == 12.0f);
  assert(row.crossCoord(p) == 34.0f);
  assert(row.mainPos(r) == 10.0f);
  assert(row.crossPos(r) == 20.0f);
  assert(row.mainSize(r) == 100.0f);
  assert(row.crossSize(r) == 50.0f);
  assert(row.makePoint(5.0f, 9.0f) == PointF(5.0f, 9.0f));
  assert(row.withMainCoord(p, 99.0f) == PointF(99.0f, 34.0f));
  assert(row.decArrow() == "<");
  assert(row.incArrow() == ">");

  const Size rowFill = row.fillMain();
  assert(rowFill.width.mode == SizingMode.fraction);
  assert(rowFill.width.value == 1.0f);
  assert(rowFill.height.mode == SizingMode.auto_);

  const Size rowFixedCross = row.fillMainFixedCross(16.0f);
  assert(rowFixedCross.width.mode == SizingMode.fraction);
  assert(rowFixedCross.height.mode == SizingMode.fixed);
  assert(rowFixedCross.height.value == 16.0f);

  const Axis col = Axis.of(FlexDirection.column);
  assert(!col.isRow);
  assert(col.mainCoord(p) == 34.0f);
  assert(col.crossCoord(p) == 12.0f);
  assert(col.mainPos(r) == 20.0f);
  assert(col.crossPos(r) == 10.0f);
  assert(col.mainSize(r) == 50.0f);
  assert(col.crossSize(r) == 100.0f);
  assert(col.makePoint(5.0f, 9.0f) == PointF(9.0f, 5.0f));
  assert(col.withMainCoord(p, 99.0f) == PointF(12.0f, 99.0f));
  assert(col.decArrow() == "^");
  assert(col.incArrow() == "v");

  const Size colFill = col.fillMain();
  assert(colFill.height.mode == SizingMode.fraction);
  assert(colFill.height.value == 1.0f);
  assert(colFill.width.mode == SizingMode.auto_);

  const Size colFixedCross = col.fillMainFixedCross(18.0f);
  assert(colFixedCross.height.mode == SizingMode.fraction);
  assert(colFixedCross.width.mode == SizingMode.fixed);
  assert(colFixedCross.width.value == 18.0f);
}
