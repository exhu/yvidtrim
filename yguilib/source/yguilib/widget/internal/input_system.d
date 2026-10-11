module yguilib.widget.internal.input_system;

package(yguilib):

import std.algorithm.searching : canFind;
import yguilib.widget.internal.focus_system;
import yguilib.widget.internal.collect_visible : VisibleWidgets, VisibleWidget;
import yguilib.events;
import yguilib.events.builder : ViewAppEventBuilder;
import yguilib.uisystem : UiSystem;
import yguilib.render.render_types;
import yguilib.widget : Widget, View;
import yguilib.widget.input_components : MouseEvent;

enum maxMouseButtons = 8;

struct HoverEntry {
  Widget widget;
  RectF absRect;
}

// TODO support multiple windows
final class InputSystem {
  this(UiSystem uiSystem) {
    assert(uiSystem !is null);
    this.uiSystem = uiSystem;
    this.focusSystem = new FocusSystem;
  }

  invariant {
    assert(uiSystem !is null);
    assert(focusSystem !is null);
  }

  /// Handles incoming input events.
  /// Returns true if the view needs updating (e.g. when focus changes).
  bool handleEventAndUpdateView(AppEvent event, VisibleWidgets widgets) {
    if (!event.isKeyboardEvent() && !event.isMouseEvent())
      return false;
    // TODO call to focus system
    if (event.isMouseEvent()) {
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
      if (w.components.mouseEvent !is null) {
        if (!w.inputEnabled)
          return;

        if (btn < maxMouseButtons)
          pressedWidgets[btn] = w;

        if (w.components.mouseEvent.mouseDown.length > 0) {
          const float lx = p.x - vw.absRect.x;
          const float ly = p.y - vw.absRect.y;
          auto val = MouseEvent.AppEventViewValue(lx, ly, btn, true);
          sendMouseEvent(w, w.components.mouseEvent.mouseDown, val);
        }
        return;
      }

      if (w.components.keyboardEvent !is null)
        continue;

      if (w.inputEnabled)
        return;
    }
  }

  void handleMouseUp(PointF p, ubyte btn, VisibleWidgets widgets) {
    if (btn >= maxMouseButtons || pressedWidgets[btn] is null)
      return;

    Widget target = pressedWidgets[btn];
    pressedWidgets[btn] = null;

    if (!target.inputEnabled)
      return;

    if (target.components.mouseEvent is null ||
        target.components.mouseEvent.mouseUp.length == 0)
      return;

    RectF targetRect = target.rect;
    bool inside = false;
    const idx = findVisibleWidgetIndex(widgets, target);
    if (idx >= 0) {
      targetRect = widgets[idx].absRect;
      inside = isHit(widgets[idx], p);
    } else {
      targetRect = computeWidgetAbsRect(target);
      inside = targetRect.contains(p);
    }

    const float lx = p.x - targetRect.x;
    const float ly = p.y - targetRect.y;
    auto val = MouseEvent.AppEventViewValue(lx, ly, btn, inside);
    sendMouseEvent(target, target.components.mouseEvent.mouseUp, val);
  }

  // NOTE: possible future optimizations (not needed at current widget counts):
  // - skip hit testing when cursor position and the widgets slice
  //   (ptr, length) are unchanged since the last motion event;
  // - build a uniform-grid spatial index in collectVisible for O(1)
  //   hit-test candidates when thousands of widgets are visible.
  void handleMouseMotion(in AppEvent event, VisibleWidgets widgets) {
    const p = PointF(event.mouse.x, event.mouse.y);
    lastMousePos = p;
    hasLastMousePos = true;
    updateHoverState(p, widgets, true);
  }

  // NOTE: no mouseLeave is sent when cursor leaves window because
  // window-leave AppEvent.Kind is not yet available.
  // NOTE: a widget disabled while hovered does not receive mouseLeave;
  // its controller should clear hover visuals upon disabling.
  void updateHoverState(PointF p, VisibleWidgets widgets, bool sendMove) {
    collectHovered(widgets, p);
    notifyDepartedWidgets(p);
    notifyEnteredAndMovedWidgets(p, sendMove);

    auto temp = hoveredWidgets;
    hoveredWidgets = hoverScratch;
    hoverScratch = temp;
  }

  void collectHovered(VisibleWidgets widgets, PointF p) {
    hoverScratch.length = 0;
    hoverScratch.assumeSafeAppend();

    const topIdx = findHoverTargetIndex(widgets, p);
    if (topIdx < 0)
      return;

    Widget want = widgets[topIdx].widget;
    foreach_reverse (i; 0 .. topIdx + 1) {
      if (widgets[i].widget !is want)
        continue;
      if (isHit(widgets[i], p)) {
        if (want.inputEnabled && want.components.mouseEvent !is null) {
          hoverScratch ~= HoverEntry(want, widgets[i].absRect);
        }
      }
      want = want.parent;
      if (want is null)
        break;
    }
  }

  void notifyDepartedWidgets(PointF p) {
    foreach (ref entry; hoveredWidgets) {
      if (!containsWidget(hoverScratch, entry.widget)) {
        if (entry.widget.components.mouseEvent !is null &&
            entry.widget.components.mouseEvent.mouseLeave.length > 0) {
          const float lx = p.x - entry.absRect.x;
          const float ly = p.y - entry.absRect.y;
          auto val = MouseEvent.AppEventViewValue(lx, ly, 0, false);
          sendMouseEvent(
            entry.widget, entry.widget.components.mouseEvent.mouseLeave, val
          );
        }
      }
    }
  }

  void notifyEnteredAndMovedWidgets(PointF p, bool sendMove) {
    foreach (ref entry; hoverScratch) {
      if (entry.widget.components.mouseEvent is null)
        continue;

      const wasHovered = containsWidget(hoveredWidgets, entry.widget);
      const float lx = p.x - entry.absRect.x;
      const float ly = p.y - entry.absRect.y;
      auto val = MouseEvent.AppEventViewValue(lx, ly, 0, true);

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
      .value(val)
      .build();
    passEvent(w, ev);
  }

  void passEvent(Widget w, AppEvent event) {
    if (w !is null && w.components.view !is null) {
      if (applyViewRenaming(w, event))
        return;
    }

    for (Widget pv = (w !is null ? w.parentView : null);
         pv !is null;
         pv = pv.parentView) {
      if (applyViewRenaming(pv, event))
        return;
    }

    uiSystem.sendAppEvent(event);
  }

  bool applyViewRenaming(Widget viewWidget, ref AppEvent event) {
    if (viewWidget.components.view is null)
      return false;

    const string currentName = event.view.eventName;
    auto pNewName = currentName in viewWidget.components.view.renameEvents;
    if (pNewName !is null) {
      if ((*pNewName).length == 0)
        return true;
      event.view.eventName = *pNewName;
      event.view.viewWidget = viewWidget;
    }
    return false;
  }

  HoverEntry[] hoveredWidgets;
  HoverEntry[] hoverScratch;
  Widget[maxMouseButtons] pressedWidgets;
  PointF lastMousePos;
  bool hasLastMousePos = false;
  FocusSystem focusSystem;
  UiSystem uiSystem;
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
    Widget w = vw.widget;
    if (w.components.mouseEvent !is null)
      return idx;
    if (w.components.keyboardEvent !is null)
      continue;
    if (w.inputEnabled)
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
  import yguilib.controller : Controller;
  import yguilib.window : Window;

  class TestUiSystem : UiSystem {
    AppEvent[] sentEvents;
    override void sendAppEvent(AppEvent ev) {
      sentEvents ~= ev;
    }
    override void popController() {}
    override void pushController(Controller c) {}
    override void pushModalController(Controller c) {}
    override void popFocusRoot() {}
    override void pushFocusRoot(Widget w) {}
    override @property Window mainWindow() { return null; }
    override void mainEventLoop() {}
  }
}

// Tests 1-3: Direct passthrough, single view renaming, and event suppression.
unittest {
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto rootNoView = new Widget(null, RectF(0, 0, 200, 200));
  auto childNoView = new Widget(rootNoView, RectF(0, 0, 50, 50));
  auto ev1 = ViewAppEventBuilder("rawClick", childNoView).value(1).build();
  inputSys.passEvent(childNoView, ev1);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "rawClick");
  assert(testUi.sentEvents[0].view.widget is childNoView);
  assert(testUi.sentEvents[0].view.viewWidget is null);

  testUi.sentEvents = null;
  auto rootView = new Widget(null, RectF(0, 0, 200, 200));
  rootView.components.view = new View;
  rootView.components.view.renameEvents["btnClick"] = "playVideo";
  auto childBtn = new Widget(rootView, RectF(0, 0, 50, 50));
  auto ev2 = ViewAppEventBuilder("btnClick", childBtn).value(1).build();
  inputSys.passEvent(childBtn, ev2);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "playVideo");
  assert(testUi.sentEvents[0].view.widget is childBtn);
  assert(testUi.sentEvents[0].view.viewWidget is rootView);

  testUi.sentEvents = null;
  rootView.components.view.renameEvents["suppressMe"] = "";
  auto ev3 = ViewAppEventBuilder("suppressMe", childBtn).value(1).build();
  inputSys.passEvent(childBtn, ev3);
  assert(testUi.sentEvents.length == 0);
}

// Tests 4-6: Nested views chaining, unmapped passthrough, and self view.
unittest {
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto outerView = new Widget(null, RectF(0, 0, 400, 400));
  outerView.components.view = new View;
  outerView.components.view.renameEvents["itemSelected"] = "orderUpdated";

  auto innerView = new Widget(outerView, RectF(0, 0, 200, 200));
  innerView.components.view = new View;
  innerView.components.view.renameEvents["click"] = "itemSelected";

  auto nestedBtn = new Widget(innerView, RectF(0, 0, 50, 50));
  auto ev4 = ViewAppEventBuilder("click", nestedBtn).value(1).build();
  inputSys.passEvent(nestedBtn, ev4);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "orderUpdated");
  assert(testUi.sentEvents[0].view.viewWidget is outerView);

  testUi.sentEvents = null;
  auto ev5 = ViewAppEventBuilder("unmappedInInner", nestedBtn).value(1).build();
  outerView.components.view.renameEvents["unmappedInInner"] = "handledByOuter";
  inputSys.passEvent(nestedBtn, ev5);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "handledByOuter");

  testUi.sentEvents = null;
  auto selfView = new Widget(null, RectF(0, 0, 100, 100));
  selfView.components.view = new View;
  selfView.components.view.renameEvents["panelClick"] = "openPanel";
  auto ev6 = ViewAppEventBuilder("panelClick", selfView).value(1).build();
  inputSys.passEvent(selfView, ev6);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "openPanel");
}

// Tests 7-8: Mouse down and up with local coords and inputEnabled check.
unittest {
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto btnWidget = new Widget(null, RectF(10, 10, 100, 50));
  btnWidget.inputEnabled = true;
  btnWidget.components.mouseEvent = new MouseEvent;
  btnWidget.components.mouseEvent.mouseDown = "btnDown";
  btnWidget.components.mouseEvent.mouseUp = "btnUp";

  VisibleWidgets visBtn = [
    VisibleWidget(btnWidget, RectF(10, 10, 100, 50), false, RectF.init)
  ];

  auto downEv = AppEvent(
    AppEvent.Kind.mouseButtonDown,
    AppEvent.MouseData(1, 20.0f, 30.0f, 0, 0, 0, 1, true, 1)
  );
  inputSys.handleEventAndUpdateView(downEv, visBtn);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "btnDown");
  auto downVal = MouseEvent.AppEventViewValue(testUi.sentEvents[0].view.value);
  assert(downVal.buttons == 1);
  assert(downVal.localX == 10.0f);
  assert(downVal.localY == 20.0f);
  assert(downVal.inside);

  testUi.sentEvents = null;
  auto upEv = AppEvent(
    AppEvent.Kind.mouseButtonUp,
    AppEvent.MouseData(1, 25.0f, 35.0f, 0, 0, 0, 1, false, 1)
  );
  inputSys.handleEventAndUpdateView(upEv, visBtn);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "btnUp");
  auto upVal = MouseEvent.AppEventViewValue(testUi.sentEvents[0].view.value);
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
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto hoverWidget = new Widget(null, RectF(50, 50, 100, 100));
  hoverWidget.inputEnabled = true;
  hoverWidget.components.mouseEvent = new MouseEvent;
  hoverWidget.components.mouseEvent.mouseEnter = "hoverEnter";
  hoverWidget.components.mouseEvent.mouseMove = "hoverMove";
  hoverWidget.components.mouseEvent.mouseLeave = "hoverLeave";

  VisibleWidgets visHover = [
    VisibleWidget(hoverWidget, RectF(50, 50, 100, 100), false, RectF.init)
  ];

  auto motionIn = AppEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 60.0f, 70.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionIn, visHover);
  assert(testUi.sentEvents.length == 2);
  assert(testUi.sentEvents[0].view.eventName == "hoverEnter");
  assert(testUi.sentEvents[1].view.eventName == "hoverMove");
  auto enterVal = MouseEvent.AppEventViewValue(testUi.sentEvents[0].view.value);
  assert(enterVal.localX == 10.0f);
  assert(enterVal.localY == 20.0f);

  testUi.sentEvents = null;
  auto motionInside = AppEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 80.0f, 90.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionInside, visHover);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "hoverMove");

  testUi.sentEvents = null;
  auto motionOut = AppEvent(
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
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto parentBox = new Widget(null, RectF(0, 0, 200, 200));
  parentBox.inputEnabled = true;
  parentBox.components.mouseEvent = new MouseEvent;
  parentBox.components.mouseEvent.mouseEnter = "parentEnter";
  parentBox.components.mouseEvent.mouseMove = "parentMove";
  parentBox.components.mouseEvent.mouseLeave = "parentLeave";

  auto childBox = new Widget(parentBox, RectF(50, 50, 50, 50));
  childBox.inputEnabled = true;
  childBox.components.mouseEvent = new MouseEvent;
  childBox.components.mouseEvent.mouseEnter = "childEnter";
  childBox.components.mouseEvent.mouseMove = "childMove";
  childBox.components.mouseEvent.mouseLeave = "childLeave";

  VisibleWidgets visNested = [
    VisibleWidget(parentBox, RectF(0, 0, 200, 200), false, RectF.init),
    VisibleWidget(childBox, RectF(50, 50, 50, 50), false, RectF.init)
  ];

  auto motionParent = AppEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 20.0f, 20.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionParent, visNested);
  assert(testUi.sentEvents.length == 2);
  assert(testUi.sentEvents[0].view.eventName == "parentEnter");

  testUi.sentEvents = null;
  auto motionChild = AppEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 60.0f, 60.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionChild, visNested);
  assert(testUi.sentEvents.length == 3);
  assert(testUi.sentEvents[0].view.eventName == "childEnter");
  assert(testUi.sentEvents[1].view.eventName == "childMove");
  assert(testUi.sentEvents[2].view.eventName == "parentMove");

  testUi.sentEvents = null;
  auto motionOut = AppEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 400.0f, 400.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionOut, visNested);
  assert(testUi.sentEvents.length == 2);
}

// Test 12: Clipped widget hit test exclusion.
unittest {
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto clippedWidget = new Widget(null, RectF(0, 0, 100, 100));
  clippedWidget.inputEnabled = true;
  clippedWidget.components.mouseEvent = new MouseEvent;
  clippedWidget.components.mouseEvent.mouseEnter = "clipEnter";

  VisibleWidgets visClipped = [
    VisibleWidget(
      clippedWidget, RectF(0, 0, 100, 100), true, RectF(0, 0, 50, 50)
    )
  ];
  auto motionOutsideClip = AppEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 80.0f, 80.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionOutsideClip, visClipped);
  assert(testUi.sentEvents.length == 0);
}

// Tests 13-16: Z-order fall-through rules and mouse capture.
unittest {
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto underBtn = new Widget(null, RectF(0, 0, 100, 50));
  underBtn.inputEnabled = true;
  underBtn.components.mouseEvent = new MouseEvent;
  underBtn.components.mouseEvent.mouseDown = "underDown";
  underBtn.components.mouseEvent.mouseUp = "underUp";

  auto plainPanel = new Widget(null, RectF(0, 0, 100, 50));
  plainPanel.inputEnabled = true; // no *Event components

  VisibleWidgets visPanelOverBtn = [
    VisibleWidget(underBtn, RectF(0, 0, 100, 50), false, RectF.init),
    VisibleWidget(plainPanel, RectF(0, 0, 100, 50), false, RectF.init)
  ];

  auto downEv = AppEvent(
    AppEvent.Kind.mouseButtonDown,
    AppEvent.MouseData(1, 20.0f, 20.0f, 0, 0, 0, 1, true, 1)
  );

  // T13: Plain enabled panel over button consumes silently
  inputSys.handleEventAndUpdateView(downEv, visPanelOverBtn);
  assert(testUi.sentEvents.length == 0);

  // T14: Disabled MouseEvent over enabled button consumes silently
  auto disabledBtn = new Widget(null, RectF(0, 0, 100, 50));
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

  // T15: Transparent child label without components inside button
  auto btnWithLabel = new Widget(null, RectF(0, 0, 100, 50));
  btnWithLabel.inputEnabled = true;
  btnWithLabel.components.mouseEvent = new MouseEvent;
  btnWithLabel.components.mouseEvent.mouseDown = "labelParentDown";
  auto childLabel = new Widget(btnWithLabel, RectF(10, 10, 30, 20));
  childLabel.inputEnabled = false;
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
  auto upOutside = AppEvent(
    AppEvent.Kind.mouseButtonUp,
    AppEvent.MouseData(1, 300.0f, 300.0f, 0, 0, 0, 1, false, 1)
  );
  inputSys.handleEventAndUpdateView(upOutside, visUnderOnly);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "underUp");
  auto upVal = MouseEvent.AppEventViewValue(testUi.sentEvents[0].view.value);
  assert(!upVal.inside);
  assert(upVal.localX == 300.0f);
}

// Tests 17-20: Up without down, down on A up on B, and updateParentViews.
unittest {
  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto btnA = new Widget(null, RectF(0, 0, 50, 50));
  btnA.inputEnabled = true;
  btnA.components.mouseEvent = new MouseEvent;
  btnA.components.mouseEvent.mouseDown = "aDown";
  btnA.components.mouseEvent.mouseUp = "aUp";

  auto btnB = new Widget(null, RectF(60, 0, 50, 50));
  btnB.inputEnabled = true;
  btnB.components.mouseEvent = new MouseEvent;
  btnB.components.mouseEvent.mouseDown = "bDown";
  btnB.components.mouseEvent.mouseUp = "bUp";

  VisibleWidgets visAB = [
    VisibleWidget(btnA, RectF(0, 0, 50, 50), false, RectF.init),
    VisibleWidget(btnB, RectF(60, 0, 50, 50), false, RectF.init)
  ];

  // T17: Up without prior down produces nothing
  auto upEvA = AppEvent(
    AppEvent.Kind.mouseButtonUp,
    AppEvent.MouseData(1, 10.0f, 10.0f, 0, 0, 0, 1, false, 1)
  );
  inputSys.handleEventAndUpdateView(upEvA, visAB);
  assert(testUi.sentEvents.length == 0);

  // T18: Down on A, up over B routes up to A
  auto downEvA = AppEvent(
    AppEvent.Kind.mouseButtonDown,
    AppEvent.MouseData(1, 10.0f, 10.0f, 0, 0, 0, 1, true, 1)
  );
  inputSys.handleEventAndUpdateView(downEvA, visAB);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "aDown");

  testUi.sentEvents = null;
  auto upEvOverB = AppEvent(
    AppEvent.Kind.mouseButtonUp,
    AppEvent.MouseData(1, 70.0f, 10.0f, 0, 0, 0, 1, false, 1)
  );
  inputSys.handleEventAndUpdateView(upEvOverB, visAB);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "aUp");

  // T20: View attached after child creation + updateParentViews works
  testUi.sentEvents = null;
  auto parentRoot = new Widget(null, RectF(0, 0, 200, 200));
  auto childW = new Widget(parentRoot, RectF(10, 10, 50, 50));
  parentRoot.components.view = new View;
  parentRoot.components.view.renameEvents["childClick"] = "renamedClick";
  parentRoot.updateParentViews();

  auto childEv = ViewAppEventBuilder("childClick", childW).value(1).build();
  inputSys.passEvent(childW, childEv);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "renamedClick");
}

// Tests 21-25: refreshHover, transparent overlay, and KeyboardEvent bypass.
unittest {
  import yguilib.widget.input_components : KeyboardEvent;

  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  auto movingBtn = new Widget(null, RectF(0, 0, 100, 100));
  movingBtn.inputEnabled = true;
  movingBtn.components.mouseEvent = new MouseEvent;
  movingBtn.components.mouseEvent.mouseEnter = "btnEnter";
  movingBtn.components.mouseEvent.mouseLeave = "btnLeave";

  VisibleWidgets visInitial = [
    VisibleWidget(movingBtn, RectF(0, 0, 100, 100), false, RectF.init)
  ];

  auto motion = AppEvent(
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
  auto overlay = new Widget(null, RectF(0, 0, 100, 100));
  overlay.inputEnabled = false; // transparent
  VisibleWidgets visOverlay = [
    VisibleWidget(movingBtn, RectF(0, 0, 100, 100), false, RectF.init),
    VisibleWidget(overlay, RectF(0, 0, 100, 100), false, RectF.init)
  ];
  inputSys.handleEventAndUpdateView(motion, visOverlay);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "btnEnter");

  // T25: KeyboardEvent-only widget over button passes clicks through
  testUi.sentEvents = null;
  auto kbWidget = new Widget(null, RectF(0, 0, 100, 100));
  kbWidget.inputEnabled = true;
  kbWidget.components.keyboardEvent = new KeyboardEvent;
  movingBtn.components.mouseEvent.mouseDown = "btnDown";

  VisibleWidgets visKbOverBtn = [
    VisibleWidget(movingBtn, RectF(0, 0, 100, 100), false, RectF.init),
    VisibleWidget(kbWidget, RectF(0, 0, 100, 100), false, RectF.init)
  ];
  auto downEv = AppEvent(
    AppEvent.Kind.mouseButtonDown,
    AppEvent.MouseData(1, 50.0f, 50.0f, 0, 0, 0, 1, true, 1)
  );
  inputSys.handleEventAndUpdateView(downEv, visKbOverBtn);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "btnDown");
}
