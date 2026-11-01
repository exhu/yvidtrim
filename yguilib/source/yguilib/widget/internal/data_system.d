module yguilib.widget.internal.data_system;

package(yguilib):
import yguilib.widget : Widget;
import yguilib.widget.system;
import yguilib.widget.data_components;

/// Handles WidgetArrayComponent and other from data_components.
final class DataSystem : WidgetSystem {
  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.preLayout;
  }

  override void preLayout(ref WidgetSystemContext ctx) {
    foreach(vw; ctx.visibleWidgets) {
      if (vw.widget.components.widgetArray !is null)
        handleWidgetArray(vw.widget);
    }
  }

private:
  void handleWidgetArray(Widget w) {
    WidgetArrayComponent c = w.components.widgetArray;
    const size_t availableWidgets = w.children.length;
    const bool layoutChanged = availableWidgets != c.itemsCount;
    const bool shouldUpdateWidgets = layoutChanged || c.modelChanged;

    if (layoutChanged) {
      const size_t newWidgets = c.itemsCount <= availableWidgets ? 0 :
        c.itemsCount - w.children.length;
      for(size_t n = 0; n < newWidgets; ++n) {
        c.provider.addWidget(w);
      }

      foreach(i, uw; w.parent.children) {
        uw.setVisible(i < c.itemsCount);
      }
    }

    if (shouldUpdateWidgets) {
      for(size_t i = 0; i < c.itemsCount; ++i) {
        c.provider.updateWidgetAt(w.parent.children[i], i);
        c.modelChanged = false;
      }
    }
  }
}
