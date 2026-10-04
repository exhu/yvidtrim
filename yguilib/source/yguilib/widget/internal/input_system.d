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
      uiSystem.sendAppEvent(AppEvent(AppEvent.ViewData(vw.widget.components.mouseEvent.mouseDown,
                                                       vw.widget, event.mouse.button)));
      return true;
    }
    return false;
  }


  FocusSystem focusSystem;
  UiSystem uiSystem;
}
