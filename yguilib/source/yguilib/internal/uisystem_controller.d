module yguilib.internal.uisystem_controller;
import yguilib.controller;
import yguilib.render : Renderer;
import yguilib.widget : Widget;
import yguilib.widget.internal.collect_visible;
import yguilib.widget.internal.widget_painter : WidgetPainterSystem;
import yguilib.widget.internal.layout_system : LayoutSystem;
import yguilib.widget.internal.input_system;
import yguilib.events;
import yguilib.uisystem;

// TODO support multiple windows
final class UiSystemController : DefaultController {
  this(UiSystem uiSystem) {
    super(uiSystem);
    painterSystem = new WidgetPainterSystem;
    visibleWidgetsCollector = new VisibleWidgetsCollector;
    layoutSystem = new LayoutSystem;
    inputSystem = new InputSystem(uiSystem);
  }

  override bool update() {
    return false;
  }

  /// actual rendering of the whole app is here
  override bool updateView() {
    import std.logger;
    trace("render");
    updateLayout();
    renderFrame();
    // false because we are the ui system layer
    return false;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.updateUiLayer) {
      return HandleResult(HandleResult.Result.updateView);
    }
    if (handleWindowEvent(ev))
      return HandleResult(HandleResult.Result.updateView);
    if (inputSystem.handleEventAndUpdateView(ev, lastVisibleWidgets))
      return HandleResult(HandleResult.Result.updateView);
    return super.handleEvent(ev);
  }

private:
  bool isViewAvailableForRendering() {
    return (uiSystem.mainWindow !is null && uiSystem.mainWindow.view !is null &&
      uiSystem.mainWindow.renderer !is null);
  }

  void renderFrame() {
    if (uiSystem.mainWindow !is null) {
      if (isViewAvailableForRendering()) {
        if (!uiSystem.mainWindow.view.isTreeDirty()) {
          return;
        }
        painterSystem.drawTree(lastVisibleWidgets, uiSystem.mainWindow.renderer);
      }
      uiSystem.mainWindow.swapBuffers();
    }
  }

  void updateLayout() {
    if (isViewAvailableForRendering()) {
      if (!uiSystem.mainWindow.view.isTreeLayoutDirty() &&
          lastVisibleWidgets.length > 0) {
        return;
      }
      // collect visible on screen without widgets parent clipping
      lastVisibleWidgets = visibleWidgetsCollector.collectVisible(
        uiSystem.mainWindow.view, uiSystem.mainWindow.renderer, true
      );
      layoutSystem.layoutTree(
        uiSystem.mainWindow.view, uiSystem.mainWindow.renderer,
        lastVisibleWidgets
      );
      // collect visible with positions and sizes adjusted by layout,
      // include clipping test
      lastVisibleWidgets = visibleWidgetsCollector.collectVisible(
        uiSystem.mainWindow.view, uiSystem.mainWindow.renderer, false
      );
    }
  }

  bool isMainWindowEvent(uint windowId) {
    return (windowId == 0 || uiSystem.mainWindow.id == 0 || windowId ==
      uiSystem.mainWindow.id);
  }

  bool handleWindowEvent(in AppEvent event) {
    if (uiSystem.mainWindow is null)
      return false;
    if (!event.isWindowEvent())
      return false;

    if (isMainWindowEvent(event.window.windowId)) {
      uiSystem.mainWindow.handleWindowEvent(event);
      if (uiSystem.mainWindow.view !is null && event.isWindowRedrawEvent()) {
        uiSystem.mainWindow.view.markTreeDirty();
        return true;
      }
    }
    return false;
  }

  WidgetPainterSystem painterSystem;
  VisibleWidgetsCollector visibleWidgetsCollector;
  VisibleWidgets lastVisibleWidgets;
  LayoutSystem layoutSystem;
  InputSystem inputSystem;
}
