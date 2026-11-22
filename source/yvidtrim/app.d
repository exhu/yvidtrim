module yvidtrim.app;

import yguilib.app : App;
import yguilib.model : ModelTracker;
import yvidtrim.controller : MainController;
import yvidtrim.model : MainModel;
import yvidtrim.view : MainView;

void main() {
  // TODO parse cmdline arguments
  auto app = App.makeAppWithTitleWh("yvidtrim", 1280, 720);
  auto tracker = ModelTracker!MainModel(new MainModel());
  auto view = new MainView(app.ui, tracker);
  app.withRootWidget(view.rootWidget());
  auto controller = new MainController(app.ui, tracker, view);
  app.ui.pushController(controller);
  app.run();
}
