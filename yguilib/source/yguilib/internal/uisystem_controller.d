module yguilib.internal.uisystem_controller;
import yguilib.controller;
import yguilib.render : Renderer;
import yguilib.widget : Widget;
import yguilib.widget.internal.collect_visible;
import yguilib.widget.internal.widget_painter : WidgetPainterSystem;
import yguilib.widget.internal.layout_system : LayoutSystem;
import yguilib.widget.internal.input_system;
import yguilib.events;

final class UiSystemController : DefaultController {
  this(SendAppEventFunc sendAppEventFunc) {
    super(sendAppEventFunc);
    painterSystem = new WidgetPainterSystem;
    visibleWidgetsCollector = new VisibleWidgetsCollector;
    layoutSystem = new LayoutSystem;
    inputSystem = new InputSystem(&sendAppEvent);
  }

  override bool update() {
    return false;
  }

  override bool updateView() {
    // do rendering here


    // false because we are the ui system layer
    return false;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.updateUiLayer) {
      return HandleResult(HandleResult.Result.updateView);
    }
    return super.handleEvent(ev);
  }

private:
  WidgetPainterSystem painterSystem;
  VisibleWidgetsCollector visibleWidgetsCollector;
  LayoutSystem layoutSystem;
  InputSystem inputSystem;
}
