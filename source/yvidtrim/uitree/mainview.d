module yvidtrim.uitree.mainview;
import yguilib.widget : Widget;
import yguilib.uisystem : UiSystem;

struct MainViewWidgets {
  Widget root;
  Widget toggle;
  Widget alpha;
  Widget container;
}

MainViewWidgets makeMainViewWidgets(UiSystem ui) {
  MainViewWidgets widgets;
  // TODO put widget tree construction code here from app.d, returns only references to widgets that
  // need to be updated by model
  // here should only be calls to private functions like widgets.root = makeRoot()
  // all builders inside those functions

  return widgets;
}

private:
// TODO place widget construction functions here
