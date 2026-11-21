/** see ./documentation/gui-overview.adoc

 */
module yguilib.app;

import yguilib.controller : Controller;
import yguilib.internal.logger : setupSdlLogger;
import yguilib.internal.uisystem_impl : UiSystemImpl;
import yguilib.uisystem : UiSystem;
import yguilib.window : Window;
import std.logger : LogLevel;

/** The only object you need to run a gui app with a window.

final class MainController : DefaultController {
  this(App app) {
  ...
  }
}

void main() {
  auto app = App.makeAppWithTitleWh("Hello World App", 1280, 720);
  app.run(new MainController(app));
}
 */
final class App {
  static App makeAppWithTitleWh(string title, int width, int height) {
    return new App(new Window(width, height, title));
  }

  /// entry point
  void run(Controller mainController) {
    assert(mainController !is null, "mainController must not be null");
    ui.pushController(mainController);
    ui.mainEventLoop();
    ui.popController();
  }

  @property UiSystem ui() {
    return fUi;
  }

package(yguilib):
  /// Use makeApp* static factory functions.
  this(Window w) {
    assert(w !is null, "w must not be null");
    setupSdlLogger(LogLevel.trace);
    fUi = new UiSystemImpl(w);
  }

  UiSystem fUi;
}
