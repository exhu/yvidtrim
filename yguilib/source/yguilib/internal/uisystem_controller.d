module yguilib.internal.uisystem_controller;

package(yguilib):

import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.uisystem : UiSystem;
import yguilib.widget : WidgetUpdateScope;
import yguilib.widget.internal.system_pipeline : WidgetSystemPipeline;
import yguilib.widget.system : SystemEventResult;

// TODO support multiple windows
final class UiSystemController : DefaultController {
  this(UiSystem uiSystem, WidgetSystemPipeline pipeline) {
    assert(uiSystem !is null);
    assert(pipeline !is null);
    super(uiSystem);
    this.pipeline = pipeline;
  }

  invariant {
    assert(pipeline !is null);
  }

  override bool update() {
    return false;
  }

  /// Actual layout, post-layout, and rendering of the whole app is here.
  override bool updateView() {
    import std.logger : trace;
    trace("render");
    pipeline.updateAndRender(uiSystem.mainWindow);
    // false because we are the ui system layer
    return false;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.updateUiLayer) {
      return HandleResult(HandleResult.Result.updateView);
    }
    if (handleWindowEvent(ev)) {
      return HandleResult(HandleResult.Result.updateView);
    }
    const SystemEventResult sysRes = pipeline.handleEvent(
      ev,
      uiSystem.mainWindow
    );
    if (sysRes.requestUpdateView) {
      return HandleResult(HandleResult.Result.updateView, sysRes.consumed);
    }
    if (sysRes.consumed) {
      return HandleResult(HandleResult.Result.nothing, true);
    }
    return super.handleEvent(ev);
  }

private:
  bool isMainWindowEvent(uint windowId) {
    return (windowId == 0 || uiSystem.mainWindow.id == 0 ||
      windowId == uiSystem.mainWindow.id);
  }

  bool handleWindowEvent(in AppEvent event) {
    if (uiSystem.mainWindow is null) {
      return false;
    }
    if (!event.isWindowEvent()) {
      return false;
    }

    if (isMainWindowEvent(event.window.windowId)) {
      uiSystem.mainWindow.handleWindowEvent(event);
      if (uiSystem.mainWindow.rootWidget !is null &&
          event.isWindowRedrawEvent()) {
        uiSystem.mainWindow.rootWidget.update(WidgetUpdateScope.all);
        return true;
      }
    }
    return false;
  }

  WidgetSystemPipeline pipeline;
}
