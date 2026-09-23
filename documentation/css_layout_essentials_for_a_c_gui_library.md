# Essential CSS-Inspired Layout Features for yguilib (D)

When designing a modern layout engine for a native GUI library,
implementing the full CSS specification is counter-productive.
Multi-pass grid systems, complex float mechanics, and CSS table
algorithms introduce engine bloat and edge-case bugs.

Instead, modern native engines (like Flexbox-based Yoga, Clay, or
Dear ImGui's internal layouts) prioritize a strict subset consisting
of the **Box Model** and a single-pass **Flexbox-lite** architecture.

---

## 1. Feature Priority Matrix

Implement these features in the exact phases listed below. Each tier
builds on the geometric guarantees of the tier before it.

```
Phase 1: Insets & Constraints (Box Model)
   |
   v
Phase 2: Direction & Spacing (Flex Flow + Gap)
   |
   v
Phase 3: Sizing Modes (Fixed, Intrinsic, Stretch)
   |
   v
Phase 4: Alignment & Distribution (Justify & Align)
```

---

## 2. Core Layout Features Breakdown

### Phase 1: Border-Box & Insets (The Foundation)
A node must reliably calculate its own outer boundary and content
area before positioning children.

- **Strict `border-box` Sizing**:
  - Always enforce
    `total_width = content + padding + border`.
  - Avoid `content-box` models entirely; they complicate coordinate
    and clip math in native rendering.
- **Insets (Padding & Margin)**:
  - Provide a simple 4-float struct (`Insets`).
  - **Padding**: Insets the layout boundary for children.
  - **Margin**: Provides outer clearance from siblings.
- **Size Bounds (`min`/`max` constraints)**:
  - `minWidth`, `maxWidth`, `minHeight`, `maxHeight`.
  - Prevents buttons and text inputs from collapsing to 0 or
    overflowing parents during window resize events.

### Phase 2: Flow Direction & Gaps
Replace hardcoded `(x, y)` coordinate positioning with relative
flow structures.

- **`FlexDirection` (`row` vs `column`)**:
  - Sets the **Main Axis** (flow direction) and the **Cross Axis**
    (perpendicular direction).
  - Nesting rows inside columns (and vice versa) covers 95% of all
    desktop/embedded application interfaces.
- **`gap` (`rowGap`, `columnGap`)**:
  - Handles uniform spacing directly inside the container logic.
  - Eliminates the need for custom margin logic on all elements
    except the last child.

### Phase 3: Sizing Modes (Unit Representation)
Desktop displays differ in DPI scale, and windows resize
dynamically. Every dimension should be represented through
distinct sizing modes:

| Sizing Mode   | CSS Equivalent       | Behavior          |
| :---          | :---                 | :---               |
| **fixed**     | `px`                 | Logical points.    |
| **auto**      | `fit-content`/`auto` | Content-driven.    |
| **fraction**  | `flex-grow` / `%`    | Fill free space.   |

### Phase 4: Alignment & Distribution
Once fixed-size and intrinsic items are calculated, distribute
remaining space along both axes.

#### Main Axis: `JustifyContent`
- **`start`**: Pack elements at the start of the layout.
- **`end`**: Push elements to the far end (standard for modal
  dialog button clusters: `[Cancel] [OK]`).
- **`center`**: Center children along the main axis.
- **`spaceBetween`**: Pin first and last elements to container
  edges; distribute remaining space evenly between interior
  elements (ideal for toolbars and titlebars).

#### Cross Axis: `AlignItems`
- **`stretch`**: Default; forces child controls to match the
  container's cross-axis dimension.
- **`center`**: Centers elements along the cross axis (keeps
  labels, icons, and input fields aligned along the same
  horizontal baseline).
- **`start` / `end`**: Pin children to top/bottom (in row) or
  left/right (in column).

---

## 3. Recommended Architectural Engine: Two-Pass Traversal

To guarantee determinism and avoid circular dependencies,
implement a recursive two-pass layout pipeline:

```
                  Root Node
                     |
    [Pass 1: Measure (Post-Order / Bottom-Up)]
                     |
    1. Measure leaf nodes (Text metrics, Icons).
    2. Aggregate children's min/intrinsic sizes into parents.
    3. Apply padding and explicit constraints upwards.
                     |
                     v
    [Pass 2: Arrange (Pre-Order / Top-Down)]
                     |
    1. Resolve parent's actual dimensions from window/screen.
    2. Deduct fixed sizes, padding, and gaps to find free space.
    3. Distribute free space among stretch/flex items.
    4. Compute final absolute coordinates (x, y, w, h).
                     |
                     v
             Render / Paint Tree
```

---

## 4. D Data Structures

Below is a lean struct layout for the layout system, implemented
in `yguilib.widget.layout`:

```d
/// Direction a flex container lays out its children.
enum FlexDirection {
  row,
  column,
}

/// Distribution of children along the main axis.
enum JustifyContent {
  start,
  end,
  center,
  spaceBetween,
}

/// Alignment of children along the cross axis.
enum AlignItems {
  start,
  end,
  center,
  stretch,
}

/// How a single dimension (width or height) is sized.
enum SizingMode {
  auto_,     /// Measured from content (intrinsic).
  fixed,     /// Explicit value in logical points.
  fraction,  /// Absorbs remaining space (flex-grow).
}

/// A dimension value paired with its sizing mode.
struct Dimension {
  float value = 0;
  SizingMode mode = SizingMode.auto_;
}

/// Four-sided insets used for padding and margin.
struct Insets {
  float top    = 0;
  float right  = 0;
  float bottom = 0;
  float left   = 0;
}
```

The `FlexContainer` component (attached to a `Widget`) carries
all style properties. Computed output (`bounds`) lives on the
`Widget.rect` field.

---

## 5. Non-Essential Features (Defer for Future Milestones)

Avoid implementing these features initially, as they
exponentially increase layout complexity:

1. **`flex-wrap`**: Introduces multi-line management and dynamic
   cross-axis expansion.
2. **CSS Grid**: Requires track calculation, span matrices, and
   multi-pass resolution.
3. **`position: relative` offsets**: Manual `top`/`left` offsets
   break the predictability of flow layouts.
4. **Percentage padding/margins**: In CSS, percentage padding is
   calculated relative to parent width even on the vertical axis,
   causing confusion. Restrict fractions solely to `width` and
   `height`.
5. **Arbitrary `z-index`**: Enforce paint order by depth-first
   tree traversal order before adding stacking context complexity.