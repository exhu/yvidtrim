module yguilib.widget.test_fixture;

import yguilib.internal.uisystem_impl : UiSystemImpl;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : ViewComponent, Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.component : WidgetComponent;
import yguilib.widget.drawing_components : Background, Border, TextLabel;
import yguilib.widget.input_components : MouseEvent;
import yguilib.widget.layout_components : AlignItems, Dimension, FlexContainer,
  FlexDirection, Insets, JustifyContent, Size, SizingMode;
import yguilib.widget.scroll_components : ScrollableArea;

/**
 * Reusable test fixture for Widget construction, hierarchy building, and
 * component setup in headless unit tests.
 *
 * Insulates tests from Widget constructor signature changes (e.g. uId,
 * addChild refactoring, name fields).
 */
class WidgetFixture {
  /// Constructs a fixture with an explicit start ID.
  this(uint startId = 1) {
    fNextId = startId;
  }

  /// Constructs a fixture bound to an existing UiSystem.
  this(UiSystem ui) {
    fUi = ui;
    if (ui !is null) {
      fNextId = ui.nextWidgetId();
    }
  }

  /// Returns the next unique widget ID.
  uint nextId() {
    if (fUi !is null) {
      return fUi.nextWidgetId();
    }
    return fNextId++;
  }

  /// Gets the underlying UiSystem, creating a headless instance if null.
  @property UiSystem ui() {
    if (fUi is null) {
      fUi = new UiSystemImpl(null);
    }
    return fUi;
  }

  /// Creates a Widget with the given parent and rect.
  Widget makeWidget(Widget parent, RectF rect) {
    return new Widget(nextId(), parent, rect);
  }

  /// Creates a root or standalone Widget with no parent.
  Widget makeWidget(RectF rect = RectF(0, 0, 100, 100)) {
    return makeWidget(null, rect);
  }

  /// Creates a root Widget with specified dimensions.
  Widget makeRoot(RectF rect = RectF(0, 0, 800, 600)) {
    return makeWidget(null, rect);
  }

  /// Creates a root Widget with width and height.
  Widget makeRoot(float width, float height) {
    return makeWidget(null, RectF(0, 0, width, height));
  }

  /// Creates a child Widget attached to parent.
  Widget makeChild(Widget parent, RectF rect = RectF(0, 0, 50, 50)) {
    assert(parent !is null, "Parent widget must not be null for makeChild");
    return makeWidget(parent, rect);
  }

  /// Creates a child Widget with width and height.
  Widget makeChild(Widget parent, float width, float height) {
    return makeChild(parent, RectF(0, 0, width, height));
  }

  /// Creates a child Widget with explicit coordinates and size.
  Widget makeChild(
    Widget parent,
    float x,
    float y,
    float width,
    float height
  ) {
    return makeChild(parent, RectF(x, y, width, height));
  }

  /// Creates a WidgetBuilder starting from this fixture's ID generator.
  WidgetBuilder builder(
    Widget parent,
    RectF rect = RectF(0, 0, 100, 100)
  ) {
    return WidgetBuilder(nextId(), parent, rect);
  }

  /// Creates a WidgetBuilder for a root or standalone widget.
  WidgetBuilder builder(RectF rect = RectF(0, 0, 100, 100)) {
    return WidgetBuilder(nextId(), null, rect);
  }

  /// Attaches a background component to widget and returns the widget.
  Widget withBackground(
    Widget w,
    ColorF color,
    Background.Style style = Background.Style.rect,
    float cornerRadius = 0.0f
  ) {
    assert(w !is null);
    w.components.background = new Background(color, style, cornerRadius);
    return w;
  }

  /// Attaches a solid border component to widget and returns the widget.
  Widget withBorder(
    Widget w,
    ColorF color,
    float width = 1.0f
  ) {
    assert(w !is null);
    w.components.border = new Border(color, width);
    return w;
  }

  /// Attaches a TextLabel component to widget and returns the widget.
  Widget withText(
    Widget w,
    string text,
    ColorF color = ColorF(1, 1, 1, 1)
  ) {
    assert(w !is null);
    w.components.textLabel = new TextLabel(text, color);
    return w;
  }

  /// Attaches a fixed Size component to widget and returns the widget.
  Widget withSize(Widget w, float width, float height) {
    assert(w !is null);
    w.components.size = Size.fixed(width, height);
    return w;
  }

  /// Sets uniform padding on widget's Size component.
  Widget withPadding(Widget w, float all) {
    assert(w !is null);
    if (w.components.size is null) {
      w.components.size = new Size();
    }
    w.components.size.padding = Insets(all);
    return w;
  }

  /// Sets vertical and horizontal padding on widget's Size component.
  Widget withPadding(Widget w, float vertical, float horizontal) {
    assert(w !is null);
    if (w.components.size is null) {
      w.components.size = new Size();
    }
    w.components.size.padding = Insets(vertical, horizontal);
    return w;
  }

  /// Sets explicit padding insets on widget's Size component.
  Widget withPadding(
    Widget w,
    float top,
    float right,
    float bottom,
    float left
  ) {
    assert(w !is null);
    if (w.components.size is null) {
      w.components.size = new Size();
    }
    w.components.size.padding = Insets(top, right, bottom, left);
    return w;
  }

  /// Sets uniform margin on widget's Size component.
  Widget withMargin(Widget w, float all) {
    assert(w !is null);
    if (w.components.size is null) {
      w.components.size = new Size();
    }
    w.components.size.margin = Insets(all);
    return w;
  }

  /// Sets vertical and horizontal margin on widget's Size component.
  Widget withMargin(Widget w, float vertical, float horizontal) {
    assert(w !is null);
    if (w.components.size is null) {
      w.components.size = new Size();
    }
    w.components.size.margin = Insets(vertical, horizontal);
    return w;
  }

  /// Sets explicit margin insets on widget's Size component.
  Widget withMargin(
    Widget w,
    float top,
    float right,
    float bottom,
    float left
  ) {
    assert(w !is null);
    if (w.components.size is null) {
      w.components.size = new Size();
    }
    w.components.size.margin = Insets(top, right, bottom, left);
    return w;
  }

  /// Attaches a row FlexContainer component to widget and returns the widget.
  Widget withFlexRow(
    Widget w,
    float gap = 0.0f,
    JustifyContent justify = JustifyContent.start,
    AlignItems align_ = AlignItems.stretch
  ) {
    assert(w !is null);
    auto fc = new FlexContainer(FlexDirection.row, gap);
    fc.justify = justify;
    fc.alignItems = align_;
    w.components.flexContainer = fc;
    return w;
  }

  /// Attaches a column FlexContainer component to widget.
  Widget withFlexColumn(
    Widget w,
    float gap = 0.0f,
    JustifyContent justify = JustifyContent.start,
    AlignItems align_ = AlignItems.stretch
  ) {
    assert(w !is null);
    auto fc = new FlexContainer(FlexDirection.column, gap);
    fc.justify = justify;
    fc.alignItems = align_;
    w.components.flexContainer = fc;
    return w;
  }

  /// Attaches a MouseEvent component with a mouseDown event name.
  Widget withMouseEvent(Widget w, string onClick) {
    assert(w !is null);
    auto me = new MouseEvent();
    me.mouseDown = onClick;
    w.components.mouseEvent = me;
    return w;
  }

  /// Attaches a ViewComponent with optional event rename map.
  Widget withView(Widget w, string[string] renameEvents = null) {
    assert(w !is null);
    auto v = new ViewComponent();
    v.renameEvents = renameEvents;
    w.components.view = v;
    return w;
  }

  /// Attaches a ScrollableArea component to widget.
  Widget withScrollable(Widget w) {
    assert(w !is null);
    w.components.scrollableArea = new ScrollableArea();
    return w;
  }

  /// Attaches a custom WidgetComponent to widget.
  Widget withComponent(C : WidgetComponent)(Widget w, C component) {
    assert(w !is null);
    w.components.set!C(component);
    return w;
  }

  /// Counts all widgets in the subtree rooted at `root` (including root).
  static size_t countNodes(const Widget root) {
    if (root is null) {
      return 0;
    }
    size_t count = 1;
    foreach (child; root.children) {
      count += countNodes(child);
    }
    return count;
  }

  /// Collects all widgets in the subtree rooted at `root` into an array.
  static Widget[] collectSubtree(Widget root) {
    if (root is null) {
      return [];
    }
    Widget[] result = [root];
    foreach (child; root.children) {
      result ~= collectSubtree(child);
    }
    return result;
  }

  /// Finds a widget by uId within the subtree rooted at `root`.
  static Widget findById(Widget root, uint uId) {
    if (root is null) {
      return null;
    }
    if (root.uId == uId) {
      return root;
    }
    foreach (child; root.children) {
      if (auto found = findById(child, uId)) {
        return found;
      }
    }
    return null;
  }

  /// Returns true if `child` is an ancestor descendant of `ancestor`.
  static bool isDescendantOf(const Widget child, const Widget ancestor) {
    if (child is null || ancestor is null) {
      return false;
    }
    for (auto cur = cast(Widget) child.parent; cur !is null; cur = cur.parent) {
      if (cur is ancestor) {
        return true;
      }
    }
    return false;
  }

private:
  uint fNextId = 1;
  UiSystem fUi = null;
}

unittest {
  auto fix = new WidgetFixture();
  assert(fix.nextId() == 1);
  assert(fix.nextId() == 2);

  auto root = fix.makeRoot(RectF(0, 0, 800, 600));
  assert(root !is null);
  assert(root.uId == 3);
  assert(root.parent is null);
  assert(root.rect == RectF(0, 0, 800, 600));

  auto child1 = fix.makeChild(root, RectF(10, 10, 100, 50));
  assert(child1.uId == 4);
  assert(child1.parent is root);
  assert(root.children.length == 1);
  assert(root.children[0] is child1);

  auto child2 = fix.makeChild(root, 50, 60, 200, 100);
  assert(child2.uId == 5);
  assert(root.children.length == 2);

  auto grandChild = fix.makeChild(child1, 5, 5, 20, 20);
  assert(grandChild.parent is child1);
  assert(child1.children.length == 1);

  // Hierarchy utilities
  assert(WidgetFixture.countNodes(root) == 4);
  assert(WidgetFixture.countNodes(child1) == 2);
  assert(WidgetFixture.countNodes(null) == 0);

  auto subtree = WidgetFixture.collectSubtree(root);
  assert(subtree.length == 4);
  assert(subtree[0] is root);
  assert(subtree[1] is child1);
  assert(subtree[2] is grandChild);
  assert(subtree[3] is child2);

  assert(WidgetFixture.findById(root, 3) is root);
  assert(WidgetFixture.findById(root, 4) is child1);
  assert(WidgetFixture.findById(root, 5) is child2);
  assert(WidgetFixture.findById(root, 6) is grandChild);
  assert(WidgetFixture.findById(root, 999) is null);

  assert(WidgetFixture.isDescendantOf(grandChild, root));
  assert(WidgetFixture.isDescendantOf(grandChild, child1));
  assert(!WidgetFixture.isDescendantOf(child2, child1));
  assert(!WidgetFixture.isDescendantOf(root, child1));

  // Component configuration helpers
  fix.withBackground(child1, ColorF(0.2f, 0.4f, 0.6f, 1.0f));
  assert(child1.components.background !is null);
  assert(child1.components.background.color == ColorF(0.2f, 0.4f, 0.6f, 1.0f));

  fix.withBorder(child1, ColorF(1, 0, 0, 1), 2.0f);
  assert(child1.components.border !is null);
  assert(child1.components.border.width == 2.0f);

  fix.withText(child1, "Hello Fixture");
  assert(child1.components.textLabel !is null);
  assert(child1.components.textLabel.caption == "Hello Fixture");

  fix.withSize(child1, 120, 60);
  assert(child1.components.size !is null);
  assert(child1.components.size.width.value == 120);

  fix.withPadding(child1, 8.0f);
  assert(child1.components.size.padding.top == 8.0f);
  assert(child1.components.size.padding.left == 8.0f);

  fix.withMargin(child1, 4.0f, 6.0f);
  assert(child1.components.size.margin.top == 4.0f);
  assert(child1.components.size.margin.left == 6.0f);

  fix.withFlexRow(root, 10.0f);
  assert(root.components.flexContainer !is null);
  assert(root.components.flexContainer.direction == FlexDirection.row);
  assert(root.components.flexContainer.gap == 10.0f);

  fix.withMouseEvent(child2, "customClick");
  assert(child2.components.mouseEvent !is null);
  assert(child2.components.mouseEvent.mouseDown == "customClick");

  fix.withView(root, ["btn": "action"]);
  assert(root.components.view !is null);
  assert(root.components.view.renameEvents["btn"] == "action");

  fix.withScrollable(child2);
  assert(child2.components.scrollableArea !is null);

  // Builder integration
  auto built = fix.builder(RectF(0, 0, 50, 50))
    .fixedSize(50, 50)
    .build();
  assert(built !is null);
  assert(built.uId == 7);

  // UiSystem binding test
  auto uiFix = new WidgetFixture(fix.ui);
  assert(uiFix.ui !is null);
  auto uiWidget = uiFix.makeWidget(RectF(0, 0, 10, 10));
  assert(uiWidget !is null);
  assert(uiWidget.uId >= 1);
}
