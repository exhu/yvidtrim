module yguilib.internal.uisystem_controller;

package(yguilib):

import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.uisystem : UiSystem;
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

  /// Signals Phase 3 that the widget tree should be updated and rendered.
  override bool updateView() {
    return true;
  }

  override HandleResult handleEvent(AppEvent ev) {
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
  WidgetSystemPipeline pipeline;
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto ui = new UiSystemImpl(null);
  auto ctrl = new UiSystemController(ui, ui.systemPipeline);

  assert(!ctrl.update());
  assert(ctrl.updateView());

  const HandleResult quitRes = ctrl.handleEvent(
    AppEvent(AppEvent.Kind.appQuit)
  );
  assert(quitRes.isQuit());

  const HandleResult userRes = ctrl.handleEvent(
    AppEvent.userEvent(AppEvent.UserData(1))
  );
  assert(!userRes.isQuit());
}
