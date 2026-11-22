/**
 * testing.d - Shared unittest helpers and mock hosts for `yguilib.controls`.
 */
module yguilib.controls.testing;

version (unittest):

import yguilib.events : AppEvent;
import yguilib.internal.uisystem_impl : UiSystemImpl;
import yguilib.object_registry : ObjectRegistry;
import yguilib.render.render_types : RectF;
import yguilib.timercontrol : TimerId;
import yguilib.timers : TimerMode;
import yguilib.widget : Widget;
import yguilib.widget.system : WidgetSystemHost;
import yguilib.widget.widget_view : WidgetView, WidgetViewController;

/// Asserts that `w` and every descendant in its subtree have non-empty names.
void verifyAllNamed(const Widget w) {
  assert(w !is null, "Widget must not be null");
  assert(w.name.length > 0, "Widget missing name");
  foreach (child; w.children) {
    verifyAllNamed(child);
  }
}

/// Computes `w`'s absolute rectangle by summing ancestor `rect.x`/`rect.y`
/// offsets up the parent chain.
RectF calcAbsRect(const Widget w) {
  assert(w !is null, "Widget must not be null");
  float x = w.rect.x;
  float y = w.rect.y;
  for (auto p = cast(Widget) w.parent; p !is null; p = p.parent) {
    x += p.rect.x;
    y += p.rect.y;
  }
  return RectF(x, y, w.rect.width, w.rect.height);
}

/// Headless `UiSystemImpl` subclass that records all `sendAppEvent` calls.
final class RecordingUiSystem : UiSystemImpl {
  AppEvent[] sentEvents;

  /// Constructs a headless `RecordingUiSystem`.
  this() {
    super(null);
  }

  override void sendAppEvent(AppEvent ev) {
    sentEvents ~= ev;
    super.sendAppEvent(ev);
  }
}

/// Minimal `WidgetSystemHost` test double recording sent events and active
/// timers without creating a window or event loop.
class DummyWidgetSystemHost : WidgetSystemHost {
  AppEvent[] sentEvents;
  bool[TimerId] activeTimers;
  TimerId nextTimerId = 1;
  ObjectRegistry!WidgetViewController dummyControllers;
  ObjectRegistry!WidgetView dummyViews;

  /// Constructs a `DummyWidgetSystemHost` with empty registries.
  this() {
    dummyControllers = new ObjectRegistry!WidgetViewController();
    dummyViews = new ObjectRegistry!WidgetView();
  }

  invariant {
    assert(dummyControllers !is null);
    assert(dummyViews !is null);
  }

  override void sendAppEvent(AppEvent ev) {
    sentEvents ~= ev;
  }

  override TimerId startTimer(
    Object owner,
    uint intervalMs,
    TimerMode mode
  ) {
    const TimerId id = nextTimerId++;
    activeTimers[id] = true;
    return id;
  }

  override void stopTimer(TimerId id) {
    activeTimers.remove(id);
  }

  override bool isTimerActive(TimerId id) const {
    return (id in activeTimers) !is null;
  }

  override @property
  ObjectRegistry!WidgetViewController widgetViewControllers() {
    return dummyControllers;
  }

  override @property ObjectRegistry!WidgetView widgetViews() {
    return dummyViews;
  }
}

unittest {
  import yguilib.events.builder : ViewAppEventBuilder;

  auto ui = new RecordingUiSystem();
  auto root = ui.makeWidget();
  root.name = "root";
  root.rect = RectF(10, 20, 200, 100);

  auto child = ui.makeWidget();
  child.name = "child";
  child.rect = RectF(5, 8, 50, 30);
  root.addChild(child);

  verifyAllNamed(root);
  assert(calcAbsRect(root) == RectF(10, 20, 200, 100));
  assert(calcAbsRect(child) == RectF(15, 28, 50, 30));

  auto ev = ViewAppEventBuilder("ping").widget(child).build();
  ui.sendAppEvent(ev);
  assert(ui.sentEvents.length == 1);
  assert(ui.sentEvents[0].view.eventName == "ping");

  auto host = new DummyWidgetSystemHost();
  assert(host.widgetViewControllers !is null);
  assert(host.widgetViews !is null);
  host.sendAppEvent(ev);
  assert(host.sentEvents.length == 1);

  const TimerId tid = host.startTimer(host, 16, TimerMode.repeat);
  assert(host.isTimerActive(tid));
  host.stopTimer(tid);
  assert(!host.isTimerActive(tid));
}
