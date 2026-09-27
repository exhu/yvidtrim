module yguilib.widget.internal.layout_axis;

package(yguilib):
import yguilib.widget : Widget;
import yguilib.widget.layout_components : Insets, Size;

/// Returns child's size on main axis (width for row, height for column).
float getMainSize(const Widget w, bool isRow) {
  return isRow ? w.rect.width : w.rect.height;
}

/// Sets child's size on main axis (width for row, height for column).
void setMainSize(Widget w, bool isRow, float val) {
  if (isRow) {
    w.rect.width = val;
  } else {
    w.rect.height = val;
  }
}

/// Returns child's size on cross axis (height for row, width for column).
float getCrossSize(const Widget w, bool isRow) {
  return isRow ? w.rect.height : w.rect.width;
}

/// Sets child's size on cross axis (height for row, width for column).
void setCrossSize(Widget w, bool isRow, float val) {
  if (isRow) {
    w.rect.height = val;
  } else {
    w.rect.width = val;
  }
}

/// Sets child's position on main axis (x for row, y for column).
void setMainPos(Widget w, bool isRow, float val) {
  if (isRow) {
    w.rect.x = val;
  } else {
    w.rect.y = val;
  }
}

/// Sets child's position on cross axis (y for row, x for column).
void setCrossPos(Widget w, bool isRow, float val) {
  if (isRow) {
    w.rect.y = val;
  } else {
    w.rect.x = val;
  }
}

/// Returns the child's margin-start on the main axis.
float getMainMarginStart(const Widget w, bool isRow) {
  const Size sz = w.components.size;
  if (sz is null) {
    return 0.0f;
  }
  return isRow ? sz.margin.left : sz.margin.top;
}

/// Returns the child's margin-end on the main axis.
float getMainMarginEnd(const Widget w, bool isRow) {
  const Size sz = w.components.size;
  if (sz is null) {
    return 0.0f;
  }
  return isRow ? sz.margin.right : sz.margin.bottom;
}

/// Returns the child's margin-start on the cross axis.
float getCrossMarginStart(const Widget w, bool isRow) {
  const Size sz = w.components.size;
  if (sz is null) {
    return 0.0f;
  }
  return isRow ? sz.margin.top : sz.margin.left;
}

/// Returns the child's margin-end on the cross axis.
float getCrossMarginEnd(const Widget w, bool isRow) {
  const Size sz = w.components.size;
  if (sz is null) {
    return 0.0f;
  }
  return isRow ? sz.margin.bottom : sz.margin.right;
}

/// Returns size + margins on main axis (outer extent).
float getMainOuterSize(const Widget w, bool isRow) {
  return getMainSize(w, isRow)
    + getMainMarginStart(w, isRow)
    + getMainMarginEnd(w, isRow);
}

/// Returns size + margins on cross axis (outer extent).
float getCrossOuterSize(const Widget w, bool isRow) {
  return getCrossSize(w, isRow)
    + getCrossMarginStart(w, isRow)
    + getCrossMarginEnd(w, isRow);
}

unittest {
  import yguilib.render.render_types : RectF;

  auto w = new Widget(null, RectF(10, 20, 30, 40));

  // Row
  assert(getMainSize(w, true) == 30);
  assert(getCrossSize(w, true) == 40);
  setMainSize(w, true, 100);
  setCrossSize(w, true, 200);
  assert(w.rect.width == 100);
  assert(w.rect.height == 200);

  setMainPos(w, true, 50);
  setCrossPos(w, true, 60);
  assert(w.rect.x == 50);
  assert(w.rect.y == 60);

  // Column
  assert(getMainSize(w, false) == 200);
  assert(getCrossSize(w, false) == 100);
  setMainSize(w, false, 75);
  setCrossSize(w, false, 85);
  assert(w.rect.height == 75);
  assert(w.rect.width == 85);

  setMainPos(w, false, 15);
  setCrossPos(w, false, 25);
  assert(w.rect.y == 15);
  assert(w.rect.x == 25);

  // Margin tests without Size component
  assert(getMainMarginStart(w, true) == 0.0f);
  assert(getMainMarginEnd(w, true) == 0.0f);
  assert(getCrossMarginStart(w, true) == 0.0f);
  assert(getCrossMarginEnd(w, true) == 0.0f);
  assert(getMainOuterSize(w, true) == 85.0f);
  assert(getCrossOuterSize(w, true) == 75.0f);

  // With Size component
  auto sz = new Size;
  sz.margin = Insets(5, 10, 15, 20); // top=5, right=10, bottom=15, left=20
  w.components.size = sz;

  // Row: main=X (left=20, right=10), cross=Y (top=5, bottom=15)
  assert(getMainMarginStart(w, true) == 20.0f);
  assert(getMainMarginEnd(w, true) == 10.0f);
  assert(getCrossMarginStart(w, true) == 5.0f);
  assert(getCrossMarginEnd(w, true) == 15.0f);
  assert(getMainOuterSize(w, true) == 85.0f + 20.0f + 10.0f);
  assert(getCrossOuterSize(w, true) == 75.0f + 5.0f + 15.0f);

  // Column: main=Y (top=5, bottom=15), cross=X (left=20, right=10)
  assert(getMainMarginStart(w, false) == 5.0f);
  assert(getMainMarginEnd(w, false) == 15.0f);
  assert(getCrossMarginStart(w, false) == 20.0f);
  assert(getCrossMarginEnd(w, false) == 10.0f);
  assert(getMainOuterSize(w, false) == 75.0f + 5.0f + 15.0f);
  assert(getCrossOuterSize(w, false) == 85.0f + 20.0f + 10.0f);
}
