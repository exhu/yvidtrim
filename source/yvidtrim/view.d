module yvidtrim.view;

import std.logger : infof;
import std.stdio : writeln;
import yguilib.model : ModelTracker;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.layout_components : AlignItems, FlexContainer;
import yvidtrim.model : MainModel;
import yvidtrim.uitree.mainview : MainViewWidgets, makeMainViewWidgets;

final class MainView {
public:
  @disable this();

  this(UiSystem ui, ref ModelTracker!MainModel otherTracker) {
    assert(ui !is null, "UiSystem must not be null");
    this.ui = ui;
    tracker = ModelTracker!MainModel.from(otherTracker);

    widgets = makeMainViewWidgets(ui);
    fc = widgets.container.components.flexContainer;
    assert(fc !is null, "FlexContainer must not be null");
    fc.alignItems = tracker.model.alignItems;

    infof("tree = %s", widgets.root.dumpTree(true));
  }

  invariant {
    assert(ui !is null);
    assert(fc !is null);
    assert(widgets.root !is null);
    assert(widgets.toggle !is null);
    assert(widgets.alpha !is null);
    assert(widgets.container !is null);
  }

  void update() {
    if (tracker.update()) {
      if (widgets.toggle.visible != tracker.model.toggleVisible) {
        widgets.toggle.visible = tracker.model.toggleVisible;
        widgets.toggle.update(WidgetUpdateScope.layout);
      }
      if (widgets.alpha.components.background !is null &&
          widgets.alpha.components.background.color.a !=
          tracker.model.alphaValue) {
        widgets.alpha.components.background.color.a =
          tracker.model.alphaValue;
        widgets.alpha.update(WidgetUpdateScope.visuals);
      }
      if (fc.alignItems != tracker.model.alignItems) {
        fc.alignItems = tracker.model.alignItems;
        widgets.container.update(WidgetUpdateScope.layout);
        writeln("alignItems=", fc.alignItems);
      }
    }
  }

  Widget rootWidget() {
    return widgets.root;
  }

private:
  UiSystem ui;
  ModelTracker!MainModel tracker;
  MainViewWidgets widgets;
  FlexContainer fc;
}

unittest {
  import yguilib.uisystem : makeHeadlessUiSystem;

  auto ui = makeHeadlessUiSystem();
  auto tracker = ModelTracker!MainModel(new MainModel());
  auto view = new MainView(ui, tracker);

  assert(view.rootWidget() !is null);

  void checkNames(Widget w) {
    assert(w !is null);
    assert(w.name.length > 0, "All widgets in MainView must be named");
    foreach (child; w.children) {
      checkNames(child);
    }
  }
  checkNames(view.rootWidget());

  auto m = tracker.edit();
  m.toggleVisible = false;
  m.alphaValue = 0.7f;
  m.alignItems = AlignItems.center;
  tracker.commit(m);

  view.update();

  assert(!view.widgets.toggle.visible);
  assert(view.widgets.alpha.components.background !is null);
  assert(view.widgets.alpha.components.background.color.a == 0.7f);
  assert(view.fc.alignItems == AlignItems.center);
}
