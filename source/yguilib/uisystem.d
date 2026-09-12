module yguilib.uisystem;

import yguilib.widget;
import yguilib.events;
import yguilib.controller;
import yguilib.clibs.sdl3;
import glad2.gles2;
import yguilib.render;
import yguilib.window;

import std.typecons;

class UiSystem {
  this(Window w) {
    mainWindow = w;
  }

  void pushController(Controller c) {
    controllersStack ~= c;
    c.onPush();
  }

  void pushModalController(Controller c) {
    auto active = getActiveControllerOrNull();
    if (active !is null) {
      active.onSuspendByModal();
    }
    controllersStack ~= c;
    getActiveControllerOrNull().onPush();
  }

  void popController() {
    auto active = getActiveControllerOrNull();
    if (active is null) {
      return;
    }

    controllersStack = controllersStack[0..$-1];
    active.onPop();
    active = getActiveControllerOrNull();
    if (active !is null) {
      active.onResumeByModal();
    }
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
      initialController.updateView();
      if (mainWindow !is null) {
        drawUi();
        mainWindow.swapBuffers();
      }
    }

    if (hasPendingAppEvents()) {
      synchronized (this) {
        wakeSent = true;
      }
      yguilib_sdl3_send_wake_event();
    }

    int currentTimeoutMs = -1;

    while (auto activeController = getActiveControllerOrNull()) {
      yguilib_sdl3_Event sdlEv;
      int res = yguilib_sdl3_wait_event(&sdlEv, currentTimeoutMs);

      if (res > 0) {
        Nullable!AppEvent appEv = appEventFromSdlEvent(sdlEv);
        if (!appEv.isNull) {
          sendAppEvent(appEv.get());
        }
      }

      Nullable!AppEvent nullableEvent = getAppEvent();
      if (!nullableEvent.isNull) {
        AppEvent event = nullableEvent.get();
        if (event.kind == AppEvent.Kind.windowResized && mainWindow !is null) {
          if (event.eventId == 0 || mainWindow.id == 0 ||
              event.eventId == mainWindow.id) {
            mainWindow.onResize(event.width, event.height);
          }
        } else if (event.kind == AppEvent.Kind.windowExposed &&
                   mainWindow !is null) {
          if (event.eventId == 0 || mainWindow.id == 0 ||
              event.eventId == mainWindow.id) {
            if (event.width > 0 && event.height > 0 &&
                (event.width != mainWindow.width ||
                 event.height != mainWindow.height)) {
              mainWindow.onResize(event.width, event.height);
            }
          }
        }
        Controller.HandleResult result = activeController.handleEvent(event);
        currentTimeoutMs = result.timeoutMs;
        if (result.result == Controller.HandleResult.Result.quit) {
          break;
        }
        if (result.result == Controller.HandleResult.Result.updateView) {
          activeController.updateView();
          if (mainWindow !is null) {
            drawUi();
            mainWindow.swapBuffers();
          }
        }
      } else if (res == 0 && currentTimeoutMs >= 0) {
        activeController.updateView();
        if (mainWindow !is null) {
          drawUi();
          mainWindow.swapBuffers();
        }
      }

      if (hasPendingAppEvents()) {
        synchronized (this) {
          wakeSent = true;
        }
        yguilib_sdl3_send_wake_event();
      }
    }
  }

  Controller getActiveControllerOrNull() {
    if (controllersStack.length != 0) {
      return controllersStack[$-1];
    }
    return null;
  }

  void sendAppEvent(AppEvent ev) {
    bool needWake = false;
    synchronized (this) {
      messageBus ~= ev;
      if (!wakeSent) {
        wakeSent = true;
        needWake = true;
      }
    }
    if (needWake) {
      yguilib_sdl3_send_wake_event();
    }
  }

  Nullable!AppEvent getAppEvent() {
    synchronized (this) {
      if (messageBus.length == 0) {
        wakeSent = false;
        return Nullable!AppEvent.init;
      }
      auto ev = messageBus[0];
      messageBus = messageBus[1..$];
      if (messageBus.length == 0) {
        messageBus = null;
        wakeSent = false;
      }
      return Nullable!AppEvent(ev);
    }
  }

  bool hasPendingAppEvents() {
    synchronized (this) {
      return messageBus.length > 0;
    }
  }

  inout(Window) getMainWindow() inout {
    return mainWindow;
  }

private:
  Nullable!AppEvent appEventFromSdlEvent(in yguilib_sdl3_Event sdlEv) {
    if (sdlEv.type == yguilib_sdl3_EventType.quit) {
      return Nullable!AppEvent(AppEvent(AppEvent.Kind.appQuit));
    }
    if (sdlEv.type == yguilib_sdl3_EventType.windowClose) {
      return Nullable!AppEvent(
        AppEvent(AppEvent.Kind.windowClose, sdlEv.windowId)
      );
    }
    if (sdlEv.type == yguilib_sdl3_EventType.windowResized) {
      return Nullable!AppEvent(
        AppEvent(
          AppEvent.Kind.windowResized,
          sdlEv.windowId,
          sdlEv.width,
          sdlEv.height
        )
      );
    }
    if (sdlEv.type == yguilib_sdl3_EventType.windowExposed) {
      return Nullable!AppEvent(
        AppEvent(
          AppEvent.Kind.windowExposed,
          sdlEv.windowId,
          sdlEv.width,
          sdlEv.height
        )
      );
    }
    return Nullable!AppEvent.init;
  }

  Controller[] controllersStack;
  AppEvent[] messageBus;
  bool wakeSent;
  Window mainWindow;
}

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

