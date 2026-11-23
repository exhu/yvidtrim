module yguilib.internal.uisystem_impl;

import glad2.gles2;
import std.typecons : Nullable;
import std.logger;
import yguilib.allochelpers : SmallBuffer;
import yguilib.clibs.sdl3;
import yguilib.controls.button : ButtonSystem;
import yguilib.timercontrol : TimerId;
import yguilib.timers : TimerIntervalMs, TimerMode;
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
import yguilib.widget.internal.virtlist_system : VirtListSystem;
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
    pipeline.registerSystem(new VirtListSystem(this));
    pipeline.registerSystem(new ScrollSystem(this));
    pipeline.registerSystem(new WidgetPainterSystem());
    debug {
      pipeline.registerSystem(new DebugDrawSystem());
    }
    pipeline.registerSystem(new DataSystem());
    pipeline.registerSystem(new ButtonSystem());
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
    Object owner,
    uint intervalMs,
    TimerMode mode
  ) {
    return timerService.startTimer(owner, intervalMs, mode);
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

  override void requestScreenshot(string path) {
    if (fMainWindow is null) {
      warningf("requestScreenshot(%s): no main window", path);
      return;
    }
    fMainWindow.requestScreenshot(path);
    if (fMainWindow.rootWidget !is null) {
      // A dirty tree makes Phase 3 render (and capture) this iteration.
      fMainWindow.rootWidget.update(WidgetUpdateScope.visuals);
    }
  }

  override void registerWidgetSystem(WidgetSystem system) {
    assert(system !is null);
    pipeline.registerSystem(system);
  }

  override void unregisterWidgetSystem(WidgetSystem system) {
    assert(system !is null);
    timerService.stopTimersForOwner(system);
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
      timerService.stopTimersForOwner(cast(Object) active);
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
      while (getActiveControllerOrNull() !is null) {
        popController();
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
    JSONValue[] controllerList;
    foreach (ctrl; controllers) {
      JSONValue[string] ctrlJson;
      ctrlJson["type"] = JSONValue(shortTypeName(ctrl));
      ctrlJson["isModal"] = JSONValue(ctrl.isModal);
      controllerList ~= JSONValue(ctrlJson);
    }
    fields["controllers"] = JSONValue(controllerList);

    JSONValue[string] viewsJson;
    foreach (name, view; fWidgetViews) {
      viewsJson[name] = JSONValue(shortTypeName(view));
    }
    fields["widgetViews"] = JSONValue(viewsJson);

    JSONValue[string] viewControllersJson;
    foreach (name, ctrl; fWidgetViewControllers) {
      viewControllersJson[name] = JSONValue(shortTypeName(ctrl));
    }
    fields["widgetViewControllers"] = JSONValue(viewControllersJson);
    fields["window"] = dumpWindowInfoJson();

    root["fields"] = JSONValue(fields);
    return serializeToJson(JSONValue(root), true);
  }

private:
  auto dumpWindowInfoJson() {
    import std.json : JSONValue;
    if (fMainWindow is null) {
      return JSONValue(null);
    }
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
    return JSONValue(winJson);
  }
  alias ControllerDirtyList = SmallBuffer!(Controller, 16);

  struct EventBatchResult {
    bool keepRunning = true;
    bool needModelUpdate = false;
    bool needRender = false;
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
  void snapshotControllers(ref SmallBuffer!(Controller, 16) outBuf) {
    outBuf.assignSlice(controllers.getAll());
  }

  bool isMainWindowEvent(uint windowId) const {
    return (windowId == 0 || fMainWindow.id == 0 ||
      windowId == fMainWindow.id);
  }

  bool handleMainWindowEvent(in AppEvent event) {
    if (fMainWindow is null || !event.isWindowEvent()) {
      return false;
    }
    if (isMainWindowEvent(event.window.windowId)) {
      fMainWindow.handleWindowEvent(event);
      if (fMainWindow.rootWidget !is null && event.isWindowRedrawEvent()) {
        fMainWindow.rootWidget.update(WidgetUpdateScope.all);
        return true;
      }
    }
    return false;
  }

  /**
   * Dispatches a discrete event through the controller stack from newest
   * (active) to oldest, stopping early when consumed.
   * Returns EventBatchResult with keepRunning = false if quit was requested.
   */
  EventBatchResult dispatchDiscreteEvent(
    AppEvent event,
    ref ControllerDirtyList dirtyViews
  ) {
    EventBatchResult batch;
    batch.needRender = handleMainWindowEvent(event);

    SmallBuffer!(Controller, 16) activeBuf;
    snapshotControllers(activeBuf);

    foreach_reverse (c; activeBuf[]) {
      if (c is null) {
        continue;
      }

      Controller.HandleResult result = c.handleEvent(event);
      final switch (result.result) {
      case Controller.HandleResult.Result.quit:
        batch.keepRunning = false;
        return batch;
      case Controller.HandleResult.Result.nothing:
        break;
      case Controller.HandleResult.Result.update:
        batch.needModelUpdate = true;
        break;
      case Controller.HandleResult.Result.updateView:
        dirtyViews.addUnique(c);
        break;
      }

      if (result.consume) {
        break;
      }
    }

    return batch;
  }

  EventBatchResult drainMessageBus(ref ControllerDirtyList dirtyViews) {
    enum size_t maxEventsPerStep = 256;
    EventBatchResult batch;
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
        batch.needModelUpdate = true;
        continue;
      }
      const EventBatchResult step = dispatchDiscreteEvent(event, dirtyViews);
      batch.needModelUpdate |= step.needModelUpdate;
      batch.needRender |= step.needRender;
      if (!step.keepRunning) {
        batch.keepRunning = false;
        return batch;
      }
    }
    return batch;
  }

  void runPhase2Updates(
    ref ControllerDirtyList dirtyViews,
    bool needModelUpdate
  ) {
    if (needModelUpdate) {
      SmallBuffer!(Controller, 16) activeBuf;
      snapshotControllers(activeBuf);
      foreach_reverse (c; activeBuf[]) {
        if (c !is null && c.update()) {
          dirtyViews.addUnique(c);
        }
      }
      pipeline.runUpdatePhase(fMainWindow);
    }

    const long tickNowNs = timerService.nowNs();
    timerService.fireDueTimers(tickNowNs, (TimerEntry entry, float dt) {
      if (auto ctrl = cast(Controller) entry.owner) {
        if (ctrl.onTimer(entry.id, dt)) {
          dirtyViews.addUnique(ctrl);
        }
      } else if (auto sys = cast(WidgetSystem) entry.owner) {
        pipeline.runSystemTimer(sys, fMainWindow, entry.id, dt);
      }
    });
  }

  void runPhase3Render(
    ref const ControllerDirtyList dirtyViews,
    bool needRender
  ) {
    if (!dirtyViews.empty) {
      SmallBuffer!(Controller, 16) activeBuf;
      snapshotControllers(activeBuf);
      foreach (c; activeBuf[]) {
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

    const bool needRender = fPendingRedraw;
    fPendingRedraw = false;
    ControllerDirtyList dirtyViews;

    const EventBatchResult batch = drainMessageBus(dirtyViews);
    if (!batch.keepRunning) {
      return false;
    }
    runPhase2Updates(dirtyViews, batch.needModelUpdate);
    runPhase3Render(dirtyViews, needRender || batch.needRender);
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
    this(UiSystem ui) {
      assert(ui !is null);
      super(ui);
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
  auto ctrl = new ThreadTestController(ui);
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
      assert(ui !is null);
      super(ui);
      this.ui = ui;
    }

    override void onPush() {
      timerId = startTimer(10, TimerMode.repeat);
    }

    override HandleResult handleEvent(in AppEvent ev) {
      if (ev.kind == AppEvent.Kind.appQuit) {
        return HandleResult(HandleResult.Result.quit);
      }
      return HandleResult(HandleResult.Result.nothing);
    }

    override bool onTimer(TimerId id, float dt) {
      if (id == timerId) {
        tickCalls++;
        return true;
      }
      return false;
    }

    override bool updateView() {
      viewTicks++;
      if (viewTicks >= 2) {
        stopTimer(timerId);
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
      assert(ui !is null);
      assert(window !is null);
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
      assert(ui !is null);
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
    this(UiSystem ui, string name, string[]* log) {
      assert(ui !is null);
      assert(log !is null);
      super(ui);
      this.name = name;
      this.log = log;
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

  auto cOldest = new PropagationTestController(ui, "oldest", &log);
  auto cNewest = new PropagationTestController(ui, "newest", &log);

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
    this(UiSystem ui, string name, string[]* log) {
      assert(ui !is null);
      assert(log !is null);
      super(ui);
      this.name = name;
      this.log = log;
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

  auto cOldest = new ConsumeTestController(ui, "oldest", &log);
  auto cNewest = new ConsumeTestController(ui, "newest", &log);
  cNewest.shouldConsume = true;

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
    this(UiSystem ui, string name, string[]* log) {
      assert(ui !is null);
      assert(log !is null);
      super(ui);
      this.name = name;
      this.log = log;
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

  auto cOldest = new ViewOrderTestController(ui, "oldest", &log);
  auto cNewest = new ViewOrderTestController(ui, "newest", &log);
  cNewest.quitAfterUpdate = true;

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
      assert(ui !is null);
      assert(count !is null);
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
    this(UiSystem ui, string name, string[]* log) {
      assert(ui !is null);
      assert(log !is null);
      super(ui);
      this.name = name;
      this.log = log;
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

  auto cOldest = new QuitTestController(ui, "oldest", &log);
  auto cNewest = new QuitTestController(ui, "newest", &log);
  cNewest.shouldQuit = true;

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
  import yguilib.timercontrol : TimerId;
  import yguilib.timers : TimerMode;
  import yguilib.widget.system : SystemPhase, WidgetSystemContext;

  final class FloodController : DefaultController {
    PointF[] motionPoints;
    int timerCount = 0;
    int viewCount = 0;

    this(UiSystem ui) {
      assert(ui !is null);
      super(ui);
    }

    override HandleResult handleEvent(AppEvent ev) {
      if (ev.kind == AppEvent.Kind.mouseMotion) {
        motionPoints ~= PointF(ev.mouse.x, ev.mouse.y);
        return HandleResult(HandleResult.Result.nothing, true);
      }
      return super.handleEvent(ev);
    }

    override bool onTimer(TimerId id, float dt) {
      timerCount++;
      return true;
    }

    override bool updateView() {
      viewCount++;
      return true;
    }
  }

  final class RenderCountSystem : WidgetSystem {
    int phaseUpdateCount = 0;
    int timerCount = 0;
    int renderCount = 0;

    override @property SystemPhase phases() const nothrow @safe {
      return SystemPhase.update | SystemPhase.render;
    }

    override void update(ref WidgetSystemContext ctx) {
      phaseUpdateCount++;
    }

    override void onTimer(ref WidgetSystemContext ctx, TimerId id, float dt) {
      timerCount++;
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

  const TimerId cTimer = ui.startTimer(
    ctrl,
    TimerIntervalMs.fps60,
    TimerMode.repeat
  );
  const TimerId sTimer = ui.startTimer(
    sys,
    TimerIntervalMs.fps60,
    TimerMode.repeat
  );
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
  assert(ctrl.timerCount == 1);
  assert(ctrl.viewCount == 1);
  assert(sys.phaseUpdateCount == 0);
  assert(sys.timerCount == 1);
  assert(sys.renderCount == 1);

  // Step 2 drains all remaining 199 queued mouseMotion events immediately
  // without waiting for next deadline (16 ms still remaining).
  assert(ui.runEventLoopStep());
  assert(ctrl.motionPoints.length == 200);
  foreach (i; 0 .. 200) {
    assert(ctrl.motionPoints[i].x == cast(float) i);
    assert(ctrl.motionPoints[i].y == cast(float) ((i * 7) % 100));
  }
  assert(ctrl.timerCount == 1);
  assert(sys.renderCount == 1);

  // Phase 2a runs SystemPhase.update on update events without firing timers.
  ui.sendAppEvent(AppEvent.makeNoRepeat(AppEvent.Kind.update));
  assert(ui.runEventLoopStep());
  assert(sys.phaseUpdateCount == 1);
  assert(sys.timerCount == 1);

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
  assert(ctrl.timerCount == 1);
  assert(sys.renderCount == 1);

  fakeNowNs += 8_000_000L;
  assert(ui.runEventLoopStep());
  assert(ctrl.timerCount == 2);
  assert(ctrl.viewCount == 2);
  assert(sys.timerCount == 2);
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
  root.components.background = Background.rect(ColorF(0.1f, 0.1f, 0.1f, 1.0f));
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
      setPriority(10);
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
      assert(ui !is null);
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

// Verifies a Controller with two independent timers (10 ms and 25 ms)
// receives distinct TimerIds, runs updateView() at most once per step, and
// stops all timers on popController().
unittest {
  import yguilib.timercontrol : invalidTimerId;

  final class MultiTimerController : DefaultController {
    TimerId fastId = invalidTimerId;
    TimerId slowId = invalidTimerId;
    TimerId[] firedIds;
    int viewCount = 0;

    this(UiSystem ui) {
      assert(ui !is null);
      super(ui);
    }

    override void onPush() {
      fastId = startTimer(10, TimerMode.repeat);
      slowId = startTimer(25, TimerMode.repeat);
    }

    override bool onTimer(TimerId id, float dt) {
      firedIds ~= id;
      return true;
    }

    override bool updateView() {
      viewCount++;
      return false;
    }
  }

  yguilib_sdl3_init();
  scope (exit) yguilib_sdl3_quit();

  auto ui = new UiSystemImpl(null);
  long fakeNowNs = 1_000_000_000L;
  ui.setTimerClock(() => fakeNowNs);

  auto ctrl = new MultiTimerController(ui);
  ui.pushController(ctrl);

  assert(ctrl.fastId != invalidTimerId);
  assert(ctrl.slowId != invalidTimerId);
  assert(ctrl.fastId != ctrl.slowId);
  assert(ui.isTimerActive(ctrl.fastId));
  assert(ui.isTimerActive(ctrl.slowId));

  // t = 10 ms: only fastId fires
  fakeNowNs += 10_000_000L;
  assert(ui.runEventLoopStep());
  assert(ctrl.firedIds == [ctrl.fastId]);
  assert(ctrl.viewCount == 1);

  // t = 20 ms: only fastId fires
  fakeNowNs += 10_000_000L;
  assert(ui.runEventLoopStep());
  assert(ctrl.firedIds == [ctrl.fastId, ctrl.fastId]);
  assert(ctrl.viewCount == 2);

  // t = 25 ms: only slowId fires (fastId next due at 30 ms)
  fakeNowNs += 5_000_000L;
  assert(ui.runEventLoopStep());
  assert(ctrl.firedIds == [ctrl.fastId, ctrl.fastId, ctrl.slowId]);
  assert(ctrl.viewCount == 3);

  // t = 30 ms: fastId fires (next due at 40 ms)
  fakeNowNs += 5_000_000L;
  assert(ui.runEventLoopStep());
  assert(ctrl.firedIds.length == 4);
  assert(ctrl.firedIds[3] == ctrl.fastId);
  assert(ctrl.viewCount == 4);

  // t = 50 ms: both fastId (40 ms) and slowId (50 ms) due in same step;
  // updateView() must run at most once for this step.
  fakeNowNs += 20_000_000L;
  assert(ui.runEventLoopStep());
  assert(ctrl.firedIds.length == 6);
  assert(ctrl.firedIds[4] == ctrl.fastId);
  assert(ctrl.firedIds[5] == ctrl.slowId);
  assert(ctrl.viewCount == 5);

  // popController() cancels all timers owned by this controller
  ui.popController();
  assert(!ui.isTimerActive(ctrl.fastId));
  assert(!ui.isTimerActive(ctrl.slowId));
  assert(ui.nextWaitTimeoutMs() == -1);
}

// Verifies WidgetSystem multi-timer dispatch, Phase 2a update(ctx) when
// needModelUpdate is true (without active timers), and timer cleanup on
// unregisterWidgetSystem().
unittest {
  import yguilib.timercontrol : invalidTimerId;
  import yguilib.widget.system : SystemPhase, WidgetSystemContext;

  final class MultiTimerSystem : WidgetSystem {
    TimerId t1 = invalidTimerId;
    TimerId t2 = invalidTimerId;
    TimerId[] firedIds;
    int updateCalls = 0;

    override @property SystemPhase phases() const nothrow @safe {
      return SystemPhase.update;
    }

    override void update(ref WidgetSystemContext ctx) {
      updateCalls++;
    }

    override void onTimer(ref WidgetSystemContext ctx, TimerId id, float dt) {
      firedIds ~= id;
    }

    void startBothTimers() {
      t1 = startTimer(10, TimerMode.repeat);
      t2 = startTimer(25, TimerMode.repeat);
    }
  }

  yguilib_sdl3_init();
  scope (exit) yguilib_sdl3_quit();

  auto ui = new UiSystemImpl(null);
  long fakeNowNs = 1_000_000_000L;
  ui.setTimerClock(() => fakeNowNs);

  auto sys = new MultiTimerSystem();
  ui.registerWidgetSystem(sys);

  // No active timers: Phase 2a update(ctx) still runs when needModelUpdate
  assert(ui.nextWaitTimeoutMs() == -1);
  ui.sendAppEvent(AppEvent.makeNoRepeat(AppEvent.Kind.update));
  assert(ui.runEventLoopStep());
  assert(sys.updateCalls == 1);
  assert(sys.firedIds.length == 0);

  // Start two independent timers on the system
  sys.startBothTimers();
  assert(sys.t1 != invalidTimerId);
  assert(sys.t2 != invalidTimerId);
  assert(sys.t1 != sys.t2);
  assert(ui.isTimerActive(sys.t1));
  assert(ui.isTimerActive(sys.t2));

  // t = 10 ms: t1 fires, update(ctx) does not run (needModelUpdate is false)
  fakeNowNs += 10_000_000L;
  assert(ui.runEventLoopStep());
  assert(sys.firedIds == [sys.t1]);
  assert(sys.updateCalls == 1);

  // t = 25 ms: both t1 (20 ms) and t2 (25 ms) fire with distinct TimerIds
  fakeNowNs += 15_000_000L;
  assert(ui.runEventLoopStep());
  assert(sys.firedIds == [sys.t1, sys.t1, sys.t2]);
  assert(sys.updateCalls == 1);

  // unregisterWidgetSystem() cancels all timers owned by the system
  ui.unregisterWidgetSystem(sys);
  assert(!ui.isTimerActive(sys.t1));
  assert(!ui.isTimerActive(sys.t2));
  assert(ui.nextWaitTimeoutMs() == -1);
}

// Verifies mainEventLoop() pops all remaining controllers in LIFO order on
// exit and stops all of their active timers.
unittest {
  import yguilib.timercontrol : invalidTimerId;

  final class LifoPopTestController : DefaultController {
    string name;
    string[]* popLog;
    TimerId timerId = invalidTimerId;

    this(UiSystem ui, string name, string[]* popLog) {
      assert(ui !is null);
      assert(popLog !is null);
      super(ui);
      this.name = name;
      this.popLog = popLog;
    }

    override void onPush() {
      timerId = startTimer(10, TimerMode.repeat);
    }

    override void onPop() {
      *popLog ~= name ~ ":onPop";
    }

    override HandleResult handleEvent(AppEvent ev) {
      if (ev.kind == AppEvent.Kind.user && ev.user.eventId == 999) {
        return HandleResult(HandleResult.Result.quit);
      }
      return super.handleEvent(ev);
    }
  }

  string[] popLog;
  auto ui = new UiSystemImpl(null);
  auto c1 = new LifoPopTestController(ui, "c1", &popLog);
  auto c2 = new LifoPopTestController(ui, "c2", &popLog);

  ui.pushController(c1);
  ui.pushController(c2);

  assert(c1.timerId != invalidTimerId);
  assert(c2.timerId != invalidTimerId);
  assert(ui.isTimerActive(c1.timerId));
  assert(ui.isTimerActive(c2.timerId));

  ui.sendAppEvent(AppEvent.userEvent(AppEvent.UserData(999)));
  ui.mainEventLoop();

  assert(ui.getActiveControllerOrNull() is null);
  assert(popLog == ["c2:onPop", "c1:onPop"]);
  assert(!ui.isTimerActive(c1.timerId));
  assert(!ui.isTimerActive(c2.timerId));
}

// Verifies requestScreenshot saves the next rendered frame and clears the
// pending request.
unittest {
  import std.file : exists, remove, tempDir;
  import std.path : buildPath;
  import yguilib.render.image : Image;
  import yguilib.render.render_types : ColorF, RectF;
  import yguilib.widget.drawing_components : Background;

  yguilib_sdl3_init();
  scope (exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_request_screenshot");
  win.create();
  scope (exit) win.destroy();

  auto ui = new UiSystemImpl(win);
  auto root = new Widget(ui.nextWidgetId());
  root.rect = RectF(0, 0, 320, 240);
  root.components.background = Background.rect(ColorF(1, 0, 0, 1));
  win.rootWidget = root;

  // Render once so the tree is clean before the request.
  ui.systemPipeline.updateAndRender(win);
  assert(!root.isTreeDirty());

  const string path = buildPath(tempDir(), "yguilib_test_screenshot.png");
  if (exists(path)) {
    remove(path);
  }
  scope (exit) {
    if (exists(path)) {
      remove(path);
    }
  }

  ui.requestScreenshot(path);
  assert(win.hasPendingScreenshot());
  assert(root.isTreeDirty());

  ui.systemPipeline.updateAndRender(win);
  assert(!win.hasPendingScreenshot());
  assert(exists(path));

  Image img = Image.loadFromFile(path);
  assert(img !is null);
  assert(img.width() == win.renderer.getPixelWidth());
  assert(img.height() == win.renderer.getPixelHeight());
  assert(img.pixels[0 .. 4] == [255, 0, 0, 255]);
}
