module yguilib.widget.internal.input_system;
import yguilib.widget.internal.focus_system;
import yguilib.widget.internal.collect_visible : VisibleWidgets, VisibleWidget;
import yguilib.events;
import yguilib.events.builder : ViewAppEventBuilder;
import yguilib.uisystem : UiSystem;
import yguilib.render.render_types;
import yguilib.widget : Widget, View;

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
    if (event.isMouseEvent())
      foreach_reverse(VisibleWidget vw; widgets) {
        if (!vw.widget.inputEnabled)
          continue;
        if (handleMouseEvent(vw, event))
          return false;
      }
    return false;
  }

private:
  bool widgetExpectsMouseEvent(Widget w, AppEvent.Kind kind) {
    if (w.components.mouseEvent is null)
      return false;
    switch (kind) {
    case AppEvent.Kind.mouseButtonDown:
      return w.components.mouseEvent.mouseDown.length > 0;
    default: break;
    }
    return false;
  }

  /// returns true to consume event
  bool handleMouseEvent(ref VisibleWidget vw, in AppEvent event) {
    if (!widgetExpectsMouseEvent(vw.widget, event.kind))
      return false;

    // TODO handle mouse down/up
    import std.logger;
    auto p = PointF(event.mouse.x, event.mouse.y);
    if (vw.absRect.contains(p)) {
      auto ev = ViewAppEventBuilder(vw.widget.components.mouseEvent.mouseDown)
        .widget(vw.widget)
        .value(event.mouse.button)
        .build();
      passEvent(vw.widget, ev);
      return true;
    }
    return false;
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
}
