module yguilib.widget.internal.layout_system;

package(yguilib):
import yguilib.render : Renderer;
import yguilib.render.render_types : PointF, RectF;
import yguilib.widget;
import yguilib.widget.layout_components;
import yguilib.widget.drawing_components;
import yguilib.widget.internal.collect_visible : VisibleWidgets, VisibleWidget;

final class LayoutSystem {
  // expects visibleWidgets to include clipped children as well
  void layoutTree(Widget root, Renderer r, VisibleWidgets visibleWidgets) {
    assert(root !is null);
    assert(r !is null);
    assert(visibleWidgets !is null);

    if (!root.visible || visibleWidgets.length == 0) {
      return;
    }

    // compute initial sizes: leaf to root
    foreach_reverse(VisibleWidget vw; visibleWidgets) {
      handleSizeComp(vw);
    }

    // compute position and sizes by flexContainers: root to leaf
    foreach(VisibleWidget vw; visibleWidgets) {
      handleFlexContainerComp(vw);
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

  // TODO split this into manageable smaller functions
  void handleFlexContainerComp(VisibleWidget vw) {
      FlexContainer flexComp = vw.widget.components.flexContainer;
      if (flexComp is null)
        return;
      if (vw.widget.children is null || vw.widget.children.length == 0)
        return;

      // TODO filter invisible (by flag, not by rects)
      auto widgets = vw.widget.children;

      // TODO move contentRect to a function
      RectF contentRect = RectF(0, 0, vw.widget.rect.width, vw.widget.rect.height);
      Border parentBorderComp = vw.widget.components.border;
      if (parentBorderComp !is null) {
        contentRect.width -= parentBorderComp.width*2;
        contentRect.height -= parentBorderComp.width*2;
        contentRect.x += parentBorderComp.width;
        contentRect.y += parentBorderComp.width;
      }
      Size parentSzComp = vw.widget.components.size;
      if (parentSzComp !is null) {
        contentRect.width -= (parentSzComp.padding.left + parentSzComp.padding.right);
        contentRect.height -= (parentSzComp.padding.top + parentSzComp.padding.bottom);
        contentRect.x += parentSzComp.padding.left;
        contentRect.y += parentSzComp.padding.top;
      }

      size_t fixedWidgets = 0;
      if (flexComp.direction == FlexDirection.row) {
        float fixedSizes = 0;
        foreach(Widget w; widgets) {
          Size sizeComp = w.components.size;
          if (sizeComp !is null) {
            if (sizeComp.width.mode == SizingMode.fraction) {
              // TODO account for fraction SizingMode
            }
            else {
              fixedSizes += w.rect.width;
              fixedWidgets += 1;
            }
          }
        }
        if (flexComp.justify == JustifyContent.start) {
          float posOffset = contentRect.x;
          foreach(i, Widget w; widgets) {
            w.rect.x = posOffset;
            // TODO handle fraction SizingMode
            posOffset += w.rect.width;
            if (i+1 < widgets.length)
              posOffset += flexComp.gap;

            final switch(flexComp.alignItems) {
            case AlignItems.start:
              w.rect.y = contentRect.y;
              break;
            case AlignItems.end:
              w.rect.y = contentRect.y + contentRect.height - w.rect.height - 1;
              break;
            case AlignItems.center:
              import std.math : floor;
              w.rect.y = floor(contentRect.y + contentRect.height*0.5 - 1 - w.rect.height*0.5 + 0.5);
              break;
            case AlignItems.stretch:
              w.rect.y = contentRect.y;
              w.rect.height = contentRect.height;
              break;
            }
          }
        }
        // TODO handle other JustifyContent
      }
      else {
        // TODO FlexDirection.column
      }
  }
}
