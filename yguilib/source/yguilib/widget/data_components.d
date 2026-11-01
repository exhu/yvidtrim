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
