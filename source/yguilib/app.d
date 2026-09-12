/** see ./documentation/gui-overview.adoc

 */
module yguilib.app;
import yguilib.uisystem;
import yguilib.controller;

class App {
  this(Window w) {
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

version(none) {
  abstract class BindingExpression {
    enum ReturnType {
      floatValue,
      integerValue,
      boolValue,
      stringValue,
      arrayValue,
      mapValue,
      modelReference,
    }
  }

  final class BindingValue : BindingExpression {
  }
}
