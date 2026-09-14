module yguilib.uisystem;

import yguilib.widget;
import yguilib.events;
import yguilib.controller;
import yguilib.clibs.sdl3;
import glad2.gles2;
import yguilib.render;
import yguilib.window;
import yguilib.widget_painter;

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
    painterSystem = new WidgetPainterSystem;
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

  void popFocuseRoot() {
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


private:
  // TODO optimize
  Widget[] collectVisibleWidgets(Widget root) {
    if (!root.visible)
      return null;

    Widget[] result = [];
    foreach(w; root.children) {
      if (w.visible) {
        result ~= w;
        result ~= collectVisibleWidgets(w);
      }
    }
    return result;
  }

  void drawWidgetTree(Widget root) {
    Widget[] collected = [root] ~ collectVisibleWidgets(root);
    painterSystem.drawWidgets(collected, mainWindow.renderer);
  }

  void drawUi() {
    if (mainWindow !is null && mainWindow.view !is null) {
      drawWidgetTree(mainWindow.view);
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

  bool isMainWindowEvent(uint eventId) const {
    return mainWindow !is null &&
      (eventId == 0 || mainWindow.id == 0 || eventId == mainWindow.id);
  }

  void handleWindowEvent(in AppEvent event) {
    if (!isMainWindowEvent(event.eventId)) {
      return;
    }
    if (event.kind == AppEvent.Kind.windowResized) {
      if (event.scale > 0.0f && event.scale != mainWindow.getDisplayScaling()) {
        mainWindow.onDisplayScaleChanged(event.scale);
      }
      mainWindow.onResize(event.width, event.height);
    } else if (event.kind == AppEvent.Kind.windowExposed) {
      if (event.width > 0 && event.height > 0 &&
          (event.width != mainWindow.pixelWidth ||
           event.height != mainWindow.pixelHeight)) {
        mainWindow.onResize(event.width, event.height);
      }
    } else if (event.kind == AppEvent.Kind.windowDisplayScaleChanged) {
      mainWindow.onDisplayScaleChanged(event.scale);
      if (event.width > 0 && event.height > 0) {
        mainWindow.onResize(event.width, event.height);
      }
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

  bool runEventLoopStep(
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
      if (result.result != Controller.HandleResult.Result.nothing) {
        updateAndRender(activeController);
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

  void sendAppEvent(AppEvent ev) {
    messageBus.send(ev);
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
            sdlEv.height,
            null,
            0.0f,
            0.0f,
            sdlEv.scale
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
      case yguilib_sdl3_EventType.windowDisplayScaleChanged:
        return Nullable!AppEvent(
          AppEvent(
            AppEvent.Kind.windowDisplayScaleChanged,
            sdlEv.windowId,
            sdlEv.width,
            sdlEv.height,
            null,
            0.0f,
            0.0f,
            sdlEv.scale
          )
        );
      case yguilib_sdl3_EventType.mouseMotion:
        return Nullable!AppEvent(
          AppEvent(
            AppEvent.Kind.mouseMotion,
            sdlEv.windowId,
            0,
            0,
            null,
            sdlEv.x,
            sdlEv.y
          )
        );
      case yguilib_sdl3_EventType.mouseButtonDown:
        return Nullable!AppEvent(
          AppEvent(
            AppEvent.Kind.mouseButtonDown,
            sdlEv.windowId,
            0,
            0,
            null,
            sdlEv.x,
            sdlEv.y
          )
        );
      case yguilib_sdl3_EventType.mouseButtonUp:
        return Nullable!AppEvent(
          AppEvent(
            AppEvent.Kind.mouseButtonUp,
            sdlEv.windowId,
            0,
            0,
            null,
            sdlEv.x,
            sdlEv.y
          )
        );
      case yguilib_sdl3_EventType.keyDown: {
        AppEvent ev = AppEvent(AppEvent.Kind.keyDown, sdlEv.windowId);
        ev.key = sdlEv.key;
        ev.scancode = sdlEv.scancode;
        ev.mod = sdlEv.mod;
        ev.repeat = sdlEv.repeat != 0;
        return Nullable!AppEvent(ev);
      }
      case yguilib_sdl3_EventType.keyUp: {
        AppEvent ev = AppEvent(AppEvent.Kind.keyUp, sdlEv.windowId);
        ev.key = sdlEv.key;
        ev.scancode = sdlEv.scancode;
        ev.mod = sdlEv.mod;
        ev.repeat = sdlEv.repeat != 0;
        return Nullable!AppEvent(ev);
      }
      case yguilib_sdl3_EventType.textEditing: {
        import core.stdc.string : strlen;
        AppEvent ev = AppEvent(AppEvent.Kind.textEditing, sdlEv.windowId);
        if (sdlEv.text !is null) {
          ev.text = sdlEv.text[0 .. strlen(sdlEv.text)].idup;
        }
        ev.editStart = sdlEv.start;
        ev.editLength = sdlEv.length;
        return Nullable!AppEvent(ev);
      }
      case yguilib_sdl3_EventType.textInput: {
        import core.stdc.string : strlen;
        AppEvent ev = AppEvent(AppEvent.Kind.textInput, sdlEv.windowId);
        if (sdlEv.text !is null) {
          ev.text = sdlEv.text[0 .. strlen(sdlEv.text)].idup;
        }
        return Nullable!AppEvent(ev);
      }
      default:
        return Nullable!AppEvent.init;
    }
  }

  ControllerStack controllers;
  MessageBus messageBus;
  Window mainWindow;
  WidgetPainterSystem painterSystem;
} // -UiSystem

// Verifies cross-thread event dispatch to the active controller.
unittest {
  import core.thread;
  import core.time;

  class ThreadTestController : DefaultController {
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

// Verifies UiSystem scaling and redraw APIs.
unittest {
  auto window = new Window(320, 240, "test_ui_scaling");
  auto ui = new UiSystem(window);

  assert(ui.getDefaultScaling() == 1.0f);
  assert(ui.getDisplayScaling() == 1.0f);
  assert(ui.getUnitsScaling() == 1.0f);

  ui.setUnitsScaling(2.0f);
  assert(ui.getUnitsScaling() == 2.0f);

  // appEventFromSdlEvent conversions
  yguilib_sdl3_Event scaleSdl;
  scaleSdl.type = yguilib_sdl3_EventType.windowDisplayScaleChanged;
  scaleSdl.windowId = 42;
  scaleSdl.width = 640;
  scaleSdl.height = 480;
  scaleSdl.scale = 2.0f;

  auto scaleApp = ui.appEventFromSdlEvent(scaleSdl);
  assert(!scaleApp.isNull);
  assert(scaleApp.get().kind == AppEvent.Kind.windowDisplayScaleChanged);
  assert(scaleApp.get().eventId == 42);
  assert(scaleApp.get().width == 640);
  assert(scaleApp.get().height == 480);
  assert(scaleApp.get().scale == 2.0f);

  yguilib_sdl3_Event mouseSdl;
  mouseSdl.type = yguilib_sdl3_EventType.mouseMotion;
  mouseSdl.windowId = 42;
  mouseSdl.x = 123.5f;
  mouseSdl.y = 234.5f;

  auto mouseApp = ui.appEventFromSdlEvent(mouseSdl);
  assert(!mouseApp.isNull);
  assert(mouseApp.get().kind == AppEvent.Kind.mouseMotion);
  assert(mouseApp.get().eventId == 42);
  assert(mouseApp.get().x == 123.5f);
  assert(mouseApp.get().y == 234.5f);

  yguilib_sdl3_Event keySdl;
  keySdl.type = yguilib_sdl3_EventType.keyDown;
  keySdl.windowId = 42;
  keySdl.key = 13;
  keySdl.scancode = 40;
  keySdl.mod = 0x0001;
  keySdl.repeat = 1;

  auto keyApp = ui.appEventFromSdlEvent(keySdl);
  assert(!keyApp.isNull);
  assert(keyApp.get().kind == AppEvent.Kind.keyDown);
  assert(keyApp.get().eventId == 42);
  assert(keyApp.get().key == 13);
  assert(keyApp.get().scancode == 40);
  assert(keyApp.get().mod == 1);
  assert(keyApp.get().repeat);

  yguilib_sdl3_Event textSdl;
  textSdl.type = yguilib_sdl3_EventType.textInput;
  textSdl.windowId = 42;
  textSdl.text = "abc\0".ptr;

  auto textApp = ui.appEventFromSdlEvent(textSdl);
  assert(!textApp.isNull);
  assert(textApp.get().kind == AppEvent.Kind.textInput);
  assert(textApp.get().eventId == 42);
  assert(textApp.get().text == "abc");

  yguilib_sdl3_Event editSdl;
  editSdl.type = yguilib_sdl3_EventType.textEditing;
  editSdl.windowId = 42;
  editSdl.text = "def\0".ptr;
  editSdl.start = 1;
  editSdl.length = 2;

  auto editApp = ui.appEventFromSdlEvent(editSdl);
  assert(!editApp.isNull);
  assert(editApp.get().kind == AppEvent.Kind.textEditing);
  assert(editApp.get().eventId == 42);
  assert(editApp.get().text == "def");
  assert(editApp.get().editStart == 1);
  assert(editApp.get().editLength == 2);
}
