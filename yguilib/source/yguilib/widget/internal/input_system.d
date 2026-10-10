module yguilib.widget.internal.input_system;
import yguilib.widget.internal.focus_system;
import yguilib.widget.internal.collect_visible : VisibleWidgets, VisibleWidget;
import yguilib.events;
import yguilib.uisystem : UiSystem;
import yguilib.render.render_types;
import yguilib.widget : Widget;

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
      // TODO implement builder pattern for ViewData AppEvent to
      // replace constructor call with so many parameters
      auto ev = AppEvent(AppEvent.ViewData(vw.widget
                                           .components
                                           .mouseEvent
                                           .mouseDown,
                                           vw.widget,
                                           null,
                                           event.mouse.button));
      passEvent(vw.widget, ev);
      return true;
    }
    return false;
  }

  void passEvent(in Widget w, in AppEvent event) {
    if (w.parentView !is null) {
      // TODO filter via w.components.view.renameEvents
      // if no event in renameEvents then passEvent(w.parentView).
      // else if empty string at renameEvents[event.view.eventName]
      // return.
      // if new name, then change event.view.viewWidget to w.parentView
      // and passEvent(...)
      return;
    }

    if (w.parent is null)
      uiSystem.sendAppEvent(event);
    else
      passEvent(w.parent, event);
}


FocusSystem focusSystem;
UiSystem uiSystem;
}
