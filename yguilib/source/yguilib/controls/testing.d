/**
 * testing.d - Shared unittest helpers and mock hosts for `yguilib.controls`.
 */
module yguilib.controls.testing;

version (unittest):

import yguilib.controller : Controller;
import yguilib.events : AppEvent;
import yguilib.internal.uisystem_impl : UiSystemImpl;
import yguilib.object_registry : ObjectRegistry;
import yguilib.render.render_types : RectF;
import yguilib.timercontrol : TimerId;
import yguilib.timers : TimerMode;
import yguilib.widget : Widget;
import yguilib.widget.system : WidgetSystem, WidgetSystemHost;
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
  if (w.parent is null) {
    return w.rect;
  }
  const RectF parentAbs = calcAbsRect(w.parent);
  return RectF(
    parentAbs.x + w.rect.x,
    parentAbs.y + w.rect.y,
    w.rect.width,
    w.rect.height
  );
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
  struct TimerRecord {
    uint intervalMs;
    TimerMode mode;
  }

  AppEvent[] sentEvents;
  bool[TimerId] activeTimers;
  TimerRecord[TimerId] timerMeta;
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

  override TimerId startControllerTimer(
    Controller target,
    uint intervalMs,
    TimerMode mode
  ) {
    const TimerId id = nextTimerId++;
    activeTimers[id] = true;
    timerMeta[id] = TimerRecord(intervalMs, mode);
    return id;
  }

  override TimerId startSystemTimer(
    WidgetSystem target,
    uint intervalMs,
    TimerMode mode
  ) {
    const TimerId id = nextTimerId++;
    activeTimers[id] = true;
    timerMeta[id] = TimerRecord(intervalMs, mode);
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

  class DummySystem : WidgetSystem {}
  auto dummySys = new DummySystem();
  const TimerId tid = host.startSystemTimer(dummySys, 16, TimerMode.repeat);
  assert(host.isTimerActive(tid));
  assert(host.timerMeta[tid].intervalMs == 16);
  assert(host.timerMeta[tid].mode == TimerMode.repeat);
  host.stopTimer(tid);
  assert(!host.isTimerActive(tid));
}
