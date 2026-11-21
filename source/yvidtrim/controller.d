module yvidtrim.controller;

import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode;
import yguilib.model : ModelTracker;
import yguilib.uisystem : UiSystem;
import yguilib.widget.layout_components : AlignItems;
import yvidtrim.model : MainModel;
import yvidtrim.view : MainView;

final class MainController : DefaultController {
public:
  @disable this();

  this(
    UiSystem ui,
    ref ModelTracker!MainModel otherTracker,
    MainView view
  ) {
    assert(ui !is null, "UiSystem must not be null");
    assert(view !is null, "MainView must not be null");
    super(ui);
    this.view = view;
    this.t = ModelTracker!MainModel.from(otherTracker);
  }

  invariant {
    assert(view !is null);
  }

  override bool updateView() {
    view.update();
    return true;
  }

  override bool update() {
    import std.algorithm.comparison : clamp;

    auto model = t.edit();
    if (model.qPressed) {
      sendQuit();
    }

    if (model.aPressed) {
      size_t e = cast(size_t)model.alignItems;
      e += 1;
      e = e % AlignItems.max;

      model.alignItems = cast(AlignItems)e;
      model.aPressed = false;
    }

    model.toggleVisible ^= true;
    model.alphaValue = clamp((model.alphaValue + 0.01f) % 1.0f, 0.1f, 1.0f);
    t.commit(model);

    return t.update();
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.keyUp) {
      if (ev.keyData.key == Keycode.q) {
        auto model = t.edit();
        model.qPressed = true;
        t.commit(model);
        return HandleResult(HandleResult.Result.update, true);
      } else if (ev.keyData.key == Keycode.a) {
        auto model = t.edit();
        model.aPressed = true;
        t.commit(model);
        return HandleResult(HandleResult.Result.update, true);
      }
    }

    return super.handleEvent(ev);
  }

private:
  MainView view;
  ModelTracker!MainModel t;
}

unittest {
  import yguilib.events.keyboard : Scancode;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  auto ui = new UiSystemImpl(null);
  auto tracker = ModelTracker!MainModel(new MainModel());
  auto view = new MainView(ui, tracker);
  auto controller = new MainController(ui, tracker, view);

  const auto aEvent = AppEvent.keyEvent(
    AppEvent.Kind.keyUp,
    AppEvent.KeyData(1, Keycode.a, Scancode.a, 0, false)
  );
  const auto aResult = controller.handleEvent(aEvent);
  assert(aResult.result == HandleResult.Result.update);
  assert(aResult.consume);
  assert(tracker.model.aPressed);

  assert(controller.update());
  assert(!tracker.model.aPressed);
  assert(tracker.model.alignItems == cast(AlignItems)1);

  assert(controller.updateView());
  Widget container;
  foreach (child; view.rootWidget().children) {
    if (child.name == "container") {
      container = child;
      break;
    }
  }
  assert(container !is null);
  assert(container.components.flexContainer !is null);
  assert(
    container.components.flexContainer.alignItems == cast(AlignItems)1
  );

  const auto qEvent = AppEvent.keyEvent(
    AppEvent.Kind.keyUp,
    AppEvent.KeyData(1, Keycode.q, Scancode.q, 0, false)
  );
  const auto qResult = controller.handleEvent(qEvent);
  assert(qResult.result == HandleResult.Result.update);
  assert(qResult.consume);
  assert(tracker.model.qPressed);

  const auto closeEvent = AppEvent.makeNoRepeat(AppEvent.Kind.windowClose);
  const auto closeResult = controller.handleEvent(closeEvent);
  assert(closeResult.result == HandleResult.Result.quit);

  const auto otherKeyEvent = AppEvent.keyEvent(
    AppEvent.Kind.keyUp,
    AppEvent.KeyData(1, Keycode.b, Scancode.b, 0, false)
  );
  const auto otherResult = controller.handleEvent(otherKeyEvent);
  assert(otherResult.result == HandleResult.Result.nothing);
  assert(!otherResult.consume);
}
