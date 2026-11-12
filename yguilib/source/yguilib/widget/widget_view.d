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

/// This reacts to top view events (after translation). Returns Result.updateView on AppEvent.update
/// And calls WidgetView.update on
interface WidgetViewController {
  string getControllerName();
  void registerWidgetView(WidgetView v);
  void unregisterWidgetView(WidgetView v);
  void unregisterViewWidget(Widget viewWidget);
}

abstract class WidgetViewControllerBase : DefaultController, WidgetViewController {
  @disable this();
  this(UiSystem uiSystem) {
    super(uiSystem);
  }
  override void registerWidgetView(WidgetView view) {
    views ~= view;
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

  override string getControllerName() {
    const fullName = typeid(this).name;
    return objectName(fullName);
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
    super(uiSystem);
  }

  override bool update() {
    // WidgetView will check models
    return true;
  }
}

/// This translates the event for ViewComponent and fetches data from model
/// into widgets of the view.
interface WidgetView {
  bool isWidgetRegistered(Widget viewWidget);
  string getWidgetViewName();
  void registerViewWidget(Widget viewWidget);
  void unregisterViewWidget(Widget viewWidget);
  /// called by the system if the event name is in renameEvents
  /// viewWidget = Widget with ViewComponent
  void translateEventForViewWidget(ref AppEvent sourceEvent, Widget viewWidget);
  /// populate widgets with data, this must be called by any controller in its updateView method.
  /// however Controller.updateView only called for the controller which handleEvent returned updateView result.
  /// If one of the controllers returns Result.update the system sends AppEvent.update to all controllers.
  /// See UiSystemImpl.dispatchEvent for events, controller updates and view updates.
  bool update();
}

void renameViewWidgetEvent(ref AppEvent event, string newName, Widget viewWidget) {
  event.view.eventName = newName;
  event.view.viewWidget = viewWidget;
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
      if (WidgetView wv = host.widgetViews.getByName(view.widgetViewName)) {
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

public:

abstract class WidgetViewBase : WidgetView {
public:
  override void registerViewWidget(Widget viewWidget) {
    viewWidgets ~= viewWidget;
  }
  override void unregisterViewWidget(Widget viewWidget) {
    import std.algorithm.mutation : remove;
    viewWidgets = viewWidgets.remove!(a => a is viewWidget);
  }

  override bool isWidgetRegistered(Widget viewWidget) {
    import std.algorithm.searching : canFind;
    return canFind(viewWidgets, viewWidget);
  }

  override string getWidgetViewName() {
    const fullName = typeid(this).name;
    return objectName(fullName);
  }

  override void translateEventForViewWidget(ref AppEvent sourceEvent,
                                            Widget viewWidget) {
    renameViewWidgetEvent(sourceEvent,
      viewWidget.components.view.renameEvents[sourceEvent.view.eventName],
      viewWidget);
  }

protected:
  Widget[] viewWidgets;
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
  assert(view.getWidgetViewName() == "SampleWidgetView");
}
