module yguilib.widget.widget_view;
import yguilib.widget : Widget;
import yguilib.events : AppEvent;

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
}

private string objectName(string fullName) {
    import std.string : lastIndexOf;
    const dotIdx = fullName.lastIndexOf('.');
    return dotIdx >= 0 ? fullName[dotIdx + 1 .. $] : fullName;
}

// TODO extend from default controller and implement updateView method
class WidgetViewControllerBase : WidgetViewController {
  override void registerWidgetView(WidgetView view) {
    views ~= view;
  }
  override void unregisterWidgetView(WidgetView view) {
    import std.algorithm.mutation : remove;
    views = views.remove!(a => a is view);
  }

  override string getControllerName() {
    const fullName = typeid(this).name;
    return objectName(fullName);
  }
protected:
  WidgetView[] views;
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
  void update();
}

void renameViewWidgetEvent(ref AppEvent event, string newName, Widget viewWidget) {
  event.view.eventName = newName;
  event.view.viewWidget = viewWidget;
}

abstract class WidgetViewBase : WidgetView {
public:
  override void registerViewWidget(Widget viewWidget) {
    viewWidgets ~= viewWidget;
  }
  override void unregisterViewWidget(Widget viewWidget) {
    import std.algorithm.mutation : remove;
    viewWidgets = viewWidgets.remove!(a => a is viewWidget);
  }

  override string getWidgetViewName() {
    const fullName = typeid(this).name;
    return objectName(fullName);
  }

  override void update() {}

  override void translateEventForViewWidget(ref AppEvent sourceEvent,
                                            Widget viewWidget) {
    renameViewWidgetEvent(sourceEvent,
      viewWidget.components.view.renameEvents[sourceEvent.view.eventName],
      viewWidget);
  }

protected:
  Widget[] viewWidgets;
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
