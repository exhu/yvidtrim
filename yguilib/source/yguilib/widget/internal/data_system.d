module yguilib.widget.internal.data_system;

package(yguilib):
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.system;
import yguilib.widget.data_components;

/// Handles WidgetArrayComponent and other from data_components.
final class DataSystem : WidgetSystem {
  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.preLayout;
  }

  override void preLayout(ref WidgetSystemContext ctx) {
    foreach (vw; ctx.visibleWidgets) {
      if (vw.widget !is null && vw.widget.components.widgetArray !is null) {
        handleWidgetArray(vw.widget);
      }
    }
  }

private:
  void handleWidgetArray(Widget w) {
    WidgetArrayComponent c = w.components.widgetArray;
    if (c is null || c.provider is null) {
      return;
    }

    size_t visibleCount = 0;
    foreach (uw; w.children) {
      if (uw.visible) {
        ++visibleCount;
      }
    }

    const size_t availableWidgets = w.children.length;
    const bool layoutChanged = visibleCount != c.itemsCount;
    const bool shouldUpdateWidgets = layoutChanged || c.modelChanged;

    if (layoutChanged) {
      const size_t newWidgets = c.itemsCount <= availableWidgets ? 0 :
        c.itemsCount - availableWidgets;
      for (size_t n = 0; n < newWidgets; ++n) {
        c.provider.addWidget(w);
      }

      foreach (i, uw; w.children) {
        uw.setVisible(i < c.itemsCount);
      }
      w.update(WidgetUpdateScope.layout);
    }

    if (shouldUpdateWidgets) {
      for (size_t i = 0; i < c.itemsCount; ++i) {
        c.provider.updateWidgetAt(w.children[i], i);
      }
      c.modelChanged = false;
    }
  }
}

version (unittest) {
  import yguilib.render.render_types : RectF;
  import yguilib.widget.visible : VisibleWidget;

  private final class MockWidgetArrayProvider : WidgetArrayProvider {
    size_t addWidgetCalls;
    size_t updateWidgetCalls;
    size_t[] updatedIndices;
    Widget[] updatedWidgets;
    uint nextId = 1000;

    override void addWidget(Widget parent) {
      ++addWidgetCalls;
      cast(void) new Widget(nextId++, parent, RectF(0, 0, 50, 20));
    }

    override void updateWidgetAt(Widget w, size_t index) {
      ++updateWidgetCalls;
      updatedIndices ~= index;
      updatedWidgets ~= w;
    }

    void reset() {
      addWidgetCalls = 0;
      updateWidgetCalls = 0;
      updatedIndices = null;
      updatedWidgets = null;
    }
  }
}

unittest {
  auto ds = new DataSystem();
  assert(ds.phases == SystemPhase.preLayout);
  assert(ds.priority == WidgetSystem.defaultPriority);
}

unittest {
  auto ds = new DataSystem();
  WidgetSystemContext ctx;

  // Empty visible widgets should not crash
  ds.preLayout(ctx);

  // Widget without widgetArray component should be ignored
  auto plainWidget = new Widget(1, null, RectF(0, 0, 100, 100));
  ctx.visibleWidgets = [VisibleWidget(plainWidget, RectF(0, 0, 100, 100))];
  ds.preLayout(ctx);
  assert(plainWidget.children.length == 0);

  // Widget with widgetArray but null provider should safely do nothing
  auto arrWidget = new Widget(2, null, RectF(0, 0, 100, 100));
  arrWidget.components.widgetArray = new WidgetArrayComponent();
  arrWidget.components.widgetArray.itemsCount = 3;
  ctx.visibleWidgets = [VisibleWidget(arrWidget, RectF(0, 0, 100, 100))];
  ds.preLayout(ctx);
  assert(arrWidget.children.length == 0);
}

unittest {
  auto ds = new DataSystem();
  auto container = new Widget(1, null, RectF(0, 0, 200, 200));
  auto comp = new WidgetArrayComponent();
  auto provider = new MockWidgetArrayProvider();
  comp.provider = provider;
  comp.itemsCount = 3;
  comp.modelChanged = false;
  container.components.widgetArray = comp;

  WidgetSystemContext ctx;
  ctx.visibleWidgets = [VisibleWidget(container, RectF(0, 0, 200, 200))];

  // Initial creation: 3 widgets added and updated
  ds.preLayout(ctx);
  assert(provider.addWidgetCalls == 3);
  assert(container.children.length == 3);
  assert(provider.updateWidgetCalls == 3);
  assert(provider.updatedIndices == [0, 1, 2]);
  assert(provider.updatedWidgets == container.children);
  foreach (child; container.children) {
    assert(child.visible);
  }
  assert(!comp.modelChanged);

  // Second pass with same itemsCount and no model change: no-op
  provider.reset();
  ds.preLayout(ctx);
  assert(provider.addWidgetCalls == 0);
  assert(provider.updateWidgetCalls == 0);
  assert(container.children.length == 3);

  // Model changed flag triggers update without adding new widgets
  provider.reset();
  comp.modelChanged = true;
  ds.preLayout(ctx);
  assert(provider.addWidgetCalls == 0);
  assert(provider.updateWidgetCalls == 3);
  assert(provider.updatedIndices == [0, 1, 2]);
  assert(provider.updatedWidgets == container.children);
  assert(!comp.modelChanged);
}

unittest {
  auto ds = new DataSystem();
  auto container = new Widget(1, null, RectF(0, 0, 200, 200));
  auto comp = new WidgetArrayComponent();
  auto provider = new MockWidgetArrayProvider();
  comp.provider = provider;
  comp.itemsCount = 3;
  container.components.widgetArray = comp;

  WidgetSystemContext ctx;
  ctx.visibleWidgets = [VisibleWidget(container, RectF(0, 0, 200, 200))];

  // Initial populate to 3 items
  ds.preLayout(ctx);
  assert(container.children.length == 3);

  // Grow itemsCount from 3 to 5: allocates 2 additional widgets
  provider.reset();
  comp.itemsCount = 5;
  ds.preLayout(ctx);
  assert(provider.addWidgetCalls == 2);
  assert(container.children.length == 5);
  assert(provider.updateWidgetCalls == 5);
  assert(provider.updatedIndices == [0, 1, 2, 3, 4]);
  foreach (child; container.children) {
    assert(child.visible);
  }

  // Shrink itemsCount from 5 to 2: pool retains 5, hides excess, updates 2
  provider.reset();
  comp.itemsCount = 2;
  ds.preLayout(ctx);
  assert(provider.addWidgetCalls == 0);
  assert(container.children.length == 5);
  assert(container.children[0].visible);
  assert(container.children[1].visible);
  assert(!container.children[2].visible);
  assert(!container.children[3].visible);
  assert(!container.children[4].visible);
  assert(provider.updateWidgetCalls == 2);
  assert(provider.updatedIndices == [0, 1]);

  // Next pass with itemsCount = 2: no repeated update or visibility toggling
  provider.reset();
  ds.preLayout(ctx);
  assert(provider.addWidgetCalls == 0);
  assert(provider.updateWidgetCalls == 0);

  // Grow from 2 to 4: reuse widgets already in pool, no new allocation
  provider.reset();
  comp.itemsCount = 4;
  ds.preLayout(ctx);
  assert(provider.addWidgetCalls == 0);
  assert(container.children.length == 5);
  assert(container.children[0].visible);
  assert(container.children[1].visible);
  assert(container.children[2].visible);
  assert(container.children[3].visible);
  assert(!container.children[4].visible);
  assert(provider.updateWidgetCalls == 4);
  assert(provider.updatedIndices == [0, 1, 2, 3]);

  // Shrink to 0: all widgets hidden, 0 updateWidgetAt calls,
  // modelChanged cleared
  provider.reset();
  comp.itemsCount = 0;
  comp.modelChanged = true;
  ds.preLayout(ctx);
  assert(provider.addWidgetCalls == 0);
  assert(container.children.length == 5);
  foreach (child; container.children) {
    assert(!child.visible);
  }
  assert(provider.updateWidgetCalls == 0);
  assert(!comp.modelChanged);

  // Stable at 0
  provider.reset();
  ds.preLayout(ctx);
  assert(provider.addWidgetCalls == 0);
  assert(provider.updateWidgetCalls == 0);
}

unittest {
  // Test multiple visible widgets processed in single preLayout pass
  auto ds = new DataSystem();
  auto cont1 = new Widget(1, null, RectF(0, 0, 100, 100));
  auto comp1 = new WidgetArrayComponent();
  auto prov1 = new MockWidgetArrayProvider();
  comp1.provider = prov1;
  comp1.itemsCount = 2;
  cont1.components.widgetArray = comp1;

  auto cont2 = new Widget(2, null, RectF(100, 0, 100, 100));
  auto comp2 = new WidgetArrayComponent();
  auto prov2 = new MockWidgetArrayProvider();
  comp2.provider = prov2;
  comp2.itemsCount = 1;
  cont2.components.widgetArray = comp2;

  WidgetSystemContext ctx;
  ctx.visibleWidgets = [
    VisibleWidget(cont1, RectF(0, 0, 100, 100)),
    VisibleWidget(cont2, RectF(100, 0, 100, 100)),
  ];

  ds.preLayout(ctx);
  assert(cont1.children.length == 2);
  assert(prov1.addWidgetCalls == 2);
  assert(prov1.updateWidgetCalls == 2);

  assert(cont2.children.length == 1);
  assert(prov2.addWidgetCalls == 1);
  assert(prov2.updateWidgetCalls == 1);
}

