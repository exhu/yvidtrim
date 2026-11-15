module yvidtrim.uitree.mainview;

import colors = yguilib.render.colors;
import yguilib.render.render_types : ColorF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Border;
import yguilib.widget.layout_components : Insets, JustifyContent;

struct MainViewWidgets {
  Widget root;
  Widget toggle;
  Widget alpha;
  Widget container;
}

MainViewWidgets makeMainViewWidgets(UiSystem ui) {
  assert(ui !is null, "UiSystem must not be null");

  MainViewWidgets widgets;
  widgets.root = makeRoot(ui);
  widgets.alpha = makeAlpha(ui, widgets.root);
  widgets.toggle = makeToggle(ui, widgets.root);
  widgets.container = makeContainer(ui, widgets.root);

  // TODO demo all other supported flex etc.
  addRightTopAnchor(ui, widgets.root);
  addLeftBottomAnchor(ui, widgets.root);
  addRightBottomAnchor(ui, widgets.root);

  return widgets;
}

private:

Widget makeRoot(UiSystem ui) {
  return WidgetBuilder.make(ui)
    .name("root")
    .bounds(10, 10, 200, 200)
    .view()
    .bg(ColorF(0.5f, 0.5f, 0.0f, 1.0f))
    .build();
}

Widget makeAlpha(UiSystem ui, Widget parent) {
  return WidgetBuilder.make(ui)
    .parent(parent)
    .name("alphaWidget")
    .bounds(35, 45, 150, 190)
    .bg(ColorF(0.0f, 1.0f, 0.5f, 0.3f))
    .border(ColorF(0.0f, 0.0f, 0.5f, 1.0f))
    .borderWidth(2.0f)
    .borderStyle(Border.Style.roundDashed)
    .borderRadius(10.0f)
    .text("Hello-0123456789")
    .textColor(ColorF(0.0f, 0.0f, 1.0f, 1.0f))
    .autoSize()
    .clipChildren(true)
    .build();
}

Widget makeToggle(UiSystem ui, Widget parent) {
  return WidgetBuilder.make(ui)
    .parent(parent)
    .name("toggleWidget")
    .bounds(15, 15, 300, 90)
    .roundBg(ColorF(0.5f, 1.0f, 0.5f, 0.3f))
    .bgRadius(15.0f)
    .build();
}

Widget makeContainer(UiSystem ui, Widget parent) {
  const auto brownMargin = Insets.horizontal(10.0f)
    .withTop(14.0f)
    .withBottom(15.0f);
  return WidgetBuilder.make(ui)
    .parent(parent)
    .name("container")
    .pos(35, 250)
    .size(400, 300)
    .bg(colors.darkGray)
    .border(colors.brightWhite)
    .borderWidth(3.0f)
    .borderStyle(Border.Style.dashed)
    .flexRow()
    .gap(8.0f)
    .justify(JustifyContent.start)
    .children(
      WidgetBuilder.make(ui)
        .name("yellowBox")
        .pos(5, 8)
        .fixedSize(100.0f, 40.0f)
        .bg(colors.yellow)
        .build(),
      WidgetBuilder.make(ui)
        .name("brownBox")
        .pos(15, 18)
        .fixedSize(110.0f, 50.0f)
        .bg(colors.brown)
        .margin(brownMargin)
        .build()
    )
    .build();
}

void addRightTopAnchor(UiSystem ui, Widget parent) {
  WidgetBuilder.make(ui)
    .parent(parent)
    .name("rightTopAnchor")
    .size(30, 30)
    .bg(colors.red)
    .anchorRight(0.0f)
    .anchorTop(3.0f)
    .build();
}

void addLeftBottomAnchor(UiSystem ui, Widget parent) {
  WidgetBuilder.make(ui)
    .parent(parent)
    .name("leftBottomAnchor")
    .size(30, 30)
    .bg(colors.brightRed)
    .anchorLeft(3.0f)
    .anchorBottom(7.0f)
    .build();
}

void addRightBottomAnchor(UiSystem ui, Widget parent) {
  WidgetBuilder.make(ui)
    .parent(parent)
    .name("rightBottomAnchor")
    .size(30, 30)
    .bg(colors.magenta)
    .anchorRight(5.0f)
    .anchorBottom(2.0f)
    .build();
}
