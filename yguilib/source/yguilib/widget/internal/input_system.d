module yguilib.widget.internal.input_system;
import yguilib.widget.internal.focus_system;
import yguilib.widget.internal.collect_visible : VisibleWidgets, VisibleWidget;
import yguilib.events;
import yguilib.events.builder : ViewAppEventBuilder;
import yguilib.uisystem : UiSystem;
import yguilib.render.render_types;
import yguilib.widget : Widget, View;

import yguilib.widget.input_components : MouseEvent;

// TODO support multiple windows
final class InputSystem {
  this(UiSystem uiSystem) {
    this.uiSystem = uiSystem;
    this.focusSystem = new FocusSystem;
  }

  /// returns true if needs to update the view (when focus system engaged)
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
        foreach_reverse (VisibleWidget vw; widgets) {
          if (!vw.widget.inputEnabled)
            continue;
          if (handleMouseButton(vw, event))
            return false;
        }
      }
    }
    return false;
  }

private:
  /// returns true to consume event
  bool handleMouseButton(ref VisibleWidget vw, in AppEvent event) {
    if (vw.widget.components.mouseEvent is null)
      return false;

    const p = PointF(event.mouse.x, event.mouse.y);
    if (!vw.absRect.contains(p))
      return false;
    if (vw.hasClip && !vw.clipRect.contains(p))
      return false;

    auto val = MouseEvent.AppEventViewValue(
      event.mouse.x, event.mouse.y, event.mouse.button
    );

    if (event.kind == AppEvent.Kind.mouseButtonDown) {
      if (vw.widget.components.mouseEvent.mouseDown.length > 0) {
        auto ev = ViewAppEventBuilder(vw.widget.components.mouseEvent.mouseDown)
          .widget(vw.widget)
          .value(val)
          .build();
        passEvent(vw.widget, ev);
        return true;
      }
    } else if (event.kind == AppEvent.Kind.mouseButtonUp) {
      if (vw.widget.components.mouseEvent.mouseUp.length > 0) {
        auto ev = ViewAppEventBuilder(vw.widget.components.mouseEvent.mouseUp)
          .widget(vw.widget)
          .value(val)
          .build();
        passEvent(vw.widget, ev);
        return true;
      }
    }
    return false;
  }

  void handleMouseMotion(in AppEvent event, VisibleWidgets widgets) {
    const p = PointF(event.mouse.x, event.mouse.y);
    auto currentHovered = collectHoveredWidgets(widgets, p);
    auto val = MouseEvent.AppEventViewValue(event.mouse.x, event.mouse.y);

    notifyDepartedWidgets(currentHovered, val);
    notifyCurrentHoveredWidgets(currentHovered, val);
    hoveredWidgets = currentHovered;
  }

  Widget[] collectHoveredWidgets(VisibleWidgets widgets, PointF p) {
    const topIdx = findTopmostVisibleWidgetIndex(widgets, p);
    if (topIdx < 0)
      return null;

    Widget[] currentHovered;
    Widget curr = widgets[topIdx].widget;
    while (curr !is null) {
      const vwIdx = findVisibleWidgetIndex(widgets, curr);
      if (vwIdx >= 0) {
        const vw = widgets[vwIdx];
        if (vw.absRect.contains(p) &&
            (!vw.hasClip || vw.clipRect.contains(p))) {
          currentHovered ~= curr;
        }
      }
      curr = curr.parent;
    }
    return currentHovered;
  }

  void notifyDepartedWidgets(
    Widget[] currentHovered,
    MouseEvent.AppEventViewValue val
  ) {
    import std.algorithm.searching : canFind;

    foreach (w; hoveredWidgets) {
      if (!currentHovered.canFind(w)) {
        if (w.components.mouseEvent !is null &&
            w.components.mouseEvent.mouseLeave.length > 0) {
          auto ev = ViewAppEventBuilder(w.components.mouseEvent.mouseLeave)
            .widget(w)
            .value(val)
            .build();
          passEvent(w, ev);
        }
      }
    }
  }

  void notifyCurrentHoveredWidgets(
    Widget[] currentHovered,
    MouseEvent.AppEventViewValue val
  ) {
    import std.algorithm.searching : canFind;

    foreach (w; currentHovered) {
      if (w.components.mouseEvent is null)
        continue;
      const wasHovered = hoveredWidgets.canFind(w);
      if (!wasHovered && w.components.mouseEvent.mouseEnter.length > 0) {
        auto ev = ViewAppEventBuilder(w.components.mouseEvent.mouseEnter)
          .widget(w)
          .value(val)
          .build();
        passEvent(w, ev);
      }
      if (w.components.mouseEvent.mouseMove.length > 0) {
        auto ev = ViewAppEventBuilder(w.components.mouseEvent.mouseMove)
          .widget(w)
          .value(val)
          .build();
        passEvent(w, ev);
      }
    }
  }

  ptrdiff_t findTopmostVisibleWidgetIndex(
    VisibleWidgets widgets,
    PointF p
  ) {
    foreach_reverse (idx, ref VisibleWidget vw; widgets) {
      if (!vw.absRect.contains(p))
        continue;
      if (vw.hasClip && !vw.clipRect.contains(p))
        continue;
      return idx;
    }
    return -1;
  }

  ptrdiff_t findVisibleWidgetIndex(VisibleWidgets widgets, Widget w) {
    foreach (idx, ref VisibleWidget vw; widgets) {
      if (vw.widget is w)
        return idx;
    }
    return -1;
  }

  void passEvent(Widget w, AppEvent event) {
    Widget curr = w;

    // Check if the originating widget itself has a View component
    if (curr !is null && curr.components.view !is null) {
      if (applyViewRenaming(curr, event)) {
        return;
      }
    }

    // Bubble up through ancestor views
    while (curr !is null) {
      Widget pv = curr.parentView;
      if (pv is null && curr.parent !is null) {
        pv = curr.findParentView();
        curr.parentView = pv;
      }
      if (pv is null) {
        break;
      }
      curr = pv;
      if (applyViewRenaming(curr, event)) {
        return;
      }
    }

    uiSystem.sendAppEvent(event);
  }

  bool applyViewRenaming(Widget viewWidget, ref AppEvent event) {
    if (viewWidget.components.view is null) {
      return false;
    }
    const string currentName = event.view.eventName;
    auto pNewName = currentName in viewWidget.components.view.renameEvents;
    if (pNewName !is null) {
      if ((*pNewName).length == 0) {
        return true;
      }
      event.view.eventName = *pNewName;
      event.view.viewWidget = viewWidget;
    }
    return false;
  }

  Widget[] hoveredWidgets;
  FocusSystem focusSystem;
  UiSystem uiSystem;
}

unittest {
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

  auto testUi = new TestUiSystem;
  auto inputSys = new InputSystem(testUi);

  // Test 1: Direct pass-through without any View in the tree
  auto rootNoView = new Widget(null, RectF(0, 0, 200, 200));
  auto childNoView = new Widget(rootNoView, RectF(0, 0, 50, 50));
  auto ev1 = ViewAppEventBuilder("rawClick", childNoView)
    .value(1)
    .build();
  inputSys.passEvent(childNoView, ev1);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].kind == AppEvent.Kind.view);
  assert(testUi.sentEvents[0].view.eventName == "rawClick");
  assert(testUi.sentEvents[0].view.widget is childNoView);
  assert(testUi.sentEvents[0].view.viewWidget is null);

  // Test 2: Single View Renaming
  testUi.sentEvents = null;
  auto rootView = new Widget(null, RectF(0, 0, 200, 200));
  rootView.components.view = new View;
  rootView.components.view.renameEvents["btnClick"] = "playVideo";
  auto childBtn = new Widget(rootView, RectF(0, 0, 50, 50));
  auto ev2 = ViewAppEventBuilder("btnClick", childBtn)
    .value(1)
    .build();
  inputSys.passEvent(childBtn, ev2);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "playVideo");
  assert(testUi.sentEvents[0].view.widget is childBtn);
  assert(testUi.sentEvents[0].view.viewWidget is rootView);

  // Test 3: Event Suppression (empty string value consumes)
  testUi.sentEvents = null;
  rootView.components.view.renameEvents["suppressMe"] = "";
  auto ev3 = ViewAppEventBuilder("suppressMe", childBtn)
    .value(1)
    .build();
  inputSys.passEvent(childBtn, ev3);
  assert(testUi.sentEvents.length == 0);

  // Test 4: Nested Views Chaining
  testUi.sentEvents = null;
  auto outerView = new Widget(null, RectF(0, 0, 400, 400));
  outerView.components.view = new View;
  outerView.components.view.renameEvents["itemSelected"] = "orderUpdated";

  auto innerView = new Widget(outerView, RectF(0, 0, 200, 200));
  innerView.components.view = new View;
  innerView.components.view.renameEvents["click"] = "itemSelected";

  auto nestedBtn = new Widget(innerView, RectF(0, 0, 50, 50));
  auto ev4 = ViewAppEventBuilder("click", nestedBtn)
    .value(1)
    .build();
  inputSys.passEvent(nestedBtn, ev4);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "orderUpdated");
  assert(testUi.sentEvents[0].view.widget is nestedBtn);
  assert(testUi.sentEvents[0].view.viewWidget is outerView);

  // Test 5: Unmapped Passthrough in Inner View
  testUi.sentEvents = null;
  auto ev5 = ViewAppEventBuilder("unmappedInInner", nestedBtn)
    .value(1)
    .build();
  outerView.components.view.renameEvents["unmappedInInner"] = "handledByOuter";
  inputSys.passEvent(nestedBtn, ev5);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "handledByOuter");
  assert(testUi.sentEvents[0].view.widget is nestedBtn);
  assert(testUi.sentEvents[0].view.viewWidget is outerView);

  // Test 6: Source Widget Itself Has View Component
  testUi.sentEvents = null;
  auto selfView = new Widget(null, RectF(0, 0, 100, 100));
  selfView.components.view = new View;
  selfView.components.view.renameEvents["panelClick"] = "openPanel";
  auto ev6 = ViewAppEventBuilder("panelClick", selfView)
    .value(1)
    .build();
  inputSys.passEvent(selfView, ev6);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "openPanel");
  assert(testUi.sentEvents[0].view.widget is selfView);
  assert(testUi.sentEvents[0].view.viewWidget is selfView);

  // Test 7: Mouse down and up with coordinates and button value
  testUi.sentEvents = null;
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
  assert(testUi.sentEvents[0].view.widget is btnWidget);
  auto downVal = MouseEvent.AppEventViewValue(testUi.sentEvents[0].view.value);
  assert(downVal.buttons == 1);
  assert(downVal.absX == 20.0f);
  assert(downVal.absY == 30.0f);

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
  assert(upVal.absX == 25.0f);
  assert(upVal.absY == 35.0f);

  // Test 8: Mouse down and up skipped when inputEnabled is false
  testUi.sentEvents = null;
  btnWidget.inputEnabled = false;
  inputSys.handleEventAndUpdateView(downEv, visBtn);
  inputSys.handleEventAndUpdateView(upEv, visBtn);
  assert(testUi.sentEvents.length == 0);

  // Test 9: Mouse enter, move, and leave transitions
  testUi.sentEvents = null;
  auto hoverWidget = new Widget(null, RectF(50, 50, 100, 100));
  hoverWidget.inputEnabled = true;
  hoverWidget.components.mouseEvent = new MouseEvent;
  hoverWidget.components.mouseEvent.mouseEnter = "hoverEnter";
  hoverWidget.components.mouseEvent.mouseMove = "hoverMove";
  hoverWidget.components.mouseEvent.mouseLeave = "hoverLeave";

  VisibleWidgets visHover = [
    VisibleWidget(hoverWidget, RectF(50, 50, 100, 100), false, RectF.init)
  ];

  // Move inside hover widget -> triggers mouseEnter and mouseMove
  auto motionIn = AppEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 60.0f, 70.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionIn, visHover);
  assert(testUi.sentEvents.length == 2);
  assert(testUi.sentEvents[0].view.eventName == "hoverEnter");
  assert(testUi.sentEvents[1].view.eventName == "hoverMove");
  auto enterVal = MouseEvent.AppEventViewValue(testUi.sentEvents[0].view.value);
  assert(enterVal.absX == 60.0f);
  assert(enterVal.absY == 70.0f);

  // Move again inside hover widget -> triggers only mouseMove
  testUi.sentEvents = null;
  auto motionInside = AppEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 80.0f, 90.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionInside, visHover);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "hoverMove");
  auto moveVal = MouseEvent.AppEventViewValue(testUi.sentEvents[0].view.value);
  assert(moveVal.absX == 80.0f);
  assert(moveVal.absY == 90.0f);

  // Move outside hover widget -> triggers mouseLeave
  testUi.sentEvents = null;
  auto motionOut = AppEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 200.0f, 200.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionOut, visHover);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "hoverLeave");
  auto leaveVal = MouseEvent.AppEventViewValue(testUi.sentEvents[0].view.value);
  assert(leaveVal.absX == 200.0f);
  assert(leaveVal.absY == 200.0f);

  // Test 10: Mouse motion handled even when inputEnabled is false
  testUi.sentEvents = null;
  hoverWidget.inputEnabled = false;
  inputSys.handleEventAndUpdateView(motionIn, visHover);
  assert(testUi.sentEvents.length == 2);
  assert(testUi.sentEvents[0].view.eventName == "hoverEnter");
  assert(testUi.sentEvents[1].view.eventName == "hoverMove");

  testUi.sentEvents = null;
  inputSys.handleEventAndUpdateView(motionOut, visHover);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "hoverLeave");

  // Test 11: Nested widgets hover hierarchy
  testUi.sentEvents = null;
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

  // Moving into parent only
  auto motionParent = AppEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 20.0f, 20.0f, 0, 0, 0, 0, false, 0)
  );
  inputSys.handleEventAndUpdateView(motionParent, visNested);
  assert(testUi.sentEvents.length == 2);
  assert(testUi.sentEvents[0].view.eventName == "parentEnter");
  assert(testUi.sentEvents[1].view.eventName == "parentMove");

  // Moving from parent into child -> child enters, parent still moving
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

  // Moving from child back to parent -> child leaves, parent still moving
  testUi.sentEvents = null;
  inputSys.handleEventAndUpdateView(motionParent, visNested);
  assert(testUi.sentEvents.length == 2);
  assert(testUi.sentEvents[0].view.eventName == "childLeave");
  assert(testUi.sentEvents[1].view.eventName == "parentMove");

  // Moving out of parent entirely
  testUi.sentEvents = null;
  inputSys.handleEventAndUpdateView(motionOut, visNested);
  assert(testUi.sentEvents.length == 1);
  assert(testUi.sentEvents[0].view.eventName == "parentLeave");

  // Test 12: Clipped widget hit test exclusion
  testUi.sentEvents = null;
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
