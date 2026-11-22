module helloworld.app;

import helloworld.controller : HelloController;
import helloworld.model : HelloModel;
import helloworld.view : HelloView;
import yguilib.app : App;
import yguilib.model : ModelTracker;

void main() {
  auto app = App.makeAppWithTitleWh("yguilib Hello World", 640, 480);

  auto tracker = ModelTracker!HelloModel(new HelloModel());
  auto view = new HelloView(app.ui, tracker);
  app.ui.mainWindow().rootWidget = view.rootWidget();

  auto controller = new HelloController(app.ui, tracker, view);
  view.update();
  app.run(controller);
}
