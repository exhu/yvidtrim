module yguilib.internal.uisystem_impl;

import glad2.gles2;
import std.typecons : Nullable;
import std.logger;
import yguilib.clibs.sdl3;
import yguilib.timers : TimerCallback, TimerId, TimerMode;
import yguilib.uisystem;
import yguilib.controller : Controller, DefaultController, HandleResult;
import yguilib.controller.internal.controller_stack : ControllerStack;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode, Scancode;
import yguilib.events.internal.message_bus : MessageBus;
import yguilib.events.internal.sdl_events : appEventFromSdlEvent;
import yguilib.render : Renderer;
import yguilib.object_registry : ObjectRegistry;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.widget_view : WidgetViewController, WidgetView;
import yguilib.widget.internal.focus_system : FocusSystem;
import yguilib.widget.internal.input_system;
import yguilib.widget.internal.layout_system : LayoutSystem;
import yguilib.widget.internal.system_pipeline : WidgetSystemPipeline;
import yguilib.widget.internal.widget_painter : WidgetPainterSystem;
debug {
  import yguilib.widget.internal.debug_draw_system : DebugDrawSystem;
}
import yguilib.widget.internal.data_system: DataSystem;
import yguilib.widget.internal.scroll_system : ScrollSystem;
import yguilib.widget.system : WidgetSystem;
import yguilib.window : Window;
import yguilib.internal.timer_service : TimerEntry, TimerService;
import yguilib.internal.uisystem_controller;

class UiSystemImpl : UiSystem {
  /// Constructs UiSystemImpl. Window w is allowed to be null in headless tests.
  this(Window w) {
    fMainWindow = w;
    messageBus = MessageBus(this);
    pipeline = new WidgetSystemPipeline(this);
    pipeline.registerSystem(new FocusSystem());
    pipeline.registerSystem(new InputSystem(this));
    pipeline.registerSystem(new LayoutSystem());
    pipeline.registerSystem(new ScrollSystem(this));
    pipeline.registerSystem(new WidgetPainterSystem());
    debug {
      pipeline.registerSystem(new DebugDrawSystem());
    }
    pipeline.registerSystem(new DataSystem());
    fWidgetViewControllers = new ObjectRegistry!WidgetViewController();
    fWidgetViews = new ObjectRegistry!WidgetView();
  }

  override uint nextWidgetId() {
    return fNextWidgetId++;
  }

  override Widget makeWidget() {
    return new Widget(nextWidgetId());
  }

  /// safe to call from a thread
  override void sendAppEvent(AppEvent ev) {
    messageBus.send(ev);
  }

  override TimerId startTimer(
    uint intervalMs,
    TimerMode mode,
    TimerCallback callback
  ) {
    return timerService.startCallbackTimer(intervalMs, mode, callback);
  }

  override TimerId startTimer(
    Controller target,
    uint intervalMs = 16,
    TimerMode mode = TimerMode.repeat
  ) {
    return timerService.startControllerTimer(target, intervalMs, mode);
  }

  override TimerId startTimer(
    WidgetSystem target,
    uint intervalMs = 16,
    TimerMode mode = TimerMode.repeat
  ) {
    return timerService.startSystemTimer(target, intervalMs, mode);
  }

  override void stopTimer(TimerId id) {
    timerService.stopTimer(id);
  }

  override bool isTimerActive(TimerId id) const {
    return timerService.isTimerActive(id);
  }

  override void setEventStatsEnabled(bool enabled) {
    messageBus.setStatsEnabled(enabled);
  }

  override @property bool eventStatsEnabled() {
    return messageBus.statsEnabled;
  }

  override @property Window mainWindow() {
    return fMainWindow;
  }

  override void registerWidgetSystem(WidgetSystem system) {
    assert(system !is null);
    pipeline.registerSystem(system);
  }

  override void unregisterWidgetSystem(WidgetSystem system) {
    assert(system !is null);
    timerService.stopTimersForSystem(system);
    pipeline.unregisterSystem(system);
  }

  package(yguilib) @property WidgetSystemPipeline systemPipeline() {
    return pipeline;
  }

  package(yguilib) void setTimerClock(long delegate() clock) {
    timerService.setClock(clock);
  }

  package(yguilib) int nextWaitTimeoutMs() const {
    return timerService.nextWaitTimeoutMs(timerService.nowNs());
  }

  protected override WidgetSystem findWidgetSystemByType(TypeInfo_Class type) {
    return pipeline.findSystemByType(type);
  }

  override void pushController(Controller c) {
    controllers.push(c);
  }

  override void pushModalController(Controller c) {
    controllers.pushModal(c);
  }

  override void popController() {
    Controller active = controllers.getActiveOrNull();
    if (active !is null) {
      timerService.stopTimersForController(active);
    }
    controllers.pop();
  }

  override void pushFocusRoot(Widget w) {
    // TODO
  }

  override void popFocusRoot() {
    // TODO
  }

  override void releaseWidget(Widget w) {
    if (w is null || w.released) {
      return;
    }

    // 1. Snapshot children and recursively release them bottom-up
    Widget[] childrenSnapshot = w.children.dup;
    foreach (child; childrenSnapshot) {
      releaseWidget(child);
    }

    // 2. Clean up references to w in Window, registries, controllers,
    // and pipeline
    if (fMainWindow !is null && fMainWindow.rootWidget is w) {
      fMainWindow.rootWidget = null;
    }

    foreach (view; fWidgetViews) {
      if (view !is null) {
        view.unregisterViewWidget(w);
      }
    }

    foreach (ctrl; fWidgetViewControllers) {
      if (ctrl !is null) {
        ctrl.unregisterViewWidget(w);
      }
    }

    foreach (ctrl; controllers) {
      if (ctrl !is null) {
        ctrl.onWidgetReleased(w);
      }
    }

    pipeline.notifyWidgetReleased(w);

    // 3. Clear w's own fields and mark released
    w.release();
  }

  override void mainEventLoop() {
    yguilib_sdl3_init();
    scope (exit) yguilib_sdl3_quit();

    if (fMainWindow !is null) {
      fMainWindow.create();
    }
    scope (exit) {
      if (fMainWindow !is null) {
        fMainWindow.destroy();
      }
    }

    auto sysCtrl = new UiSystemController(this, pipeline);
    pushController(sysCtrl);
    scope (exit) {
      if (controllers.getActiveOrNull() is sysCtrl) {
        popController();
      } else {
        timerService.stopTimersForController(sysCtrl);
      }
    }

    pipeline.updateAndRender(fMainWindow);

    messageBus.bindMainThread();
    scope (exit) messageBus.unbindMainThread();

    while (getActiveControllerOrNull() !is null) {
      if (!runEventLoopStep()) {
        break;
      }
    }
    messageBus.logStats();
  }

  override @property
  ObjectRegistry!WidgetViewController widgetViewControllers() {
    return fWidgetViewControllers;
  }

  override @property ObjectRegistry!WidgetView widgetViews() {
    return fWidgetViews;
  }

  override string dumpInfo() {
    import std.json : JSONValue;
    import yguilib.serhelpers : serializeToJson, shortTypeName;

    JSONValue[string] root;
    root["type"] = JSONValue("UiSystem");

    JSONValue[string] fields;

    // Controller stack
    JSONValue[] controllerList;
    foreach (ctrl; controllers) {
      JSONValue[string] ctrlJson;
      ctrlJson["type"] = JSONValue(shortTypeName(ctrl));
      ctrlJson["isModal"] = JSONValue(ctrl.isModal);
      controllerList ~= JSONValue(ctrlJson);
    }
    fields["controllers"] = JSONValue(controllerList);

    // Registered views
    JSONValue[string] viewsJson;
    foreach (name, view; fWidgetViews) {
      viewsJson[name] = JSONValue(shortTypeName(view));
    }
    fields["widgetViews"] = JSONValue(viewsJson);

    // Registered view controllers
    JSONValue[string] viewControllersJson;
    foreach (name, ctrl; fWidgetViewControllers) {
      viewControllersJson[name] = JSONValue(shortTypeName(ctrl));
    }
    fields["widgetViewControllers"] = JSONValue(viewControllersJson);

    // Window
    if (fMainWindow !is null) {
      JSONValue[string] winJson;
      winJson["title"] = JSONValue(fMainWindow.title);
      winJson["width"] = JSONValue(fMainWindow.width);
      winJson["height"] = JSONValue(fMainWindow.height);

      if (fMainWindow.rootWidget !is null) {
        JSONValue[string] rootWidgetJson;
        rootWidgetJson["name"] = JSONValue(fMainWindow.rootWidget.name);
        rootWidgetJson["uId"] = JSONValue(fMainWindow.rootWidget.uId);
        winJson["rootWidget"] = JSONValue(rootWidgetJson);
      } else {
        winJson["rootWidget"] = JSONValue(null);
      }
      fields["window"] = JSONValue(winJson);
    } else {
      fields["window"] = JSONValue(null);
    }

    root["fields"] = JSONValue(fields);
    return serializeToJson(JSONValue(root));
  }

private:
  struct ControllerDirtyList {
    Controller[16] stackBuf;
    size_t stackCount = 0;
    Controller[] heapList;

    void add(Controller c) {
      if (c is null || contains(c)) {
        return;
      }
      if (heapList.length > 0) {
        heapList ~= c;
      } else if (stackCount < stackBuf.length) {
        stackBuf[stackCount++] = c;
      } else {
        heapList = stackBuf[].dup;
        heapList ~= c;
      }
    }

    bool contains(Controller c) const {
      if (heapList.length > 0) {
        foreach (item; heapList) {
          if (item is c) {
            return true;
          }
        }
        return false;
      }
      foreach (item; stackBuf[0 .. stackCount]) {
        if (item is c) {
          return true;
        }
      }
      return false;
    }

    @property bool empty() const {
      return stackCount == 0 && heapList.length == 0;
    }
  }

  void enqueueSdlEvent(in yguilib_sdl3_Event sdlEv) {
    Nullable!AppEvent appEv = appEventFromSdlEvent(sdlEv);
    if (!appEv.isNull) {
      sendAppEvent(appEv.get());
    }
  }

  void waitForEventsIfIdle() {
    if (!messageBus.prepareToWait()) {
      return;
    }
    const int waitMs = timerService.nextWaitTimeoutMs(timerService.nowNs());
    if (waitMs == 0) {
      return;
    }
    yguilib_sdl3_Event sdlEv;
    const int res = yguilib_sdl3_wait_event(&sdlEv, waitMs);
    if (res > 0) {
      enqueueSdlEvent(sdlEv);
    }
  }

  void drainSdlEvents() {
    yguilib_sdl3_Event sdlEv;
    while (yguilib_sdl3_poll_event(&sdlEv) > 0) {
      enqueueSdlEvent(sdlEv);
    }
  }

  /**
   * Snapshots active controllers to a local stack buffer to avoid GC
   * allocations and protect against stack mutations during handleEvent.
   */
  Controller[] snapshotControllers(ref Controller[16] stackBuf) {
    const size_t numControllers = controllers.length;
    if (numControllers <= stackBuf.length) {
      stackBuf[0 .. numControllers] =
        controllers.getAll()[0 .. numControllers];
      return stackBuf[0 .. numControllers];
    }
    return controllers.getAll().dup;
  }

  bool isMainWindowEvent(uint windowId) const {
    return (windowId == 0 || fMainWindow.id == 0 ||
      windowId == fMainWindow.id);
  }

  void handleMainWindowEvent(in AppEvent event, ref bool needRender) {
    if (fMainWindow is null || !event.isWindowEvent()) {
      return;
    }
    if (isMainWindowEvent(event.window.windowId)) {
      fMainWindow.handleWindowEvent(event);
      if (fMainWindow.rootWidget !is null && event.isWindowRedrawEvent()) {
        fMainWindow.rootWidget.update(WidgetUpdateScope.all);
        needRender = true;
      }
    }
  }

  /**
   * Dispatches a discrete event through the controller stack from newest
   * (active) to oldest, stopping early when consumed.
   * Returns false if quit was requested.
   */
  bool dispatchDiscreteEvent(
    AppEvent event,
    ref ControllerDirtyList dirtyViews,
    ref bool needModelUpdate,
    ref bool needRender
  ) {
    handleMainWindowEvent(event, needRender);

    Controller[16] stackBuf;
    Controller[] activeList = snapshotControllers(stackBuf);

    for (ptrdiff_t i = cast(ptrdiff_t) activeList.length - 1; i >= 0; --i) {
      Controller c = activeList[i];
      if (c is null) {
        continue;
      }

      Controller.HandleResult result = c.handleEvent(event);
      final switch (result.result) {
      case Controller.HandleResult.Result.quit:
        return false;
      case Controller.HandleResult.Result.nothing:
        break;
      case Controller.HandleResult.Result.update:
        needModelUpdate = true;
        break;
      case Controller.HandleResult.Result.updateView:
        dirtyViews.add(c);
        break;
      }

      if (result.consume) {
        break;
      }
    }

    return true;
  }

  bool drainMessageBus(
    ref ControllerDirtyList dirtyViews,
    ref bool needModelUpdate,
    ref bool needRender
  ) {
    enum size_t maxEventsPerStep = 256;
    size_t processed = 0;
    while (processed < maxEventsPerStep) {
      if (processed > 0 && timerService.hasDueTimers(timerService.nowNs())) {
        break;
      }
      Nullable!AppEvent nullableEvent = getAppEvent();
      if (nullableEvent.isNull) {
        break;
      }
      processed++;
      AppEvent event = nullableEvent.get();
      if (event.kind == AppEvent.Kind.update) {
        needModelUpdate = true;
        continue;
      }
      if (!dispatchDiscreteEvent(
          event, dirtyViews, needModelUpdate, needRender)) {
        return false;
      }
    }
    return true;
  }

  void runPhase2Updates(
    ref ControllerDirtyList dirtyViews,
    bool needModelUpdate,
    ref bool needRender
  ) {
    if (needModelUpdate) {
      Controller[16] stackBuf;
      Controller[] activeList = snapshotControllers(stackBuf);
      foreach_reverse (c; activeList) {
        if (c !is null && c.update()) {
          dirtyViews.add(c);
        }
      }
    }

    const long tickNowNs = timerService.nowNs();
    timerService.fireDueTimers(tickNowNs, (TimerEntry entry, float dt) {
      final switch (entry.targetKind) {
      case TimerEntry.TargetKind.controller:
        if (entry.controllerTarget !is null &&
            entry.controllerTarget.tick(dt)) {
          dirtyViews.add(entry.controllerTarget);
        }
        break;
      case TimerEntry.TargetKind.widgetSystem:
        if (entry.systemTarget !is null) {
          pipeline.runSystemUpdate(entry.systemTarget, fMainWindow, dt);
        }
        break;
      case TimerEntry.TargetKind.callback:
        if (entry.callback !is null && entry.callback(entry.id, dt)) {
          needRender = true;
        }
        break;
      }
    });
  }

  void runPhase3Render(in ControllerDirtyList dirtyViews, bool needRender) {
    if (!dirtyViews.empty) {
      Controller[16] stackBuf;
      Controller[] activeList = snapshotControllers(stackBuf);
      foreach (c; activeList) {
        if (c !is null && dirtyViews.contains(c)) {
          if (c.updateView()) {
            needRender = true;
          }
        }
      }
    }

    const bool treeNeedsRender = fMainWindow !is null &&
      fMainWindow.rootWidget !is null &&
      (fMainWindow.rootWidget.isTreeDirty() ||
        fMainWindow.rootWidget.isTreeLayoutDirty());
    if (needRender || treeNeedsRender) {
      pipeline.updateAndRender(fMainWindow);
    }
  }

  bool runEventLoopStep() {
    waitForEventsIfIdle();
    drainSdlEvents();

    bool needModelUpdate = false;
    bool needRender = fPendingRedraw;
    fPendingRedraw = false;
    ControllerDirtyList dirtyViews;

    if (!drainMessageBus(dirtyViews, needModelUpdate, needRender)) {
      return false;
    }
    runPhase2Updates(dirtyViews, needModelUpdate, needRender);
    runPhase3Render(dirtyViews, needRender);
    return true;
  }

  Controller getActiveControllerOrNull() {
    return controllers.getActiveOrNull();
  }

  Nullable!AppEvent getAppEvent() {
    return messageBus.get();
  }

  bool hasPendingAppEvents() {
    return messageBus.hasPending();
  }

  void redraw() {
    if (fMainWindow !is null && fMainWindow.rootWidget !is null) {
      fMainWindow.rootWidget.update(WidgetUpdateScope.all);
      fPendingRedraw = true;
    }
  }

  /**
   * Sets the additional scaling factor above displayScaling (e.g. to support
   * zooming in/out UI for user preferences). Defaults to 1.0.
   */
  void setUnitsScaling(float scaling) {
    if (fMainWindow !is null) {
      fMainWindow.setUnitsScaling(scaling);
    }
    redraw();
  }

  /**
   * Gets the additional scaling factor above displayScaling (defaults to 1.0).
   */
  float getUnitsScaling() const {
    if (fMainWindow !is null) {
      return fMainWindow.getUnitsScaling();
    }
    return 1.0f;
  }

  float getDisplayScaling() const {
    if (fMainWindow !is null) {
      return fMainWindow.getDisplayScaling();
    }
    return 1.0f;
  }

  void setDisplayScaling(float scaling) {
    if (fMainWindow !is null) {
      fMainWindow.setDisplayScaling(scaling);
    }
    redraw();
  }

  float getDefaultScaling() const {
    if (fMainWindow !is null) {
      return fMainWindow.getDefaultScaling();
    }
    return 1.0f;
  }

  ControllerStack controllers;
  MessageBus messageBus;
  TimerService timerService;
  Window fMainWindow;
  WidgetSystemPipeline pipeline;
  ObjectRegistry!WidgetViewController fWidgetViewControllers;
  ObjectRegistry!WidgetView fWidgetViews;
  uint fNextWidgetId = 1;
  bool fPendingRedraw = false;
} // -UiSystem

////// TESTS /////

// Verifies cross-thread event dispatch to the active controller.
unittest {
  import core.thread;
  import core.time;

  class ThreadTestController : DefaultController {
    this() {
      super(null);
    }
    const(AppEvent)[] received;

    override HandleResult handleEvent(in AppEvent ev) {
      if (ev.kind == AppEvent.Kind.user) {
        received ~= ev;
      }
      if (ev.kind == AppEvent.Kind.user && ev.user.eventId == 999) {
        return HandleResult(HandleResult.Result.quit);
      }
      return HandleResult(HandleResult.Result.nothing);
    }
  }

  auto window = new Window(100, 100, "aaa");
  auto ui = new UiSystemImpl(window);
  auto ctrl = new ThreadTestController;
  ui.pushController(ctrl);

  auto worker = new Thread({
    Thread.sleep(msecs(20));
    ui.sendAppEvent(AppEvent.userEvent(AppEvent.UserData(101)));
    ui.sendAppEvent(AppEvent.userEvent(AppEvent.UserData(102)));
    ui.sendAppEvent(AppEvent.userEvent(AppEvent.UserData(999)));
  });
  worker.start();

  ui.mainEventLoop();
  worker.join();

  assert(ctrl.received.length == 3);
  assert(ctrl.received[0].kind == AppEvent.Kind.user);
  assert(ctrl.received[0].user.eventId == 101);
  assert(ctrl.received[1].user.eventId == 102);
  assert(ctrl.received[2].user.eventId == 999);
}

// Verifies timer-driven periodic tick and view updates in the main event loop.
unittest {
  class TickController : DefaultController {
    UiSystemImpl ui;
    TimerId timerId = 0;
    int tickCalls = 0;
    int viewTicks = 0;

    this(UiSystemImpl ui) {
      super(ui);
      this.ui = ui;
    }

    override void onPush() {
      timerId = startTickTimer(10, TimerMode.repeat);
    }

    override HandleResult handleEvent(in AppEvent ev) {
      if (ev.kind == AppEvent.Kind.appQuit) {
        return HandleResult(HandleResult.Result.quit);
      }
      return HandleResult(HandleResult.Result.nothing);
    }

    override bool tick(float dt) {
      tickCalls++;
      return true;
    }

    override bool updateView() {
      viewTicks++;
      if (viewTicks >= 2) {
        stopTickTimer(timerId);
        ui.sendAppEvent(AppEvent(AppEvent.Kind.appQuit));
      }
      return true;
    }
  }

  auto window = new Window(100, 100, "aaa");
  auto uiTick = new UiSystemImpl(window);
  auto tickCtrl = new TickController(uiTick);
  uiTick.pushController(tickCtrl);

  uiTick.mainEventLoop();
  assert(tickCtrl.tickCalls >= 2);
  assert(tickCtrl.viewTicks >= 2);
}

// Verifies window resize event handling and renderer viewport updates.
unittest {
  class ResizeTestController : DefaultController {
    this(UiSystemImpl ui, Window window) {
      super(ui);
      this.window = window;
    }
    Window window;
    const(AppEvent)[] received;
    int updateCount = 0;

    int viewportWidth = 0;
    int viewportHeight = 0;

    override HandleResult handleEvent(AppEvent ev) {
      if (ev.kind == AppEvent.Kind.user && ev.user.eventId == 1) {
        return HandleResult(HandleResult.Result.updateView);
      }
      if (ev.kind == AppEvent.Kind.windowResized &&
          ev.window.width == 640 && ev.window.height == 480) {
        received ~= ev;
        if (window.renderer !is null) {
          viewportWidth = window.renderer.getViewportWidth();
          viewportHeight = window.renderer.getViewportHeight();
        }
        return HandleResult(HandleResult.Result.updateView);
      }
      if (ev.kind == AppEvent.Kind.user && ev.user.eventId == 999) {
        received ~= ev;
        return HandleResult(HandleResult.Result.quit);
      }
      return super.handleEvent(ev);
    }

    override bool updateView() {
      updateCount++;
      if (updateCount == 1) {
        sendAppEvent(
          AppEvent.windowEvent(
            AppEvent.Kind.windowResized,
            AppEvent.WindowData(0, 640, 480)
          )
        );
      } else if (received.length == 1) {
        sendAppEvent(AppEvent.userEvent(AppEvent.UserData(999)));
      }
      return true;
    }
  }

  auto window = new Window(320, 240, "test_resize_window");
  auto ui = new UiSystemImpl(window);
  auto ctrl = new ResizeTestController(ui, window);
  ui.pushController(ctrl);

  ui.sendAppEvent(AppEvent.userEvent(AppEvent.UserData(1)));

  ui.mainEventLoop();

  assert(ctrl.received.length == 2);
  assert(ctrl.received[0].kind == AppEvent.Kind.windowResized);
  assert(ctrl.received[0].window.width == 640);
  assert(ctrl.received[0].window.height == 480);
  assert(ctrl.received[1].kind == AppEvent.Kind.user);
  assert(window.width == 640);
  assert(window.height == 480);
  assert(ctrl.viewportWidth == 640);
  assert(ctrl.viewportHeight == 480);
  assert(ctrl.updateCount >= 1);
}

// Verifies window expose event handling and controller notification.
unittest {
  class ExposeTestController : DefaultController {
    this(UiSystemImpl ui) {
      super(ui);
    }
    const(AppEvent)[] received;
    int updateCount = 0;

    override HandleResult handleEvent(AppEvent ev) {
      if (ev.kind == AppEvent.Kind.windowExposed) {
        if (!sawExposed) {
          received ~= ev;
          sawExposed = true;
        }
      }
      if (ev.kind == AppEvent.Kind.user && ev.user.eventId == 999) {
        received ~= ev;
        return HandleResult(HandleResult.Result.quit);
      }
      return super.handleEvent(ev);
    }

    bool sawExposed = false;

    override bool updateView() {
      updateCount++;
      if (updateCount == 1) {
        sendAppEvent(AppEvent.userEvent(AppEvent.UserData(999)));
      }
      return true;
    }
  }

  auto window = new Window(320, 240, "test_expose_window");
  auto ui = new UiSystemImpl(window);
  auto ctrl = new ExposeTestController(ui);
  ui.pushController(ctrl);

  ui.sendAppEvent(AppEvent.windowEvent(
    AppEvent.Kind.windowExposed,
    AppEvent.WindowData(0, 320, 240)
  ));

  ui.mainEventLoop();

  assert(ctrl.received.length == 2);
  assert(ctrl.received[0].kind == AppEvent.Kind.windowExposed);
  assert(ctrl.received[1].kind == AppEvent.Kind.user);
  assert(ctrl.updateCount >= 1);
}

// Verifies UiSystemImpl scaling and redraw APIs.
unittest {
  auto window = new Window(320, 240, "test_ui_scaling");
  auto ui = new UiSystemImpl(window);

  assert(ui.getDefaultScaling() == 1.0f);
  assert(ui.getDisplayScaling() == 1.0f);
  assert(ui.getUnitsScaling() == 1.0f);

  ui.setUnitsScaling(2.0f);
  assert(ui.getUnitsScaling() == 2.0f);
}

// Verifies unconsumed event propagation from newest to oldest controller.
unittest {
  class PropagationTestController : DefaultController {
    string name;
    string[]* log;
    bool shouldConsume;
    this(string name, string[]* log, bool shouldConsume = false) {
      super(null);
      this.name = name;
      this.log = log;
      this.shouldConsume = shouldConsume;
    }

    override HandleResult handleEvent(AppEvent ev) {
      if (ev.kind == AppEvent.Kind.user && ev.user.eventId == 42) {
        *log ~= name ~ ":handleEvent";
        HandleResult res;
        res.result = HandleResult.Result.nothing;
        res.consume = shouldConsume;
        return res;
      }
      if (ev.kind == AppEvent.Kind.user && ev.user.eventId == 999) {
        return HandleResult(HandleResult.Result.quit);
      }
      return super.handleEvent(ev);
    }
  }

  string[] log;
  auto window = new Window(100, 100, "test_prop");
  auto ui = new UiSystemImpl(window);

  auto cOldest = new PropagationTestController("oldest", &log, false);
  auto cNewest = new PropagationTestController("newest", &log, false);

  ui.pushController(cOldest);
  ui.pushController(cNewest);

  ui.sendAppEvent(AppEvent.userEvent(AppEvent.UserData(42)));
  ui.sendAppEvent(AppEvent.userEvent(AppEvent.UserData(999)));

  ui.mainEventLoop();

  assert(log == ["newest:handleEvent", "oldest:handleEvent"]);
}

// Verifies event consumption stopping propagation down the controller stack.
unittest {
  class ConsumeTestController : DefaultController {
    string name;
    string[]* log;
    bool shouldConsume;
    this(string name, string[]* log, bool shouldConsume) {
      super(null);
      this.name = name;
      this.log = log;
      this.shouldConsume = shouldConsume;
    }

    override HandleResult handleEvent(AppEvent ev) {
      if (ev.kind == AppEvent.Kind.user && ev.user.eventId == 42) {
        *log ~= name ~ ":handleEvent";
        HandleResult res;
        res.result = HandleResult.Result.nothing;
        res.consume = shouldConsume;
        return res;
      }
      if (ev.kind == AppEvent.Kind.user && ev.user.eventId == 999) {
        return HandleResult(HandleResult.Result.quit);
      }
      return super.handleEvent(ev);
    }
  }

  string[] log;
  auto window = new Window(100, 100, "test_consume");
  auto ui = new UiSystemImpl(window);

  auto cOldest = new ConsumeTestController("oldest", &log, false);
  auto cNewest = new ConsumeTestController("newest", &log, true);

  ui.pushController(cOldest);
  ui.pushController(cNewest);

  ui.sendAppEvent(AppEvent.userEvent(AppEvent.UserData(42)));
  ui.sendAppEvent(AppEvent.userEvent(AppEvent.UserData(999)));

  ui.mainEventLoop();

  assert(log == ["newest:handleEvent"]);
}

// Verifies updateView ordering and batched view updates across stack.
unittest {
  class ViewOrderTestController : DefaultController {
    string name;
    string[]* log;
    bool quitAfterUpdate;
    this(string name, string[]* log, UiSystem ui, bool quitAfterUpdate) {
      super(ui);
      this.name = name;
      this.log = log;
      this.quitAfterUpdate = quitAfterUpdate;
    }

    override HandleResult handleEvent(AppEvent ev) {
      if (ev.kind == AppEvent.Kind.user && ev.user.eventId == 42) {
        HandleResult res;
        res.result = HandleResult.Result.updateView;
        res.consume = false;
        return res;
      }
      if (ev.kind == AppEvent.Kind.user && ev.user.eventId == 999) {
        return HandleResult(HandleResult.Result.quit);
      }
      return super.handleEvent(ev);
    }

    override bool updateView() {
      *log ~= name ~ ":updateView";
      if (quitAfterUpdate) {
        sendAppEvent(AppEvent.userEvent(AppEvent.UserData(999)));
      }
      return true;
    }
  }

  string[] log;
  auto window = new Window(100, 100, "test_view_order");
  auto ui = new UiSystemImpl(window);

  auto cOldest = new ViewOrderTestController("oldest", &log, ui, false);
  auto cNewest = new ViewOrderTestController("newest", &log, ui, true);

  ui.pushController(cOldest);
  ui.pushController(cNewest);

  ui.sendAppEvent(AppEvent.userEvent(AppEvent.UserData(42)));

  ui.mainEventLoop();

  // "oldest:updateView" followed by "newest:updateView" for event 42.
  assert(log == [
    "oldest:updateView",
    "newest:updateView"
  ]);
}

// Verifies multiple Result.update returns trigger a single Phase 2 update().
unittest {
  class MultiUpdateTestController : DefaultController {
    UiSystemImpl ui;
    int* updateCount;
    this(UiSystemImpl ui, int* count) {
      super(ui);
      this.ui = ui;
      this.updateCount = count;
    }

    override bool update() {
      (*updateCount)++;
      if (*updateCount >= 2) {
        ui.sendAppEvent(AppEvent(AppEvent.Kind.appQuit));
      }
      return false;
    }

    override HandleResult handleEvent(AppEvent ev) {
      if (ev.kind == AppEvent.Kind.user && ev.user.eventId == 42) {
        HandleResult res;
        res.result = HandleResult.Result.update;
        res.consume = false;
        return res;
      }
      if (ev.kind == AppEvent.Kind.appQuit) {
        return HandleResult(HandleResult.Result.quit);
      }
      return super.handleEvent(ev);
    }
  }

  int updateCount = 0;
  auto window = new Window(100, 100, "test_multi_update");
  auto ui = new UiSystemImpl(window);

  auto cOldest = new MultiUpdateTestController(ui, &updateCount);
  auto cNewest = new MultiUpdateTestController(ui, &updateCount);

  ui.pushController(cOldest);
  ui.pushController(cNewest);

  ui.sendAppEvent(AppEvent.userEvent(AppEvent.UserData(42)));

  ui.mainEventLoop();

  // Both controllers handled event 42 and returned Result.update.
  // Phase 2 invoked update() once on each controller (1 increment each).
  assert(updateCount == 2);
}

// Verifies Result.quit immediately terminates event loop without propagation.
unittest {
  class QuitTestController : DefaultController {
    string name;
    string[]* log;
    bool shouldQuit;
    this(string name, string[]* log, bool shouldQuit) {
      super(null);
      this.name = name;
      this.log = log;
      this.shouldQuit = shouldQuit;
    }

    override HandleResult handleEvent(AppEvent ev) {
      *log ~= name ~ ":handleEvent";
      if (shouldQuit) {
        return HandleResult(HandleResult.Result.quit);
      }
      return HandleResult(HandleResult.Result.nothing);
    }
  }

  string[] log;
  auto window = new Window(100, 100, "test_quit");
  auto ui = new UiSystemImpl(window);

  auto cOldest = new QuitTestController("oldest", &log, false);
  auto cNewest = new QuitTestController("newest", &log, true);

  ui.pushController(cOldest);
  ui.pushController(cNewest);

  ui.sendAppEvent(AppEvent.userEvent(AppEvent.UserData(1)));
  ui.mainEventLoop();

  assert(log == ["newest:handleEvent"]);
}

// Verifies timer auto-cleanup, idle sleep (-1), and non-merged curved
// mouseMotion flood without timer starvation or multi-render stalls.
unittest {
  import yguilib.render.render_types : PointF, RectF;
  import yguilib.timers : TimerId, TimerMode;
  import yguilib.widget.system : SystemPhase, WidgetSystemContext;

  final class FloodController : DefaultController {
    PointF[] motionPoints;
    int tickCount = 0;
    int viewCount = 0;

    this(UiSystem ui) {
      super(ui);
    }

    override HandleResult handleEvent(AppEvent ev) {
      if (ev.kind == AppEvent.Kind.mouseMotion) {
        motionPoints ~= PointF(ev.mouse.x, ev.mouse.y);
        return HandleResult(HandleResult.Result.nothing, true);
      }
      return super.handleEvent(ev);
    }

    override bool tick(float dt) {
      tickCount++;
      return true;
    }

    override bool updateView() {
      viewCount++;
      return true;
    }
  }

  final class RenderCountSystem : WidgetSystem {
    int updateCount = 0;
    int renderCount = 0;

    override @property SystemPhase phases() const nothrow @safe {
      return SystemPhase.update | SystemPhase.render;
    }

    override void update(ref WidgetSystemContext ctx, float dt) {
      updateCount++;
      if (ctx.root !is null) {
        ctx.root.update(WidgetUpdateScope.visuals);
      }
    }

    override void render(ref WidgetSystemContext ctx) {
      renderCount++;
    }
  }

  yguilib_sdl3_init();
  scope (exit) yguilib_sdl3_quit();

  auto win = new Window(200, 200, "test_flood_timers");
  win.create();
  scope (exit) win.destroy();

  auto ui = new UiSystemImpl(win);
  long fakeNowNs = 1_000_000_000L;
  ui.setTimerClock(() => fakeNowNs);

  auto root = new Widget(ui.nextWidgetId());
  root.rect = RectF(0, 0, 200, 200);
  win.rootWidget = root;
  ui.systemPipeline.updateAndRender(win);

  // Flush any OS window-creation events (e.g. initial Expose) before testing.
  yguilib_sdl3_Event discardEv;
  while (yguilib_sdl3_poll_event(&discardEv) > 0) {}

  auto sys = new RenderCountSystem();
  ui.registerWidgetSystem(sys);

  auto ctrl = new FloodController(ui);
  ui.pushController(ctrl);

  // Idle when no timers active
  assert(ui.nextWaitTimeoutMs() == -1);

  const TimerId cTimer = ui.startTimer(ctrl, 16, TimerMode.repeat);
  const TimerId sTimer = ui.startTimer(sys, 16, TimerMode.repeat);
  assert(ui.isTimerActive(cTimer));
  assert(ui.isTimerActive(sTimer));
  assert(ui.nextWaitTimeoutMs() == 16);

  // Queue 200 curved mouseMotion waypoints across a 16 ms window
  foreach (i; 0 .. 200) {
    const float fx = cast(float) i;
    const float fy = cast(float) ((i * 7) % 100);
    ui.sendAppEvent(AppEvent.mouseEvent(
      AppEvent.Kind.mouseMotion,
      AppEvent.MouseData(1, fx, fy)
    ));
  }

  // Advance clock by 16 ms so timer is already due at start of flood:
  // Step 1 processes 1 event, yields Phase 1 to fire due timers without
  // starvation, and renders once.
  fakeNowNs += 16_000_000L;
  assert(ui.runEventLoopStep());
  assert(ctrl.motionPoints.length == 1);
  assert(ctrl.tickCount == 1);
  assert(ctrl.viewCount == 1);
  assert(sys.updateCount == 1);
  assert(sys.renderCount == 1);

  // Step 2 drains all remaining 199 queued mouseMotion events immediately
  // without waiting for next deadline (16 ms still remaining).
  assert(ui.runEventLoopStep());
  assert(ctrl.motionPoints.length == 200);
  foreach (i; 0 .. 200) {
    assert(ctrl.motionPoints[i].x == cast(float) i);
    assert(ctrl.motionPoints[i].y == cast(float) ((i * 7) % 100));
  }
  assert(ctrl.tickCount == 1);
  assert(sys.renderCount == 1);

  // Queue another 200 curved waypoints before deadline -> all 200 drain in one
  // step, and advancing clock fires timers once with a single render pass.
  ctrl.motionPoints = null;
  foreach (i; 0 .. 200) {
    const float fx = cast(float) (200 - i);
    const float fy = cast(float) ((i * 5) % 80);
    ui.sendAppEvent(AppEvent.mouseEvent(
      AppEvent.Kind.mouseMotion,
      AppEvent.MouseData(1, fx, fy)
    ));
  }
  fakeNowNs += 8_000_000L;
  assert(ui.runEventLoopStep());
  assert(ctrl.motionPoints.length == 200);
  assert(ctrl.tickCount == 1);
  assert(sys.renderCount == 1);

  fakeNowNs += 8_000_000L;
  assert(ui.runEventLoopStep());
  assert(ctrl.tickCount == 2);
  assert(ctrl.viewCount == 2);
  assert(sys.updateCount == 2);
  assert(sys.renderCount == 2);

  // Pop controller & unregister system -> timers auto-cancelled, idle = -1
  ui.popController();
  assert(!ui.isTimerActive(cTimer));
  ui.unregisterWidgetSystem(sys);
  assert(!ui.isTimerActive(sTimer));
  assert(ui.nextWaitTimeoutMs() == -1);
}

// Verifies dirty flag optimization gating in updateAndRender.
unittest {
  import yguilib.render.render_types : ColorF, RectF;
  import yguilib.widget.drawing_components : Background;

  yguilib_sdl3_init();
  scope (exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_dirty_gating");
  win.create();
  scope (exit) win.destroy();

  auto ui = new UiSystemImpl(win);
  auto root = new Widget(ui.nextWidgetId());
  root.rect = RectF(0, 0, 320, 240);
  root.components.background = new Background(ColorF(0.1f, 0.1f, 0.1f, 1.0f));
  win.rootWidget = root;

  assert(root.isTreeLayoutDirty());
  assert(root.isTreeDirty());

  // First layout and render pass: performs layout and rendering
  ui.systemPipeline.updateAndRender(win);
  assert(!root.isTreeLayoutDirty());
  assert(!root.isTreeDirty());

  // With flags clean, layout and rendering must be skipped
  ui.systemPipeline.updateAndRender(win);
  assert(!root.isTreeLayoutDirty());
  assert(!root.isTreeDirty());

  // Mark paint-only dirty
  root.update(WidgetUpdateScope.visuals);
  assert(!root.isTreeLayoutDirty());
  assert(root.isTreeDirty());

  // updateAndRender must execute render and clear dirty without layoutDirty
  ui.systemPipeline.updateAndRender(win);
  assert(!root.isTreeLayoutDirty());
  assert(!root.isTreeDirty());
}

// Verifies end-to-end custom WidgetSystem registration, lookup, and execution.
unittest {
  import yguilib.render.render_types : ColorF, RectF;
  import yguilib.widget.component : WidgetComponent;
  import yguilib.widget.system : SystemPhase, WidgetSystemContext;

  final class CounterComponent : WidgetComponent {
    int count;
    this(int count) {
      this.count = count;
    }
  }

  final class CounterSystem : WidgetSystem {
    this() nothrow @safe {
      super(10);
    }

    override @property SystemPhase phases() const nothrow @safe {
      return SystemPhase.preLayout;
    }

    override void preLayout(ref WidgetSystemContext ctx) {
      if (ctx.root is null) {
        return;
      }
      traverse(ctx.root);
    }

    int totalCount = 0;

  private:
    void traverse(Widget w) {
      if (auto c = w.components.get!CounterComponent()) {
        totalCount += c.count;
      }
      foreach (child; w.children) {
        traverse(child);
      }
    }
  }

  yguilib_sdl3_init();
  scope (exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_custom_system");
  win.create();
  scope (exit) win.destroy();

  auto ui = new UiSystemImpl(win);
  auto customSys = new CounterSystem();
  ui.registerWidgetSystem(customSys);

  // Verify typed lookup via UiSystem interface
  UiSystem uiSys = ui;
  auto found = uiSys.findWidgetSystem!CounterSystem();
  assert(found is customSys);

  auto root = new Widget(ui.nextWidgetId());
  root.rect = RectF(0, 0, 320, 240);
  root.components.set(new CounterComponent(5));
  auto child = new Widget(ui.nextWidgetId());
  child.rect = RectF(10, 10, 100, 50);
  child.components.set(new CounterComponent(10));
  root.addChild(child);
  win.rootWidget = root;

  assert(customSys.totalCount == 0);
  ui.systemPipeline.updateAndRender(win);
  assert(customSys.totalCount == 15);

  // Unregister system
  ui.unregisterWidgetSystem(customSys);
  assert(uiSys.findWidgetSystem!CounterSystem() is null);

  ui.systemPipeline.updateAndRender(win);
  assert(customSys.totalCount == 15); // not incremented further
}

// Verifies widgetViewControllers and widgetViews registries on UiSystem.
unittest {
  import yguilib.widget.widget_view : WidgetViewBase;

  class DummyController : WidgetViewController {
    string name;
    this(string name) {
      this.name = name;
    }
    string getControllerName() {
      return name;
    }
    void registerWidgetView(WidgetView v) {}
    void unregisterWidgetView(WidgetView v) {}
    void unregisterViewWidget(Widget viewWidget) {}
  }

  class DummyView : WidgetViewBase {
    override void translateEventForViewWidget(
      ref AppEvent sourceEvent,
      Widget viewWidget
    ) scope return {
    }
  }

  UiSystem ui = new UiSystemImpl(null);
  assert(ui.widgetViewControllers !is null);
  assert(ui.widgetViews !is null);

  auto ctrl = new DummyController("mainCtrl");
  assert(ui.widgetViewControllers.register(ctrl.getControllerName(), ctrl));
  assert(ui.widgetViewControllers.getByName("mainCtrl") is ctrl);
  assert(ui.widgetViewControllers.unregister("mainCtrl", ctrl));
  assert(ui.widgetViewControllers.getByName("mainCtrl") is null);

  auto view = new DummyView();
  assert(ui.widgetViews.register(view.getWidgetViewName(), view));
  assert(ui.widgetViews.getByName("DummyView") is view);
  assert(ui.widgetViews.unregister("DummyView", view));
  assert(ui.widgetViews.getByName("DummyView") is null);
}

// Verifies sequential nextWidgetId generation and independent counters.
unittest {
  auto ui1 = new UiSystemImpl(null);
  assert(ui1.nextWidgetId() == 1);
  assert(ui1.nextWidgetId() == 2);
  assert(ui1.nextWidgetId() == 3);

  auto ui2 = new UiSystemImpl(null);
  assert(ui2.nextWidgetId() == 1);
  assert(ui2.nextWidgetId() == 2);
  assert(ui1.nextWidgetId() == 4);
}

// Verifies releaseWidget unregistering from views, controllers, window, and
// pipeline.
unittest {
  import yguilib.render.render_types : RectF;
  import yguilib.widget.widget_view : WidgetViewBase;

  class TestView : WidgetViewBase {
    override void translateEventForViewWidget(
      ref AppEvent sourceEvent,
      Widget viewWidget
    ) scope return {
    }
  }

  auto win = new Window(100, 100, "test_release_widget");
  auto ui = new UiSystemImpl(win);

  auto view = new TestView();
  ui.widgetViews.register("TestView", view);

  auto root = new Widget(ui.nextWidgetId());
  auto child = new Widget(ui.nextWidgetId());
  root.addChild(child);
  win.rootWidget = root;

  view.registerViewWidget(root);
  view.registerViewWidget(child);
  assert(view.isWidgetRegistered(root));
  assert(view.isWidgetRegistered(child));
  assert(win.rootWidget is root);

  // Releasing root should release child first, then root, and clear
  // window.rootWidget
  ui.releaseWidget(root);

  assert(root.released);
  assert(child.released);
  assert(win.rootWidget is null);
  assert(!view.isWidgetRegistered(root));
  assert(!view.isWidgetRegistered(child));
}

// Verifies dumpInfo returns expected structure with controllers, views,
// view controllers, and window with root widget info.
unittest {
  import std.json : parseJSON;
  import yguilib.controller : DefaultController;
  import yguilib.widget.widget_view : WidgetViewBase, WidgetViewControllerBase;

  class DumpTestView : WidgetViewBase {
    override void translateEventForViewWidget(
      ref AppEvent sourceEvent,
      Widget viewWidget
    ) scope return {
    }
  }

  class DumpTestViewController : WidgetViewControllerBase {
    this(UiSystem ui) {
      super(ui);
    }
    override string getControllerName() {
      return "DumpTestViewController";
    }
  }

  auto win = new Window(800, 600, "dump_test_window");
  auto ui = new UiSystemImpl(win);

  auto root = new Widget(ui.nextWidgetId());
  root.name = "testRoot";
  win.rootWidget = root;

  auto ctrl = new DefaultController(ui);
  ui.pushController(ctrl);

  auto view = new DumpTestView();
  ui.widgetViews.register("testView", view);

  auto viewCtrl = new DumpTestViewController(ui);
  ui.widgetViewControllers.register("testViewCtrl", viewCtrl);

  string jsonStr = ui.dumpInfo();
  auto doc = parseJSON(jsonStr);

  assert(doc["type"].str == "UiSystem");
  auto fields = doc["fields"];

  // Controllers: check DefaultController is in the stack
  assert(fields["controllers"].array.length >= 1);
  bool foundCtrl = false;
  foreach (c; fields["controllers"].array) {
    if (c["type"].str == "DefaultController") {
      foundCtrl = true;
      assert(c["isModal"].boolean == false);
    }
  }
  assert(foundCtrl);

  // Widget views
  assert("testView" in fields["widgetViews"].object);
  assert(fields["widgetViews"]["testView"].str == "DumpTestView");

  // Widget view controllers
  assert("testViewCtrl" in fields["widgetViewControllers"].object);
  assert(fields["widgetViewControllers"]["testViewCtrl"].str
    == "DumpTestViewController");

  // Window & rootWidget
  auto winJson = fields["window"];
  assert(winJson["title"].str == "dump_test_window");
  assert(winJson["width"].integer == 800);
  assert(winJson["height"].integer == 600);
  assert(winJson["rootWidget"]["name"].str == "testRoot");
  assert(winJson["rootWidget"]["uId"].integer == root.uId);
  // Ensure full widget tree fields are not included
  assert("children" !in winJson["rootWidget"].object);
  assert("components" !in winJson["rootWidget"].object);
}

// Verifies runtime event stats toggling through UiSystem.
unittest {
  UiSystem ui = new UiSystemImpl(null);
  debug {
    assert(ui.eventStatsEnabled);
  } else {
    assert(!ui.eventStatsEnabled);
  }
  ui.setEventStatsEnabled(false);
  assert(!ui.eventStatsEnabled);
  ui.setEventStatsEnabled(true);
  assert(ui.eventStatsEnabled);
}
