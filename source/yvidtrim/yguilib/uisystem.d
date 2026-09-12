module yvidtrim.yguilib.uisystem;
import yvidtrim.yguilib.widget;
import yvidtrim.yguilib.events;
import yvidtrim.yguilib.controller;

class UiSystem {

  void pushController(Controller c) {
    controllersStack ~= c;
    // TODO
  }

  void pushModalController(Controller c) {
    controllersStack ~= c;
    // TODO
  }

  void popController() {
    controllersStack = controllersStack[0..$-1];
    // TODO
  }

  void pushFocusRoot(Widget w) {
  }
  void popFocuseRoot() {
  }

  Controller[] controllersStack;
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
