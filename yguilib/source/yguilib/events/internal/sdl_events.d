module yguilib.events.internal.sdl_events;

package(yguilib):

import std.typecons : Nullable;
import yguilib.clibs.sdl3;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode, Scancode;

Nullable!AppEvent appEventFromSdlEvent(in yguilib_sdl3_Event sdlEv) {
  switch (sdlEv.type) {
    case yguilib_sdl3_EventType.quit:
      return Nullable!AppEvent(AppEvent(AppEvent.Kind.appQuit));

    case yguilib_sdl3_EventType.windowClose:
      return Nullable!AppEvent(AppEvent(
        AppEvent.Kind.windowClose,
        AppEvent.WindowData(sdlEv.windowId)
      ));

    case yguilib_sdl3_EventType.windowResized:
      return Nullable!AppEvent(AppEvent(
        AppEvent.Kind.windowResized,
        AppEvent.WindowData(
          sdlEv.windowId,
          sdlEv.width,
          sdlEv.height,
          sdlEv.scale
        )
      ));

    case yguilib_sdl3_EventType.windowExposed:
      return Nullable!AppEvent(AppEvent(
        AppEvent.Kind.windowExposed,
        AppEvent.WindowData(sdlEv.windowId, sdlEv.width, sdlEv.height)
      ));

    case yguilib_sdl3_EventType.windowDisplayScaleChanged:
      return Nullable!AppEvent(AppEvent(
        AppEvent.Kind.windowDisplayScaleChanged,
        AppEvent.WindowData(
          sdlEv.windowId,
          sdlEv.width,
          sdlEv.height,
          sdlEv.scale
        )
      ));

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

    case yguilib_sdl3_EventType.textEditing:
      return Nullable!AppEvent(AppEvent(
        AppEvent.Kind.textEditing,
        AppEvent.TextData(
          sdlEv.windowId,
          fromCStr(sdlEv.text),
          sdlEv.start,
          sdlEv.length
        )
      ));

    case yguilib_sdl3_EventType.textInput:
      return Nullable!AppEvent(AppEvent(
        AppEvent.Kind.textInput,
        AppEvent.TextData(sdlEv.windowId, fromCStr(sdlEv.text))
      ));

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
  return AppEvent(
    kind,
    AppEvent.MouseData(sdlEv.windowId, sdlEv.x, sdlEv.y)
  );
}

private AppEvent makeKeyEvent(
  AppEvent.Kind kind,
  in yguilib_sdl3_Event sdlEv
) {
  return AppEvent(
    kind,
    AppEvent.KeyData(
      sdlEv.windowId,
      cast(Keycode)sdlEv.key,
      cast(Scancode)sdlEv.scancode,
      sdlEv.mod,
      sdlEv.repeat != 0
    )
  );
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
  assert(scaleApp.get().window.windowId == 42);
  assert(scaleApp.get().window.width == 640);
  assert(scaleApp.get().window.height == 480);
  assert(scaleApp.get().window.scale == 2.0f);

  yguilib_sdl3_Event mouseSdl;
  mouseSdl.type = yguilib_sdl3_EventType.mouseMotion;
  mouseSdl.windowId = 42;
  mouseSdl.x = 123.5f;
  mouseSdl.y = 234.5f;

  auto mouseApp = appEventFromSdlEvent(mouseSdl);
  assert(!mouseApp.isNull);
  assert(mouseApp.get().kind == AppEvent.Kind.mouseMotion);
  assert(mouseApp.get().mouse.windowId == 42);
  assert(mouseApp.get().mouse.x == 123.5f);
  assert(mouseApp.get().mouse.y == 234.5f);

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
  assert(keyApp.get().keyData.windowId == 42);
  assert((cast(uint)keyApp.get().keyData.key) == 13);
  assert((cast(uint)keyApp.get().keyData.scancode) == 40);
  assert(keyApp.get().keyData.mod == 1);
  assert(keyApp.get().keyData.repeat);

  yguilib_sdl3_Event textSdl;
  textSdl.type = yguilib_sdl3_EventType.textInput;
  textSdl.windowId = 42;
  textSdl.text = "abc\0".ptr;

  auto textApp = appEventFromSdlEvent(textSdl);
  assert(!textApp.isNull);
  assert(textApp.get().kind == AppEvent.Kind.textInput);
  assert(textApp.get().textData.windowId == 42);
  assert(textApp.get().textData.text == "abc");

  yguilib_sdl3_Event editSdl;
  editSdl.type = yguilib_sdl3_EventType.textEditing;
  editSdl.windowId = 42;
  editSdl.text = "def\0".ptr;
  editSdl.start = 1;
  editSdl.length = 2;

  auto editApp = appEventFromSdlEvent(editSdl);
  assert(!editApp.isNull);
  assert(editApp.get().kind == AppEvent.Kind.textEditing);
  assert(editApp.get().textData.windowId == 42);
  assert(editApp.get().textData.text == "def");
  assert(editApp.get().textData.editStart == 1);
  assert(editApp.get().textData.editLength == 2);
}
