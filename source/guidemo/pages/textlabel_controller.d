/**
 * textlabel_controller.d - Page 2 controller for TextLabel Playground demo.
 */
module guidemo.pages.textlabel_controller;

import guidemo.common : isKey, syncPageShell;
import guidemo.demo_model_helpers : isPageActive;
import guidemo.model : DemoModel, DemoPage, TextLabelPageModel;
import guidemo.pages.textlabel_page : TextLabelPage;
import yguilib.controller : DefaultController, HandleResult;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode, Scancode;
import yguilib.model : ModelTracker;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.drawing_components : TextLabel;

/// Controller handling Page 2 keyboard shortcuts for TextLabel options.
final class TextLabelPageController : DefaultController {
  this(
    UiSystem ui,
    ref ModelTracker!DemoModel demoTracker,
    Widget parent
  ) {
    assert(ui !is null, "ui must not be null");
    assert(parent !is null, "parent must not be null");
    this(ui, demoTracker, new TextLabelPage(ui, parent));
  }

  this(
    UiSystem ui,
    ref ModelTracker!DemoModel demoTracker,
    TextLabelPage page
  ) {
    assert(ui !is null, "ui must not be null");
    assert(page !is null, "page must not be null");
    super(ui);
    this.demoTracker = ModelTracker!DemoModel.from(demoTracker);
    this.page = page;
    this.tracker = ModelTracker!TextLabelPageModel.from(page.getTracker());
    syncPageShell(
      this.demoTracker,
      DemoPage.textLabel,
      page.getRootWidget(),
      page.formatStatus()
    );
  }

  invariant {
    assert(page !is null);
  }

  override bool update() {
    return demoTracker.update();
  }

  override bool updateView() {
    page.update();
    if (syncPageShell(
        demoTracker,
        DemoPage.textLabel,
        page.getRootWidget(),
        page.formatStatus()
      )) {
      sendUpdate();
    }
    return true;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.keyDown &&
        isPageActive(demoTracker.model, DemoPage.textLabel)) {
      if (handlePageKey(ev)) {
        return HandleResult(HandleResult.Result.updateView, true);
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
      size_t nextAlign = (cast(size_t) model.labelAlignment + 1) % 3;
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
  auto page = new TextLabelPage(ui, root);
  auto ctrl = new TextLabelPageController(ui, demoTracker, page);

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
  assert(page.getTracker().model.labelMultiline);

  // Switch to Page 2 (activePage == DemoPage.textLabel)
  assert(!page.isVisible());
  auto dm = demoTracker.edit();
  dm.activePage = DemoPage.textLabel;
  demoTracker.commit(dm);

  auto hrUpdate = ctrl.handleEvent(AppEvent(AppEvent.Kind.update));
  assert(hrUpdate.result == HandleResult.Result.updateView);
  assert(!hrUpdate.consume);
  ctrl.updateView();
  assert(page.isVisible());

  auto hrM = ctrl.handleEvent(makeKeyDown(Keycode.m, Scancode.m));
  assert(hrM.result == HandleResult.Result.updateView);
  assert(hrM.consume);
  assert(!page.getTracker().model.labelMultiline);

  auto hrL = ctrl.handleEvent(makeKeyDown(Keycode.l, Scancode.l));
  assert(hrL.consume);
  assert(page.getTracker().model.labelAlignment == TextLabel.Alignment.center);

  // Unrelated key [D] is not consumed
  auto hrD = ctrl.handleEvent(makeKeyDown(Keycode.d, Scancode.d));
  assert(hrD.result == HandleResult.Result.nothing);
  assert(!hrD.consume);
}
