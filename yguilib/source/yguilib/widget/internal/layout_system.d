module yguilib.widget.internal.layout_system;

package(yguilib):
import yguilib.render : Renderer;
import yguilib.widget;
import yguilib.widget.layout;

final class LayoutSystem {
  void layoutTree(Widget root, Renderer r) {
    assert(root !is null);
    assert(r !is null);
    if (!root.visible) {
      return;
    }
    // TODO need to get the visibleBuf from PainterSystem
    version(none) {
      visibleBuf.clear();
      const float vw = r.getLogicWidth();
      const float vh = r.getLogicHeight();
      // TODO extract visible to reuse for layout system
      collectVisible(root, 0.0f, 0.0f, vw, vh);
      drawWidgets(visibleBuf[], r);
    }
  }

private:
}
