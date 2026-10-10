/// Layout components for the CSS-inspired flexbox-lite engine.
///
/// Provides the type vocabulary for the four-phase layout model
/// described in `documentation/css_layout_essentials_for_a_c_gui_library.md`:
///   Phase 1 - Insets & Constraints (Insets, Dimension, min/max)
///   Phase 2 - Direction & Spacing (FlexDirection, gap)
///   Phase 3 - Sizing Modes (SizingMode: auto_, fixed, fraction)
///   Phase 4 - Alignment (JustifyContent, AlignItems)
module yguilib.widget.layout_components;
import std.typecons : Nullable;
import yguilib.widget.component;

/// How a single dimension (width or height) is sized.
///
/// Every widget dimension should be one of these three modes
/// rather than a bare pixel value, so the layout engine can
/// distinguish between content-driven, explicit, and flexible
/// sizing during the measure/arrange passes.
enum SizingMode {
  /// Measured from content (intrinsic). The layout engine
  /// queries the widget's content (text extents, icon size, etc.)
  /// to determine the natural size.
  /// For FlexContainer it's sum of children sizes in FlexDirection,
  /// and max for cross axis. If there're no children, then
  /// text or other content/visible component size.
  auto_,
  /// Explicit value in logical points.
  /// Final pixel size = `value * dpiScale`.
  fixed,
  /// Absorbs remaining free space on the container's axis.
  /// The `value` field acts as a flex-grow weight: widgets with
  /// equal `value` share leftover space equally.
  fraction,
}

/// A dimension value paired with its sizing mode.
///
/// Used for width, height, minWidth, maxWidth, etc.
/// When `mode` is `auto_`, `value` is ignored by the engine.
struct Dimension {
  float value = 0;
  SizingMode mode = SizingMode.auto_;
}

struct Insets {
  float top = 0;
  float right = 0;
  float bottom = 0;
  float left = 0;

  this(float all) {
    top = right = bottom = left = all;
  }

  this(float vertical, float horizontal) {
    top = bottom = vertical;
    left = right = horizontal;
  }

  this(float top, float right, float bottom, float left) {
    this.top = top;
    this.right = right;
    this.bottom = bottom;
    this.left = left;
  }
}

/// Direction a flex container lays out its children along the
/// main axis. The cross axis is always perpendicular.
enum FlexDirection {
  /// Children flow left-to-right (main = X, cross = Y).
  row,
  /// Children flow top-to-bottom (main = Y, cross = X).
  column,
}

/// Distribution of children along the main axis.
enum JustifyContent {
  /// Pack children at the start of the main axis.
  start,
  /// Push children to the far end of the main axis.
  end,
  /// Center children along the main axis.
  center,
  /// Pin first/last children to container edges; distribute
  /// remaining space evenly between interior children.
  spaceBetween,
}

/// Alignment of children along the cross axis.
enum AlignItems {
  /// Pin children to the start of the cross axis.
  start,
  /// Pin children to the end of the cross axis.
  end,
  /// Center children along the cross axis.
  center,
  /// Stretch children to fill the container's cross-axis
  /// extent. This is the default behaviour.
  stretch,
}

/// Flex container component (CSS `display: flex`).
///
/// Attach to a `Widget` to make it lay out its children
/// according to the flexbox-lite model. A container without
/// this component uses no automatic layout.
class FlexContainer : Component {
  this() {}

  this(FlexDirection direction, float gap = 0) {
    this.direction = direction;
    this.gap = gap;
  }

  FlexContainer withJustify(JustifyContent justify) {
    this.justify = justify;
    return this;
  }

  FlexContainer withAlign(AlignItems align_) {
    this.alignItems = align_;
    return this;
  }

  static FlexContainer row(float gap = 0) {
    return new FlexContainer(FlexDirection.row, gap);
  }

  static FlexContainer column(float gap = 0) {
    return new FlexContainer(FlexDirection.column, gap);
  }

  // -- Phase 2: Direction & Spacing --

  /// Main axis direction for child flow.
  FlexDirection direction = FlexDirection.row;
  /// Spacing between children along the main axis, in logical
  /// points. Replaces per-child margin hacks.
  float gap = 0;

  // -- Phase 4: Alignment --

  /// How children are distributed along the main axis.
  JustifyContent justify = JustifyContent.start;
  /// How children are aligned along the cross axis.
  AlignItems alignItems = AlignItems.stretch;
}

/// Sizing component carrying a widget's own dimensional style.
///
/// Holds explicit width/height plus min/max constraints
/// (Phase 1 & 3).  Every widget that participates in
/// layout should carry this component.
class Size : Component {
  this() {}

  this(Insets padding) {
    this.padding = padding;
  }

  this(Dimension width, Dimension height) {
    this.width = width;
    this.height = height;
  }

  Size withPadding(Insets insets) {
    this.padding = insets;
    return this;
  }

  Size withMargin(Insets insets) {
    this.margin = insets;
    return this;
  }

  Size withMinSize(float minW, float minH = 0.0f) {
    this.minWidth = minW;
    this.minHeight = minH;
    return this;
  }

  Size withMaxSize(float maxW, float maxH = float.infinity) {
    this.maxWidth = maxW;
    this.maxHeight = maxH;
    return this;
  }

  static Size fixed(float w, float h) {
    auto sz = new Size();
    sz.width = Dimension(w, SizingMode.fixed);
    sz.height = Dimension(h, SizingMode.fixed);
    return sz;
  }

  static Size autoSize() {
    auto sz = new Size();
    sz.width = Dimension(0, SizingMode.auto_);
    sz.height = Dimension(0, SizingMode.auto_);
    return sz;
  }

  static Size fraction(float wFr, float hFr = 0.0f) {
    auto sz = new Size();
    sz.width = Dimension(wFr, SizingMode.fraction);
    sz.height = Dimension(
      hFr,
      hFr > 0.0f ? SizingMode.fraction : SizingMode.auto_
    );
    return sz;
  }

  // -- Phase 3: Sizing Modes --

  /// Desired width of the widget.
  Dimension width;
  /// Desired height of the widget.
  Dimension height;

  // -- Phase 1: Size Bounds --

  /// Minimum width constraint (logical points). Zero means
  /// unconstrained.
  float minWidth = 0;
  /// Maximum width constraint (logical points).
  /// `float.infinity` means unconstrained.
  float maxWidth = float.infinity;
  /// Minimum height constraint (logical points). Zero means
  /// unconstrained.
  float minHeight = 0;
  /// Maximum height constraint (logical points).
  /// `float.infinity` means unconstrained.
  float maxHeight = float.infinity;

  // -- Phase 1: Insets --

  /// Inner insets — shrinks the content area for children.
  /// Note: Border component also affects, i.e. children/content area is what
  /// left after (padding + border.width)
  Insets padding;

  /// Outer clearance from sibling widgets (applied by the parent
  /// flex container during arrangement).
  Insets margin;
}

/// Anchors a widget against its parent's content bounds.
///
/// Out-of-flow: ignored by parent `FlexContainer` flow and positioned
/// relative to the parent's content area (deducting border and padding).
class Anchor : Component {
  this() {}

  this(
    Nullable!float left,
    Nullable!float top = Nullable!float.init,
    Nullable!float right = Nullable!float.init,
    Nullable!float bottom = Nullable!float.init
  ) {
    this.left = left;
    this.top = top;
    this.right = right;
    this.bottom = bottom;
  }

  Anchor withRight(float right) {
    import std.typecons : nullable;
    this.right = nullable(right);
    return this;
  }

  Anchor withBottom(float bottom) {
    import std.typecons : nullable;
    this.bottom = nullable(bottom);
    return this;
  }

  Anchor withLeft(float left) {
    import std.typecons : nullable;
    this.left = nullable(left);
    return this;
  }

  Anchor withTop(float top) {
    import std.typecons : nullable;
    this.top = nullable(top);
    return this;
  }

  /// Offset from parent's left content edge in logical points.
  Nullable!float left;
  /// Offset from parent's top content edge in logical points.
  Nullable!float top;
  /// Offset from parent's right content edge in logical points.
  Nullable!float right;
  /// Offset from parent's bottom content edge in logical points.
  Nullable!float bottom;
}

unittest {
  // Insets constructors
  const Insets i1 = Insets(8.0f);
  assert(i1.top == 8.0f && i1.right == 8.0f && i1.bottom == 8.0f &&
    i1.left == 8.0f);

  const Insets i2 = Insets(6.0f, 12.0f);
  assert(i2.top == 6.0f && i2.bottom == 6.0f);
  assert(i2.left == 12.0f && i2.right == 12.0f);

  // FlexContainer builder
  auto fc = FlexContainer.row(8.0f)
    .withJustify(JustifyContent.center)
    .withAlign(AlignItems.stretch);
  assert(fc.direction == FlexDirection.row);
  assert(fc.gap == 8.0f);
  assert(fc.justify == JustifyContent.center);
  assert(fc.alignItems == AlignItems.stretch);

  // Size builder & factories
  auto szFixed = Size.fixed(100.0f, 50.0f)
    .withPadding(Insets(4.0f))
    .withMargin(Insets(2.0f))
    .withMinSize(80.0f)
    .withMaxSize(200.0f);
  assert(szFixed.width.mode == SizingMode.fixed);
  assert(szFixed.width.value == 100.0f);
  assert(szFixed.padding.top == 4.0f);
  assert(szFixed.margin.left == 2.0f);
  assert(szFixed.minWidth == 80.0f);
  assert(szFixed.maxWidth == 200.0f);

  auto szAuto = Size.autoSize();
  assert(szAuto.width.mode == SizingMode.auto_);

  auto szFrac = Size.fraction(1.0f);
  assert(szFrac.width.mode == SizingMode.fraction);

  // Anchor builder
  import std.typecons : nullable;
  auto anch = new Anchor(nullable(5.0f), nullable(10.0f))
    .withRight(15.0f)
    .withBottom(20.0f);
  assert(!anch.left.isNull && anch.left.get == 5.0f);
  assert(!anch.right.isNull && anch.right.get == 15.0f);
  assert(!anch.bottom.isNull && anch.bottom.get == 20.0f);
}
