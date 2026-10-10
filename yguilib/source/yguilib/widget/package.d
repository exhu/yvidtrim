module yguilib.widget;
import yguilib.widget.component;
import yguilib.widget.drawing_components;
import yguilib.render.render_types;
import yguilib.widget.layout_components;
import yguilib.widget.input_components;
import yguilib.controller : Controller;

// TODO implement code first approach, without symbolic bindings

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
class View : Component {
  /// Renames an event and changes event.view.viewWidget to the attached widget.
  /// An empty string value ("") prevents the event from going up the tree.
  string[string] renameEvents;
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
  View view;
  Focus focus;
  DefaultButton defaultButton;
  KeyboardEvent keyboardEvent;
  MouseEvent mouseEvent;
}

final class Widget {
  this(Widget parent, RectF rect) {
    this.parent = parent;
    this.rect = rect;
    if (parent) {
      parent.children ~= this;
      parentView = findParentView();
    }
  }

  /// call after changing properties' or components' values
  void update() {
    markDirty(false);
  }

  /// force update everything (usually not necessary)
  void updateLayout() {
    markLayoutDirty();
  }

  /// force only rerender (could be used to optimize animation-only updates)
  void updateOnlyVisuals() {
    dirty = true;
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
  Widget parentView;

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

  /// Sets the dirty flag.
  /// If layout is true, or if this widget has auto-sized dimensions,
  /// marks this widget and its ancestors as layout-dirty so the layout
  /// system recalculates stale geometry.
  /// If layout is false, marks only this widget as dirty for redrawing,
  /// preserving cached layout calculations.
  void markDirty(bool layout = true) {
    dirty = true;
    if (layout || hasAutoSizing() || isFlexContainer() ||
        isParentFlexContainer()) {
      markLayoutDirty();
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

  // Paint-only dirty on child (no auto sizing)
  child.markDirty(false);
  assert(child.dirty);
  assert(!child.layoutDirty);
  assert(!root.dirty);
  assert(!root.layoutDirty);
  assert(root.isTreeDirty());
  assert(!root.isTreeLayoutDirty());

  // Reset and test auto sizing upgrade
  child.dirty = false;
  auto sz = new Size;
  sz.width = Dimension(0, SizingMode.auto_);
  child.components.size = sz;
  assert(child.hasAutoSizing());

  child.markDirty(false); // even with layout=false, auto_ forces layout
  assert(child.dirty);
  assert(child.layoutDirty);
  assert(root.dirty);
  assert(root.layoutDirty);
  assert(root.isTreeLayoutDirty());

  // Test markTreeDirty
  root.dirty = false;
  root.layoutDirty = false;
  child.dirty = false;
  child.layoutDirty = false;
  root.markTreeDirty();
  assert(root.dirty && root.layoutDirty);
  assert(child.dirty && child.layoutDirty);

  // Test visibility culling in tree checks
  root.dirty = false;
  child.dirty = true;
  assert(root.isTreeDirty());
  child.visible = false;
  assert(!root.isTreeDirty());
}
