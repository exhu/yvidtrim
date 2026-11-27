module yguilib.widget.data_components;
import yguilib.widget.component;
import yguilib.widget : Widget;

interface WidgetArrayProvider {
  void addWidget(Widget parent);
  void updateWidgetAt(Widget w, size_t index);
}

/// Creates child Widgets based on itemsCount via WidgetArrayProvider.
/// When itemsCount changes to lower hides unused Widgets, but does not
/// remove from the tree. Calls updateWidget when itemsCount changes or
/// modelChanged flag is true (clears flag after that).
/// That logic is implemented by DataSystem.
final class WidgetArrayComponent : WidgetComponent {
public:
  WidgetArrayProvider provider;
  size_t itemsCount;
  bool modelChanged;
}

unittest {
  final class DummyProvider : WidgetArrayProvider {
    override void addWidget(Widget parent) {}
    override void updateWidgetAt(Widget w, size_t index) {}
  }

  auto comp = new WidgetArrayComponent();
  assert(comp.provider is null);
  assert(comp.itemsCount == 0);
  assert(!comp.modelChanged);

  auto prov = new DummyProvider();
  comp.provider = prov;
  comp.itemsCount = 4;
  comp.modelChanged = true;
  assert(comp.provider is prov);
  assert(comp.itemsCount == 4);
  assert(comp.modelChanged);
}
