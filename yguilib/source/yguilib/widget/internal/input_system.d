module yguilib.widget.internal.input_system;
import yguilib.widget.internal.collect_visible : VisibleWidgets, VisibleWidget;
import yguilib.events;

// TODO support multiple windows
final class InputSystem {
  this(void delegate(AppEvent event) sendAppEvent) {
    this.sendAppEvent = sendAppEvent;
  }

  /// returns true if needs to update the view
  bool handleEventAndUpdateView(AppEvent event, VisibleWidgets widgets) {
    if (!event.isKeyboardEvent() && !event.isMouseEvent())
      return false;
    foreach_reverse(VisibleWidget w; widgets) {
      // TODO handle mouse down/up

    }
    return false;
  }

private:
  void delegate(AppEvent event) sendAppEvent;
}
