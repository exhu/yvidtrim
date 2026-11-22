module yguilib.uisystem;
import yguilib.controller : Controller;
import yguilib.events : AppEvent;
import yguilib.timers : TimerId, TimerMode;
import yguilib.widget : Widget;
import yguilib.widget.widget_view : WidgetViewController, WidgetView;
import yguilib.widget.system : WidgetSystem, WidgetSystemHost;
import yguilib.window : Window;
import yguilib.object_registry : ObjectRegistry;

interface UiRegistry {
  @property ObjectRegistry!WidgetViewController widgetViewControllers();
  @property ObjectRegistry!WidgetView widgetViews();
}

interface ControllerStack {
  void popController();
  void pushController(Controller c);
  void pushModalController(Controller c);
}

interface FocusControl {
  void popFocusRoot();
  void pushFocusRoot(Widget w);
}

interface EventControl {
  void sendAppEvent(AppEvent ev);
}

/// Main-thread timer registration service replacing per-event timeoutMs.
interface TimerControl {
  /**
   * Starts a timer owned by `owner` (must not be null), firing on the main
   * thread during Phase 2b of the event loop (after Phase 1 input drain and
   * Phase 2a model-sync `update()`, and before Phase 3 `updateView()` and
   * rendering).
   *
   * Supported owners:
   * - `Controller`: When due in Phase 2b, `UiSystem` calls
   *   `owner.onTimer(id, dt)`. If it returns `true`, `owner.updateView()` is
   *   scheduled for Phase 3. Automatically cancelled when `owner` is popped
   *   from `ControllerStack`.
   * - `WidgetSystem`: When due in Phase 2b, `UiSystem` calls
   *   `owner.onTimer(ctx, id, dt)` regardless of `SystemPhase` flags, before
   *   Phase 3 layout and rendering. Automatically cancelled when `owner` is
   *   unregistered via `unregisterWidgetSystem()`.
   *
   * Note: Timers are not deduplicated per `owner`. Calling this multiple
   * times for the same owner registers independent timers; if multiple are
   * due in the same event-loop step, `onTimer` is called independently for
   * each due timer `(id, dt)`. Calling `startTimer()` / `stopTimer()` from
   * inside `onTimer()` is safe.
   */
  TimerId startTimer(
    Object owner,
    uint intervalMs,
    TimerMode mode
  );

  /// Cancels an active timer. Passing `invalidTimerId` (0) or an already
  /// stopped/expired ID is a safe no-op.
  void stopTimer(TimerId id);

  /// Returns `true` if `id` refers to a currently active timer.
  bool isTimerActive(TimerId id) const;
}

/// Interface for registering and querying WidgetSystems on UiSystem.
interface WidgetSystemControl {
  void registerWidgetSystem(WidgetSystem system);
  void unregisterWidgetSystem(WidgetSystem system);
  T findWidgetSystem(T : WidgetSystem)() {
    return cast(T) findWidgetSystemByType(typeid(T));
  }

protected:
  WidgetSystem findWidgetSystemByType(TypeInfo_Class type);
}

/// Manages Controllers, Messaging, Windows, and WidgetSystems.
interface UiSystem : ControllerStack, WidgetSystemHost, FocusControl,
  WidgetSystemControl, UiRegistry {
  @property Window mainWindow();
  void mainEventLoop();
  uint nextWidgetId();
  Widget makeWidget();
  void releaseWidget(Widget w);
  void setEventStatsEnabled(bool enabled);
  @property bool eventStatsEnabled();

  /// Returns a JSON string with debugging info (controller stack, registered
  /// views and view controllers, main window and root widget name/uId) in the
  /// `{type, fields}` schema. Main-thread only; reads UI state without
  /// locking.
  string dumpInfo();
}
