module yguilib.uisystem;
import yguilib.controller : Controller;
import yguilib.events : AppEvent;
import yguilib.widget : Widget;
import yguilib.window : Window;

interface ControllerStack {
  void popController();
  void pushController(Controller c);
  void pushModalController(Controller c);
}

interface FocusControl {
  void popFocusRoot();
  void pushFocusRoot(Widget w);
}

interface EventControl {
  void sendAppEvent(AppEvent ev);
}

/// Manages Controllers, Messaging, Windows
interface UiSystem : ControllerStack, EventControl, FocusControl {
  inout(Window) getMainWindow() inout;
  void mainEventLoop();
}
