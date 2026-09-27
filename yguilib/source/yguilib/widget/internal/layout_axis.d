module yguilib.widget.internal.layout_axis;

package(yguilib):
import yguilib.widget : Widget;

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
}
