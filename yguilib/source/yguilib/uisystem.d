module yguilib.uisystem;
import yguilib.controller : Controller;
import yguilib.events : AppEvent;
import yguilib.widget : Widget, WidgetViewController;
import yguilib.widget.system : WidgetSystem, WidgetSystemHost;
import yguilib.window : Window;

interface ControllerStack {
  void popController();
  void pushController(Controller c);
  void pushModalController(Controller c);

  void registerWidgetViewController(WidgetViewController c);
  void unregisterWidgetViewController(WidgetViewController c);
}

interface FocusControl {
  void popFocusRoot();
  void pushFocusRoot(Widget w);
}

interface EventControl {
  void sendAppEvent(AppEvent ev);
}

/// Interface for registering and querying WidgetSystems on UiSystem.
interface WidgetSystemControl {
  void registerWidgetSystem(WidgetSystem system);
  void unregisterWidgetSystem(WidgetSystem system);
  T findWidgetSystem(T : WidgetSystem)() {
    return cast(T) findWidgetSystemByType(typeid(T));
  }

protected:
  WidgetSystem findWidgetSystemByType(TypeInfo_Class type);
}

/// Manages Controllers, Messaging, Windows, and WidgetSystems.
interface UiSystem : ControllerStack, WidgetSystemHost, FocusControl,
  WidgetSystemControl {
  @property Window mainWindow();
  void mainEventLoop();
}
