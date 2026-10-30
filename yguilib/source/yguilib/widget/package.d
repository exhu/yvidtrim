module yguilib.widget;
import yguilib.widget.component;
import yguilib.widget.drawing_components;
import yguilib.render.render_types;
import yguilib.widget.layout_components;
import yguilib.widget.input_components;
import yguilib.render.font : defaultFontPtSize;
import std.typecons : Nullable;

// TODO implement code first approach, without symbolic bindings

interface WidgetViewController {
  string getControllerName();
  void addView(Widget v);
}

/// Widgets can have this component to mark a root view to rename events
/// (e.g. "buttonClick" into "togglePlay"), or to select which events are
/// propagated up via the same event name.
/// This component is needed to implement widget tree reuse, e.g. to have
/// commonly used dialogs, or complex widgets (e.g. text input field with a
/// label, or button that highlights on mouse hover).
/// A widget subtree is the view, and attached code that translates events and
/// updates data in the view is a view controller.
/// The view event name and view widget reference help the corresponding
/// controller handle the proper event.
/// The default controllers are the whole screen.
///
/// Event handling flow:
/// 1. Controllers on ControllerStack receive raw input events first.
/// 2. If upper controllers do not consume the raw input event,
///    UiSystemController receives it and passes it to InputSystem.
/// 3. InputSystem generates a view event (e.g. defined name for a mouseDown)
///    and bubbles it up the hierarchy through parent views.
/// 4. At each View boundary, renameEvents is checked:
///    - If mapped to a non-empty name: renames the event and updates
///      event.view.viewWidget to that view widget.
///    - If mapped to an empty string (""): suppresses (consumes) the event.
///    - If unmapped: passes through unchanged up the tree.
/// 5. When the root widget for the window is reached (i.e. parent is null),
///    UiSystem.sendAppEvent is called.
///
/// Thus the widget tree can be constructed separately from controller code.
/// Controllers are then created with pointers to view widgets and data.
class ViewComponent : Component {
  /// Renames an event and changes event.view.viewWidget to the attached widget.
  /// An empty string value ("") prevents the event from going up the tree.
  string[string] renameEvents;
  /// Add this widget to registered named WidgetViewController. Can be useful for composite widgets.
  /// E.g. an app needs to implement one hover button or a colour picker
  /// controller to monitor and animate Widgets, that controller gets registered
  /// by name and widgets are autowired to it.
  // visual editor features:
  // TODO implement
  string addToController;
  // TODO parameters to that view, whose controller checks models on update.
  // this is a design parameter, at runtime ModelTracker instances to be constructed.
  // so need a named registry of model types and a factory, so that ModelTracker instances
  // can be constructed at runtime via string parameters.
  string[string] trackedModels;
}

struct WidgetComponents {
  // layout
  FlexContainer flexContainer;
  Size size;
  Anchor anchor;

  // drawing
  Background background;
  TextLabel textLabel;
  Border border;
  CustomDraw customDraw;

  // action/logic
  ViewComponent view;
  Focus focus;
  DefaultButton defaultButton;
  KeyboardEvent keyboardEvent;
  MouseEvent mouseEvent;

  /// Attaches or replaces a user-defined component of type `C`.
  /// Pass `null` to remove the component of type `C`.
  void set(C : Component)(C comp) {
    if (comp is null) {
      custom.remove(typeid(C));
    } else {
      custom[typeid(C)] = comp;
    }
  }

  /// Retrieves a user-defined component of type `C`, or `null` if absent.
  inout(C) get(C : Component)() inout {
    if (auto p = typeid(C) in custom) {
      return cast(inout(C))*p;
    }
    return null;
  }

  /// Returns true if a user-defined component of type `C` is attached.
  bool has(C : Component)() const {
    return (typeid(C) in custom) !is null;
  }

private:
  Component[TypeInfo_Class] custom;
}

/// Specifies which aspect of a widget changed when calling `Widget.update`.
///
/// Semantics overview:
/// - `parentView`: Recomputes cached `parentView` for this widget and all
///   descendants. Use when `ViewComponent` is added/removed or a subtree is
///   attached.
/// - `content`: Marks `dirty = true` on this widget, and if `hasAutoSizing()`
///   is true, marks this widget and its ancestors `layoutDirty` and `dirty`.
///   Use when text caption, font, multiline, ellipsis, or image content
///   changed.
/// - `visuals`: Marks only `this.dirty = true` without triggering layout
///   recalculation. Use when color, alpha, corner radius, dash style, or
///   alignment within fixed bounds changed.
/// - `layout`: Marks this widget and its ancestors `layoutDirty = true` and
///   `dirty = true`. Use when `visible`, `rect`, `Size`, `FlexContainer`,
///   `Anchor`, padding, margin, or border width changed.
/// - `all`: Recomputes `parentView` for the subtree, marks ancestors
///   `layoutDirty`, and marks this widget and all descendants `dirty` and
///   `layoutDirty`. Safe catch-all and full-tree invalidation (e.g. window
///   redraw or scaling change).
enum WidgetUpdateScope {
  /// Recomputes cached `parentView` for this widget and all descendants.
  /// Use when `ViewComponent` is added/removed or a subtree is attached.
  parentView,
  /// Intrinsic content changed (e.g. text caption, font, multiline, ellipsis,
  /// or image). Sets `dirty = true`, and if `hasAutoSizing()` is true, marks
  /// this widget and its ancestors `layoutDirty` and `dirty`.
  content,
  /// Visual-only properties changed (e.g. color, alpha, corner radius, dash
  /// style, or alignment within fixed bounds). Sets `dirty = true` on this
  /// widget and never triggers layout recalculation.
  visuals,
  /// Geometry, visibility, or layout components changed (e.g. `visible`,
  /// `rect`, `Size`, `FlexContainer`, `Anchor`, padding, margin, or border
  /// width). Marks this widget and its ancestors `layoutDirty = true` and
  /// `dirty = true`.
  layout,
  /// Full invalidation: recomputes `parentView` for the subtree, marks
  /// ancestors `layoutDirty`, and marks this widget and all descendants
  /// `dirty` and `layoutDirty`.
  all,
}

final class Widget {
  /// Constructs a widget. `parent` is allowed to be null for root widgets.
  this(Widget parent, RectF rect) {
    this.parent = parent;
    this.rect = rect;
    if (parent) {
      parent.children ~= this;
      fParentView = findParentView();
    }
  }

  /// Invalidates cached state and marks the widget for redraw and/or layout
  /// according to `scope_`.
  void update(WidgetUpdateScope scope_ = WidgetUpdateScope.all) {
    final switch (scope_) {
    case WidgetUpdateScope.parentView:
      updateParentViews();
      break;
    case WidgetUpdateScope.visuals:
      dirty = true;
      break;
    case WidgetUpdateScope.content:
      dirty = true;
      if (hasAutoSizing()) {
        markLayoutDirty();
      }
      break;
    case WidgetUpdateScope.layout:
      markLayoutDirty();
      break;
    case WidgetUpdateScope.all:
      updateParentViews();
      markLayoutDirty();
      markTreeDirty();
      break;
    }
  }

  /// Returns the widget's content area rectangle, accounting for border
  /// and padding components.
  RectF getContentArea() const {
    import std.algorithm.comparison : max;

    float borderWidth = 0.0f;
    if (components.border !is null &&
        components.border.style != Border.Style.none) {
      borderWidth = max(0.0f, components.border.width);
    }

    float padLeft = 0.0f;
    float padRight = 0.0f;
    float padTop = 0.0f;
    float padBottom = 0.0f;

    if (components.size !is null) {
      padLeft = components.size.padding.left;
      padRight = components.size.padding.right;
      padTop = components.size.padding.top;
      padBottom = components.size.padding.bottom;
    }

    const float startX = borderWidth + padLeft;
    const float startY = borderWidth + padTop;
    const float availW = max(
      0.0f,
      rect.width - (borderWidth * 2.0f + padLeft + padRight)
    );
    const float availH = max(
      0.0f,
      rect.height - (borderWidth * 2.0f + padTop + padBottom)
    );

    return RectF(startX, startY, availW, availH);
  }


  /// Sets text caption. If unchanged, returns false.
  /// If changed, updates caption and marks content-dirty (which triggers
  /// layout recalculation only when auto-sized).
  bool setCaption(string newCaption) {
    if (components.textLabel is null) {
      return false;
    }
    if (components.textLabel.caption == newCaption) {
      return false;
    }
    components.textLabel.caption = newCaption;
    update(WidgetUpdateScope.content);
    return true;
  }

  /// Sets background color. If unchanged, returns false.
  /// If changed, updates color and marks only visual-dirty (dirty = true),
  /// avoiding layout recalculation on parent flex containers.
  bool setBackgroundColor(ColorF newColor) {
    if (components.background is null) {
      return false;
    }
    if (components.background.color == newColor) {
      return false;
    }
    components.background.color = newColor;
    update(WidgetUpdateScope.visuals);
    return true;
  }

  /// Sets text color. If unchanged, returns false.
  /// If changed, updates color and marks only visual-dirty (dirty = true).
  bool setTextColor(ColorF newColor) {
    if (components.textLabel is null) {
      return false;
    }
    if (components.textLabel.color == newColor) {
      return false;
    }
    components.textLabel.color = newColor;
    update(WidgetUpdateScope.visuals);
    return true;
  }

  /// Sets border color. If unchanged, returns false.
  /// If changed, updates color and marks only visual-dirty (dirty = true).
  bool setBorderColor(ColorF newColor) {
    if (components.border is null) {
      return false;
    }
    if (components.border.color == newColor) {
      return false;
    }
    components.border.color = newColor;
    update(WidgetUpdateScope.visuals);
    return true;
  }

  /// Sets widget visibility. If unchanged, returns false.
  /// If changed, updates visibility and marks layout-dirty.
  bool setVisible(bool newVis) {
    if (visible == newVis) {
      return false;
    }
    visible = newVis;
    update(WidgetUpdateScope.layout);
    return true;
  }

  /// Checks if this or child Widget has the name.
  /// Returns null if none.
  Widget findByName(string nameToSearch) {
    if (name == nameToSearch)
      return this;
    foreach (c; children) {
      auto w = c.findByName(nameToSearch);
      if (w)
        return w;
    }
    return null;
  }

  Widget parent;
  RectF rect;
  /// it is not allowed to change available components after initialization
  WidgetComponents components;
  bool handleInput;
  /// it is not allowed to change after initialization by the end user
  Widget[] children;
  bool clipContents = true;
  bool clipChildren = false;
  bool visible = true;
  bool inputEnabled = false;
  /// points to nearest parent widget with View component
  @property inout(Widget) parentView() inout {
    return fParentView;
  }
  /// non-unique name to show in serialized form and to find in the tree.
  string name;

package(yguilib):
  /// Returns true if this widget has auto sizing on width or height.
  bool hasAutoSizing() const {
    if (components.size !is null) {
      return components.size.width.mode == SizingMode.auto_ ||
        components.size.height.mode == SizingMode.auto_;
    }
    return false;
  }

  bool isParentFlexContainer() const {
    if (parent is null)
      return false;

    return parent.components.flexContainer !is null;
  }

  bool isFlexContainer() const {
    return components.flexContainer !is null;
  }

  /// Returns true if this widget or any visible descendant needs redrawing.
  bool isTreeDirty() const {
    if (!visible) {
      return false;
    }
    if (dirty) {
      return true;
    }
    foreach (child; children) {
      if (child.isTreeDirty()) {
        return true;
      }
    }
    return false;
  }

  /// Returns true if this widget or any visible descendant needs layout.
  bool isTreeLayoutDirty() const {
    if (!visible) {
      return false;
    }
    if (layoutDirty) {
      return true;
    }
    foreach (child; children) {
      if (child.isTreeLayoutDirty()) {
        return true;
      }
    }
    return false;
  }

  Widget findParentView() {
    if (parent is null)
      return null;
    if (parent.components.view !is null)
      return parent;
    return parent.findParentView();
  }

  bool dirty = true;
  bool layoutDirty = true;

private:
  /// Recomputes cached parentView for this widget and all its descendants.
  void updateParentViews() {
    fParentView = findParentView();
    foreach (child; children) {
      child.updateParentViews();
    }
  }

  /// Marks this widget and its ancestors as layout dirty.
  void markLayoutDirty() {
    layoutDirty = true;
    dirty = true;
    if (parent !is null && !parent.layoutDirty) {
      parent.markLayoutDirty();
    }
  }

  /// Marks this widget and all its descendants as dirty and layout-dirty.
  void markTreeDirty() {
    dirty = true;
    layoutDirty = true;
    foreach (child; children) {
      child.markTreeDirty();
    }
  }

  Widget fParentView;
}

unittest {
  auto w = new Widget(null, RectF(10, 20, 100, 80));
  assert(w.getContentArea() == RectF(0, 0, 100, 80));

  w.components.border = new Border(ColorF(1, 0, 0, 1));
  w.components.border.width = 5.0f;
  assert(w.getContentArea() == RectF(5, 5, 90, 70));

  w.components.border.style = Border.Style.none;
  assert(w.getContentArea() == RectF(0, 0, 100, 80));
  w.components.border.style = Border.Style.rect;

  w.components.size = new Size();
  w.components.size.padding = Insets(2, 4, 6, 8);
  assert(w.getContentArea() == RectF(13, 7, 78, 62));

  w.rect = RectF(0, 0, 10, 10);
  assert(w.getContentArea() == RectF(13, 7, 0, 0));
}

unittest {
  auto root = new Widget(null, RectF(0, 0, 200, 200));
  auto child = new Widget(root, RectF(0, 0, 100, 100));

  assert(root.dirty && root.layoutDirty);
  assert(child.dirty && child.layoutDirty);
  assert(root.isTreeDirty());
  assert(root.isTreeLayoutDirty());

  // Clear flags manually
  root.dirty = false;
  root.layoutDirty = false;
  child.dirty = false;
  child.layoutDirty = false;

  assert(!root.isTreeDirty());
  assert(!root.isTreeLayoutDirty());

  // Visuals-only update on child
  child.update(WidgetUpdateScope.visuals);
  assert(child.dirty);
  assert(!child.layoutDirty);
  assert(!root.dirty);
  assert(!root.layoutDirty);
  assert(root.isTreeDirty());
  assert(!root.isTreeLayoutDirty());

  // Content update on child without auto sizing: only visual dirty
  child.dirty = false;
  child.update(WidgetUpdateScope.content);
  assert(child.dirty);
  assert(!child.layoutDirty);
  assert(!root.dirty);
  assert(!root.layoutDirty);

  // Content update on child with auto sizing: upgrades to layout dirty
  child.dirty = false;
  auto sz = new Size;
  sz.width = Dimension(0, SizingMode.auto_);
  child.components.size = sz;
  assert(child.hasAutoSizing());

  child.update(WidgetUpdateScope.content);
  assert(child.dirty);
  assert(child.layoutDirty);
  assert(root.dirty);
  assert(root.layoutDirty);
  assert(root.isTreeLayoutDirty());

  // Visuals update on auto-sized child does NOT trigger layout dirty
  root.dirty = false;
  root.layoutDirty = false;
  child.dirty = false;
  child.layoutDirty = false;
  child.update(WidgetUpdateScope.visuals);
  assert(child.dirty);
  assert(!child.layoutDirty);
  assert(!root.layoutDirty);

  // Layout update marks widget and ancestors layout dirty
  child.dirty = false;
  child.components.size = null;
  child.update(WidgetUpdateScope.layout);
  assert(child.dirty && child.layoutDirty);
  assert(root.dirty && root.layoutDirty);

  // Test WidgetUpdateScope.all (default update())
  root.dirty = false;
  root.layoutDirty = false;
  child.dirty = false;
  child.layoutDirty = false;
  root.components.view = new ViewComponent;
  assert(child.parentView is null);
  root.update();
  assert(root.dirty && root.layoutDirty);
  assert(child.dirty && child.layoutDirty);
  assert(child.parentView is root);

  root.dirty = false;
  child.dirty = true;
  assert(root.isTreeDirty());
  child.visible = false;
  assert(!root.isTreeDirty());
}

unittest {
  import yguilib.widget.builder : WidgetBuilder;

  auto root = WidgetBuilder(RectF(0, 0, 800, 600))
    .flex(FlexDirection.row, 10.0f)
    .background(ColorF(0.1f, 0.1f, 0.1f, 1.0f))
    .build();

  auto item = WidgetBuilder(root, RectF(0, 0, 100, 50))
    .fixedSize(100.0f, 50.0f)
    .padding(4.0f, 8.0f)
    .margin(Insets(2.0f))
    .roundBackground(ColorF(0.2f, 0.4f, 0.8f, 1.0f), 6.0f)
    .border(ColorF(1.0f, 1.0f, 1.0f, 1.0f), 1.5f)
    .text("Button")
    .onMouseDown("btnClick")
    .clipContents(true)
    .clipChildren(false)
    .build();

  assert(item.components.size !is null);
  assert(item.components.size.width.value == 100.0f);
  assert(item.components.size.padding.top == 4.0f);
  assert(item.components.size.padding.right == 8.0f);
  assert(item.components.background !is null);
  assert(item.components.border !is null);
  assert(item.components.textLabel !is null);
  assert(item.components.textLabel.caption == "Button");
  assert(item.inputEnabled);
  assert(item.components.mouseEvent !is null);
  assert(item.components.mouseEvent.mouseDown == "btnClick");
  assert(item.clipContents);
  assert(!item.clipChildren);

  // Test mutators: setCaption
  root.dirty = false;
  root.layoutDirty = false;
  item.dirty = false;
  item.layoutDirty = false;

  // Same caption: no-op
  assert(!item.setCaption("Button"));
  assert(!item.dirty);

  // New caption: changed, since fixed size and single line, layout is NOT dirty
  assert(item.setCaption("New Title"));
  assert(item.components.textLabel.caption == "New Title");
  assert(item.dirty);
  assert(!item.layoutDirty);
  assert(!root.layoutDirty);

  // setBackgroundColor: marks only visual dirty
  root.dirty = false;
  item.dirty = false;
  assert(!item.setBackgroundColor(item.components.background.color));
  assert(!item.dirty);

  assert(item.setBackgroundColor(ColorF(0.5f, 0.5f, 0.5f, 1.0f)));
  assert(item.dirty);
  assert(!item.layoutDirty);
  assert(!root.layoutDirty);

  // setVisible
  item.dirty = false;
  item.layoutDirty = false;
  root.layoutDirty = false;
  assert(!item.setVisible(true));
  assert(!item.dirty);

  assert(item.setVisible(false));
  assert(!item.visible);
  assert(item.dirty && item.layoutDirty);
  assert(root.layoutDirty);
}

// Verifies custom user-defined Component storage in WidgetComponents.
unittest {
  final class TooltipComponent : Component {
    string text;
    this(string text) {
      this.text = text;
    }
  }

  final class BadgeComponent : Component {
    int count;
    this(int count) {
      this.count = count;
    }
  }

  auto w = new Widget(null, RectF(0, 0, 100, 100));

  // Initial state: empty
  assert(!w.components.has!TooltipComponent());
  assert(w.components.get!TooltipComponent() is null);
  assert(!w.components.has!BadgeComponent());
  assert(w.components.get!BadgeComponent() is null);

  // Set first component
  auto tooltip = new TooltipComponent("Info");
  w.components.set(tooltip);
  assert(w.components.has!TooltipComponent());
  assert(w.components.get!TooltipComponent() is tooltip);
  assert(w.components.get!TooltipComponent().text == "Info");

  // Read via const reference
  const(Widget) cw = w;
  assert(cw.components.has!TooltipComponent());
  assert(cw.components.get!TooltipComponent() is tooltip);
  assert(cw.components.get!TooltipComponent().text == "Info");

  // Set second component without overwriting first
  auto badge = new BadgeComponent(5);
  w.components.set(badge);
  assert(w.components.has!TooltipComponent());
  assert(w.components.get!TooltipComponent() is tooltip);
  assert(w.components.has!BadgeComponent());
  assert(w.components.get!BadgeComponent() is badge);
  assert(w.components.get!BadgeComponent().count == 5);

  // Replace existing component
  auto newTooltip = new TooltipComponent("Updated");
  w.components.set(newTooltip);
  assert(w.components.get!TooltipComponent() is newTooltip);
  assert(w.components.get!TooltipComponent().text == "Updated");
  assert(w.components.get!BadgeComponent() is badge);

  // Remove component with null
  w.components.set!TooltipComponent(null);
  assert(!w.components.has!TooltipComponent());
  assert(w.components.get!TooltipComponent() is null);
  assert(w.components.has!BadgeComponent());
  assert(w.components.get!BadgeComponent() is badge);
}
