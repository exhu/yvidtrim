module yguilib.widget.builder;
import yguilib.widget;

// see documentation/yguilib_api_improvements.md

// TODO make it easy to construct a widget, e.g.
// auto myTextLabel = WidgetBuilder(parent, rect = RectF(0,0,60,30)).withAutoSize()
//   .withBackground(colors.red)
//   .withTextLabel("abc", colors.white)
//   .withAnchor(5, 5, null, null)
//   .build();
struct WidgetBuilder {

  Widget build() {
    return null;
  }
}

// TODO build a flex row widget
Widget flexRow(Widget parent, float gap, Widget[] children) {
  return null;
}
