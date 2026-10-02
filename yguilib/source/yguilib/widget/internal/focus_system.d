module yguilib.widget.internal.focus_system;
import yguilib.widget;
import yguilib.events;
import yguilib.widget.internal.collect_visible : VisibleWidgets, VisibleWidget;

final class FocusSystem {
  // TODO needs to cache widgets to map distance, detect which widget is next/prev in focusing
  // for convenient arrow/gamepad navigation
  // TODO support focus root (i.e. cycle focus only inside a subtree, e.g. an active dialog)

  /// returns true on focus change
  bool handleEventAndUpdateView(AppEvent event, VisibleWidgets widgets) {
    // TODO focus on mouse click
    // TODO focus on tab, shift-tab
    return false;
  }
}
