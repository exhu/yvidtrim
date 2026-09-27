module yguilib.widget.internal.layout_system;

package(yguilib):
import yguilib.render : Renderer;
import yguilib.widget;
import yguilib.widget.layout;
import yguilib.widget.internal.collect_visible : VisibleWidgets, VisibleWidget;

final class LayoutSystem {
  void layoutTree(Widget root, Renderer r, VisibleWidgets visibleWidgets) {
    assert(root !is null);
    assert(r !is null);
    assert(visibleWidgets !is null);
    if (!root.visible) {
      return;
    }
  }

private:
}
