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
        AppEvent.WindowData(sdlEv.window.windowId)
      ));

    case yguilib_sdl3_EventType.windowResized:
      return Nullable!AppEvent(AppEvent(
        AppEvent.Kind.windowResized,
        AppEvent.WindowData(
          sdlEv.window.windowId,
          sdlEv.window.width,
          sdlEv.window.height,
          sdlEv.window.scale
        )
      ));

    case yguilib_sdl3_EventType.windowExposed:
      return Nullable!AppEvent(AppEvent(
        AppEvent.Kind.windowExposed,
        AppEvent.WindowData(
          sdlEv.window.windowId,
          sdlEv.window.width,
          sdlEv.window.height
        )
      ));

    case yguilib_sdl3_EventType.windowDisplayScaleChanged:
      return Nullable!AppEvent(AppEvent(
        AppEvent.Kind.windowDisplayScaleChanged,
        AppEvent.WindowData(
          sdlEv.window.windowId,
          sdlEv.window.width,
          sdlEv.window.height,
          sdlEv.window.scale
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

    case yguilib_sdl3_EventType.mouseWheel:
      return Nullable!AppEvent(AppEvent(
        AppEvent.Kind.mouseWheel,
        AppEvent.WheelData(
          sdlEv.wheel.windowId,
          sdlEv.wheel.x,
          sdlEv.wheel.y,
          sdlEv.wheel.mouseX,
          sdlEv.wheel.mouseY,
          sdlEv.wheel.direction,
          sdlEv.wheel.integerX,
          sdlEv.wheel.integerY
        )
      ));

    case yguilib_sdl3_EventType.keyDown:
      return Nullable!AppEvent(makeKeyEvent(AppEvent.Kind.keyDown, sdlEv));

    case yguilib_sdl3_EventType.keyUp:
      return Nullable!AppEvent(makeKeyEvent(AppEvent.Kind.keyUp, sdlEv));

    case yguilib_sdl3_EventType.textEditing:
      return Nullable!AppEvent(AppEvent(
        AppEvent.Kind.textEditing,
        AppEvent.TextData(
          sdlEv.textEditing.windowId,
          fromCStr(sdlEv.textEditing.text),
          sdlEv.textEditing.start,
          sdlEv.textEditing.length
        )
      ));

    case yguilib_sdl3_EventType.textInput:
      return Nullable!AppEvent(AppEvent(
        AppEvent.Kind.textInput,
        AppEvent.TextData(
          sdlEv.textInput.windowId,
          fromCStr(sdlEv.textInput.text)
        )
      ));

    default:
      return Nullable!AppEvent.init;
  }
}

private:

string fromCStr(const(char)* s) {
  if (s is null) {
    return null;
  }
  import core.stdc.string : strlen;
  return s[0 .. strlen(s)].idup;
}

AppEvent makeMouseEvent(
  AppEvent.Kind kind,
  in yguilib_sdl3_Event sdlEv
) {
  if (kind == AppEvent.Kind.mouseMotion) {
    return AppEvent(
      kind,
      AppEvent.MouseData(
        sdlEv.motion.windowId,
        sdlEv.motion.x,
        sdlEv.motion.y,
        sdlEv.motion.state,
        sdlEv.motion.xrel,
        sdlEv.motion.yrel,
        0,
        false,
        0
      )
    );
  } else {
    return AppEvent(
      kind,
      AppEvent.MouseData(
        sdlEv.button.windowId,
        sdlEv.button.x,
        sdlEv.button.y,
        0,
        0.0f,
        0.0f,
        sdlEv.button.button,
        sdlEv.button.down != 0,
        sdlEv.button.clicks
      )
    );
  }
}

AppEvent makeKeyEvent(
  AppEvent.Kind kind,
  in yguilib_sdl3_Event sdlEv
) {
  return AppEvent(
    kind,
    AppEvent.KeyData(
      sdlEv.key.windowId,
      cast(Keycode)sdlEv.key.key,
      cast(Scancode)sdlEv.key.scancode,
      sdlEv.key.mod,
      sdlEv.key.repeat != 0
    )
  );
}

// Verifies appEventFromSdlEvent conversions for SDL3 events.
unittest {
  yguilib_sdl3_Event scaleSdl;
  scaleSdl.window.type = yguilib_sdl3_EventType.windowDisplayScaleChanged;
  scaleSdl.window.windowId = 42;
  scaleSdl.window.width = 640;
  scaleSdl.window.height = 480;
  scaleSdl.window.scale = 2.0f;

  auto scaleApp = appEventFromSdlEvent(scaleSdl);
  assert(!scaleApp.isNull);
  assert(scaleApp.get().kind == AppEvent.Kind.windowDisplayScaleChanged);
  assert(scaleApp.get().window.windowId == 42);
  assert(scaleApp.get().window.width == 640);
  assert(scaleApp.get().window.height == 480);
  assert(scaleApp.get().window.scale == 2.0f);

  yguilib_sdl3_Event mouseMotionSdl;
  mouseMotionSdl.motion.type = yguilib_sdl3_EventType.mouseMotion;
  mouseMotionSdl.motion.windowId = 42;
  mouseMotionSdl.motion.x = 123.5f;
  mouseMotionSdl.motion.y = 234.5f;
  mouseMotionSdl.motion.state = 0x01;
  mouseMotionSdl.motion.xrel = 10.0f;
  mouseMotionSdl.motion.yrel = -5.0f;

  auto motionApp = appEventFromSdlEvent(mouseMotionSdl);
  assert(!motionApp.isNull);
  assert(motionApp.get().kind == AppEvent.Kind.mouseMotion);
  assert(motionApp.get().mouse.windowId == 42);
  assert(motionApp.get().mouse.x == 123.5f);
  assert(motionApp.get().mouse.y == 234.5f);
  assert(motionApp.get().mouse.state == 0x01);
  assert(motionApp.get().mouse.xrel == 10.0f);
  assert(motionApp.get().mouse.yrel == -5.0f);

  yguilib_sdl3_Event mouseButtonSdl;
  mouseButtonSdl.button.type = yguilib_sdl3_EventType.mouseButtonDown;
  mouseButtonSdl.button.windowId = 42;
  mouseButtonSdl.button.x = 100.0f;
  mouseButtonSdl.button.y = 200.0f;
  mouseButtonSdl.button.button = 3;
  mouseButtonSdl.button.down = 1;
  mouseButtonSdl.button.clicks = 2;

  auto buttonApp = appEventFromSdlEvent(mouseButtonSdl);
  assert(!buttonApp.isNull);
  assert(buttonApp.get().kind == AppEvent.Kind.mouseButtonDown);
  assert(buttonApp.get().mouse.windowId == 42);
  assert(buttonApp.get().mouse.x == 100.0f);
  assert(buttonApp.get().mouse.y == 200.0f);
  assert(buttonApp.get().mouse.state == 0);
  assert(buttonApp.get().mouse.button == 3);
  assert(buttonApp.get().mouse.down);
  assert(buttonApp.get().mouse.clicks == 2);

  yguilib_sdl3_Event wheelSdl;
  wheelSdl.wheel.type = yguilib_sdl3_EventType.mouseWheel;
  wheelSdl.wheel.windowId = 42;
  wheelSdl.wheel.x = 0.5f;
  wheelSdl.wheel.y = -1.0f;
  wheelSdl.wheel.mouseX = 150.0f;
  wheelSdl.wheel.mouseY = 250.0f;
  wheelSdl.wheel.direction = 1;
  wheelSdl.wheel.integerX = 0;
  wheelSdl.wheel.integerY = -1;

  auto wheelApp = appEventFromSdlEvent(wheelSdl);
  assert(!wheelApp.isNull);
  assert(wheelApp.get().kind == AppEvent.Kind.mouseWheel);
  assert(wheelApp.get().wheel.windowId == 42);
  assert(wheelApp.get().wheel.x == 0.5f);
  assert(wheelApp.get().wheel.y == -1.0f);
  assert(wheelApp.get().wheel.mouseX == 150.0f);
  assert(wheelApp.get().wheel.mouseY == 250.0f);
  assert(wheelApp.get().wheel.direction == 1);
  assert(wheelApp.get().wheel.integerX == 0);
  assert(wheelApp.get().wheel.integerY == -1);

  yguilib_sdl3_Event keySdl;
  keySdl.key.type = yguilib_sdl3_EventType.keyDown;
  keySdl.key.windowId = 42;
  keySdl.key.key = 13;
  keySdl.key.scancode = 40;
  keySdl.key.mod = 0x0001;
  keySdl.key.repeat = 1;

  auto keyApp = appEventFromSdlEvent(keySdl);
  assert(!keyApp.isNull);
  assert(keyApp.get().kind == AppEvent.Kind.keyDown);
  assert(keyApp.get().keyData.windowId == 42);
  assert((cast(uint)keyApp.get().keyData.key) == 13);
  assert((cast(uint)keyApp.get().keyData.scancode) == 40);
  assert(keyApp.get().keyData.mod == 1);
  assert(keyApp.get().keyData.repeat);

  yguilib_sdl3_Event textSdl;
  textSdl.textInput.type = yguilib_sdl3_EventType.textInput;
  textSdl.textInput.windowId = 42;
  textSdl.textInput.text = "abc\0".ptr;

  auto textApp = appEventFromSdlEvent(textSdl);
  assert(!textApp.isNull);
  assert(textApp.get().kind == AppEvent.Kind.textInput);
  assert(textApp.get().textData.windowId == 42);
  assert(textApp.get().textData.text == "abc");

  yguilib_sdl3_Event editSdl;
  editSdl.textEditing.type = yguilib_sdl3_EventType.textEditing;
  editSdl.textEditing.windowId = 42;
  editSdl.textEditing.text = "def\0".ptr;
  editSdl.textEditing.start = 1;
  editSdl.textEditing.length = 2;

  auto editApp = appEventFromSdlEvent(editSdl);
  assert(!editApp.isNull);
  assert(editApp.get().kind == AppEvent.Kind.textEditing);
  assert(editApp.get().textData.windowId == 42);
  assert(editApp.get().textData.text == "def");
  assert(editApp.get().textData.editStart == 1);
  assert(editApp.get().textData.editLength == 2);
}
