module yguilib.events.internal.sdl_events;

package(yguilib):

import std.typecons : Nullable;
import yguilib.clibs.sdl3;
import yguilib.events : AppEvent, KeyCode, ScanCode;

Nullable!AppEvent appEventFromSdlEvent(in yguilib_sdl3_Event sdlEv) {
  switch (sdlEv.type) {
    case yguilib_sdl3_EventType.quit:
      return Nullable!AppEvent(AppEvent(AppEvent.Kind.appQuit));

    case yguilib_sdl3_EventType.windowClose: {
      AppEvent ev = AppEvent(AppEvent.Kind.windowClose);
      ev.windowId = sdlEv.windowId;
      return Nullable!AppEvent(ev);
    }

    case yguilib_sdl3_EventType.windowResized: {
      AppEvent ev = AppEvent(AppEvent.Kind.windowResized);
      ev.windowId = sdlEv.windowId;
      ev.width = sdlEv.width;
      ev.height = sdlEv.height;
      ev.scale = sdlEv.scale;
      return Nullable!AppEvent(ev);
    }

    case yguilib_sdl3_EventType.windowExposed: {
      AppEvent ev = AppEvent(AppEvent.Kind.windowExposed);
      ev.windowId = sdlEv.windowId;
      ev.width = sdlEv.width;
      ev.height = sdlEv.height;
      return Nullable!AppEvent(ev);
    }

    case yguilib_sdl3_EventType.windowDisplayScaleChanged: {
      AppEvent ev = AppEvent(AppEvent.Kind.windowDisplayScaleChanged);
      ev.windowId = sdlEv.windowId;
      ev.width = sdlEv.width;
      ev.height = sdlEv.height;
      ev.scale = sdlEv.scale;
      return Nullable!AppEvent(ev);
    }

    case yguilib_sdl3_EventType.mouseMotion:
    case yguilib_sdl3_EventType.mouseButtonDown:
    case yguilib_sdl3_EventType.mouseButtonUp: {
      AppEvent.Kind kind;
      if (sdlEv.type == yguilib_sdl3_EventType.mouseMotion) {
        kind = AppEvent.Kind.mouseMotion;
      } else if (sdlEv.type == yguilib_sdl3_EventType.mouseButtonDown) {
        kind = AppEvent.Kind.mouseButtonDown;
      } else {
        kind = AppEvent.Kind.mouseButtonUp;
      }
      return Nullable!AppEvent(makeMouseEvent(kind, sdlEv));
    }

    case yguilib_sdl3_EventType.keyDown:
      return Nullable!AppEvent(makeKeyEvent(AppEvent.Kind.keyDown, sdlEv));

    case yguilib_sdl3_EventType.keyUp:
      return Nullable!AppEvent(makeKeyEvent(AppEvent.Kind.keyUp, sdlEv));

    case yguilib_sdl3_EventType.textEditing: {
      AppEvent ev = AppEvent(AppEvent.Kind.textEditing);
      ev.windowId = sdlEv.windowId;
      ev.text = fromCStr(sdlEv.text);
      ev.editStart = sdlEv.start;
      ev.editLength = sdlEv.length;
      return Nullable!AppEvent(ev);
    }

    case yguilib_sdl3_EventType.textInput: {
      AppEvent ev = AppEvent(AppEvent.Kind.textInput);
      ev.windowId = sdlEv.windowId;
      ev.text = fromCStr(sdlEv.text);
      return Nullable!AppEvent(ev);
    }

    default:
      return Nullable!AppEvent.init;
  }
}

private string fromCStr(const(char)* s) {
  if (s is null) {
    return null;
  }
  import core.stdc.string : strlen;
  return s[0 .. strlen(s)].idup;
}

private AppEvent makeMouseEvent(
  AppEvent.Kind kind,
  in yguilib_sdl3_Event sdlEv
) {
  AppEvent ev = AppEvent(kind);
  ev.windowId = sdlEv.windowId;
  ev.x = sdlEv.x;
  ev.y = sdlEv.y;
  return ev;
}

private AppEvent makeKeyEvent(
  AppEvent.Kind kind,
  in yguilib_sdl3_Event sdlEv
) {
  AppEvent ev = AppEvent(kind);
  ev.windowId = sdlEv.windowId;
  ev.key = cast(KeyCode)sdlEv.key;
  ev.scancode = cast(ScanCode)sdlEv.scancode;
  ev.mod = sdlEv.mod;
  ev.repeat = sdlEv.repeat != 0;
  return ev;
}

// Verifies appEventFromSdlEvent conversions for SDL3 events.
unittest {
  yguilib_sdl3_Event scaleSdl;
  scaleSdl.type = yguilib_sdl3_EventType.windowDisplayScaleChanged;
  scaleSdl.windowId = 42;
  scaleSdl.width = 640;
  scaleSdl.height = 480;
  scaleSdl.scale = 2.0f;

  auto scaleApp = appEventFromSdlEvent(scaleSdl);
  assert(!scaleApp.isNull);
  assert(scaleApp.get().kind == AppEvent.Kind.windowDisplayScaleChanged);
  assert(scaleApp.get().windowId == 42);
  assert(scaleApp.get().width == 640);
  assert(scaleApp.get().height == 480);
  assert(scaleApp.get().scale == 2.0f);

  yguilib_sdl3_Event mouseSdl;
  mouseSdl.type = yguilib_sdl3_EventType.mouseMotion;
  mouseSdl.windowId = 42;
  mouseSdl.x = 123.5f;
  mouseSdl.y = 234.5f;

  auto mouseApp = appEventFromSdlEvent(mouseSdl);
  assert(!mouseApp.isNull);
  assert(mouseApp.get().kind == AppEvent.Kind.mouseMotion);
  assert(mouseApp.get().windowId == 42);
  assert(mouseApp.get().x == 123.5f);
  assert(mouseApp.get().y == 234.5f);

  yguilib_sdl3_Event keySdl;
  keySdl.type = yguilib_sdl3_EventType.keyDown;
  keySdl.windowId = 42;
  keySdl.key = 13;
  keySdl.scancode = 40;
  keySdl.mod = 0x0001;
  keySdl.repeat = 1;

  auto keyApp = appEventFromSdlEvent(keySdl);
  assert(!keyApp.isNull);
  assert(keyApp.get().kind == AppEvent.Kind.keyDown);
  assert(keyApp.get().windowId == 42);
  assert(keyApp.get().key == 13);
  assert(keyApp.get().scancode == 40);
  assert(keyApp.get().mod == 1);
  assert(keyApp.get().repeat);

  yguilib_sdl3_Event textSdl;
  textSdl.type = yguilib_sdl3_EventType.textInput;
  textSdl.windowId = 42;
  textSdl.text = "abc\0".ptr;

  auto textApp = appEventFromSdlEvent(textSdl);
  assert(!textApp.isNull);
  assert(textApp.get().kind == AppEvent.Kind.textInput);
  assert(textApp.get().windowId == 42);
  assert(textApp.get().text == "abc");

  yguilib_sdl3_Event editSdl;
  editSdl.type = yguilib_sdl3_EventType.textEditing;
  editSdl.windowId = 42;
  editSdl.text = "def\0".ptr;
  editSdl.start = 1;
  editSdl.length = 2;

  auto editApp = appEventFromSdlEvent(editSdl);
  assert(!editApp.isNull);
  assert(editApp.get().kind == AppEvent.Kind.textEditing);
  assert(editApp.get().windowId == 42);
  assert(editApp.get().text == "def");
  assert(editApp.get().editStart == 1);
  assert(editApp.get().editLength == 2);
}
