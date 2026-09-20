module yguilib.uisystem;

import yguilib.widget;
import yguilib.events;
import yguilib.controller;
import yguilib.clibs.sdl3;
import glad2.gles2;
import yguilib.render;
import yguilib.window;
import yguilib.widget_painter;
import yguilib.keyboard;
import yguilib.priv.controller_stack;
import yguilib.priv.message_bus;
import yguilib.priv.sdl_events;

import std.typecons;

class UiSystem {
  this(Window w) {
    mainWindow = w;
    messageBus = MessageBus(this);
    painterSystem = new WidgetPainterSystem;
  }

  void sendAppEvent(AppEvent ev) {
    messageBus.send(ev);
  }

  inout(Window) getMainWindow() inout {
    return mainWindow;
  }

  void pushController(Controller c) {
    controllers.push(c);
  }

  void pushModalController(Controller c) {
    controllers.pushModal(c);
  }

  void popController() {
    controllers.pop();
  }

  void pushFocusRoot(Widget w) {
    // TODO
  }

  void popFocusRoot() {
    // TODO
  }

  void mainEventLoop() {
    yguilib_sdl3_init();
    scope(exit) yguilib_sdl3_quit();

    if (mainWindow !is null) {
      mainWindow.create();
    }
    scope(exit) {
      if (mainWindow !is null) {
        mainWindow.destroy();
      }
    }

    auto initialController = getActiveControllerOrNull();
    if (initialController !is null) {
      updateAndRender(initialController);
    }

    messageBus.ensureWake();

    int currentTimeoutMs = -1;

    while (auto activeController = getActiveControllerOrNull()) {
      if (!runEventLoopStep(activeController, currentTimeoutMs)) {
        break;
      }
    }
  }

package:
  static bool isOnScreen(in RectF rect, float vw, float vh) {
    return WidgetPainterSystem.isOnScreen(rect, vw, vh);
  }

private:
  void drawUi() {
    if (mainWindow !is null && mainWindow.view !is null &&
        mainWindow.renderer !is null) {
      painterSystem.drawTree(mainWindow.view, mainWindow.renderer);
    }
  }

  void renderFrame() {
    if (mainWindow !is null) {
      drawUi();
      mainWindow.swapBuffers();
    }
  }

  void updateAndRender(Controller controller) {
    if (controller !is null) {
      controller.updateView();
    }
    renderFrame();
  }

  bool isMainWindowEvent(uint windowId) const {
    return mainWindow !is null &&
      (windowId == 0 || mainWindow.id == 0 || windowId == mainWindow.id);
  }

  void handleWindowEvent(in AppEvent event) {
    if (mainWindow !is null && isMainWindowEvent(event.windowId)) {
      mainWindow.handleWindowEvent(event);
    }
  }

  int pollSdlEvent(int timeoutMs) {
    yguilib_sdl3_Event sdlEv;
    int res = yguilib_sdl3_wait_event(&sdlEv, timeoutMs);
    if (res > 0) {
      Nullable!AppEvent appEv = appEventFromSdlEvent(sdlEv);
      if (!appEv.isNull) {
        sendAppEvent(appEv.get());
      }
    }
    return res;
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

  /**
   * Applies timeout resolution rules:
   * - If visited controllers specified a timeout, use minimum non-negative.
   * - If all controllers in stack were visited without timeout, reset to -1.
   * - If consumed early without timeout, preserve pending timeout for
   *   unvisited controllers.
   */
  static void applyTimeout(
    ref int currentTimeoutMs,
    bool hasTimeout,
    int nextTimeoutMs,
    bool allControllersVisited
  ) {
    if (hasTimeout) {
      currentTimeoutMs = nextTimeoutMs;
    } else if (allControllersVisited) {
      currentTimeoutMs = -1;
    }
  }

  /**
   * Updates views in oldest-to-newest order (base views before overlays)
   * and renders the frame at most once.
   */
  void applyViewUpdatesAndRender(Controller[] viewsToUpdate) {
    for (ptrdiff_t i = cast(ptrdiff_t)viewsToUpdate.length - 1; i >= 0; --i) {
      viewsToUpdate[i].updateView();
    }
    if (viewsToUpdate.length > 0) {
      renderFrame();
    }
  }

  /**
   * Dispatches an event through the controller stack from newest (active) to
   * oldest, stopping early when consumed. Batches update and view renders.
   * Returns false if quit was requested.
   */
  bool dispatchEvent(
    AppEvent event,
    ref int currentTimeoutMs
  ) {
    Controller[16] stackBuf;
    Controller[] activeList = snapshotControllers(stackBuf);

    bool needUpdate = false;
    Controller[16] viewUpdateBuf;
    size_t viewUpdateCount = 0;
    bool allControllersVisited = true;

    int nextTimeoutMs = -1;
    bool hasTimeout = false;

    // Pass unconsumed event from newest (active) to oldest controller.
    for (ptrdiff_t i = cast(ptrdiff_t)activeList.length - 1; i >= 0; --i) {
      Controller c = activeList[i];
      if (c is null) {
        continue;
      }

      Controller.HandleResult result = c.handleEvent(event);

      if (result.timeoutMs >= 0) {
        if (!hasTimeout || result.timeoutMs < nextTimeoutMs) {
          nextTimeoutMs = result.timeoutMs;
          hasTimeout = true;
        }
      }

      final switch (result.result) {
      case Controller.HandleResult.Result.quit:
        return false;
      case Controller.HandleResult.Result.nothing:
        break;
      case Controller.HandleResult.Result.update:
        needUpdate = true;
        break;
      case Controller.HandleResult.Result.updateView:
        if (viewUpdateCount < viewUpdateBuf.length) {
          viewUpdateBuf[viewUpdateCount++] = c;
        }
        break;
      }

      if (result.consume) {
        allControllersVisited = (i == 0);
        break;
      }
    }

    applyTimeout(currentTimeoutMs, hasTimeout, nextTimeoutMs,
      allControllersVisited);
    applyViewUpdatesAndRender(viewUpdateBuf[0 .. viewUpdateCount]);

    if (needUpdate) {
      sendAppEvent(AppEvent(AppEvent.Kind.update));
    }

    return true;
  }

  bool runEventLoopStep(
    Controller activeController,
    ref int currentTimeoutMs
  ) {
    int waitRes = pollSdlEvent(currentTimeoutMs);

    Nullable!AppEvent nullableEvent = getAppEvent();
    if (!nullableEvent.isNull) {
      AppEvent event = nullableEvent.get();
      handleWindowEvent(event);
      if (!dispatchEvent(event, currentTimeoutMs)) {
        return false;
      }
    } else if (waitRes == 0 && currentTimeoutMs >= 0) {
      updateAndRender(activeController);
    }

    messageBus.ensureWake();
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
    auto active = getActiveControllerOrNull();
    if (active !is null) {
      updateAndRender(active);
    } else {
      renderFrame();
    }
  }

  /**
   * Sets the additional scaling factor above displayScaling (e.g. to support
   * zooming in/out UI for user preferences). Defaults to 1.0.
   */
  void setUnitsScaling(float scaling) {
    if (mainWindow !is null) {
      mainWindow.setUnitsScaling(scaling);
    }
    redraw();
  }

  /**
   * Gets the additional scaling factor above displayScaling (defaults to 1.0).
   */
  float getUnitsScaling() const {
    if (mainWindow !is null) {
      return mainWindow.getUnitsScaling();
    }
    return 1.0f;
  }

  float getDisplayScaling() const {
    if (mainWindow !is null) {
      return mainWindow.getDisplayScaling();
    }
    return 1.0f;
  }

  void setDisplayScaling(float scaling) {
    if (mainWindow !is null) {
      mainWindow.setDisplayScaling(scaling);
    }
    redraw();
  }

  float getDefaultScaling() const {
    if (mainWindow !is null) {
      return mainWindow.getDefaultScaling();
    }
    return 1.0f;
  }

  Nullable!AppEvent appEventFromSdlEvent(in yguilib_sdl3_Event sdlEv) {
    return yguilib.priv.sdl_events.appEventFromSdlEvent(sdlEv);
  }

  ControllerStack controllers;
  MessageBus messageBus;
  Window mainWindow;
  WidgetPainterSystem painterSystem;
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
      if (ev.kind == AppEvent.Kind.user && ev.eventId == 999) {
        return HandleResult(HandleResult.Result.quit);
      }
      return HandleResult(HandleResult.Result.nothing);
    }
  }

  auto window = new Window(100, 100, "aaa");
  auto ui = new UiSystem(window);
  auto ctrl = new ThreadTestController;
  ui.pushController(ctrl);

  auto worker = new Thread({
    Thread.sleep(msecs(20));
    ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 101));
    ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 102));
    ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 999));
  });
  worker.start();

  ui.mainEventLoop();
  worker.join();

  assert(ctrl.received.length == 3);
  assert(ctrl.received[0].kind == AppEvent.Kind.user);
  assert(ctrl.received[0].eventId == 101);
  assert(ctrl.received[1].eventId == 102);
  assert(ctrl.received[2].eventId == 999);
}

// Verifies timeout-driven periodic view updates in the main event loop.
unittest {
  class TickController : DefaultController {
    UiSystem ui;
    int ticks = 0;
    this(UiSystem ui) {
      super(null);
      this.ui = ui;
    }

    override HandleResult handleEvent(in AppEvent ev) {
      if (ev.kind == AppEvent.Kind.appQuit) {
        return HandleResult(HandleResult.Result.quit);
      }
      HandleResult res;
      res.result = HandleResult.Result.nothing;
      res.timeoutMs = 10;
      return res;
    }

    override void updateView() {
      ticks++;
      if (ticks >= 2) {
        ui.sendAppEvent(AppEvent(AppEvent.Kind.appQuit));
      }
    }
  }

  auto window = new Window(100, 100, "aaa");
  auto uiTick = new UiSystem(window);
  auto tickCtrl = new TickController(uiTick);
  uiTick.pushController(tickCtrl);
  uiTick.sendAppEvent(AppEvent(AppEvent.Kind.user, 1));

  uiTick.mainEventLoop();
  assert(tickCtrl.ticks >= 2);
}

// Verifies window resize event handling and renderer viewport updates.
unittest {
  class ResizeTestController : DefaultController {
    this() {
      super(null);
    }
    const(AppEvent)[] received;
    int updateCount = 0;

    override HandleResult handleEvent(AppEvent ev) {
      received ~= ev;
      if (ev.kind == AppEvent.Kind.windowResized) {
        return HandleResult(HandleResult.Result.updateView);
      }
      if (ev.kind == AppEvent.Kind.user && ev.eventId == 999) {
        return HandleResult(HandleResult.Result.quit);
      }
      return super.handleEvent(ev);
    }

    override void updateView() {
      updateCount++;
    }
  }

  auto window = new Window(320, 240, "test_resize_window");
  auto ui = new UiSystem(window);
  auto ctrl = new ResizeTestController();
  ui.pushController(ctrl);

  ui.sendAppEvent(
    AppEvent(AppEvent.Kind.windowResized, 0, 640, 480)
  );
  ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 999));

  ui.mainEventLoop();

  assert(ctrl.received.length == 2);
  assert(ctrl.received[0].kind == AppEvent.Kind.windowResized);
  assert(ctrl.received[0].width == 640);
  assert(ctrl.received[0].height == 480);
  assert(ctrl.received[1].kind == AppEvent.Kind.user);
  assert(window.width == 640);
  assert(window.height == 480);
  assert(window.renderer !is null);
  assert(window.renderer.getViewportWidth() == 640);
  assert(window.renderer.getViewportHeight() == 480);
  assert(ctrl.updateCount >= 1);
}

// Verifies window expose event handling and controller notification.
unittest {
  class ExposeTestController : DefaultController {
    this() {
      super(null);
    }
    const(AppEvent)[] received;
    int updateCount = 0;

    override HandleResult handleEvent(AppEvent ev) {
      received ~= ev;
      if (ev.kind == AppEvent.Kind.user && ev.eventId == 999) {
        return HandleResult(HandleResult.Result.quit);
      }
      return super.handleEvent(ev);
    }

    override void updateView() {
      updateCount++;
    }
  }

  auto window = new Window(320, 240, "test_expose_window");
  auto ui = new UiSystem(window);
  auto ctrl = new ExposeTestController();
  ui.pushController(ctrl);

  ui.sendAppEvent(AppEvent(AppEvent.Kind.windowExposed, 0, 320, 240));
  ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 999));

  ui.mainEventLoop();

  assert(ctrl.received.length == 2);
  assert(ctrl.received[0].kind == AppEvent.Kind.windowExposed);
  assert(ctrl.received[1].kind == AppEvent.Kind.user);
  assert(ctrl.updateCount >= 1);
}

// Verifies UiSystem scaling and redraw APIs.
unittest {
  auto window = new Window(320, 240, "test_ui_scaling");
  auto ui = new UiSystem(window);

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
      if (ev.kind == AppEvent.Kind.user && ev.eventId == 42) {
        *log ~= name ~ ":handleEvent";
        HandleResult res;
        res.result = HandleResult.Result.nothing;
        res.consume = shouldConsume;
        return res;
      }
      if (ev.kind == AppEvent.Kind.user && ev.eventId == 999) {
        return HandleResult(HandleResult.Result.quit);
      }
      return super.handleEvent(ev);
    }
  }

  string[] log;
  auto window = new Window(100, 100, "test_prop");
  auto ui = new UiSystem(window);

  auto cOldest = new PropagationTestController("oldest", &log, false);
  auto cNewest = new PropagationTestController("newest", &log, false);

  ui.pushController(cOldest);
  ui.pushController(cNewest);

  ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 42));
  ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 999));

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
      if (ev.kind == AppEvent.Kind.user && ev.eventId == 42) {
        *log ~= name ~ ":handleEvent";
        HandleResult res;
        res.result = HandleResult.Result.nothing;
        res.consume = shouldConsume;
        return res;
      }
      if (ev.kind == AppEvent.Kind.user && ev.eventId == 999) {
        return HandleResult(HandleResult.Result.quit);
      }
      return super.handleEvent(ev);
    }
  }

  string[] log;
  auto window = new Window(100, 100, "test_consume");
  auto ui = new UiSystem(window);

  auto cOldest = new ConsumeTestController("oldest", &log, false);
  auto cNewest = new ConsumeTestController("newest", &log, true);

  ui.pushController(cOldest);
  ui.pushController(cNewest);

  ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 42));
  ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 999));

  ui.mainEventLoop();

  assert(log == ["newest:handleEvent"]);
}

// Verifies updateView ordering and batched view updates across stack.
unittest {
  class ViewOrderTestController : DefaultController {
    string name;
    string[]* log;
    this(string name, string[]* log) {
      super(null);
      this.name = name;
      this.log = log;
    }

    override HandleResult handleEvent(AppEvent ev) {
      if (ev.kind == AppEvent.Kind.user && ev.eventId == 42) {
        HandleResult res;
        res.result = HandleResult.Result.updateView;
        res.consume = false;
        return res;
      }
      if (ev.kind == AppEvent.Kind.user && ev.eventId == 999) {
        return HandleResult(HandleResult.Result.quit);
      }
      return super.handleEvent(ev);
    }

    override void updateView() {
      *log ~= name ~ ":updateView";
    }
  }

  string[] log;
  auto window = new Window(100, 100, "test_view_order");
  auto ui = new UiSystem(window);

  auto cOldest = new ViewOrderTestController("oldest", &log);
  auto cNewest = new ViewOrderTestController("newest", &log);

  ui.pushController(cOldest);
  ui.pushController(cNewest);

  ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 42));
  ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 999));

  ui.mainEventLoop();

  // "newest:updateView" from initial setup in mainEventLoop, then
  // "oldest:updateView" followed by "newest:updateView" for event 42.
  assert(log == [
    "newest:updateView",
    "oldest:updateView",
    "newest:updateView"
  ]);
}

// Verifies multiple Result.update returns send only one AppEvent.Kind.update.
unittest {
  class MultiUpdateTestController : DefaultController {
    UiSystem ui;
    int* updateEventCount;
    this(UiSystem ui, int* count) {
      super(null);
      this.ui = ui;
      this.updateEventCount = count;
    }

    override HandleResult handleEvent(AppEvent ev) {
      if (ev.kind == AppEvent.Kind.user && ev.eventId == 42) {
        HandleResult res;
        res.result = HandleResult.Result.update;
        res.consume = false;
        return res;
      }
      if (ev.kind == AppEvent.Kind.update) {
        (*updateEventCount)++;
        if (*updateEventCount >= 2) {
          ui.sendAppEvent(AppEvent(AppEvent.Kind.appQuit));
        }
        return HandleResult(HandleResult.Result.nothing);
      }
      if (ev.kind == AppEvent.Kind.appQuit) {
        return HandleResult(HandleResult.Result.quit);
      }
      return super.handleEvent(ev);
    }
  }

  int updateEventCount = 0;
  auto window = new Window(100, 100, "test_multi_update");
  auto ui = new UiSystem(window);

  auto cOldest = new MultiUpdateTestController(ui, &updateEventCount);
  auto cNewest = new MultiUpdateTestController(ui, &updateEventCount);

  ui.pushController(cOldest);
  ui.pushController(cNewest);

  ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 42));

  ui.mainEventLoop();

  // Both controllers handled event 42 and returned Result.update.
  // UiSystem sent exactly ONE AppEvent.Kind.update.
  // Both controllers received that single update event (1 increment each).
  assert(updateEventCount == 2);
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
  auto ui = new UiSystem(window);

  auto cOldest = new QuitTestController("oldest", &log, false);
  auto cNewest = new QuitTestController("newest", &log, true);

  ui.pushController(cOldest);
  ui.pushController(cNewest);

  ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 1));
  ui.mainEventLoop();

  assert(log == ["newest:handleEvent"]);
}

// Verifies timeout resolution across multiple controllers in stack.
unittest {
  class TimeoutTestController : DefaultController {
    int myTimeout;
    bool shouldConsume;
    this(int timeout, bool shouldConsume = false) {
      super(null);
      this.myTimeout = timeout;
      this.shouldConsume = shouldConsume;
    }

    override HandleResult handleEvent(AppEvent ev) {
      HandleResult res;
      res.result = HandleResult.Result.nothing;
      res.timeoutMs = myTimeout;
      res.consume = shouldConsume;
      return res;
    }
  }

  auto window = new Window(100, 100, "test_timeout");
  auto ui = new UiSystem(window);

  auto cOldest = new TimeoutTestController(100, false);
  auto cNewest = new TimeoutTestController(20, false);

  ui.pushController(cOldest);
  ui.pushController(cNewest);

  ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 1));

  int timeoutMs = -1;
  // Step 1: Unconsumed event visited both controllers.
  // Minimum timeout between 100 and 20 is 20.
  bool cont = ui.runEventLoopStep(cNewest, timeoutMs);
  assert(cont);
  assert(timeoutMs == 20);

  // Step 2: cNewest consumes event with timeout -1.
  // cOldest's pending timeout of 20 should be preserved because cOldest
  // was not visited.
  cNewest.myTimeout = -1;
  cNewest.shouldConsume = true;
  ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 2));
  cont = ui.runEventLoopStep(cNewest, timeoutMs);
  assert(cont);
  assert(timeoutMs == 20);

  // Step 3: cNewest does not consume event with timeout -1, and cOldest
  // also returns -1.
  // All controllers visited and none requested timeout => reset to -1.
  cNewest.shouldConsume = false;
  cOldest.myTimeout = -1;
  ui.sendAppEvent(AppEvent(AppEvent.Kind.user, 3));
  cont = ui.runEventLoopStep(cNewest, timeoutMs);
  assert(cont);
  assert(timeoutMs == -1);
}
