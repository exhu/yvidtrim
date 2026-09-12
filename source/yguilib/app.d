/** see ./documentation/gui-overview.adoc

 */
module yguilib.app;
import yguilib.uisystem;
import yguilib.controller;

class App {
  // TODO controller stack, windows, systems

  /// entry point
  void run(Controller mainController) {

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
