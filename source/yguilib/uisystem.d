module yguilib.uisystem;

import yguilib.widget;
import yguilib.events;
import yguilib.controller;
import yguilib.clibs.sdl3;
import glad2.gles2;
import yguilib.render;
import yguilib.window;

import std.typecons;

private struct ControllerStack {
  void push(Controller c) {
    assert(c !is null);
    c.isModal = false;
    stack ~= c;
    c.onPush();
  }

  void pushModal(Controller c) {
    assert(c !is null);
    c.isModal = true;
    auto active = getActiveOrNull();
    if (active !is null) {
      active.onSuspendByModal();
    }
    stack ~= c;
    c.onPush();
  }

  void pop() {
    auto active = getActiveOrNull();
    if (active is null) {
      return;
    }
    const bool wasModal = active.isModal;
    stack.length -= 1;
    active.onPop();
    active = getActiveOrNull();
    if (active !is null && wasModal) {
      active.onResumeByModal();
    }
  }

  Controller getActiveOrNull() {
    if (stack.length != 0) {
      return stack[$ - 1];
    }
    return null;
  }

  bool empty() const {
    return stack.length == 0;
  }

  size_t length() const {
    return stack.length;
  }

private:
  Controller[] stack;
}

private struct MessageBus {
  @disable this();
  this(Object lockObj) {
    assert(lockObj !is null);
    this.lock = lockObj;
  }

  invariant {
    assert(lock !is null);
  }

  void send(AppEvent ev) {
    bool needWake = false;
    synchronized (lock) {
      if (head >= events.length) {
        events.length = 0;
        head = 0;
      }
      events ~= ev;
      if (!wakeSent) {
        wakeSent = true;
        needWake = true;
      }
    }
    if (needWake) {
      yguilib_sdl3_send_wake_event();
    }
  }

  Nullable!AppEvent get() {
    synchronized (lock) {
      if (head >= events.length) {
        events.length = 0;
        head = 0;
        wakeSent = false;
        return Nullable!AppEvent.init;
      }
      auto ev = events[head++];
      if (head >= events.length) {
        events.length = 0;
        head = 0;
        wakeSent = false;
      }
      return Nullable!AppEvent(ev);
    }
  }

  bool hasPending() {
    synchronized (lock) {
      return head < events.length;
    }
  }

  void ensureWake() {
    bool needWake = false;
    synchronized (lock) {
      if (head < events.length) {
        wakeSent = true;
        needWake = true;
      }
    }
    if (needWake) {
      yguilib_sdl3_send_wake_event();
    }
  }

private:
  AppEvent[] events;
  size_t head = 0;
  bool wakeSent = false;
  Object lock;
}

class UiSystem {
  this(Window w) {
    mainWindow = w;
    messageBus = MessageBus(this);
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

  void popFocuseRoot() {
    // TODO
  }

  private void drawUi() {
    // TODO render hierarchy
    if (mainWindow !is null && mainWindow.view !is null) {
      if (mainWindow.view.components.background !is null) {
        mainWindow.renderer.drawFillRect(
          mainWindow.view.rect,
          mainWindow.view.components.background.color
        );
      }
    }
  }

  private void renderFrame() {
    if (mainWindow !is null) {
      drawUi();
      mainWindow.swapBuffers();
    }
  }

  private void updateAndRender(Controller controller) {
    if (controller !is null) {
      controller.updateView();
    }
    renderFrame();
  }

  private bool isMainWindowEvent(uint eventId) const {
    return mainWindow !is null &&
      (eventId == 0 || mainWindow.id == 0 || eventId == mainWindow.id);
  }

  private void handleWindowEvent(in AppEvent event) {
    if (!isMainWindowEvent(event.eventId)) {
      return;
    }
    if (event.kind == AppEvent.Kind.windowResized) {
      mainWindow.onResize(event.width, event.height);
    } else if (event.kind == AppEvent.Kind.windowExposed) {
      if (event.width > 0 && event.height > 0 &&
          (event.width != mainWindow.width ||
           event.height != mainWindow.height)) {
        mainWindow.onResize(event.width, event.height);
      }
    }
  }

  private int pollSdlEvent(int timeoutMs) {
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

  private bool runEventLoopStep(
    Controller activeController,
    ref int currentTimeoutMs
  ) {
    int waitRes = pollSdlEvent(currentTimeoutMs);

    Nullable!AppEvent nullableEvent = getAppEvent();
    if (!nullableEvent.isNull) {
      AppEvent event = nullableEvent.get();
      handleWindowEvent(event);

      Controller.HandleResult result = activeController.handleEvent(event);
      currentTimeoutMs = result.timeoutMs;
      if (result.result == Controller.HandleResult.Result.quit) {
        return false;
      }
      if (result.result == Controller.HandleResult.Result.updateView) {
        updateAndRender(activeController);
      }
    } else if (waitRes == 0 && currentTimeoutMs >= 0) {
      updateAndRender(activeController);
    }

    messageBus.ensureWake();
    return true;
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

  Controller getActiveControllerOrNull() {
    return controllers.getActiveOrNull();
  }

  void sendAppEvent(AppEvent ev) {
    messageBus.send(ev);
  }

  Nullable!AppEvent getAppEvent() {
    return messageBus.get();
  }

  bool hasPendingAppEvents() {
    return messageBus.hasPending();
  }

  inout(Window) getMainWindow() inout {
    return mainWindow;
  }

private:
  Nullable!AppEvent appEventFromSdlEvent(in yguilib_sdl3_Event sdlEv) {
    switch (sdlEv.type) {
      case yguilib_sdl3_EventType.quit:
        return Nullable!AppEvent(AppEvent(AppEvent.Kind.appQuit));
      case yguilib_sdl3_EventType.windowClose:
        return Nullable!AppEvent(
          AppEvent(AppEvent.Kind.windowClose, sdlEv.windowId)
        );
      case yguilib_sdl3_EventType.windowResized:
        return Nullable!AppEvent(
          AppEvent(
            AppEvent.Kind.windowResized,
            sdlEv.windowId,
            sdlEv.width,
            sdlEv.height
          )
        );
      case yguilib_sdl3_EventType.windowExposed:
        return Nullable!AppEvent(
          AppEvent(
            AppEvent.Kind.windowExposed,
            sdlEv.windowId,
            sdlEv.width,
            sdlEv.height
          )
        );
      default:
        return Nullable!AppEvent.init;
    }
  }

  ControllerStack controllers;
  MessageBus messageBus;
  Window mainWindow;
} // -UiSystem

// Verifies cross-thread event dispatch to the active controller.
unittest {
  import core.thread;
  import core.time;

  class ThreadTestController : DefaultController {
    const(AppEvent)[] received;

    override HandleResult handleEvent(in AppEvent ev) {
      received ~= ev;
      if (ev.kind == AppEvent.Kind.user && ev.eventId == 999) {
        return HandleResult(HandleResult.Result.quit);
      }
      return HandleResult(HandleResult.Result.nothing);
    }
  }

  auto window = new Window(100,100,"aaa");
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
    const(AppEvent)[] received;
    int updateCount = 0;

    override HandleResult handleEvent(in AppEvent ev) {
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
    const(AppEvent)[] received;
    int updateCount = 0;

    override HandleResult handleEvent(in AppEvent ev) {
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

// Verifies ControllerStack push, modal push, and pop lifecycle transitions.
unittest {
  class ModalTrackController : DefaultController {
    string[]* log;
    string name;

    this(string name, string[]* log) {
      this.name = name;
      this.log = log;
    }

    override void onPush() {
      *log ~= name ~ ":onPush";
    }

    override void onPop() {
      *log ~= name ~ ":onPop";
    }

    override void onSuspendByModal() {
      *log ~= name ~ ":onSuspend";
    }

    override void onResumeByModal() {
      *log ~= name ~ ":onResume";
    }
  }

  string[] log;
  ControllerStack stack;
  assert(stack.empty());
  assert(stack.length == 0);

  auto c1 = new ModalTrackController("c1", &log);
  auto c2 = new ModalTrackController("c2", &log);

  stack.push(c1);
  assert(stack.getActiveOrNull() is c1);
  assert(stack.length == 1);

  stack.pushModal(c2);
  assert(stack.getActiveOrNull() is c2);
  assert(stack.length == 2);

  stack.pop();
  assert(stack.getActiveOrNull() is c1);
  assert(stack.length == 1);

  stack.pop();
  assert(stack.empty());
  assert(stack.getActiveOrNull() is null);

  assert(log == [
    "c1:onPush",
    "c1:onSuspend",
    "c2:onPush",
    "c2:onPop",
    "c1:onResume",
    "c1:onPop"
  ]);
}

// Verifies MessageBus event queueing, retrieval, and buffer reuse.
unittest {
  MessageBus bus = MessageBus(new Object);
  assert(!bus.hasPending());
  assert(bus.get().isNull);

  bus.send(AppEvent(AppEvent.Kind.user, 1));
  bus.send(AppEvent(AppEvent.Kind.user, 2));
  assert(bus.hasPending());

  auto ev1 = bus.get();
  assert(!ev1.isNull && ev1.get().eventId == 1);
  assert(bus.hasPending());

  auto ev2 = bus.get();
  assert(!ev2.isNull && ev2.get().eventId == 2);
  assert(!bus.hasPending());
  assert(bus.get().isNull);

  // Re-enqueue to verify queue reuse without reallocation
  bus.send(AppEvent(AppEvent.Kind.user, 3));
  assert(bus.hasPending());
  auto ev3 = bus.get();
  assert(!ev3.isNull && ev3.get().eventId == 3);
  assert(!bus.hasPending());
}
