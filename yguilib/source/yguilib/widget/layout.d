module yguilib.widget.layout;
import yguilib.widget.component;

enum LayoutUnits {
  pixels,
  percents
}

struct LayoutUnitsValue {
  float value;
  LayoutUnits kind;
}


// layout
class FlexContainer : Component {
  // TODO css display: flex
  enum Direction {
    row, column, row_reverse, column_reverse,
  }
  // TODO justify-content, align-items, gap, flex-wrap
}

class GridContainer : Component {
  // TODO css display: grid
}

enum ColumnAnchor {
  left,
  right,
}

enum RowAnchor {
  top,
  bottom,
}

struct AnchorValue {
  // TODO optionality?
  ColumnAnchor column;
  LayoutUnitsValue columnValue;
  ColumnAnchor row;
  LayoutUnitsValue rowValue;
}

class Position : Component {
  AnchorValue anchor;
}
