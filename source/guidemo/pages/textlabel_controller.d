/**
 * textlabel_controller.d - Page 2 controller for TextLabel Playground demo.
 */
module guidemo.pages.textlabel_controller;

import guidemo.common : PageControllerParams, isKey, syncPageShellView,
  syncPageStatus;
import guidemo.demo_model_helpers : isPageActive;
import guidemo.model : DemoModel, DemoPage, TextLabelPageModel;
import guidemo.pages.textlabel_page : TextLabelPage;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode, Scancode;
import yguilib.model : ModelTracker;
import yguilib.widget.drawing_components : TextLabel;

/// Parameters for constructing TextLabelPageController.
alias TextLabelPageControllerParams =
  PageControllerParams!(TextLabelPage, ModelTracker!TextLabelPageModel);

/// Controller handling Page 2 keyboard shortcuts for TextLabel options.
final class TextLabelPageController : DefaultController {
  @disable this();

  /// Constructs the controller from fluent `params`.
  this(ref TextLabelPageControllerParams params) {
    assert(params.ui !is null, "ui must not be null");
    assert(params.page !is null, "page must not be null");
    super(params.ui);
    this.demoTracker = ModelTracker!DemoModel.from(params.demoTracker);
    this.page = params.page;
    this.tracker = ModelTracker!TextLabelPageModel.from(params.trackers);
    syncPageShellView(
      this.demoTracker.model,
      DemoPage.textLabel,
      page.rootWidget()
    );
    syncPageStatus(
      this.demoTracker,
      DemoPage.textLabel,
      page.formatStatus()
    );
  }

  invariant {
    assert(page !is null);
  }

  override bool update() {
    const bool demoChanged = demoTracker.update();
    const bool pageChanged = tracker.update();
    const bool statusChanged = syncPageStatus(
      demoTracker,
      DemoPage.textLabel,
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
      DemoPage.textLabel,
      page.rootWidget()
    );
    return true;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.keyDown &&
        isPageActive(demoTracker.model, DemoPage.textLabel)) {
      if (handlePageKey(ev)) {
        return HandleResult(HandleResult.Result.update, true);
      }
    }
    return super.handleEvent(ev);
  }

private:
  bool handlePageKey(in AppEvent ev) {
    auto model = tracker.edit();
    bool handled = true;
    if (isKey(ev, Keycode.m, Scancode.m)) {
      model.labelMultiline = !model.labelMultiline;
    } else if (isKey(ev, Keycode.e, Scancode.e)) {
      model.labelEllipsis = !model.labelEllipsis;
    } else if (isKey(ev, Keycode.l, Scancode.l)) {
      const size_t nextAlign = (cast(size_t) model.labelAlignment + 1) % 3;
      model.labelAlignment = cast(TextLabel.Alignment) nextAlign;
    } else if (isKey(ev, Keycode.t, Scancode.t)) {
      model.labelSampleIndex = (model.labelSampleIndex + 1) %
        TextLabelPage.labelInteractiveSamples.length;
    } else {
      handled = false;
    }
    tracker.commit(model);
    return handled;
  }

  ModelTracker!DemoModel demoTracker;
  ModelTracker!TextLabelPageModel tracker;
  TextLabelPage page;
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget : Widget;

  auto ui = new UiSystemImpl(null);
  auto demoModel = new DemoModel();
  auto demoTracker = ModelTracker!DemoModel(demoModel);
  auto root = new Widget(ui.nextWidgetId());
  auto pageTracker = ModelTracker!TextLabelPageModel(
    new TextLabelPageModel()
  );
  auto page = new TextLabelPage(ui, root, pageTracker);
  TextLabelPageControllerParams params;
  params.withUi(ui)
    .withDemoTracker(demoTracker)
    .withTrackers(pageTracker)
    .withPage(page);
  auto ctrl = new TextLabelPageController(params);

  AppEvent makeKeyDown(Keycode k, Scancode sc) {
    return AppEvent.keyEvent(
      AppEvent.Kind.keyDown,
      AppEvent.KeyData(1, k, sc)
    );
  }

  // When on Page 1 (activePage == 0), Page 2 shortcuts are ignored
  auto hrIgnored = ctrl.handleEvent(makeKeyDown(Keycode.m, Scancode.m));
  assert(hrIgnored.result == HandleResult.Result.nothing);
  assert(!hrIgnored.consume);
  assert(pageTracker.model.labelMultiline);

  // Switch to Page 2 (activePage == DemoPage.textLabel)
  assert(!page.visible());
  auto dm = demoTracker.edit();
  dm.activePage = DemoPage.textLabel;
  demoTracker.commit(dm);

  assert(ctrl.update());
  assert(!ctrl.update());
  ctrl.updateView();
  assert(page.visible());

  auto hrM = ctrl.handleEvent(makeKeyDown(Keycode.m, Scancode.m));
  assert(hrM.result == HandleResult.Result.update);
  assert(hrM.consume);
  assert(!pageTracker.model.labelMultiline);

  auto hrL = ctrl.handleEvent(makeKeyDown(Keycode.l, Scancode.l));
  assert(hrL.consume);
  assert(pageTracker.model.labelAlignment == TextLabel.Alignment.center);

  // Unrelated key [D] is not consumed
  auto hrD = ctrl.handleEvent(makeKeyDown(Keycode.d, Scancode.d));
  assert(hrD.result == HandleResult.Result.nothing);
  assert(!hrD.consume);
}
