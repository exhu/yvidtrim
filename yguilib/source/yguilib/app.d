/** see ./documentation/gui-overview.adoc

 */
module yguilib.app;

import yguilib.controller : Controller;
import yguilib.internal.logger : setupSdlLogger;
import yguilib.uisystem : UiSystem;
import yguilib.window : Window;

class App {
  this(Window w) {
    setupSdlLogger();
    ui = new UiSystem(w);
  }
  /// entry point
  void run(Controller mainController) {
    ui.pushController(mainController);
    ui.mainEventLoop();
    ui.popController();
  }

  UiSystem ui;
}
