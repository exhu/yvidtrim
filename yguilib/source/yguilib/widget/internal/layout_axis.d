module yguilib.widget.internal.layout_axis;

package(yguilib):
import yguilib.widget : Widget;
import yguilib.widget.layout_components : Size;

/// Returns child's size on main axis (width for row, height for column).
float mainSize(const Widget w, bool isRow) {
  return isRow ? w.rect.width : w.rect.height;
}

/// Sets child's size on main axis (width for row, height for column).
void assignMainSize(Widget w, bool isRow, float val) {
  if (isRow) {
    w.rect.width = val;
  } else {
    w.rect.height = val;
  }
}

/// Returns child's size on cross axis (height for row, width for column).
float crossSize(const Widget w, bool isRow) {
  return isRow ? w.rect.height : w.rect.width;
}

/// Sets child's size on cross axis (height for row, width for column).
void assignCrossSize(Widget w, bool isRow, float val) {
  if (isRow) {
    w.rect.height = val;
  } else {
    w.rect.width = val;
  }
}

/// Sets child's position on main axis (x for row, y for column).
void assignMainPos(Widget w, bool isRow, float val) {
  if (isRow) {
    w.rect.x = val;
  } else {
    w.rect.y = val;
  }
}

/// Sets child's position on cross axis (y for row, x for column).
void assignCrossPos(Widget w, bool isRow, float val) {
  if (isRow) {
    w.rect.y = val;
  } else {
    w.rect.x = val;
  }
}

/// Returns the child's margin-start on the main axis.
float mainMarginStart(const Widget w, bool isRow) {
  const Size sz = w.components.size;
  if (sz is null) {
    return 0.0f;
  }
  return isRow ? sz.margin.left : sz.margin.top;
}

/// Returns the child's margin-end on the main axis.
float mainMarginEnd(const Widget w, bool isRow) {
  const Size sz = w.components.size;
  if (sz is null) {
    return 0.0f;
  }
  return isRow ? sz.margin.right : sz.margin.bottom;
}

/// Returns the child's margin-start on the cross axis.
float crossMarginStart(const Widget w, bool isRow) {
  const Size sz = w.components.size;
  if (sz is null) {
    return 0.0f;
  }
  return isRow ? sz.margin.top : sz.margin.left;
}

/// Returns the child's margin-end on the cross axis.
float crossMarginEnd(const Widget w, bool isRow) {
  const Size sz = w.components.size;
  if (sz is null) {
    return 0.0f;
  }
  return isRow ? sz.margin.bottom : sz.margin.right;
}

/// Returns size + margins on main axis (outer extent).
float mainOuterSize(const Widget w, bool isRow) {
  return mainSize(w, isRow)
    + mainMarginStart(w, isRow)
    + mainMarginEnd(w, isRow);
}

/// Returns size + margins on cross axis (outer extent).
float crossOuterSize(const Widget w, bool isRow) {
  return crossSize(w, isRow)
    + crossMarginStart(w, isRow)
    + crossMarginEnd(w, isRow);
}

unittest {
  import yguilib.render.render_types : RectF;
  import yguilib.widget.layout_components : Insets;

  auto w = new Widget(1);
  w.rect = RectF(10, 20, 30, 40);

  // Row
  assert(mainSize(w, true) == 30);
  assert(crossSize(w, true) == 40);
  assignMainSize(w, true, 100);
  assignCrossSize(w, true, 200);
  assert(w.rect.width == 100);
  assert(w.rect.height == 200);

  assignMainPos(w, true, 50);
  assignCrossPos(w, true, 60);
  assert(w.rect.x == 50);
  assert(w.rect.y == 60);

  // Column
  assert(mainSize(w, false) == 200);
  assert(crossSize(w, false) == 100);
  assignMainSize(w, false, 75);
  assignCrossSize(w, false, 85);
  assert(w.rect.height == 75);
  assert(w.rect.width == 85);

  assignMainPos(w, false, 15);
  assignCrossPos(w, false, 25);
  assert(w.rect.y == 15);
  assert(w.rect.x == 25);

  // Margin tests without Size component
  assert(mainMarginStart(w, true) == 0.0f);
  assert(mainMarginEnd(w, true) == 0.0f);
  assert(crossMarginStart(w, true) == 0.0f);
  assert(crossMarginEnd(w, true) == 0.0f);
  assert(mainOuterSize(w, true) == 85.0f);
  assert(crossOuterSize(w, true) == 75.0f);

  // With Size component
  auto sz = new Size;
  sz.margin = Insets(5, 10, 15, 20); // top=5, right=10, bottom=15, left=20
  w.components.size = sz;

  // Row: main=X (left=20, right=10), cross=Y (top=5, bottom=15)
  assert(mainMarginStart(w, true) == 20.0f);
  assert(mainMarginEnd(w, true) == 10.0f);
  assert(crossMarginStart(w, true) == 5.0f);
  assert(crossMarginEnd(w, true) == 15.0f);
  assert(mainOuterSize(w, true) == 85.0f + 20.0f + 10.0f);
  assert(crossOuterSize(w, true) == 75.0f + 5.0f + 15.0f);

  // Column: main=Y (top=5, bottom=15), cross=X (left=20, right=10)
  assert(mainMarginStart(w, false) == 5.0f);
  assert(mainMarginEnd(w, false) == 15.0f);
  assert(crossMarginStart(w, false) == 20.0f);
  assert(crossMarginEnd(w, false) == 10.0f);
  assert(mainOuterSize(w, false) == 75.0f + 5.0f + 15.0f);
  assert(crossOuterSize(w, false) == 85.0f + 20.0f + 10.0f);
}
