module helloworld.controller;

import helloworld.model : HelloModel, helloTextPalette;
import helloworld.view : HelloView, cycleColorEvent;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker;
import yguilib.uisystem : UiSystem;

/// Controller cycling the Hello World text color when the button is pressed.
final class HelloController : DefaultController {
public:
  @disable this();

  this(
    UiSystem ui,
    ref ModelTracker!HelloModel otherTracker,
    HelloView view
  ) {
    assert(ui !is null, "UiSystem must not be null");
    assert(view !is null, "HelloView must not be null");
    super(ui);
    this.view = view;
    tracker = ModelTracker!HelloModel.from(otherTracker);
  }

  invariant {
    assert(view !is null);
  }

  override bool update() {
    return tracker.update();
  }

  override bool updateView() {
    view.update();
    return true;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.view &&
        ev.view.eventName == cycleColorEvent) {
      auto m = tracker.edit();
      m.colorIndex = (m.colorIndex + 1) % helloTextPalette.length;
      tracker.commit(m);
      return HandleResult(HandleResult.Result.update, true);
    }
    return super.handleEvent(ev);
  }

private:
  HelloView view;
  ModelTracker!HelloModel tracker;
}

unittest {
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto ui = new UiSystemImpl(null);
  auto tracker = ModelTracker!HelloModel(new HelloModel());
  auto view = new HelloView(ui, tracker);
  auto ctrl = new HelloController(ui, tracker, view);

  view.update();
  auto label = view.rootWidget().children[0];
  assert(label.components.textLabel.color == helloTextPalette[0]);

  foreach (i; 1 .. helloTextPalette.length + 1) {
    auto ev = ViewAppEventBuilder(cycleColorEvent).build();
    auto hr = ctrl.handleEvent(ev);
    assert(hr.result == HandleResult.Result.update);
    assert(hr.consume);
    assert(ctrl.update());
    assert(ctrl.updateView());
    assert(
      label.components.textLabel.color ==
        helloTextPalette[i % helloTextPalette.length]
    );
  }

  const auto closeEv = AppEvent.makeNoRepeat(AppEvent.Kind.windowClose);
  const auto closeHr = ctrl.handleEvent(closeEv);
  assert(closeHr.result == HandleResult.Result.quit);
}
