module yguilib.widget.visible;

import yguilib.render.render_types : PointF, RectF;
import yguilib.widget : Widget;
import yguilib.widget.component : WidgetComponent;

/// Represents a visible widget in pre-order (root-to-leaf, back-to-front)
/// traversal along with its resolved screen-space rectangle and active
/// ancestor clip rectangle.
struct VisibleWidget {
  Widget widget;
  RectF absRect;
  bool hasClip;
  RectF clipRect;

  /// Returns true if `p` is inside `absRect` and (when `hasClip` is true)
  /// inside `clipRect`.
  bool containsPoint(in PointF p) const {
    if (hasClip && !clipRect.contains(p)) {
      return false;
    }
    return absRect.contains(p);
  }
}

/// Contiguous slice of visible widgets in pre-order (root-to-leaf).
alias VisibleWidgets = VisibleWidget[];

/// Returns the topmost visible widget containing `p` that has a custom
/// component `C`, or `null` if no visible widget matches.
Widget findTopmostWithComponent(C : WidgetComponent)(
  VisibleWidgets widgets,
  PointF p
) {
  import yguilib.widget : WidgetComponents;

  static assert(
    !WidgetComponents.isBuiltinComponent!C,
    "findTopmostWithComponent only supports custom WidgetComponents"
  );
  foreach_reverse (ref vw; widgets) {
    if (vw.widget is null || !vw.widget.components.has!C()) {
      continue;
    }
    if (vw.containsPoint(p)) {
      return vw.widget;
    }
  }
  return null;
}

unittest {
  final class MarkerComponent : WidgetComponent {}

  auto base = new Widget(1);
  base.components.set(new MarkerComponent());

  auto overlayPlain = new Widget(2);

  auto topMarked = new Widget(3);
  topMarked.components.set(new MarkerComponent());

  auto clipped = new Widget(4);
  clipped.components.set(new MarkerComponent());

  VisibleWidgets list = [
    VisibleWidget(base, RectF(0, 0, 100, 100), false, RectF()),
    VisibleWidget(overlayPlain, RectF(10, 10, 80, 80), false, RectF()),
    VisibleWidget(topMarked, RectF(20, 20, 40, 40), false, RectF()),
    VisibleWidget(clipped, RectF(20, 20, 40, 40), true, RectF(20, 20, 10, 10)),
  ];

  // Inside clipped's clipRect -> returns clipped
  assert(findTopmostWithComponent!MarkerComponent(list, PointF(25, 25))
    is clipped);

  // Inside clipped's absRect, outside clipRect -> skips clipped, hits topMarked
  assert(findTopmostWithComponent!MarkerComponent(list, PointF(35, 35))
    is topMarked);

  // Inside overlayPlain (no MarkerComponent) and base -> skips overlayPlain
  assert(findTopmostWithComponent!MarkerComponent(list, PointF(15, 15))
    is base);

  // Outside all widgets -> returns null
  assert(findTopmostWithComponent!MarkerComponent(list, PointF(150, 150))
    is null);

  // VisibleWidget.containsPoint
  auto vwUnclipped = VisibleWidget(
    base, RectF(10, 10, 50, 50), false, RectF()
  );
  assert(vwUnclipped.containsPoint(PointF(10, 10)));
  assert(vwUnclipped.containsPoint(PointF(59, 59)));
  assert(!vwUnclipped.containsPoint(PointF(60, 10)));

  auto vwClipped = VisibleWidget(
    base, RectF(10, 10, 50, 50), true, RectF(20, 20, 15, 15)
  );
  assert(vwClipped.containsPoint(PointF(25, 25)));
  assert(!vwClipped.containsPoint(PointF(15, 15)));
  assert(!vwClipped.containsPoint(PointF(40, 40)));
}
