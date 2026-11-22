module helloworld.view;

import helloworld.model : HelloModel;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : TextLabel;
import yguilib.widget.layout_components : AlignItems, JustifyContent;

/// View event emitted when the color-cycle button is pressed.
enum cycleColorEvent = "helloCycleColor";

/// View constructing the centered Hello World text and color button.
final class HelloView {
public:
  @disable this();

  this(UiSystem ui, ref ModelTracker!HelloModel otherTracker) {
    assert(ui !is null, "UiSystem must not be null");
    this.ui = ui;
    tracker = ModelTracker!HelloModel.from(otherTracker);
    buildTree();
  }

  invariant {
    assert(ui !is null);
    assert(root !is null);
    assert(helloLabel !is null);
    assert(cycleBtn !is null);
  }

  void update() {
    if (!tracker.update()) {
      return;
    }
    helloLabel.setTextColor(tracker.model.currentColor());
  }

  Widget rootWidget() {
    return root;
  }

private:
  void buildTree() {
    root = WidgetBuilder.make(ui)
      .name("helloRoot")
      .rect(RectF(0, 0, 640, 480))
      .bg(ColorF(0.08f, 0.09f, 0.12f, 1.0f))
      .flexColumn()
      .justify(JustifyContent.center)
      .alignItems(AlignItems.center)
      .gap(16.0f)
      .build();

    helloLabel = WidgetBuilder.make(ui)
      .parent(root)
      .name("helloLabel")
      .rect(RectF(0, 0, 0, 0))
      .autoSize()
      .text("Hello, World!")
      .textColor(tracker.model.currentColor())
      .fontSize(32.0f)
      .textAlign(TextLabel.Alignment.center)
      .build();

    cycleBtn = WidgetBuilder.make(ui)
      .parent(root)
      .name("cycleColorBtn")
      .rect(RectF(0, 0, 180, 40))
      .fixedSize(180.0f, 40.0f)
      .roundBg(ColorF(0.18f, 0.24f, 0.34f, 1.0f))
      .bgRadius(6.0f)
      .roundBorder(ColorF(0.35f, 0.45f, 0.62f, 1.0f))
      .borderWidth(1.0f)
      .text("Cycle Text Color")
      .textColor(ColorF(0.95f, 0.95f, 0.95f, 1.0f))
      .fontSize(14.0f)
      .textAlign(TextLabel.Alignment.center)
      .onMouseDown(cycleColorEvent)
      .build();
  }

  UiSystem ui;
  ModelTracker!HelloModel tracker;
  Widget root;
  Widget helloLabel;
  Widget cycleBtn;
}

unittest {
  import helloworld.model : helloTextPalette;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.layout_components : FlexDirection, SizingMode;

  auto ui = new UiSystemImpl(null);
  auto tracker = ModelTracker!HelloModel(new HelloModel());
  auto view = new HelloView(ui, tracker);

  Widget root = view.rootWidget();
  assert(root !is null);
  assert(root.children.length == 2);

  void verifyAllNamed(Widget w) {
    assert(w !is null);
    assert(w.name.length > 0, "All widgets must be named");
    foreach (child; w.children) {
      verifyAllNamed(child);
    }
  }
  verifyAllNamed(root);

  auto fc = root.components.flexContainer;
  assert(fc !is null);
  assert(fc.direction == FlexDirection.column);
  assert(fc.justify == JustifyContent.center);
  assert(fc.alignItems == AlignItems.center);
  assert(fc.gap == 16.0f);

  Widget label = root.children[0];
  assert(label.name == "helloLabel");
  assert(label.components.textLabel !is null);
  assert(label.components.textLabel.caption == "Hello, World!");
  assert(label.components.textLabel.color == helloTextPalette[0]);
  assert(label.components.size !is null);
  assert(label.components.size.width.mode == SizingMode.auto_);
  assert(label.components.size.height.mode == SizingMode.auto_);

  Widget btn = root.children[1];
  assert(btn.name == "cycleColorBtn");
  assert(btn.components.size !is null);
  assert(btn.components.size.width.mode == SizingMode.fixed);
  assert(btn.components.size.height.mode == SizingMode.fixed);
  assert(btn.components.mouseEvent !is null);
  assert(btn.components.mouseEvent.mouseDown == cycleColorEvent);

  auto m = tracker.edit();
  m.colorIndex = 1;
  tracker.commit(m);
  view.update();
  assert(label.components.textLabel.color == helloTextPalette[1]);
}
