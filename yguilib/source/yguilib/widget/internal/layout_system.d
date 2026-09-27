module yguilib.widget.internal.layout_system;

package(yguilib):
import yguilib.render : Renderer;
import yguilib.render.render_types : PointF;
import yguilib.widget;
import yguilib.widget.layout_components;
import yguilib.widget.internal.collect_visible : VisibleWidgets, VisibleWidget;

final class LayoutSystem {
  void layoutTree(Widget root, Renderer r, VisibleWidgets visibleWidgets) {
    assert(root !is null);
    assert(r !is null);
    assert(visibleWidgets !is null);

    if (!root.visible || visibleWidgets.length == 0) {
      return;
    }

    foreach_reverse(VisibleWidget vw; visibleWidgets) {
      handleSizeComp(vw);
      }
    }

private:
  void handleSizeComp(VisibleWidget vw) {
      Size szComp = vw.widget.components.size;
      if (szComp is null)
        return;

      PointF contentSize;
      if (szComp.width.mode == SizingMode.auto_ ||
            szComp.height.mode == SizingMode.auto_) {
          // TODO calc text size etc. in contentSize
      }

      switch(szComp.width.mode) {
      case SizingMode.fixed:{
        vw.widget.rect.width = szComp.width.value;
        break;
      }
      case SizingMode.auto_:{
        // TODO set rect.width/height to
        // contentSize.x + Border.width + padding.left + padding.right
      }
      default:{}
      }

      switch(szComp.height.mode) {
      case SizingMode.fixed:{
        vw.widget.rect.height = szComp.height.value;
        break;
      }
      case SizingMode.auto_:{
        // TODO set rect.width/height to
        // contentSize.y + Border.width + padding.top + padding.bottom
      }
      default:{}
      }
      // TODO constrain by min/max width/height
  }
}
