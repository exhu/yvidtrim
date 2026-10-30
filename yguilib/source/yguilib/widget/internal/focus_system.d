module yguilib.widget.internal.focus_system;

package(yguilib):

import yguilib.events : AppEvent;
import yguilib.widget : Widget;
import yguilib.widget.system : SystemEventResult, SystemPhase,
  WidgetSystem, WidgetSystemContext;
import yguilib.widget.visible : VisibleWidget, VisibleWidgets;

final class FocusSystem : WidgetSystem {
  // TODO needs to cache widgets to map distance, detect which widget is
  // next/prev in focusing for convenient arrow/gamepad navigation
  // TODO support focus root (i.e. cycle focus only inside a subtree,
  // e.g. an active dialog)

  this() nothrow @safe {
    super(focusSystemPriority);
  }

  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.event;
  }

  override SystemEventResult handleEvent(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    const bool updated = handleEventAndUpdateView(event, ctx.visibleWidgets);
    return SystemEventResult(false, updated);
  }

  /// returns true on focus change
  bool handleEventAndUpdateView(in AppEvent event, VisibleWidgets widgets) {
    // TODO focus on mouse click
    // TODO focus on tab, shift-tab
    return false;
  }
}

unittest {
  auto fs = new FocusSystem();
  assert(fs.priority == WidgetSystem.focusSystemPriority);
  assert(fs.phases == SystemPhase.event);

  WidgetSystemContext ctx;
  AppEvent ev;
  auto res = fs.handleEvent(ev, ctx);
  assert(!res.consumed);
  assert(!res.requestUpdateView);
}
