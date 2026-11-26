module yguilib.widget.internal.input_system;

package(yguilib):

import yguilib.allochelpers : ReusableArray;
import yguilib.clibs.sdl3 : yguilib_sdl3_capture_mouse,
  yguilib_sdl3_set_relative_mouse_mode, yguilib_sdl3_warp_mouse_in_window;
import yguilib.widget.internal.focus_system;
import yguilib.widget.system : SystemEventResult, SystemPhase,
  WidgetSystem, WidgetSystemContext, WidgetSystemHost;
import yguilib.widget.visible : VisibleWidget, VisibleWidgets;
import yguilib.events;
import yguilib.events.builder : ViewAppEventBuilder;
import yguilib.render.render_types;
import yguilib.widget : Widget, ViewComponent, WidgetUpdateScope;
import yguilib.widget.input_components : CursorCapture, MouseEvent;
import yguilib.widget.widget_view : WidgetView, renameViewWidgetEvent,
  passViewEvent;
import std.logger;

enum maxMouseButtons = 8;

struct HoverEntry {
  Widget widget;
  RectF absRect;
}

// TODO support multiple windows
final class InputSystem : WidgetSystem {
  this(WidgetSystemHost host) {
    assert(host !is null);
    priority(inputSystemPriority);
    this.host = host;
    this.focusSystem = new FocusSystem;
  }

  invariant {
    assert(host !is null);
    assert(focusSystem !is null);
  }

  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.event | SystemPhase.postLayout;
  }

  override void onRegister(WidgetSystemHost newHost) {
    if (newHost !is null) {
      host = newHost;
    }
  }

  override SystemEventResult handleEvent(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    const bool updateView = handleEventAndUpdateView(
      event,
      ctx.visibleWidgets
    );
    return SystemEventResult(false, updateView);
  }

  override void postLayout(ref WidgetSystemContext ctx) {
    refreshHover(ctx.visibleWidgets);
  }

  override void onWidgetReleased(Widget w) {
    if (w is null) {
      return;
    }
    hoveredWidgets.compact((const ref HoverEntry e) => e.widget !is w);
    hoverScratch.compact((const ref HoverEntry e) => e.widget !is w);
    foreach (ref pw; pressedWidgets) {
      if (pw is w) {
        pw = null;
      }
    }
    syncCursorCapture();
  }

  /// Returns true if cursor capture is currently active on the window
  /// (for both `CursorCapture.capture` and `CursorCapture.lock`).
  @property bool isCursorCaptured() const nothrow @safe {
    return hasCursorCapture;
  }

  /// Returns true if the cursor is currently locked (hidden, relative mouse
  /// mode) by a pressed widget with `CursorCapture.lock`.
  @property bool isCursorLocked() const nothrow @safe {
    return hasCursorLock;
  }

  /// Handles incoming input events.
  /// Returns true if the view needs updating (e.g. when focus changes).
  bool handleEventAndUpdateView(in AppEvent event, VisibleWidgets widgets) {
    if (event.kind == AppEvent.Kind.windowMouseLeave) {
      handleWindowMouseLeave(widgets);
      return false;
    }
    if (event.kind == AppEvent.Kind.windowMouseEnter) {
      return false;
    }
    if (!event.isKeyboardEvent() && !event.isMouseEvent())
      return false;
    // TODO call to focus system
    if (event.isMouseEvent()) {
      if (event.kind == AppEvent.Kind.mouseMotion ||
          event.kind == AppEvent.Kind.mouseButtonDown ||
          event.kind == AppEvent.Kind.mouseButtonUp) {
        lastWindowId = event.mouse.windowId;
      }
      if (event.kind == AppEvent.Kind.mouseMotion) {
        handleMouseMotion(event, widgets);
        return false;
      }
      if (event.kind == AppEvent.Kind.mouseButtonDown ||
          event.kind == AppEvent.Kind.mouseButtonUp) {
        handleMouseButton(event, widgets);
        return false;
      }
    }
    return false;
  }

  /// Re-evaluates hover states after tree layout or geometry changes.
  /// Dispatches mouseEnter and mouseLeave events when hover targets shift
  /// without triggering mouseMove.
  void refreshHover(VisibleWidgets widgets) {
    if (!hasLastMousePos)
      return;
    updateHoverState(lastMousePos, widgets, false);
  }

private:
  void handleMouseButton(in AppEvent event, VisibleWidgets widgets) {
    const p = PointF(event.mouse.x, event.mouse.y);
    const ubyte btn = event.mouse.button;

    if (event.kind == AppEvent.Kind.mouseButtonDown) {
      handleMouseDown(p, btn, widgets);
    } else if (event.kind == AppEvent.Kind.mouseButtonUp) {
      handleMouseUp(p, btn, widgets);
    }
  }

  void handleMouseDown(PointF p, ubyte btn, VisibleWidgets widgets) {
    foreach_reverse (ref VisibleWidget vw; widgets) {
      if (!isHit(vw, p))
        continue;

      Widget w = vw.widget;
      // Widgets without `handleInput` are transparent to the pointer.
      if (!w.handleInput)
        continue;

      // The first hittable widget is the target and always blocks; a
      // disabled one (or one without MouseEvent) swallows the press.
      if (w.components.mouseEvent !is null && w.inputEnabled) {
        if (btn < maxMouseButtons) {
          pressedWidgets[btn] = w;
          lastPressPos = p;
          syncCursorCapture();
        }

        if (w.components.mouseEvent.mouseDown.length > 0) {
          const float lx = p.x - vw.absRect.x;
          const float ly = p.y - vw.absRect.y;
          auto val = MouseEvent.AppEventViewValue.pack(
            lx, ly, btn, true, 0.0f, 0.0f, p.x, p.y
          );
          sendMouseEvent(w, w.components.mouseEvent.mouseDown, val);
        }
      }
      return;
    }
  }

  void handleMouseUp(PointF upPos, ubyte btn, VisibleWidgets widgets) {
    if (btn >= maxMouseButtons || pressedWidgets[btn] is null)
      return;

    // While locked the reported pointer position is meaningless; the cursor
    // is restored to the press point, so report mouseUp there.
    const PointF p = hasCursorLock ? lockOrigin : upPos;
    Widget target = pressedWidgets[btn];
    pressedWidgets[btn] = null;
    syncCursorCapture();

    if (!target.inputEnabled)
      return;

    if (target.components.mouseEvent is null ||
        target.components.mouseEvent.mouseUp.length == 0)
      return;

    const WidgetHitInfo hit = resolveWidgetRectAndHit(widgets, target, p);

    const float lx = p.x - hit.targetRect.x;
    const float ly = p.y - hit.targetRect.y;
    auto val = MouseEvent.AppEventViewValue.pack(
      lx, ly, btn, hit.inside, 0.0f, 0.0f, p.x, p.y
    );
    sendMouseEvent(target, target.components.mouseEvent.mouseUp, val);
  }

  // NOTE: possible future optimizations (not needed at current widget counts):
  // - skip hit testing when cursor position and the widgets slice
  //   (ptr, length) are unchanged since the last motion event;
  // - build a uniform-grid spatial index in collectVisible for O(1)
  //   hit-test candidates when thousands of widgets are visible.
  void handleMouseMotion(in AppEvent event, VisibleWidgets widgets) {
    const rel = PointF(event.mouse.xrel, event.mouse.yrel);
    if (hasCursorLock) {
      // Locked: position stays at the press point, only deltas matter;
      // hover state is frozen. Each motion event is dispatched on its own.
      dispatchMouseDrag(lockOrigin, rel, widgets);
      return;
    }
    const p = PointF(event.mouse.x, event.mouse.y);
    lastMousePos = p;
    hasLastMousePos = true;
    updateHoverState(p, widgets, true);
    dispatchMouseDrag(p, rel, widgets);
  }

  void dispatchMouseDrag(
    PointF p,
    PointF rel,
    VisibleWidgets widgets
  ) {
    bool hasStale = false;
    foreach (size_t i, Widget target; pressedWidgets) {
      if (target is null) {
        continue;
      }
      if (target.released || !target.inputEnabled) {
        hasStale = true;
        continue;
      }
      auto me = target.components.mouseEvent;
      if (me is null || me.mouseDrag.length == 0) {
        continue;
      }

      const WidgetHitInfo hit = resolveWidgetRectAndHit(widgets, target, p);

      const float lx = p.x - hit.targetRect.x;
      const float ly = p.y - hit.targetRect.y;
      auto val = MouseEvent.AppEventViewValue.pack(
        lx, ly, cast(ubyte) i, hit.inside, rel.x, rel.y, p.x, p.y
      );
      sendMouseEvent(target, me.mouseDrag, val);
    }
    // Drop a lock (or capture) held by a widget that became inactive.
    if (hasStale && hasCursorCapture) {
      syncCursorCapture();
    }
  }

  struct WidgetHitInfo {
    RectF targetRect;
    bool inside;
  }

  static WidgetHitInfo resolveWidgetRectAndHit(
    VisibleWidgets widgets,
    Widget target,
    PointF p
  ) {
    const idx = findVisibleWidgetIndex(widgets, target);
    if (idx >= 0) {
      return WidgetHitInfo(widgets[idx].absRect, isHit(widgets[idx], p));
    }
    const RectF targetRect = computeWidgetAbsRect(target);
    return WidgetHitInfo(targetRect, targetRect.contains(p));
  }

  // Applies the strongest CursorCapture mode wanted by active pressed
  // widgets. SDL return values are ignored (they fail in headless tests).
  void syncCursorCapture() {
    CursorCapture wanted = CursorCapture.none;
    foreach (pw; pressedWidgets) {
      if (pw !is null && !pw.released && pw.inputEnabled &&
          pw.components.mouseEvent !is null &&
          pw.components.mouseEvent.cursorCapture > wanted) {
        wanted = pw.components.mouseEvent.cursorCapture;
      }
    }
    const bool shouldCapture = wanted >= CursorCapture.capture;
    const bool shouldLock = wanted >= CursorCapture.lock;
    if (shouldCapture != hasCursorCapture) {
      hasCursorCapture = shouldCapture;
      yguilib_sdl3_capture_mouse(shouldCapture ? 1 : 0);
    }
    if (shouldLock && !hasCursorLock) {
      hasCursorLock = true;
      lockWindowId = lastWindowId;
      lockOrigin = lastPressPos;
      yguilib_sdl3_set_relative_mouse_mode(lockWindowId, 1);
    } else if (!shouldLock && hasCursorLock) {
      hasCursorLock = false;
      yguilib_sdl3_set_relative_mouse_mode(lockWindowId, 0);
      yguilib_sdl3_warp_mouse_in_window(
        lockWindowId, lockOrigin.x, lockOrigin.y
      );
      lastMousePos = lockOrigin;
    }
  }

  void handleWindowMouseLeave(VisibleWidgets widgets) {
    hasLastMousePos = false;
    updateHoverState(lastMousePos, widgets, false);
  }

  // NOTE: when cursor leaves the window (windowMouseLeave), hasLastMousePos
  // is cleared and updateHoverState sends mouseLeave to all hovered widgets.
  // NOTE: a widget disabled while hovered does not receive mouseLeave;
  // its controller should clear hover visuals upon disabling.
  void updateHoverState(PointF p, VisibleWidgets widgets, bool sendMove) {
    collectHovered(widgets, p);
    notifyDepartedWidgets(p);
    notifyEnteredAndMovedWidgets(p, sendMove);
    hoveredWidgets.swapWith(hoverScratch);
  }

  void collectHovered(VisibleWidgets widgets, PointF p) {
    hoverScratch.clear();

    if (!hasLastMousePos)
      return;

    const topIdx = findHoverTargetIndex(widgets, p);
    if (topIdx < 0)
      return;

    Widget want = widgets[topIdx].widget;
    foreach_reverse (i; 0 .. topIdx + 1) {
      if (widgets[i].widget !is want)
        continue;
      if (isHit(widgets[i], p)) {
        if (want.inputEnabled && want.components.mouseEvent !is null) {
          hoverScratch.push(HoverEntry(want, widgets[i].absRect));
        }
      }
      want = want.parent;
      if (want is null)
        break;
    }
  }

  void notifyDepartedWidgets(PointF p) {
    foreach (ref entry; hoveredWidgets[]) {
      if (!containsWidget(hoverScratch[], entry.widget)) {
        if (entry.widget.components.mouseEvent !is null &&
            entry.widget.components.mouseEvent.mouseLeave.length > 0) {
          const float lx = p.x - entry.absRect.x;
          const float ly = p.y - entry.absRect.y;
          auto val = MouseEvent.AppEventViewValue.pack(
            lx, ly, 0, false, 0.0f, 0.0f, p.x, p.y
          );
          sendMouseEvent(
            entry.widget, entry.widget.components.mouseEvent.mouseLeave, val
          );
        }
      }
    }
  }

  void notifyEnteredAndMovedWidgets(PointF p, bool sendMove) {
    foreach (ref entry; hoverScratch[]) {
      if (entry.widget.components.mouseEvent is null)
        continue;

      const wasHovered = containsWidget(hoveredWidgets[], entry.widget);
      const float lx = p.x - entry.absRect.x;
      const float ly = p.y - entry.absRect.y;
      auto val = MouseEvent.AppEventViewValue.pack(
        lx, ly, 0, true, 0.0f, 0.0f, p.x, p.y
      );

      if (!wasHovered &&
          entry.widget.components.mouseEvent.mouseEnter.length > 0) {
        sendMouseEvent(
          entry.widget, entry.widget.components.mouseEvent.mouseEnter, val
        );
      }
      if (sendMove &&
          entry.widget.components.mouseEvent.mouseMove.length > 0) {
        sendMouseEvent(
          entry.widget, entry.widget.components.mouseEvent.mouseMove, val
        );
      }
    }
  }

  void sendMouseEvent(
    Widget w,
    string eventName,
    in MouseEvent.AppEventViewValue val
  ) {
    if (eventName.length == 0)
      return;
    auto ev = ViewAppEventBuilder(eventName)
      .widget(w)
      .valueArray(val)
      .build();
    passViewEvent(host, w, ev);
  }

  ReusableArray!HoverEntry hoveredWidgets;
  ReusableArray!HoverEntry hoverScratch;
  Widget[maxMouseButtons] pressedWidgets;
  bool hasCursorCapture = false;
  bool hasCursorLock = false;
  uint lockWindowId = 0;
  PointF lockOrigin;
  PointF lastPressPos;
  uint lastWindowId = 0;
  PointF lastMousePos;
  bool hasLastMousePos = false;
  FocusSystem focusSystem;
  WidgetSystemHost host;
}

private:

bool isHit(in VisibleWidget vw, PointF p) {
  return vw.absRect.contains(p) && (!vw.hasClip || vw.clipRect.contains(p));
}

bool containsWidget(in HoverEntry[] list, Widget w) {
  foreach (ref entry; list) {
    if (entry.widget is w)
      return true;
  }
  return false;
}

ptrdiff_t findVisibleWidgetIndex(VisibleWidgets widgets, Widget w) {
  foreach (idx, ref VisibleWidget vw; widgets) {
    if (vw.widget is w)
      return idx;
  }
  return -1;
}

ptrdiff_t findHoverTargetIndex(VisibleWidgets widgets, PointF p) {
  foreach_reverse (idx, ref VisibleWidget vw; widgets) {
    if (!isHit(vw, p))
      continue;
    if (vw.widget.handleInput)
      return idx;
  }
  return -1;
}

RectF computeWidgetAbsRect(Widget w) {
  if (w is null)
    return RectF(0, 0, 0, 0);
  float x = 0.0f;
  float y = 0.0f;
  for (Widget cur = w; cur !is null; cur = cur.parent) {
    x += cur.rect.x;
    y += cur.rect.y;
  }
  return RectF(x, y, w.rect.width, w.rect.height);
}

version (unittest) {
  import yguilib.object_registry : ObjectRegistry;
  import yguilib.timercontrol : TimerId, invalidTimerId;
  import yguilib.timers : TimerMode;
  import yguilib.widget.widget_view : WidgetViewController;

  class TestUiSystem : WidgetSystemHost {
    AppEvent[] sentEvents;
    ObjectRegistry!WidgetViewController dummyControllers;
    ObjectRegistry!WidgetView dummyViews;

    this() {
      dummyControllers = new ObjectRegistry!WidgetViewController();
      dummyViews = new ObjectRegistry!WidgetView();
    }

    override void sendAppEvent(AppEvent ev) {
      sentEvents ~= ev;
    }

    override TimerId startTimer(
      Object owner,
      uint intervalMs,
      TimerMode mode
    ) {
      return invalidTimerId;
    }

    override void stopTimer(TimerId id) {}

    override bool isTimerActive(TimerId id) const {
      return false;
    }

    override @property
    ObjectRegistry!WidgetViewController widgetViewControllers() {
      return dummyControllers;
    }

    override @property ObjectRegistry!WidgetView widgetViews() {
      return dummyViews;
    }
  }
}

// Tests 1-3: Direct passthrough, single view renaming, and event suppression.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto rootNoView = fix.makeRootWithRect(RectF(0, 0, 200, 200));
  auto childNoView = fix.makeChildWithRect(rootNoView, RectF(0, 0, 50, 50));
  auto ev1 = ViewAppEventBuilder("rawClick")
    .widget(childNoView)
    .value(1)
    .build();
  passViewEvent(testUi, childNoView, ev1);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "rawClick");
  assert(testUi.sentEvents[0].view.widget is childNoView);
  assert(testUi.sentEvents[0].view.viewWidget is null);

  testUi.sentEvents = null;
  auto rootView = fix.makeRootWithRect(RectF(0, 0, 200, 200));
  rootView.components.view = new ViewComponent;
  rootView.components.view.renameEvents["btnClick"] = "playVideo";
  auto childBtn = fix.makeChildWithRect(rootView, RectF(0, 0, 50, 50));
  auto ev2 = ViewAppEventBuilder("btnClick")
    .widget(childBtn)
    .value(1)
    .build();
  passViewEvent(testUi, childBtn, ev2);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "playVideo");
  assert(testUi.sentEvents[0].view.widget is childBtn);
  assert(testUi.sentEvents[0].view.viewWidget is rootView);

  testUi.sentEvents = null;
  rootView.components.view.renameEvents["suppressMe"] = "";
  auto ev3 = ViewAppEventBuilder("suppressMe")
    .widget(childBtn)
    .value(1)
    .build();
  passViewEvent(testUi, childBtn, ev3);
  assert(testUi.sentEvents.length == 0);
}

// Tests 4-6: Nested views chaining, unmapped passthrough, and self view.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto outerView = fix.makeRootWithRect(RectF(0, 0, 400, 400));
  outerView.components.view = new ViewComponent;
  outerView.components.view.renameEvents["itemSelected"] = "orderUpdated";

  auto innerView = fix.makeChildWithRect(outerView, RectF(0, 0, 200, 200));
  innerView.components.view = new ViewComponent;
  innerView.components.view.renameEvents["click"] = "itemSelected";

  auto nestedBtn = fix.makeChildWithRect(innerView, RectF(0, 0, 50, 50));
  auto ev4 = ViewAppEventBuilder("click")
    .widget(nestedBtn)
    .value(1)
    .build();
  passViewEvent(testUi, nestedBtn, ev4);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "orderUpdated");
  assert(testUi.sentEvents[0].view.viewWidget is outerView);

  testUi.sentEvents = null;
  auto ev5 = ViewAppEventBuilder("unmappedInInner")
    .widget(nestedBtn)
    .value(1)
    .build();
  outerView.components.view.renameEvents["unmappedInInner"] = "handledByOuter";
  passViewEvent(testUi, nestedBtn, ev5);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "handledByOuter");

  testUi.sentEvents = null;
  auto selfView = fix.makeRootWithRect(RectF(0, 0, 100, 100));
  selfView.components.view = new ViewComponent;
  selfView.components.view.renameEvents["panelClick"] = "openPanel";
  auto ev6 = ViewAppEventBuilder("panelClick")
    .widget(selfView)
    .value(1)
    .build();
  passViewEvent(testUi, selfView, ev6);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "openPanel");
}

// Tests 7-8: Mouse down and up with local coords and inputEnabled check.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto btnWidget = fix.makeRootWithRect(RectF(10, 10, 100, 50));
  btnWidget.handleInput = true;
  btnWidget.components.mouseEvent = new MouseEvent;
  btnWidget.components.mouseEvent.mouseDown = "btnDown";
  btnWidget.components.mouseEvent.mouseUp = "btnUp";

  VisibleWidgets visBtn = [
    VisibleWidget(btnWidget, RectF(10, 10, 100, 50), false, RectF.init)
  ];

  auto downEv = AppEvent.mouseEvent(
    AppEvent.Kind.mouseButtonDown,
    AppEvent.MouseData(1, 20.0f, 30.0f, 0, 0, 0, 1, true, 1)
  );
  inputSys.handleEventAndUpdateView(downEv, visBtn);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "btnDown");
  auto downVal = MouseEvent.AppEventViewValue.fromRaw(
    testUi.sentEvents[0].view.value
  );
  assert(downVal.buttons == 1);
  assert(downVal.localX == 10.0f);
  assert(downVal.localY == 20.0f);
  assert(downVal.inside);

  testUi.sentEvents = null;
  auto upEv = AppEvent.mouseEvent(
    AppEvent.Kind.mouseButtonUp,
    AppEvent.MouseData(1, 25.0f, 35.0f, 0, 0, 0, 1, false, 1)
  );
  inputSys.handleEventAndUpdateView(upEv, visBtn);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "btnUp");
  auto upVal = MouseEvent.AppEventViewValue.fromRaw(
    testUi.sentEvents[0].view.value
  );
  assert(upVal.buttons == 1);
  assert(upVal.localX == 15.0f);
  assert(upVal.localY == 25.0f);
  assert(upVal.inside);

  testUi.sentEvents = null;
  btnWidget.inputEnabled = false;
  inputSys.handleEventAndUpdateView(downEv, visBtn);
  inputSys.handleEventAndUpdateView(upEv, visBtn);
  assert(testUi.sentEvents.length == 0);
}

// Tests 9-10: Mouse enter, move, leave, and inputEnabled gating on hover.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto hoverWidget = fix.makeRootWithRect(RectF(50, 50, 100, 100));
  hoverWidget.handleInput = true;
  hoverWidget.components.mouseEvent = new MouseEvent;
  hoverWidget.components.mouseEvent.mouseEnter = "hoverEnter";
  hoverWidget.components.mouseEvent.mouseMove = "hoverMove";
  hoverWidget.components.mouseEvent.mouseLeave = "hoverLeave";

  VisibleWidgets visHover = [
    VisibleWidget(hoverWidget, RectF(50, 50, 100, 100), false, RectF.init)
  ];

  auto motionIn = AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 60.0f, 70.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionIn, visHover);
  assert(testUi.sentEvents.length == 2);
  assert(testUi.sentEvents[0].view.eventName == "hoverEnter");
  assert(testUi.sentEvents[1].view.eventName == "hoverMove");
  auto enterVal = MouseEvent.AppEventViewValue.fromRaw(
    testUi.sentEvents[0].view.value
  );
  assert(enterVal.localX == 10.0f);
  assert(enterVal.localY == 20.0f);

  testUi.sentEvents = null;
  auto motionInside = AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 80.0f, 90.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionInside, visHover);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "hoverMove");

  testUi.sentEvents = null;
  auto motionOut = AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 200.0f, 200.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionOut, visHover);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "hoverLeave");

  // Disabled hover widget does NOT handle mouse motion
  testUi.sentEvents = null;
  hoverWidget.inputEnabled = false;
  inputSys.handleEventAndUpdateView(motionIn, visHover);
  inputSys.handleEventAndUpdateView(motionOut, visHover);
  assert(testUi.sentEvents.length == 0);
}

// Tests 11-12: Nested widgets hover hierarchy and clip rect exclusion.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto parentBox = fix.makeRootWithRect(RectF(0, 0, 200, 200));
  parentBox.handleInput = true;
  parentBox.components.mouseEvent = new MouseEvent;
  parentBox.components.mouseEvent.mouseEnter = "parentEnter";
  parentBox.components.mouseEvent.mouseMove = "parentMove";
  parentBox.components.mouseEvent.mouseLeave = "parentLeave";

  auto childBox = fix.makeChildWithRect(parentBox, RectF(50, 50, 50, 50));
  childBox.handleInput = true;
  childBox.components.mouseEvent = new MouseEvent;
  childBox.components.mouseEvent.mouseEnter = "childEnter";
  childBox.components.mouseEvent.mouseMove = "childMove";
  childBox.components.mouseEvent.mouseLeave = "childLeave";

  VisibleWidgets visNested = [
    VisibleWidget(parentBox, RectF(0, 0, 200, 200), false, RectF.init),
    VisibleWidget(childBox, RectF(50, 50, 50, 50), false, RectF.init)
  ];

  auto motionParent = AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 20.0f, 20.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionParent, visNested);
  assert(testUi.sentEvents.length == 2);
  assert(testUi.sentEvents[0].view.eventName == "parentEnter");

  testUi.sentEvents = null;
  auto motionChild = AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 60.0f, 60.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionChild, visNested);
  assert(testUi.sentEvents.length == 3);
  assert(testUi.sentEvents[0].view.eventName == "childEnter");
  assert(testUi.sentEvents[1].view.eventName == "childMove");
  assert(testUi.sentEvents[2].view.eventName == "parentMove");

  testUi.sentEvents = null;
  auto motionOut = AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 400.0f, 400.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionOut, visNested);
  assert(testUi.sentEvents.length == 2);
}

// Test 12: Clipped widget hit test exclusion.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto clippedWidget = fix.makeRootWithRect(RectF(0, 0, 100, 100));
  clippedWidget.handleInput = true;
  clippedWidget.components.mouseEvent = new MouseEvent;
  clippedWidget.components.mouseEvent.mouseEnter = "clipEnter";

  VisibleWidgets visClipped = [
    VisibleWidget(
      clippedWidget, RectF(0, 0, 100, 100), true, RectF(0, 0, 50, 50)
    )
  ];
  auto motionOutsideClip = AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 80.0f, 80.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionOutsideClip, visClipped);
  assert(testUi.sentEvents.length == 0);
}

// Tests 13-16: Z-order fall-through rules and mouse capture.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto underBtn = fix.makeRootWithRect(RectF(0, 0, 100, 50));
  underBtn.handleInput = true;
  underBtn.components.mouseEvent = new MouseEvent;
  underBtn.components.mouseEvent.mouseDown = "underDown";
  underBtn.components.mouseEvent.mouseUp = "underUp";

  auto plainPanel = fix.makeRootWithRect(RectF(0, 0, 100, 50));
  plainPanel.handleInput = true; // no *Event components

  VisibleWidgets visPanelOverBtn = [
    VisibleWidget(underBtn, RectF(0, 0, 100, 50), false, RectF.init),
    VisibleWidget(plainPanel, RectF(0, 0, 100, 50), false, RectF.init)
  ];

  auto downEv = AppEvent.mouseEvent(
    AppEvent.Kind.mouseButtonDown,
    AppEvent.MouseData(1, 20.0f, 20.0f, 0, 0, 0, 1, true, 1)
  );

  // T13: Plain enabled panel over button consumes silently
  inputSys.handleEventAndUpdateView(downEv, visPanelOverBtn);
  assert(testUi.sentEvents.length == 0);

  // T14: Disabled MouseEvent over enabled button consumes silently
  auto disabledBtn = fix.makeRootWithRect(RectF(0, 0, 100, 50));
  disabledBtn.handleInput = true;
  disabledBtn.inputEnabled = false;
  disabledBtn.components.mouseEvent = new MouseEvent;
  disabledBtn.components.mouseEvent.mouseDown = "disabledDown";
  VisibleWidgets visDisOverBtn = [
    VisibleWidget(underBtn, RectF(0, 0, 100, 50), false, RectF.init),
    VisibleWidget(disabledBtn, RectF(0, 0, 100, 50), false, RectF.init)
  ];
  testUi.sentEvents = null;
  inputSys.handleEventAndUpdateView(downEv, visDisOverBtn);
  assert(testUi.sentEvents.length == 0);

  // T15: Transparent child label (handleInput == false) inside button
  auto btnWithLabel = fix.makeRootWithRect(RectF(0, 0, 100, 50));
  btnWithLabel.handleInput = true;
  btnWithLabel.components.mouseEvent = new MouseEvent;
  btnWithLabel.components.mouseEvent.mouseDown = "labelParentDown";
  auto childLabel = fix.makeChildWithRect(btnWithLabel, RectF(10, 10, 30, 20));
  VisibleWidgets visLabelInBtn = [
    VisibleWidget(btnWithLabel, RectF(0, 0, 100, 50), false, RectF.init),
    VisibleWidget(childLabel, RectF(10, 10, 30, 20), false, RectF.init)
  ];
  testUi.sentEvents = null;
  inputSys.handleEventAndUpdateView(downEv, visLabelInBtn);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "labelParentDown");

  // T16: Down inside, up outside captured to pressed widget with inside=false
  testUi.sentEvents = null;
  VisibleWidgets visUnderOnly = [
    VisibleWidget(underBtn, RectF(0, 0, 100, 50), false, RectF.init)
  ];
  inputSys.handleEventAndUpdateView(downEv, visUnderOnly);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "underDown");

  testUi.sentEvents = null;
  auto upOutside = AppEvent.mouseEvent(
    AppEvent.Kind.mouseButtonUp,
    AppEvent.MouseData(1, 300.0f, 300.0f, 0, 0, 0, 1, false, 1)
  );
  inputSys.handleEventAndUpdateView(upOutside, visUnderOnly);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "underUp");
  auto upVal = MouseEvent.AppEventViewValue.fromRaw(
    testUi.sentEvents[0].view.value
  );
  assert(!upVal.inside);
  assert(upVal.localX == 300.0f);
}

// Verifies a disabled plain panel with handleInput over a button blocks the
// click: no events reach the button or the panel.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto underBtn = fix.makeRootWithRect(RectF(0, 0, 100, 50));
  underBtn.handleInput = true;
  underBtn.components.mouseEvent = new MouseEvent;
  underBtn.components.mouseEvent.mouseDown = "underDown";
  underBtn.components.mouseEvent.mouseUp = "underUp";
  underBtn.components.mouseEvent.mouseEnter = "underEnter";

  auto panel = fix.makeRootWithRect(RectF(0, 0, 100, 50));
  panel.handleInput = true;
  panel.inputEnabled = false;

  VisibleWidgets vis = [
    VisibleWidget(underBtn, RectF(0, 0, 100, 50), false, RectF.init),
    VisibleWidget(panel, RectF(0, 0, 100, 50), false, RectF.init)
  ];

  inputSys.handleEventAndUpdateView(
    AppEvent.mouseEvent(
      AppEvent.Kind.mouseMotion,
      AppEvent.MouseData(1, 20.0f, 20.0f, 0, 0, 0, 0, false, 0)
    ),
    vis
  );
  inputSys.handleEventAndUpdateView(
    AppEvent.mouseEvent(
      AppEvent.Kind.mouseButtonDown,
      AppEvent.MouseData(1, 20.0f, 20.0f, 0, 0, 0, 1, true, 1)
    ),
    vis
  );
  inputSys.handleEventAndUpdateView(
    AppEvent.mouseEvent(
      AppEvent.Kind.mouseButtonUp,
      AppEvent.MouseData(1, 20.0f, 20.0f, 0, 0, 0, 1, false, 1)
    ),
    vis
  );
  assert(testUi.sentEvents.length == 0);
}

// Verifies a widget with a MouseEvent but handleInput == false is not hit:
// the click and hover reach the hittable widget below it.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto underBtn = fix.makeRootWithRect(RectF(0, 0, 100, 50));
  underBtn.handleInput = true;
  underBtn.components.mouseEvent = new MouseEvent;
  underBtn.components.mouseEvent.mouseDown = "underDown";
  underBtn.components.mouseEvent.mouseEnter = "underEnter";

  auto overW = fix.makeRootWithRect(RectF(0, 0, 100, 50));
  assert(!overW.handleInput);
  overW.components.mouseEvent = new MouseEvent;
  overW.components.mouseEvent.mouseDown = "overDown";
  overW.components.mouseEvent.mouseEnter = "overEnter";

  VisibleWidgets vis = [
    VisibleWidget(underBtn, RectF(0, 0, 100, 50), false, RectF.init),
    VisibleWidget(overW, RectF(0, 0, 100, 50), false, RectF.init)
  ];

  inputSys.handleEventAndUpdateView(
    AppEvent.mouseEvent(
      AppEvent.Kind.mouseMotion,
      AppEvent.MouseData(1, 20.0f, 20.0f, 0, 0, 0, 0, false, 0)
    ),
    vis
  );
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "underEnter");

  testUi.sentEvents = null;
  inputSys.handleEventAndUpdateView(
    AppEvent.mouseEvent(
      AppEvent.Kind.mouseButtonDown,
      AppEvent.MouseData(1, 20.0f, 20.0f, 0, 0, 0, 1, true, 1)
    ),
    vis
  );
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "underDown");
}

// Tests 17-20: Up without down, down on A up on B, and updateParentViews.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto btnA = fix.makeRootWithRect(RectF(0, 0, 50, 50));
  btnA.handleInput = true;
  btnA.components.mouseEvent = new MouseEvent;
  btnA.components.mouseEvent.mouseDown = "aDown";
  btnA.components.mouseEvent.mouseUp = "aUp";

  auto btnB = fix.makeRootWithRect(RectF(60, 0, 50, 50));
  btnB.handleInput = true;
  btnB.components.mouseEvent = new MouseEvent;
  btnB.components.mouseEvent.mouseDown = "bDown";
  btnB.components.mouseEvent.mouseUp = "bUp";

  VisibleWidgets visAB = [
    VisibleWidget(btnA, RectF(0, 0, 50, 50), false, RectF.init),
    VisibleWidget(btnB, RectF(60, 0, 50, 50), false, RectF.init)
  ];

  // T17: Up without prior down produces nothing
  auto upEvA = AppEvent.mouseEvent(
    AppEvent.Kind.mouseButtonUp,
    AppEvent.MouseData(1, 10.0f, 10.0f, 0, 0, 0, 1, false, 1)
  );
  inputSys.handleEventAndUpdateView(upEvA, visAB);
  assert(testUi.sentEvents.length == 0);

  // T18: Down on A, up over B routes up to A
  auto downEvA = AppEvent.mouseEvent(
    AppEvent.Kind.mouseButtonDown,
    AppEvent.MouseData(1, 10.0f, 10.0f, 0, 0, 0, 1, true, 1)
  );
  inputSys.handleEventAndUpdateView(downEvA, visAB);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "aDown");

  testUi.sentEvents = null;
  auto upEvOverB = AppEvent.mouseEvent(
    AppEvent.Kind.mouseButtonUp,
    AppEvent.MouseData(1, 70.0f, 10.0f, 0, 0, 0, 1, false, 1)
  );
  inputSys.handleEventAndUpdateView(upEvOverB, visAB);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "aUp");

  // T20: View attached after child creation + update(parentView) works
  testUi.sentEvents = null;
  auto fix2 = new WidgetFixture();
  auto parentRoot = fix2.makeRootWithRect(RectF(0, 0, 200, 200));
  auto childW = fix2.makeChildWithRect(parentRoot, RectF(10, 10, 50, 50));
  parentRoot.components.view = new ViewComponent;
  parentRoot.components.view.renameEvents["childClick"] = "renamedClick";
  parentRoot.update(WidgetUpdateScope.parentView);

  auto childEv = ViewAppEventBuilder("childClick")
    .widget(childW)
    .value(1)
    .build();
  passViewEvent(testUi, childW, childEv);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "renamedClick");
}

// Tests 21-25: refreshHover, transparent overlay, and KeyboardEvent-only
// widget transparency (no handleInput).
unittest {
  import yguilib.widget.input_components : KeyboardEvent;
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto movingBtn = fix.makeRootWithRect(RectF(0, 0, 100, 100));
  movingBtn.handleInput = true;
  movingBtn.components.mouseEvent = new MouseEvent;
  movingBtn.components.mouseEvent.mouseEnter = "btnEnter";
  movingBtn.components.mouseEvent.mouseLeave = "btnLeave";

  VisibleWidgets visInitial = [
    VisibleWidget(movingBtn, RectF(0, 0, 100, 100), false, RectF.init)
  ];

  auto motion = AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 50.0f, 50.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motion, visInitial);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "btnEnter");

  // T22: refreshHover dispatches mouseLeave when widget moves away
  testUi.sentEvents = null;
  VisibleWidgets visMovedAway = [
    VisibleWidget(movingBtn, RectF(200, 200, 100, 100), false, RectF.init)
  ];
  inputSys.refreshHover(visMovedAway);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "btnLeave");

  // T24: Transparent overlay passes hover through to underlying widget
  testUi.sentEvents = null;
  auto overlay = fix.makeRootWithRect(RectF(0, 0, 100, 100));
  // transparent: handleInput is false by default
  VisibleWidgets visOverlay = [
    VisibleWidget(movingBtn, RectF(0, 0, 100, 100), false, RectF.init),
    VisibleWidget(overlay, RectF(0, 0, 100, 100), false, RectF.init)
  ];
  inputSys.handleEventAndUpdateView(motion, visOverlay);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "btnEnter");

  // T25: KeyboardEvent-only widget over button passes clicks through
  // because it is not hittable (handleInput == false); handleInput covers
  // pointer input only.
  testUi.sentEvents = null;
  auto kbWidget = fix.makeRootWithRect(RectF(0, 0, 100, 100));
  kbWidget.components.keyboardEvent = new KeyboardEvent;
  movingBtn.components.mouseEvent.mouseDown = "btnDown";

  VisibleWidgets visKbOverBtn = [
    VisibleWidget(movingBtn, RectF(0, 0, 100, 100), false, RectF.init),
    VisibleWidget(kbWidget, RectF(0, 0, 100, 100), false, RectF.init)
  ];
  auto downEv = AppEvent.mouseEvent(
    AppEvent.Kind.mouseButtonDown,
    AppEvent.MouseData(1, 50.0f, 50.0f, 0, 0, 0, 1, true, 1)
  );
  inputSys.handleEventAndUpdateView(downEv, visKbOverBtn);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "btnDown");
}

// Verifies InputSystem WidgetSystem priority, phases, and phase entry points.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  assert(inputSys.priority == WidgetSystem.inputSystemPriority);
  assert(inputSys.phases == (SystemPhase.event | SystemPhase.postLayout));

  WidgetSystemContext ctx;
  ctx.host = testUi;
  auto btn = fix.makeRootWithRect(RectF(0, 0, 100, 100));
  btn.handleInput = true;
  ctx.visibleWidgets = [
    VisibleWidget(btn, RectF(0, 0, 100, 100), false, RectF.init)
  ];

  auto motion = AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(0, 50.0f, 50.0f, 0, 0, 0, 0, false, 0)
  );

  auto res = inputSys.handleEvent(motion, ctx);
  assert(!res.consumed);
  assert(!res.requestUpdateView);

  // postLayout triggers refreshHover
  inputSys.postLayout(ctx);
}

// Verifies windowMouseLeave dispatches mouseLeave and clears hover state.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto parentBox = fix.makeRootWithRect(RectF(0, 0, 200, 200));
  parentBox.handleInput = true;
  parentBox.components.mouseEvent = new MouseEvent;
  parentBox.components.mouseEvent.mouseEnter = "parentEnter";
  parentBox.components.mouseEvent.mouseLeave = "parentLeave";

  auto childBox = fix.makeChildWithRect(parentBox, RectF(50, 50, 50, 50));
  childBox.handleInput = true;
  childBox.components.mouseEvent = new MouseEvent;
  childBox.components.mouseEvent.mouseEnter = "childEnter";
  childBox.components.mouseEvent.mouseLeave = "childLeave";

  VisibleWidgets vis = [
    VisibleWidget(parentBox, RectF(0, 0, 200, 200), false, RectF.init),
    VisibleWidget(childBox, RectF(50, 50, 50, 50), false, RectF.init)
  ];

  auto motionIn = AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 60.0f, 70.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionIn, vis);
  assert(testUi.sentEvents.length == 2);
  assert(testUi.sentEvents[0].view.eventName == "childEnter");
  assert(testUi.sentEvents[1].view.eventName == "parentEnter");

  testUi.sentEvents = null;
  auto winLeave = AppEvent.windowEvent(
    AppEvent.Kind.windowMouseLeave,
    AppEvent.WindowData(1)
  );
  inputSys.handleEventAndUpdateView(winLeave, vis);
  assert(testUi.sentEvents.length == 2);
  assert(testUi.sentEvents[0].view.eventName == "childLeave");
  assert(testUi.sentEvents[1].view.eventName == "parentLeave");
  auto childLeaveVal = MouseEvent.AppEventViewValue.fromRaw(
    testUi.sentEvents[0].view.value
  );
  assert(!childLeaveVal.inside);
  assert(childLeaveVal.localX == 10.0f);
  assert(childLeaveVal.localY == 20.0f);

  // refreshHover while outside window should not re-hover
  testUi.sentEvents = null;
  inputSys.refreshHover(vis);
  assert(testUi.sentEvents.length == 0);

  // windowMouseEnter does not re-hover at stale position before mouseMotion
  auto winEnter = AppEvent.windowEvent(
    AppEvent.Kind.windowMouseEnter,
    AppEvent.WindowData(1)
  );
  inputSys.handleEventAndUpdateView(winEnter, vis);
  assert(testUi.sentEvents.length == 0);

  // Re-entering with mouseMotion dispatches mouseEnter again
  inputSys.handleEventAndUpdateView(motionIn, vis);
  assert(testUi.sentEvents.length == 2);
  assert(testUi.sentEvents[0].view.eventName == "childEnter");
  assert(testUi.sentEvents[1].view.eventName == "parentEnter");
}

// Verifies mouseDrag delivery inside/outside bounds and cursor capture state.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto dragBox = fix.makeRootWithRect(RectF(20, 30, 80, 40));
  dragBox.handleInput = true;
  dragBox.components.mouseEvent = new MouseEvent;
  dragBox.components.mouseEvent.mouseDown = "dragDown";
  dragBox.components.mouseEvent.mouseDrag = "dragMove";
  dragBox.components.mouseEvent.mouseUp = "dragUp";
  dragBox.components.mouseEvent.cursorCapture = CursorCapture.capture;

  VisibleWidgets vis = [
    VisibleWidget(dragBox, RectF(20, 30, 80, 40), false, RectF.init)
  ];

  // Press inside dragBox activates cursor capture
  assert(!inputSys.isCursorCaptured);
  auto downEv = AppEvent.mouseEvent(
    AppEvent.Kind.mouseButtonDown,
    AppEvent.MouseData(1, 50.0f, 45.0f, 0, 0, 0, 1, true, 1)
  );
  inputSys.handleEventAndUpdateView(downEv, vis);
  assert(inputSys.isCursorCaptured);
  assert(!inputSys.isCursorLocked);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "dragDown");
  auto downVal = MouseEvent.AppEventViewValue.fromRaw(
    testUi.sentEvents[0].view.value
  );
  assert(downVal.windowX == 50.0f);
  assert(downVal.windowY == 45.0f);

  // Dragging outside widget bounds still emits mouseDrag with window & rel
  testUi.sentEvents = null;
  auto dragOutsideEv = AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 220.0f, 15.0f, 1, 170.0f, -30.0f, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(dragOutsideEv, vis);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "dragMove");
  auto dragVal = MouseEvent.AppEventViewValue.fromRaw(
    testUi.sentEvents[0].view.value
  );
  assert(dragVal.buttons == 1);
  assert(!dragVal.inside);
  assert(dragVal.localX == 200.0f);
  assert(dragVal.localY == -15.0f);
  assert(dragVal.relX == 170.0f);
  assert(dragVal.relY == -30.0f);
  assert(dragVal.windowX == 220.0f);
  assert(dragVal.windowY == 15.0f);

  // Releasing outside releases cursor capture and fires mouseUp
  testUi.sentEvents = null;
  auto upOutsideEv = AppEvent.mouseEvent(
    AppEvent.Kind.mouseButtonUp,
    AppEvent.MouseData(1, 220.0f, 15.0f, 0, 0, 0, 1, false, 1)
  );
  inputSys.handleEventAndUpdateView(upOutsideEv, vis);
  assert(!inputSys.isCursorCaptured);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "dragUp");

  // Releasing widget mid-drag also clears cursor capture
  inputSys.handleEventAndUpdateView(downEv, vis);
  assert(inputSys.isCursorCaptured);
  inputSys.onWidgetReleased(dragBox);
  assert(!inputSys.isCursorCaptured);
}

// Verifies CursorCapture.lock: frozen position, relative deltas, no hover
// changes while locked, and unlock on mouseUp / widget release.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto knob = fix.makeRootWithRect(RectF(20, 30, 80, 40));
  knob.handleInput = true;
  knob.components.mouseEvent = new MouseEvent;
  knob.components.mouseEvent.mouseDown = "knobDown";
  knob.components.mouseEvent.mouseDrag = "knobDrag";
  knob.components.mouseEvent.mouseUp = "knobUp";
  knob.components.mouseEvent.cursorCapture = CursorCapture.lock;

  auto other = fix.makeRootWithRect(RectF(200, 200, 50, 50));
  other.handleInput = true;
  other.components.mouseEvent = new MouseEvent;
  other.components.mouseEvent.mouseEnter = "otherEnter";

  VisibleWidgets vis = [
    VisibleWidget(knob, RectF(20, 30, 80, 40), false, RectF.init),
    VisibleWidget(other, RectF(200, 200, 50, 50), false, RectF.init)
  ];

  auto downEv = AppEvent.mouseEvent(
    AppEvent.Kind.mouseButtonDown,
    AppEvent.MouseData(1, 50.0f, 45.0f, 0, 0, 0, 1, true, 1)
  );
  assert(!inputSys.isCursorLocked);
  inputSys.handleEventAndUpdateView(downEv, vis);
  assert(inputSys.isCursorLocked);
  assert(inputSys.isCursorCaptured);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "knobDown");

  // Motion over `other` with deltas: drag stays at press point, no enter
  testUi.sentEvents = null;
  inputSys.handleEventAndUpdateView(
    AppEvent.mouseEvent(
      AppEvent.Kind.mouseMotion,
      AppEvent.MouseData(1, 220.0f, 220.0f, 1, 7.0f, -3.0f, 0, false, 0)
    ),
    vis
  );
  inputSys.handleEventAndUpdateView(
    AppEvent.mouseEvent(
      AppEvent.Kind.mouseMotion,
      AppEvent.MouseData(1, 900.0f, -50.0f, 1, -2.0f, 11.0f, 0, false, 0)
    ),
    vis
  );
  assert(testUi.sentEvents.length == 2);
  foreach (idx, ref ev; testUi.sentEvents) {
    assert(ev.view.eventName == "knobDrag");
    auto v = MouseEvent.AppEventViewValue.fromRaw(ev.view.value);
    assert(v.windowX == 50.0f && v.windowY == 45.0f);
    assert(v.localX == 30.0f && v.localY == 15.0f);
    assert(v.inside);
    if (idx == 0) {
      assert(v.relX == 7.0f && v.relY == -3.0f);
    } else {
      assert(v.relX == -2.0f && v.relY == 11.0f);
    }
  }

  // mouseUp at an arbitrary position: unlocked, payload at press point
  testUi.sentEvents = null;
  inputSys.handleEventAndUpdateView(
    AppEvent.mouseEvent(
      AppEvent.Kind.mouseButtonUp,
      AppEvent.MouseData(1, 900.0f, -50.0f, 0, 0, 0, 1, false, 1)
    ),
    vis
  );
  assert(!inputSys.isCursorLocked);
  assert(!inputSys.isCursorCaptured);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "knobUp");
  auto upVal = MouseEvent.AppEventViewValue.fromRaw(
    testUi.sentEvents[0].view.value
  );
  assert(upVal.windowX == 50.0f && upVal.windowY == 45.0f);
  assert(upVal.localX == 30.0f && upVal.localY == 15.0f);
  assert(upVal.inside);

  // Releasing the locked widget mid-drag clears the lock
  inputSys.handleEventAndUpdateView(downEv, vis);
  assert(inputSys.isCursorLocked);
  inputSys.onWidgetReleased(knob);
  assert(!inputSys.isCursorLocked);
  assert(!inputSys.isCursorCaptured);
}

// Verifies a disabled locked widget drops the lock on the next motion.
unittest {
  import yguilib.widget.test_fixture : WidgetFixture;

  auto fix = new WidgetFixture();
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto knob = fix.makeRootWithRect(RectF(0, 0, 50, 50));
  knob.handleInput = true;
  knob.components.mouseEvent = new MouseEvent;
  knob.components.mouseEvent.mouseDrag = "knobDrag";
  knob.components.mouseEvent.cursorCapture = CursorCapture.lock;
  VisibleWidgets vis = [
    VisibleWidget(knob, RectF(0, 0, 50, 50), false, RectF.init)
  ];

  inputSys.handleEventAndUpdateView(
    AppEvent.mouseEvent(
      AppEvent.Kind.mouseButtonDown,
      AppEvent.MouseData(1, 10.0f, 10.0f, 0, 0, 0, 1, true, 1)
    ),
    vis
  );
  assert(inputSys.isCursorLocked);
  knob.inputEnabled = false;
  testUi.sentEvents = null;
  inputSys.handleEventAndUpdateView(
    AppEvent.mouseEvent(
      AppEvent.Kind.mouseMotion,
      AppEvent.MouseData(1, 10.0f, 10.0f, 1, 4.0f, 0.0f, 0, false, 0)
    ),
    vis
  );
  assert(testUi.sentEvents.length == 0);
  assert(!inputSys.isCursorLocked);
  assert(!inputSys.isCursorCaptured);
}
