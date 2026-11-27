module yguilib.widget.widget_view;
import yguilib.widget : Widget, ViewComponent;
import yguilib.widget.system : WidgetSystemHost;
import yguilib.events : AppEvent;
import yguilib.controller : DefaultController;
import yguilib.uisystem : UiSystem;

// TODO implement code first approach, without symbolic bindings

/*
  uisystem.dispatchEvent():
    - WidgetViewController
      - for each registeredWidgetView:
        isWidgetRegistered(event.widget)
    - WidgetView
    - Widget with ViewComponent
 */

/// This reacts to top view events (after translation). Returns
/// Result.updateView on AppEvent.update and calls WidgetView.update.
interface WidgetViewController {
  string controllerName();
  void registerWidgetView(WidgetView v);
  void unregisterWidgetView(WidgetView v);
  void unregisterViewWidget(Widget viewWidget);
}

abstract class WidgetViewControllerBase :
  DefaultController, WidgetViewController {
  @disable this();
  this(UiSystem uiSystem) {
    assert(uiSystem !is null, "uiSystem must not be null");
    super(uiSystem);
  }
  override void registerWidgetView(WidgetView view) {
    assert(view !is null, "view must not be null");
    import std.algorithm.searching : canFind;
    if (!canFind(views, view)) {
      views ~= view;
    }
  }
  override void unregisterWidgetView(WidgetView view) {
    import std.algorithm.mutation : remove;
    views = views.remove!(a => a is view);
  }

  override void unregisterViewWidget(Widget viewWidget) {
    foreach (v; views) {
      if (v !is null) {
        v.unregisterViewWidget(viewWidget);
      }
    }
  }

  override void onWidgetReleased(Widget w) {
    unregisterViewWidget(w);
  }

  override string controllerName() {
    const fullName = typeid(this).name;
    return objectName(fullName);
  }

  override bool update() {
    // WidgetView will check models
    return true;
  }

  override bool updateView() {
    bool shouldUpdate = false;
    foreach(v; views) {
      shouldUpdate = v.update() || shouldUpdate;
    }
    return shouldUpdate;
  }
protected:
  WidgetView[] views;
}

final class DefaultWidgetViewController : WidgetViewControllerBase {
  this(UiSystem uiSystem) {
    assert(uiSystem !is null, "uiSystem must not be null");
    super(uiSystem);
  }
}

/// This translates the event for ViewComponent and fetches data from model
/// into widgets of the view.
interface WidgetView {
  bool isWidgetRegistered(Widget viewWidget);
  string widgetViewName();
  void registerViewWidget(Widget viewWidget);
  void unregisterViewWidget(Widget viewWidget);
  /// called by the system if the event name is in renameEvents
  /// viewWidget = Widget with ViewComponent
  void translateEventForViewWidget(ref AppEvent sourceEvent, Widget viewWidget);
  /// Populate widgets with data; must be called by any controller in its
  /// updateView method.
  /// Controller.updateView is only called for the controller whose handleEvent
  /// returned updateView result.
  /// If a controller returns Result.update, the system sends AppEvent.update
  /// to all controllers.
  /// See UiSystemImpl.dispatchEvent for events, controller and view updates.
  bool update();
}

void renameViewWidgetEvent(
  ref AppEvent event,
  string newName,
  Widget viewWidget
) {
  event.view.eventName = newName;
  event.view.viewWidget = viewWidget;
}

abstract class WidgetViewBase : WidgetView {
public:
  override void registerViewWidget(Widget viewWidget) {
    assert(viewWidget !is null, "viewWidget must not be null");
    if (!isWidgetRegistered(viewWidget)) {
      viewWidgets ~= viewWidget;
    }
  }
  override void unregisterViewWidget(Widget viewWidget) {
    import std.algorithm.mutation : remove;
    viewWidgets = viewWidgets.remove!(a => a is viewWidget);
  }

  override bool isWidgetRegistered(Widget viewWidget) {
    import std.algorithm.searching : canFind;
    return canFind(viewWidgets, viewWidget);
  }

  override string widgetViewName() {
    const fullName = typeid(this).name;
    return objectName(fullName);
  }

  override void translateEventForViewWidget(
    ref AppEvent sourceEvent,
    Widget viewWidget
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto view = viewWidget.components.view;
    if (view is null) {
      return;
    }
    if (auto pNewName = sourceEvent.view.eventName in view.renameEvents) {
      renameViewWidgetEvent(sourceEvent, *pNewName, viewWidget);
    }
  }

  override bool update() {
    return false;
  }

protected:
  Widget[] viewWidgets;
}

package(yguilib):

/// Bubbles a view event through the widget hierarchy, renaming or suppressing
/// it when passing through ViewComponents, and finally delivering it to host.
void passViewEvent(WidgetSystemHost host, Widget w, AppEvent event) {
  assert(host !is null);
  if (w !is null && w.components.view !is null) {
    if (applyViewRenaming(host, w, event)) {
      return;
    }
  }

  for (Widget pv = (w !is null ? w.parentView : null);
    pv !is null;
    pv = pv.parentView) {
    if (applyViewRenaming(host, pv, event)) {
      return;
    }
  }

  host.sendAppEvent(event);
}

/// Returns true if the event should be suppressed (skipped).
bool applyViewRenaming(
  WidgetSystemHost host,
  Widget viewWidget,
  ref AppEvent event
) {
  assert(host !is null);
  ViewComponent view = viewWidget.components.view;
  if (view is null) {
    return false;
  }

  const string currentName = event.view.eventName;
  auto pNewName = currentName in view.renameEvents;
  if (pNewName !is null) {
    if ((*pNewName).length == 0) {
      return true;
    }
    if (view.widgetViewName.length != 0) {
      if (WidgetView wv = host.widgetViews.findByName(view.widgetViewName)) {
        wv.translateEventForViewWidget(event, viewWidget);
      } else {
        import std.logger : error;
        error("WidgetView not registered: %s", view.widgetViewName);
      }
    } else {
      renameViewWidgetEvent(event, *pNewName, viewWidget);
    }
  }
  return false;
}

private:

string objectName(string fullName) {
  import std.string : lastIndexOf;
  const dotIdx = fullName.lastIndexOf('.');
  return dotIdx >= 0 ? fullName[dotIdx + 1 .. $] : fullName;
}

unittest {
  final class SampleWidgetView : WidgetViewBase {
    override void translateEventForViewWidget(
      ref AppEvent sourceEvent,
      Widget viewWidget
    ) scope return {
    }
  }

  auto view = new SampleWidgetView();
  assert(view.widgetViewName() == "SampleWidgetView");
  assert(!view.update());
}

unittest {
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.test_fixture : MockWidgetSystemHost;

  final class TestView : WidgetViewBase {
    int updateCalls = 0;

    override bool update() {
      updateCalls++;
      return true;
    }
  }

  final class TestViewController : WidgetViewControllerBase {
    this(UiSystem ui) {
      super(ui);
    }
  }

  auto ui = new UiSystemImpl(null);
  auto ctrl = new TestViewController(ui);
  auto view = new TestView();
  assert(ctrl.controllerName() == "TestViewController");
  assert(ctrl.update());

  // Deduplicated registration on controller and view
  ctrl.registerWidgetView(view);
  ctrl.registerWidgetView(view);
  assert(ctrl.updateView());
  assert(view.updateCalls == 1);

  auto w1 = ui.makeWidget();
  w1.components.view = new ViewComponent();
  w1.components.view.renameEvents["rawClick"] = "renamedClick";
  w1.components.view.renameEvents["suppressed"] = "";
  w1.components.view.widgetViewName = "TestView";

  view.registerViewWidget(w1);
  view.registerViewWidget(w1);
  assert(view.isWidgetRegistered(w1));

  // translateEventForViewWidget handles missing key and valid key
  auto missingEv = ViewAppEventBuilder("unknown").widget(w1).build();
  view.translateEventForViewWidget(missingEv, w1);
  assert(missingEv.view.eventName == "unknown");

  auto validEv = ViewAppEventBuilder("rawClick").widget(w1).build();
  view.translateEventForViewWidget(validEv, w1);
  assert(validEv.view.eventName == "renamedClick");
  assert(validEv.view.viewWidget is w1);

  // passViewEvent & applyViewRenaming: bubbles through parentView, suppresses
  // "", and translates via host.widgetViews when widgetViewName is set.
  auto host = new MockWidgetSystemHost();
  host.widgetViews.register("TestView", view);

  auto child = ui.makeWidget();
  w1.addChild(child);
  assert(child.parentView is w1);

  auto ev1 = ViewAppEventBuilder("rawClick").widget(child).build();
  passViewEvent(host, child, ev1);
  assert(host.sentEvents.length == 1);
  assert(host.sentEvents[0].view.eventName == "renamedClick");
  assert(host.sentEvents[0].view.viewWidget is w1);

  auto evSuppressed = ViewAppEventBuilder("suppressed").widget(child).build();
  passViewEvent(host, child, evSuppressed);
  assert(host.sentEvents.length == 1);

  // onWidgetReleased unregisters view widget; unregisterWidgetView removes view
  ctrl.onWidgetReleased(w1);
  assert(!view.isWidgetRegistered(w1));

  ctrl.unregisterWidgetView(view);
  assert(!ctrl.updateView());
  assert(view.updateCalls == 1);
}
