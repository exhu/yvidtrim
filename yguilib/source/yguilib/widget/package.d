module yguilib.widget;
import yguilib.widget.component;
import yguilib.widget.drawing_components;
import yguilib.render.render_types;
import yguilib.widget.layout_components;
import yguilib.widget.input_components;

// TODO implement code first approach, without symbolic bindings

/// widgets can have this component to mark a root view
abstract class View : Component {
  //TrackedViewModel[string] params;

  /// exported events, if values are not null/empty then the event is exported
  /// under a new name up the tree
  string[string] events;
  // TODO

  /// must update controls
  abstract void update();
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
  InputEnabled inputEnabled;
  Focus focus;
  DefaultButton defaultButton;
  KeyboardAction keyboardAction;
}

/// Classification of widget invalidation for scoped and batch mutators.
enum InvalidationKind {
  /// Redraw visual paint only without recalculating layout geometry.
  paint,
  /// Recalculate layout geometry and redraw.
  layout,
}

/// Resolves the field name in WidgetComponents matching component type T
/// (or matching superclass for polymorphic components like View).
template componentMemberName(T) {
  import std.traits : FieldNameTuple;

  private template findField(fields...) {
    static if (fields.length == 0) {
      static assert(
        false,
        "Type " ~ T.stringof ~ " is not a component of Widget"
      );
    } else {
      static if (
        is(typeof(__traits(getMember, WidgetComponents, fields[0])) == T) ||
        is(T : typeof(__traits(getMember, WidgetComponents, fields[0])))
      ) {
        enum findField = fields[0];
      } else {
        enum findField = findField!(fields[1 .. $]);
      }
    }
  }

  enum componentMemberName = findField!(FieldNameTuple!WidgetComponents);
}

/// Resolves the default InvalidationKind for component type T.
template defaultInvalidationKind(T) {
  static if (
    is(T == FlexContainer) ||
    is(T == Size) ||
    is(T == Anchor) ||
    is(T == Border) ||
    is(T == TextLabel) ||
    is(T : View)
  ) {
    enum defaultInvalidationKind = InvalidationKind.layout;
  } else {
    enum defaultInvalidationKind = InvalidationKind.paint;
  }
}

final class Widget {
  this(Widget parent, RectF rect) {
    this.parent = parent;
    this.rect = rect;
    if (parent)
      parent.children ~= this;
  }

  /// Returns true if this widget has auto sizing on width or height.
  bool hasAutoSizing() const {
    if (components.size !is null) {
      return components.size.width.mode == SizingMode.auto_ ||
        components.size.height.mode == SizingMode.auto_;
    }
    return false;
  }

  /// Returns true if this widget is currently inside a batchUpdate block.
  bool isBatching() const {
    return batchDepth > 0;
  }

  /// Sets the dirty flag.
  /// If layout is true, or if this widget has auto-sized dimensions,
  /// marks this widget and its ancestors as layout-dirty so the layout
  /// system recalculates stale geometry.
  /// If layout is false, marks only this widget as dirty for redrawing,
  /// preserving cached layout calculations.
  /// When batchUpdate() is active, ancestor tree walks are deferred until
  /// the outermost batch scope finishes.
  void markDirty(bool layout = true) {
    dirty = true;
    if (batchDepth > 0) {
      batchPendingDirty = true;
      if (layout || hasAutoSizing()) {
        batchPendingLayout = true;
        layoutDirty = true;
      }
      return;
    }
    if (layout || hasAutoSizing()) {
      markLayoutDirty();
    }
  }

  /// Sets the dirty flag using an InvalidationKind.
  void markDirty(InvalidationKind kind) {
    markDirty(kind == InvalidationKind.layout);
  }

  /// Marks this widget and its ancestors as layout dirty.
  /// When batchUpdate() is active, ancestor tree walks are deferred until
  /// the outermost batch scope finishes.
  void markLayoutDirty() {
    layoutDirty = true;
    dirty = true;
    if (batchDepth > 0) {
      batchPendingDirty = true;
      batchPendingLayout = true;
      return;
    }
    if (parent !is null && !parent.layoutDirty) {
      parent.markLayoutDirty();
    }
  }

  /// Mutates an attached component using its default InvalidationKind.
  Widget modify(T)(scope void delegate(T) fn) {
    return modify!T(defaultInvalidationKind!T, fn);
  }

  /// Mutates an attached component with an explicit InvalidationKind.
  Widget modify(T)(InvalidationKind kind, scope void delegate(T) fn) {
    enum memberName = componentMemberName!T;
    alias FieldType = typeof(__traits(getMember, components, memberName));
    static if (is(T == FieldType)) {
      auto comp = __traits(getMember, components, memberName);
    } else {
      auto rawComp = __traits(getMember, components, memberName);
      assert(
        rawComp !is null,
        "Cannot modify null " ~ T.stringof ~ " on Widget"
      );
      auto comp = cast(T) rawComp;
      assert(comp !is null, "Component is not of type " ~ T.stringof);
    }
    assert(comp !is null, "Cannot modify null " ~ T.stringof ~ " on Widget");
    fn(comp);
    markDirty(kind == InvalidationKind.layout);
    return this;
  }

  /// Overload accepting boolean layout flag.
  Widget modify(T)(bool layout, scope void delegate(T) fn) {
    return modify!T(
      layout ? InvalidationKind.layout : InvalidationKind.paint,
      fn
    );
  }

  /// Struct overloads for future Phase 3 value-struct components.
  static if (!is(T == class)) {
    Widget modify(T)(scope void delegate(ref T) fn) {
      return modify!T(defaultInvalidationKind!T, fn);
    }

    Widget modify(T)(InvalidationKind kind, scope void delegate(ref T) fn) {
      enum memberName = componentMemberName!T;
      fn(__traits(getMember, components, memberName));
      markDirty(kind == InvalidationKind.layout);
      return this;
    }

    Widget modify(T)(bool layout, scope void delegate(ref T) fn) {
      return modify!T(
        layout ? InvalidationKind.layout : InvalidationKind.paint,
        fn
      );
    }
  }

  /// Batches multiple updates to this widget, defaulting to layout dirty.
  void batchUpdate(scope void delegate() fn) {
    batchUpdate(InvalidationKind.layout, fn);
  }

  /// Batches multiple updates with an explicit default InvalidationKind.
  void batchUpdate(InvalidationKind defaultKind, scope void delegate() fn) {
    batchPendingDirty = true;
    if (defaultKind == InvalidationKind.layout) {
      batchPendingLayout = true;
      layoutDirty = true;
    }
    ++batchDepth;
    scope(exit) {
      --batchDepth;
      if (batchDepth == 0) {
        const bool lay = batchPendingLayout;
        const bool dirtyNeeded = batchPendingDirty;
        batchPendingDirty = false;
        batchPendingLayout = false;
        if (lay) {
          if (parent !is null && !parent.layoutDirty) {
            parent.markLayoutDirty();
          }
        }
      }
    }
    fn();
  }

  /// Overload accepting boolean layout flag.
  void batchUpdate(bool layout, scope void delegate() fn) {
    batchUpdate(
      layout ? InvalidationKind.layout : InvalidationKind.paint,
      fn
    );
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
  WidgetComponents components;
  bool handleInput;
  bool visible = true;
  bool clipContents = true;
  bool clipChildren = false;
  Widget[] children;
  bool dirty = true;
  bool layoutDirty = true;

private:
  /// Nesting depth of active batchUpdate() scopes. When greater than zero,
  /// ancestor tree invalidation passes are deferred until the outermost
  /// batch ends.
  uint batchDepth = 0;

  /// Tracks whether any paint or layout invalidation occurred during a batch.
  bool batchPendingDirty = false;

  /// Tracks whether a layout recalculation was requested during a batch.
  bool batchPendingLayout = false;
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

unittest {
  // Unit tests for modify!T
  auto root = new Widget(null, RectF(0, 0, 200, 200));
  auto child = new Widget(root, RectF(0, 0, 100, 100));

  child.components.background = new Background(ColorF(1, 0, 0, 1));
  child.components.border = new Border(ColorF(0, 1, 0, 1));
  child.components.size = new Size;
  child.components.size.width = Dimension(100, SizingMode.fixed);
  child.components.size.height = Dimension(100, SizingMode.fixed);

  root.dirty = false;
  root.layoutDirty = false;
  child.dirty = false;
  child.layoutDirty = false;

  // 1. modify!Background defaults to paint-only invalidation
  child.modify!Background((bg) {
    bg.color = ColorF(0, 0, 1, 1);
  });
  assert(child.dirty);
  assert(!child.layoutDirty);
  assert(!root.dirty);
  assert(!root.layoutDirty);

  // 2. modify!Size defaults to layout invalidation
  child.dirty = false;
  child.modify!Size((sz) {
    sz.width = Dimension(120, SizingMode.fixed);
  });
  assert(child.dirty);
  assert(child.layoutDirty);
  assert(root.dirty);
  assert(root.layoutDirty);

  // 3. Explicit InvalidationKind overrides
  root.dirty = false;
  root.layoutDirty = false;
  child.dirty = false;
  child.layoutDirty = false;

  // Border defaults to layout, but override to paint
  child.modify!Border(InvalidationKind.paint, (b) {
    b.color = ColorF(1, 1, 0, 1);
  });
  assert(child.dirty);
  assert(!child.layoutDirty);
  assert(!root.layoutDirty);

  // Background defaults to paint, but override to layout
  child.dirty = false;
  child.modify!Background(InvalidationKind.layout, (bg) {
    bg.cornerRadius = 20.0f;
  });
  assert(child.dirty);
  assert(child.layoutDirty);
  assert(root.layoutDirty);

  // 4. Fluent return chaining
  child.dirty = false;
  auto ret = child
    .modify!Background((bg) { bg.color.a = 0.5f; })
    .modify!Border(InvalidationKind.paint, (b) { b.width = 3.0f; });
  assert(ret is child);

  // 5. Attempting to modify null component throws AssertError
  import core.exception : AssertError;
  import std.exception : assertThrown;

  auto bare = new Widget(null, RectF(0, 0, 10, 10));
  assertThrown!AssertError(bare.modify!Background((bg) { bg.color.a = 0; }));
}

unittest {
  // Unit tests for batchUpdate
  auto root = new Widget(null, RectF(0, 0, 300, 300));
  auto parent = new Widget(root, RectF(0, 0, 200, 200));
  auto child = new Widget(parent, RectF(0, 0, 100, 100));

  child.components.background = new Background(ColorF(1, 0, 0, 1));
  child.components.textLabel = new TextLabel("Initial", ColorF(1, 1, 1, 1));
  child.components.size = new Size;
  child.components.size.width = Dimension(100, SizingMode.fixed);
  child.components.size.height = Dimension(100, SizingMode.fixed);

  root.dirty = false;
  root.layoutDirty = false;
  parent.dirty = false;
  parent.layoutDirty = false;
  child.dirty = false;
  child.layoutDirty = false;

  // 1. batchUpdate on child coalesces updates and walks parent once
  child.batchUpdate({
    assert(child.isBatching());
    child.modify!Background((bg) { bg.color = ColorF(0, 1, 0, 1); });
    child.modify!TextLabel((tl) { tl.caption = "Updated"; });
    // Intermediate check: ancestors not yet walked
    assert(!parent.layoutDirty);
    assert(!root.layoutDirty);
  });
  assert(!child.isBatching());
  assert(child.dirty);
  assert(child.layoutDirty);
  assert(parent.layoutDirty);
  assert(root.layoutDirty);

  // 2. Paint-only batch without layout changes does not walk ancestors
  root.dirty = false;
  root.layoutDirty = false;
  parent.dirty = false;
  parent.layoutDirty = false;
  child.dirty = false;
  child.layoutDirty = false;

  child.batchUpdate(InvalidationKind.paint, {
    child.modify!Background((bg) { bg.color.a = 0.8f; });
  });
  assert(child.dirty);
  assert(!child.layoutDirty);
  assert(!parent.dirty);
  assert(!parent.layoutDirty);
  assert(!root.layoutDirty);

  // 3. Paint batch escalates to layout if layout mutation occurs inside
  child.dirty = false;
  child.batchUpdate(InvalidationKind.paint, {
    child.modify!Background((bg) { bg.color.a = 0.9f; });
    child.modify!Size((sz) { sz.width = Dimension(150, SizingMode.fixed); });
  });
  assert(child.dirty);
  assert(child.layoutDirty);
  assert(parent.layoutDirty);
  assert(root.layoutDirty);

  // 4. Nested batchUpdate
  root.layoutDirty = false;
  parent.layoutDirty = false;
  child.layoutDirty = false;

  child.batchUpdate({
    child.batchUpdate(InvalidationKind.paint, {
      child.modify!Background((bg) { bg.color.a = 0.2f; });
    });
    // Inner batch ended, but outer batch still active
    assert(child.isBatching());
    assert(!parent.layoutDirty);
    child.modify!TextLabel((tl) { tl.caption = "Nested"; });
  });
  assert(!child.isBatching());
  assert(child.layoutDirty);
  assert(parent.layoutDirty);
  assert(root.layoutDirty);

  // 5. Exception safety restores batchDepth
  child.dirty = false;
  child.layoutDirty = false;
  try {
    child.batchUpdate({
      child.modify!Background((bg) { bg.color.a = 0.1f; });
      throw new Exception("Test exception");
    });
  } catch (Exception) {}
  assert(!child.isBatching());
}

