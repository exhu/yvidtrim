/** see ./documentation/gui-overview.adoc

 */
module yguilib.app;

import yguilib.internal.logger : setupSdlLogger;
import yguilib.internal.uisystem_impl : UiSystemImpl;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
import yguilib.window : Window;
import std.logger : LogLevel;

/** The only object you need to run a gui app with a window.

final class MainController : DefaultController {
  this(UiSystem ui, ref ModelTracker!MainModel tracker, MainView view) {
  ...
  }
}

void main() {
  auto app = App.makeAppWithTitleWh("Hello World App", 1280, 720);
  auto tracker = ModelTracker!MainModel(new MainModel());
  auto view = new MainView(app.ui, tracker);
  app.withRootWidget(view.rootWidget());
  app.ui.pushController(new MainController(app.ui, tracker, view));
  app.run();
}
 */
final class App {
  @disable this();

  invariant {
    assert(fUi !is null);
  }

  static App makeAppWithTitleWh(string title, int width, int height) {
    assert(width > 0 && height > 0, "window dimensions must be > 0");
    return new App(new Window(width, height, title));
  }

  /// Sets the main window's root widget and returns `this` for chaining.
  App withRootWidget(Widget root) {
    assert(root !is null, "root must not be null");
    fUi.mainWindow().rootWidget = root;
    return this;
  }

  /// Runs the application main event loop. Push controllers via
  /// `ui.pushController(...)` before calling `run()`.
  void run() {
    ui.mainEventLoop();
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

private:
  UiSystem fUi;
}

unittest {
  import core.exception : AssertError;
  import std.exception : assertThrown;
  import std.logger : sharedLog;

  auto prevLog = sharedLog;
  scope (exit) sharedLog = prevLog;

  assertThrown!AssertError(App.makeAppWithTitleWh("bad", 0, 100));
  assertThrown!AssertError(App.makeAppWithTitleWh("bad", 100, -1));

  auto app = App.makeAppWithTitleWh("test_app", 320, 240);
  assert(app.ui !is null);
  assert(app.ui.mainWindow !is null);
  assert(app.ui.mainWindow.title == "test_app");

  auto root = app.ui.makeWidget();
  assert(app.withRootWidget(root) is app);
  assert(app.ui.mainWindow.rootWidget is root);
}
