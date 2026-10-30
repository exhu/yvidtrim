module yguilib.widget.visible;

import yguilib.render.render_types : RectF;
import yguilib.widget : Widget;

/// Represents a visible widget in pre-order (root-to-leaf, back-to-front)
/// traversal along with its resolved screen-space rectangle and active
/// ancestor clip rectangle.
struct VisibleWidget {
  Widget widget;
  RectF absRect;
  bool hasClip;
  RectF clipRect;
}

/// Contiguous slice of visible widgets in pre-order (root-to-leaf).
alias VisibleWidgets = VisibleWidget[];
