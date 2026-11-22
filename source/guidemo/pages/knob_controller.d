/**
 * knob_controller.d - Page 8 controller for the cursor-locked drag value
 * knob showcase.
 */
module guidemo.pages.knob_controller;

import guidemo.common : PageControllerParams, syncPageShellView,
  syncPageStatus;
import guidemo.model : DemoModel, DemoPage, KnobPageModel;
import guidemo.pages.knob_page : KnobPage, knobDownEvent, knobDragEvent,
  knobUpEvent;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker;
import yguilib.widget.input_components : MouseEvent;

/// Value change per pixel of horizontal relative drag motion.
enum float knobSensitivity = 0.01f;

/// Parameters for constructing KnobPageController.
alias KnobPageControllerParams =
  PageControllerParams!(KnobPage, ModelTracker!KnobPageModel);

/// Controller translating locked-cursor drag deltas into knob value changes.
final class KnobPageController : DefaultController {
  @disable this();

  /// Constructs the controller from fluent `params`.
  this(
    ref PageControllerParams!(KnobPage, ModelTracker!KnobPageModel) params
  ) {
    assert(params.ui !is null, "ui must not be null");
    assert(params.page !is null, "page must not be null");
    super(params.ui);
    this.demoTracker = ModelTracker!DemoModel.from(params.demoTracker);
    this.tracker = ModelTracker!KnobPageModel.from(params.trackers);
    this.page = params.page;
    syncPageShellView(
      this.demoTracker.model,
      DemoPage.knob,
      page.rootWidget()
    );
    syncPageStatus(this.demoTracker, DemoPage.knob, page.formatStatus());
  }

  invariant {
    assert(page !is null);
  }

  override bool update() {
    const bool demoChanged = demoTracker.update();
    const bool pageChanged = tracker.update();
    const bool statusChanged = syncPageStatus(
      demoTracker,
      DemoPage.knob,
      page.formatStatus()
    );
    if (statusChanged) {
      demoTracker.update();
    }
    return demoChanged || pageChanged || statusChanged;
  }

  override bool updateView() {
    page.update();
    syncPageShellView(
      demoTracker.model,
      DemoPage.knob,
      page.rootWidget()
    );
    return true;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind != AppEvent.Kind.view) {
      return super.handleEvent(ev);
    }

    const string eventName = ev.view.eventName;
    if (eventName == knobDownEvent) {
      setDragging(true);
    } else if (eventName == knobUpEvent) {
      setDragging(false);
    } else if (eventName == knobDragEvent) {
      const auto val = MouseEvent.AppEventViewValue.fromRaw(ev.view.value);
      if (val.relX == 0.0f) {
        return HandleResult(HandleResult.Result.nothing, true);
      }
      auto m = tracker.edit();
      m.value += val.relX * knobSensitivity;
      tracker.commit(m);
    } else {
      return super.handleEvent(ev);
    }
    return HandleResult(HandleResult.Result.update, true);
  }

private:
  void setDragging(bool dragging) {
    auto m = tracker.edit();
    m.dragging = dragging;
    tracker.commit(m);
  }

  ModelTracker!DemoModel demoTracker;
  ModelTracker!KnobPageModel tracker;
  KnobPage page;
}

unittest {
  import std.math : isClose;
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  auto ui = new UiSystemImpl(null);
  auto root = new Widget(ui.nextWidgetId());
  auto demoTracker = ModelTracker!DemoModel(new DemoModel());
  auto knobTracker = ModelTracker!KnobPageModel(new KnobPageModel());
  auto page = new KnobPage(ui, root, knobTracker);
  KnobPageControllerParams params;
  params.withUi(ui)
    .withDemoTracker(demoTracker)
    .withTrackers(knobTracker)
    .withPage(page);
  auto ctrl = new KnobPageController(params);

  auto downEv = ViewAppEventBuilder(knobDownEvent).build();
  assert(ctrl.handleEvent(downEv).consume);
  assert(knobTracker.model.dragging);

  // Locked drag: local coords stay at the press point, deltas in relX/relY.
  auto dragVal = MouseEvent.AppEventViewValue.pack(
    10.0f, 10.0f, 1, true, 25.0f, 7.0f, 30.0f, 30.0f
  );
  auto dragEv = ViewAppEventBuilder(knobDragEvent)
    .valueArray(dragVal.raw)
    .build();
  assert(ctrl.handleEvent(dragEv).consume);
  assert(isClose(knobTracker.model.value, 25.0f * knobSensitivity));

  // Negative relX beyond any widget/window bound keeps accumulating.
  auto backVal = MouseEvent.AppEventViewValue.pack(
    10.0f, 10.0f, 1, true, -5000.0f, 0.0f, 30.0f, 30.0f
  );
  auto backEv = ViewAppEventBuilder(knobDragEvent)
    .valueArray(backVal.raw)
    .build();
  ctrl.handleEvent(backEv);
  assert(isClose(
    knobTracker.model.value,
    (25.0f - 5000.0f) * knobSensitivity
  ));

  // Vertical-only drag is ignored.
  const float before = knobTracker.model.value;
  auto vertVal = MouseEvent.AppEventViewValue.pack(
    10.0f, 10.0f, 1, true, 0.0f, 40.0f, 30.0f, 30.0f
  );
  auto vertEv = ViewAppEventBuilder(knobDragEvent)
    .valueArray(vertVal.raw)
    .build();
  ctrl.handleEvent(vertEv);
  assert(knobTracker.model.value == before);

  auto upEv = ViewAppEventBuilder(knobUpEvent).build();
  assert(ctrl.handleEvent(upEv).consume);
  assert(!knobTracker.model.dragging);

  // View reflects the model after updateView.
  ctrl.updateView();
  assert(page.formatValue() == "-49.75");

  // Unrelated event is not consumed.
  auto otherEv = ViewAppEventBuilder("btnCountAction").build();
  auto hrOther = ctrl.handleEvent(otherEv);
  assert(hrOther.result == HandleResult.Result.nothing);
  assert(!hrOther.consume);

  // Page visibility follows DemoModel.activePage.
  assert(!page.isVisible());
  auto dm = demoTracker.edit();
  dm.activePage = DemoPage.knob;
  demoTracker.commit(dm);
  assert(ctrl.update());
  ctrl.updateView();
  assert(page.isVisible());
}
