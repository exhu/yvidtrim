module yguilib.uisystem;
import yguilib.controller : Controller;
import yguilib.events : AppEvent;
import yguilib.timers : TimerCallback, TimerId, TimerMode;
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
   * Starts a standalone callback timer firing on the main thread during
   * Phase 2 of the event loop (after Phase 1 input drain and Phase 2a
   * `Controller.update()` model sync, and before Phase 3 `updateView()`
   * and rendering).
   *
   * Note: This callback is NOT invoked as part of `Controller.update()`
   * and does NOT automatically call `Controller.update()` or
   * `Controller.updateView()`. Return `true` to request a Phase 3 render
   * pass (e.g. after direct widget mutations), or call `sendUpdate()` if
   * controllers need a model-sync pass. For controller-owned animations
   * that should drive `tick(dt)` -> `updateView()`, prefer
   * `startControllerTimer`.
   *
   * Calling `start*Timer()` / `stopTimer()` from inside `callback` is safe.
   * Unlike `startControllerTimer` and `startSystemTimer`, callback timers
   * have no automatic owner cleanup; callers must call `stopTimer(id)`
   * before captured objects are destroyed.
   */
  TimerId startCallbackTimer(
    uint intervalMs,
    TimerMode mode,
    TimerCallback callback
  );

  /**
   * Starts a timer bound to `target`. When due in Phase 2 (after input
   * drain and model sync, before Phase 3), `UiSystem` calls
   * `target.tick(dt)` directly (independent of `Controller.update()`).
   * If `tick(dt)` returns `true`, `target.updateView()` is scheduled for
   * Phase 3. Automatically cancelled when `target` is popped from
   * `ControllerStack`.
   *
   * Note: Timers are not deduplicated per `target`. Calling this multiple
   * times for the same `Controller` registers independent timers; if
   * multiple are due in the same event-loop step, `target.tick(dt)` is
   * called once per due timer (each with that timer's `dt`), while
   * `target.updateView()` is still invoked at most once in Phase 3.
   */
  TimerId startControllerTimer(
    Controller target,
    uint intervalMs,
    TimerMode mode
  );

  /**
   * Starts a timer bound to `target` (which must include
   * `SystemPhase.update`). When due in Phase 2, `UiSystem` calls
   * `target.update(ctx, dt)` before Phase 3 layout and rendering.
   * Automatically cancelled when `target` is unregistered from the
   * pipeline.
   *
   * Note: Timers are not deduplicated per `target`. Calling this multiple
   * times for the same `WidgetSystem` registers independent timers; if
   * multiple are due in the same event-loop step, `target.update(ctx, dt)`
   * is called once per due timer (each with that timer's `dt`).
   */
  TimerId startSystemTimer(
    WidgetSystem target,
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
