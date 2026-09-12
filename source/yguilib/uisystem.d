module yguilib.uisystem;
import yguilib.widget;
import yguilib.events;
import yguilib.controller;

class UiSystem {

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
    if (active is null)
      return;

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

  void mainEventLoop() {
    while(auto activeController = getActiveControllerOrNull()) {
      AppEvent event;
      // TODO replace with sdl wait event loop
      // which converts sdl events to supported app events
      // via appEventFromSdlEvent()
      // and adds AppEvent to the end of the queue,
      // then pulls the oldest event in the UiSystem queue and
      // passes to activeController.handleEvent
      // if there are move events in the messageBus then
      // send custom sdl wake event to resume from the wait loop later
      event.kind = AppEvent.Kind.appQuit;
      Controller.HandleResult result = activeController.handleEvent(event);
      if (result.result == Controller.HandleResult.Result.quit)
        break;
    }
  }

  Controller getActiveControllerOrNull() {
    if (controllersStack.length != 0) {
      return controllersStack[$-1];
    }
    return null;
  }


  // TODO implement
  void sendAppEvent(AppEvent ev) {
    // TODO thread-safe add to messageBus
    // TODO also should send wake sdl event if it's not sent already
  }

private:
  // TODO here should accept an event type from clibs.sdl3
  AppEvent appEventFromSdlEvent() {
    // TODO
    return AppEvent();
  }

  Controller[] controllersStack;
  AppEvent messageBus;
  // TODO controller stack, windows, systems
  // TODO thread-safe message queue

}

class Window {
  this(int w, int h, string title) {
    this.w = w;
    this.h = h;
    this.title = title;
  }

  int w;
  int h;
  string title;

  Widget view;
}
