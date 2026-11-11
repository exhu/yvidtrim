module yguilib.widget;
import yguilib.widget.component;
import yguilib.widget.drawing_components;
import yguilib.render.render_types;
import yguilib.widget.layout_components;
import yguilib.widget.input_components;
import yguilib.widget.data_components;
import yguilib.render.font : defaultFontPtSize;
import yguilib.widget.widget_view : WidgetViewController, WidgetView;
import yguilib.serhelpers : SerIgnore, toJsonValue, serializeToJson;
import std.json : JSONValue, JSONType;
import std.typecons : Nullable;

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
class ViewComponent : WidgetComponent {
  /// Renames an event and changes event.view.viewWidget to the attached widget.
  /// An empty string value ("") prevents the event from going up the tree.
  string[string] renameEvents;
  // The following is for when graphical WYSIWYG editor (but first building widget tree via
  // json) phase of yguilib will be in development:
  /// Add this widget to registered named WidgetViewController. Can be useful for composite widgets.
  /// E.g. an app needs to implement one hover button or a colour picker
  /// controller to monitor and animate Widgets, that controller gets registered
  /// by name and widgets are autowired to it.
  // visual editor features:
  // TODO implement
  //string controllerName;
  // TODO optional (can be null) translator for events in renameEvents
  // and to update values from model
  string widgetViewName;

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

  import yguilib.widget.scroll_components : ScrollableArea;
  // action/logic
  ScrollableArea scrollableArea;
  ViewComponent view;
  Focus focus;
  DefaultButton defaultButton;
  KeyboardEvent keyboardEvent;
  MouseEvent mouseEvent;

  // data driven
  WidgetArrayComponent widgetArray;

  /// Attaches or replaces a user-defined component of type `C`.
  /// Pass `null` to remove the component of type `C`.
  void set(C : WidgetComponent)(C comp) {
    if (comp is null) {
      custom.remove(typeid(C));
      customSerializers.remove(typeid(C));
    } else {
      custom[typeid(C)] = comp;
      customSerializers[typeid(C)] = (const WidgetComponent c) {
        return toJsonValue(cast(const C) c);
      };
    }
  }

  /// Retrieves a user-defined component of type `C`, or `null` if absent.
  inout(C) get(C : WidgetComponent)() inout {
    if (auto p = typeid(C) in custom) {
      return cast(inout(C))*p;
    }
    return null;
  }

  /// Returns true if a user-defined component of type `C` is attached.
  bool has(C : WidgetComponent)() const {
    return (typeid(C) in custom) !is null;
  }

  /// Appends user-defined custom components to serialized fields.
  void onSerializeFields(ref JSONValue[string] fields) const {
    JSONValue[string] customMap;
    foreach (ti, comp; custom) {
      if (comp !is null) {
        if (auto serializer = ti in customSerializers) {
          customMap[ti.toString()] = (*serializer)(comp);
        } else {
          customMap[ti.toString()] = toJsonValue(comp);
        }
      }
    }
    fields["custom"] = JSONValue(customMap);
  }

private:
  @SerIgnore WidgetComponent[TypeInfo_Class] custom;
  @SerIgnore JSONValue function(const WidgetComponent)[TypeInfo_Class]
    customSerializers;
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
  @disable this();

  /// Constructs a widget with unique ID.
  this(uint uId) {
    this.uId = uId;
  }

  /// Adds `w` as a child of this widget.
  /// If `w` already has a parent, removes `w` from that parent first.
  void addChild(Widget w) {
    assert(w !is null, "Child widget must not be null");
    assert(w !is this, "Widget cannot be a child of itself");
    assert(!isChildOf(w), "Cannot add an ancestor as a child");

    if (w.fParent is this) {
      return;
    }
    if (w.fParent !is null) {
      w.fParent.detachChild(w);
    }
    w.fParent = this;
    fChildren ~= w;
    w.updateParentViews();
    markLayoutDirty();
    w.markTreeDirty();
  }

  /// Removes `w` from this widget if it is a child.
  bool removeChild(Widget w) {
    import std.algorithm.mutation : remove;

    if (w is null || w.fParent !is this) {
      return false;
    }
    fChildren = fChildren.remove!(c => c is w);
    w.fParent = null;
    w.fParentView = null;
    w.updateParentViews();
    markLayoutDirty();
    w.markTreeDirty();
    return true;
  }

  /// Detaches `w` from this widget if it is a child.
  void detachChild(Widget w) {
    removeChild(w);
  }

  /// Returns true if this widget is a descendant of `ancestor`.
  bool isChildOf(const Widget ancestor) const {
    if (ancestor is null || fParent is null) {
      return false;
    }
    if (fParent is ancestor) {
      return true;
    }
    return fParent.isChildOf(ancestor);
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

  /// Sets scroll offset on ScrollableArea component. If unchanged or no
  /// ScrollableArea component, returns false. If changed, marks layout-dirty.
  bool setScrollOffset(PointF newOffset) {
    if (components.scrollableArea is null) {
      return false;
    }
    if (components.scrollableArea.offset == newOffset) {
      return false;
    }
    components.scrollableArea.offset = newOffset;
    update(WidgetUpdateScope.layout);
    return true;
  }

  /// Dumps the widget (and optionally its children) as a human-readable
  /// pretty-formatted JSON string for debugging layout and widget state.
  string dumpTree(bool withChildren = true) const {
    import std.json : toJSON, JSONOptions;
    const JSONValue jv = dumpToJsonValue(withChildren);
    return toJSON(jv, true, JSONOptions.specialFloatLiterals);
  }

  /// Converts the widget to a JSONValue, including or excluding children.
  JSONValue dumpToJsonValue(bool withChildren = true) const {
    JSONValue[string] root;
    root["type"] = JSONValue("Widget");

    JSONValue[string] fields;
    fields["uId"] = toJsonValue(uId);
    fields["name"] = toJsonValue(name);
    fields["rect"] = toJsonValue(rect);
    fields["components"] = toJsonValue(components);
    fields["handleInput"] = toJsonValue(handleInput);
    fields["clipContents"] = toJsonValue(clipContents);
    fields["clipChildren"] = toJsonValue(clipChildren);
    fields["visible"] = toJsonValue(visible);
    fields["inputEnabled"] = toJsonValue(inputEnabled);
    fields["dirty"] = toJsonValue(dirty);
    fields["layoutDirty"] = toJsonValue(layoutDirty);

    if (fParent !is null) {
      fields["parentUId"] = JSONValue(fParent.uId);
    } else {
      fields["parentUId"] = JSONValue(null);
    }

    if (fParentView !is null) {
      fields["parentViewUId"] = JSONValue(fParentView.uId);
    } else {
      fields["parentViewUId"] = JSONValue(null);
    }

    if (withChildren) {
      JSONValue[] childrenArr;
      foreach (child; fChildren) {
        childrenArr ~= child.dumpToJsonValue(true);
      }
      fields["children"] = JSONValue(childrenArr);
    }

    root["fields"] = JSONValue(fields);
    return JSONValue(root);
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

  /// Checks if this or child Widget has the given `uId`.
  /// Returns null if none.
  inout(Widget) findByUId(uint idToSearch) inout {
    if (uId == idToSearch) {
      return this;
    }
    foreach (c; children) {
      auto w = c.findByUId(idToSearch);
      if (w !is null) {
        return w;
      }
    }
    return null;
  }

  const uint uId;
  RectF rect;
  /// it is not allowed to change available components after initialization
  WidgetComponents components;
  bool handleInput;
  bool clipContents = true;
  bool clipChildren = false;
  bool visible = true;
  bool inputEnabled = false;

  /// points to parent widget in hierarchy
  @property inout(Widget) parent() inout {
    return fParent;
  }

  /// list of child widgets
  @property inout(Widget[]) children() inout {
    return fChildren;
  }

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
    if (fParent is null)
      return false;

    return fParent.components.flexContainer !is null;
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
    foreach (child; fChildren) {
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
    foreach (child; fChildren) {
      if (child.isTreeLayoutDirty()) {
        return true;
      }
    }
    return false;
  }

  Widget findParentView() {
    if (fParent is null)
      return null;
    if (fParent.components.view !is null)
      return fParent;
    return fParent.findParentView();
  }

  bool dirty = true;
  bool layoutDirty = true;

private:
  /// Recomputes cached parentView for this widget and all its descendants.
  void updateParentViews() {
    fParentView = findParentView();
    foreach (child; fChildren) {
      child.updateParentViews();
    }
  }

  /// Marks this widget and its ancestors as layout dirty.
  void markLayoutDirty() {
    layoutDirty = true;
    dirty = true;
    if (fParent !is null && !fParent.layoutDirty) {
      fParent.markLayoutDirty();
    }
  }

  /// Marks this widget and all its descendants as dirty and layout-dirty.
  void markTreeDirty() {
    dirty = true;
    layoutDirty = true;
    foreach (child; fChildren) {
      child.markTreeDirty();
    }
  }

  @SerIgnore Widget fParent;
  @SerIgnore Widget[] fChildren;
  @SerIgnore Widget fParentView;
}

unittest {
  auto w = new Widget(1);
  w.rect = RectF(10, 20, 100, 80);
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
  auto root = new Widget(1);
  root.rect = RectF(0, 0, 200, 200);
  auto child = new Widget(2);
  child.rect = RectF(0, 0, 100, 100);
  root.addChild(child);

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

  auto root = WidgetBuilder(1)
    .rect(RectF(0, 0, 800, 600))
    .flex(FlexDirection.row, 10.0f)
    .background(ColorF(0.1f, 0.1f, 0.1f, 1.0f))
    .build();

  auto item = WidgetBuilder(2)
    .parent(root)
    .rect(RectF(0, 0, 100, 50))
    .fixedSize(100.0f, 50.0f)
    .padding(4.0f, 8.0f)
    .margin(Insets.all(2.0f))
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

// Verifies custom user-defined WidgetComponent storage in WidgetComponents.
unittest {
  final class TooltipComponent : WidgetComponent {
    string text;
    this(string text) {
      this.text = text;
    }
  }

  final class BadgeComponent : WidgetComponent {
    int count;
    this(int count) {
      this.count = count;
    }
  }

  auto w = new Widget(1);
  w.rect = RectF(0, 0, 100, 100);

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

// Verifies Widget.uId uniqueness and findByUId lookup.
unittest {
  auto root = new Widget(10);
  root.rect = RectF(0, 0, 200, 200);
  auto child1 = new Widget(20);
  child1.rect = RectF(0, 0, 50, 50);
  root.addChild(child1);
  auto child2 = new Widget(30);
  child2.rect = RectF(50, 0, 50, 50);
  root.addChild(child2);
  auto grandChild = new Widget(40);
  grandChild.rect = RectF(0, 0, 20, 20);
  child1.addChild(grandChild);

  assert(root.uId == 10);
  assert(child1.uId == 20);
  assert(child2.uId == 30);
  assert(grandChild.uId == 40);

  assert(root.findByUId(10) is root);
  assert(root.findByUId(20) is child1);
  assert(root.findByUId(30) is child2);
  assert(root.findByUId(40) is grandChild);
  assert(root.findByUId(999) is null);
  assert(child1.findByUId(30) is null);
}

// Verifies addChild, reparenting, removeChild, and single-parent ownership.
unittest {
  auto p1 = new Widget(1);
  auto p2 = new Widget(2);
  auto c = new Widget(3);

  assert(c.parent is null);
  assert(p1.children.length == 0);
  assert(p2.children.length == 0);

  // Add child to p1
  p1.addChild(c);
  assert(c.parent is p1);
  assert(p1.children.length == 1);
  assert(p1.children[0] is c);
  assert(p2.children.length == 0);

  // Re-adding to same parent is a no-op
  p1.addChild(c);
  assert(p1.children.length == 1);
  assert(c.parent is p1);

  // Adding to p2 automatically removes from p1 (single parent ownership)
  p2.addChild(c);
  assert(c.parent is p2);
  assert(p1.children.length == 0);
  assert(p2.children.length == 1);
  assert(p2.children[0] is c);

  // removeChild detaches c
  assert(p2.removeChild(c));
  assert(c.parent is null);
  assert(p2.children.length == 0);

  // removeChild when not a child returns false
  assert(!p2.removeChild(c));
}

// Verifies Widget.dumpTree serialization.
unittest {
  import std.json : parseJSON;
  import yguilib.widget.builder : WidgetBuilder;

  final class TestExtraComponent : WidgetComponent {
    string info;
    int count;
    this(string info, int count) {
      this.info = info;
      this.count = count;
    }
  }

  auto root = WidgetBuilder(100)
    .rect(RectF(0, 0, 800, 600))
    .flex(FlexDirection.column, 5.0f)
    .background(ColorF(0.1f, 0.2f, 0.3f, 1.0f))
    .build();
  root.name = "RootPanel";

  auto child = WidgetBuilder(101)
    .parent(root)
    .rect(RectF(10, 10, 120, 40))
    .fixedSize(120.0f, 40.0f)
    .text("DumpButton")
    .border(ColorF(1.0f, 1.0f, 1.0f, 1.0f), 2.0f)
    .build();
  child.name = "Button1";
  child.components.set(new TestExtraComponent("extraData", 7));

  // Dump without children
  string rootOnlyJson = root.dumpTree(false);
  auto parsedRootOnly = parseJSON(rootOnlyJson);
  assert(parsedRootOnly["type"].str == "Widget");
  assert(parsedRootOnly["fields"]["uId"].integer == 100);
  assert(parsedRootOnly["fields"]["name"].str == "RootPanel");
  assert("children" !in parsedRootOnly["fields"]);
  auto rootComps = parsedRootOnly["fields"]["components"]["fields"];
  assert(rootComps["flexContainer"]["type"].str == "FlexContainer");

  // Dump with children
  string fullTreeJson = root.dumpTree(true);
  auto parsedFull = parseJSON(fullTreeJson);
  assert(parsedFull["type"].str == "Widget");
  assert(parsedFull["fields"]["uId"].integer == 100);
  assert("children" in parsedFull["fields"]);
  auto childrenArray = parsedFull["fields"]["children"].array;
  assert(childrenArray.length == 1);

  auto parsedChild = childrenArray[0];
  assert(parsedChild["type"].str == "Widget");
  assert(parsedChild["fields"]["uId"].integer == 101);
  assert(parsedChild["fields"]["name"].str == "Button1");
  assert(parsedChild["fields"]["parentUId"].integer == 100);
  auto childComps = parsedChild["fields"]["components"]["fields"];
  assert(childComps["textLabel"]["fields"]["caption"].str == "DumpButton");

  // Check custom component serialized in child
  auto customMap = childComps["custom"].object;
  assert(TestExtraComponent.classinfo.name in customMap);
  auto parsedExtra = customMap[TestExtraComponent.classinfo.name];
  assert(parsedExtra["fields"]["info"].str == "extraData");
  assert(parsedExtra["fields"]["count"].integer == 7);
}
