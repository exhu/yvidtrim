/**
 * layout_painter_controller.d - Page 1 controller for Layout & Painter demo.
 */
module guidemo.pages.layout_painter_controller;

import guidemo.common : isKey, syncPageShell;
import guidemo.demo_model_helpers : isPageActive;
import guidemo.model : DemoModel, DemoPage, LayoutPainterPageModel;
import guidemo.pages.layout_painter_page : LayoutPainterPage;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode, Scancode;
import yguilib.model : ModelTracker;
import yguilib.timers : AnimationTimer, AnimationWrapMode, DeltaTimer;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.layout_components : AlignItems, FlexDirection,
  JustifyContent;

/// Controller handling Page 1 keyboard shortcuts and alpha pulse animation.
final class LayoutPainterPageController : DefaultController {
  this(
    UiSystem ui,
    ref ModelTracker!DemoModel demoTracker,
    Widget parent
  ) {
    assert(ui !is null, "ui must not be null");
    assert(parent !is null, "parent must not be null");
    this(ui, demoTracker, new LayoutPainterPage(ui, parent));
  }

  this(
    UiSystem ui,
    ref ModelTracker!DemoModel demoTracker,
    LayoutPainterPage page
  ) {
    assert(ui !is null, "ui must not be null");
    assert(page !is null, "page must not be null");
    super(ui);
    this.demoTracker = ModelTracker!DemoModel.from(demoTracker);
    this.page = page;
    this.tracker = ModelTracker!LayoutPainterPageModel.from(page.getTracker());
    alphaTimer.start(1.2f, AnimationWrapMode.pingPong);
    const bool onPage = isPageActive(
      this.demoTracker.model,
      DemoPage.layoutPainter
    );
    alphaTimer.setPause(!onPage);
    wasOnPage1 = onPage;
    syncPageShell(
      this.demoTracker,
      DemoPage.layoutPainter,
      page.getRootWidget(),
      page.formatStatus()
    );
  }

  invariant {
    assert(page !is null);
  }

  override bool updateView() {
    page.update();
    if (syncPageShell(
        demoTracker,
        DemoPage.layoutPainter,
        page.getRootWidget(),
        page.formatStatus()
      )) {
      sendUpdate();
    }
    return true;
  }

  override bool update() {
    const bool demoChanged = demoTracker.update();
    syncAlphaTimer();
    if (!isPageActive(demoTracker.model, DemoPage.layoutPainter) ||
        alphaTimer.isPaused()) {
      return demoChanged;
    }

    const float dt = alphaDeltaTimer.step();
    alphaTimer.update(dt);
    auto model = tracker.edit();
    model.alphaValue = alphaTimer.map(0.2f, 1.0f);
    tracker.commit(model);
    return tracker.update() || demoChanged;
  }

  override HandleResult handleEvent(AppEvent ev) {
    syncAlphaTimer();
    const bool onPage1 = isPageActive(
      demoTracker.model,
      DemoPage.layoutPainter
    );

    if (ev.kind == AppEvent.Kind.keyDown && onPage1) {
      if (handlePageKey(ev)) {
        HandleResult res;
        res.result = HandleResult.Result.updateView;
        res.consume = true;
        res.timeoutMs = animationTimeoutMs();
        return res;
      }
    }

    if (ev.kind == AppEvent.Kind.update) {
      HandleResult res;
      res.result = update()
        ? HandleResult.Result.updateView
        : HandleResult.Result.nothing;
      res.consume = false;
      res.timeoutMs = animationTimeoutMs();
      return res;
    }

    HandleResult res;
    res.result = isAnimating() && update() ? HandleResult.Result.updateView : HandleResult.Result.nothing;
    res.consume = false;
    res.timeoutMs = animationTimeoutMs();
    return res;
  }

private:
  bool handlePageKey(in AppEvent ev) {
    auto model = tracker.edit();
    bool handled = true;
    if (isKey(ev, Keycode.t, Scancode.t)) {
      model.textSampleIndex = (model.textSampleIndex + 1) % 3;
    } else if (isKey(ev, Keycode.d, Scancode.d)) {
      model.direction = model.direction == FlexDirection.row
        ? FlexDirection.column
        : FlexDirection.row;
    } else if (isKey(ev, Keycode.j, Scancode.j)) {
      size_t nextJ = (cast(size_t) model.justify + 1) %
        (JustifyContent.max + 1);
      model.justify = cast(JustifyContent) nextJ;
    } else if (isKey(ev, Keycode.a, Scancode.a)) {
      size_t nextA = (cast(size_t) model.alignItems + 1) %
        (AlignItems.max + 1);
      model.alignItems = cast(AlignItems) nextA;
    } else if (isKey(ev, Keycode.g, Scancode.g)) {
      model.gap = (model.gap >= 24.0f) ? 0.0f : (model.gap + 8.0f);
    } else if (isKey(ev, Keycode.v, Scancode.v)) {
      model.child2Visible = !model.child2Visible;
    } else {
      handled = false;
    }
    tracker.commit(model);
    return handled;
  }

  void syncAlphaTimer() {
    const bool onPage1 = isPageActive(
      demoTracker.model,
      DemoPage.layoutPainter
    );
    if (onPage1 != wasOnPage1) {
      alphaDeltaTimer.reset();
      alphaTimer.setPause(!onPage1);
      wasOnPage1 = onPage1;
    }
  }

  bool isAnimating() {
    return animationTimeoutMs() != -1;
  }

  int animationTimeoutMs() {
    if (isPageActive(demoTracker.model, DemoPage.layoutPainter) &&
        !alphaTimer.isPaused()) {
      return 16;
    }
    return -1;
  }

  ModelTracker!DemoModel demoTracker;
  ModelTracker!LayoutPainterPageModel tracker;
  LayoutPainterPage page;
  AnimationTimer alphaTimer;
  DeltaTimer alphaDeltaTimer;
  bool wasOnPage1 = true;
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  auto ui = new UiSystemImpl(null);
  auto demoModel = new DemoModel();
  auto demoTracker = ModelTracker!DemoModel(demoModel);
  auto root = new Widget(ui.nextWidgetId());
  auto page = new LayoutPainterPage(ui, root);
  auto ctrl = new LayoutPainterPageController(ui, demoTracker, page);

  AppEvent makeKeyDown(Keycode k, Scancode sc) {
    return AppEvent.keyEvent(
      AppEvent.Kind.keyDown,
      AppEvent.KeyData(1, k, sc)
    );
  }

  // Page 1 active: [D] toggles FlexDirection and consumes event
  auto hrD = ctrl.handleEvent(makeKeyDown(Keycode.d, Scancode.d));
  assert(hrD.result == HandleResult.Result.updateView);
  assert(hrD.consume);
  assert(hrD.timeoutMs == 16);
  assert(page.getTracker().model.direction == FlexDirection.column);

  // Page 1 active: [M] is unrelated and must not be consumed
  auto hrM = ctrl.handleEvent(makeKeyDown(Keycode.m, Scancode.m));
  assert(hrM.result == HandleResult.Result.nothing);
  assert(!hrM.consume);

  // Page 1 alpha pulse animates on update event
  const float alphaBefore = page.getTracker().model.alphaValue;
  auto hrTick = ctrl.handleEvent(AppEvent(AppEvent.Kind.update));
  assert(hrTick.result == HandleResult.Result.updateView);
  assert(!hrTick.consume);
  assert(hrTick.timeoutMs == 16);
  assert(page.getTracker().model.alphaValue != alphaBefore);

  // Switch away from Page 1: shortcuts ignored and animation paused
  auto dm = demoTracker.edit();
  dm.activePage = 1;
  demoTracker.commit(dm);

  auto hrD2 = ctrl.handleEvent(makeKeyDown(Keycode.d, Scancode.d));
  assert(hrD2.result == HandleResult.Result.nothing);
  assert(!hrD2.consume);
  assert(hrD2.timeoutMs == -1);
  assert(page.getTracker().model.direction == FlexDirection.column);
}
