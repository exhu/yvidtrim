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

/// This translates the event for ViewComponent and fetches data from model
/// into widgets of the view.
interface WidgetView {
  bool isWidgetRegistered(Widget viewWidget);
  string getWidgetViewName();
  void registerViewWidget(Widget viewWidget);
  void unregisterViewWidget(Widget viewWidget);
  /// called by the system if the event name is in renameEvents
  /// viewWidget = Widget with ViewComponent
  void translateEventForViewWidget(ref AppEvent sourceEvent, Widget viewWidget) scope return;
  /// populate widgets with data, this must be called by any controller in its updateView method.
  /// however Controller.updateView only called for the controller which handleEvent returned updateView result.
  /// If one of the controllers returns Result.update the system sends AppEvent.update to all controllers.
  /// See UiSystemImpl.dispatchEvent for events, controller updates and view updates.
  void update();
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
    import std.string : lastIndexOf;
    const fullName = typeid(this).name;
    const dotIdx = fullName.lastIndexOf('.');
    return dotIdx >= 0 ? fullName[dotIdx + 1 .. $] : fullName;
  }

  override void update() {}

protected:
  Widget[] viewWidgets;
}

unittest {
  final class SampleWidgetView : WidgetViewBase {
    override ref AppEvent translateEventForViewWidget(
      ref AppEvent sourceEvent,
      Widget viewWidget
    ) scope return {
      return sourceEvent;
    }
  }

  auto view = new SampleWidgetView();
  assert(view.getWidgetViewName() == "SampleWidgetView");
}
