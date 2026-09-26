/// Layout components for the CSS-inspired flexbox-lite engine.
///
/// Provides the type vocabulary for the four-phase layout model
/// described in `documentation/css_layout_essentials_for_a_c_gui_library.md`:
///   Phase 1 - Insets & Constraints (Insets, Dimension, min/max)
///   Phase 2 - Direction & Spacing (FlexDirection, gap)
///   Phase 3 - Sizing Modes (SizingMode: auto_, fixed, fraction)
///   Phase 4 - Alignment (JustifyContent, AlignItems)
module yguilib.widget.layout;
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

/// Four-sided insets used for padding and margin.
///
/// Follows CSS shorthand order: top, right, bottom, left.
struct Insets {
  float top = 0;
  float right = 0;
  float bottom = 0;
  float left = 0;
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
  Insets padding;

  /// Outer clearance from sibling widgets.
  // can be replaced by dummy widgets, so don't implement yet
  // Insets margin;
}
