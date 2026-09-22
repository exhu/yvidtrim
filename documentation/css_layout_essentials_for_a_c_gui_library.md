# Essential CSS-Inspired Layout Features for a C GUI Library

When designing a modern layout engine for a native C GUI library, implementing the full CSS specification is counter-productive. Multi-pass grid systems, complex float mechanics, and CSS table algorithms introduce engine bloat and edge-case bugs.

Instead, modern native engines (like Flexbox-based Yoga, Clay, or Dear ImGui’s internal layouts) prioritize a strict subset consisting of the **Box Model** and a single-pass **Flexbox-lite** architecture.

---

## 1. Feature Priority Matrix

Implement these features in the exact phases listed below. Each tier builds on the geometric guarantees of the tier before it.

```
Phase 1: Insets & Constraints (Box Model)
   │
   ▼
Phase 2: Direction & Spacing (Flex Flow + Gap)
   │
   ▼
Phase 3: Sizing Modes (Fixed, Intrinsic, Stretch)
   │
   ▼
Phase 4: Alignment & Distribution (Justify & Align)
```

---

## 2. Core Layout Features Breakdown

### Phase 1: Border-Box & Insets (The Foundation)
A node must reliably calculate its own outer boundary and content area before positioning children.

- **Strict `border-box` Sizing**:
  - Always enforce `total_width = content + padding + border`.
  - Avoid `content-box` models entirely; they complicate coordinate and clip math in native rendering.
- **Insets (Padding & Margin)**:
  - Provide a simple 4-float struct: `{ float top, right, bottom, left; }`.
  - **Padding**: Insets the layout boundary for children.
  - **Margin**: Provides outer clearance from siblings.
- **Size Bounds (`min`/`max` constraints)**:
  - `min_width`, `max_width`, `min_height`, `max_height`.
  - Prevents buttons and text inputs from collapsing to 0 or overflowing parents during window resize events.

### Phase 2: Flow Direction & Gaps
Replace hardcoded `(x, y)` coordinate positioning with relative flow structures.

- **`flex-direction` (`row` vs `column`)**:
  - Sets the **Main Axis** (flow direction) and the **Cross Axis** (perpendicular direction).
  - Nesting rows inside columns (and vice versa) covers 95% of all desktop/embedded application interfaces.
- **`gap` (`row_gap`, `column_gap`)**:
  - Handles uniform spacing directly inside the container logic.
  - Eliminates the need to write custom logic for `margin-right` on all elements except the `last-child`.

### Phase 3: Sizing Modes (Unit Representation)
Desktop displays differ in DPI scale, and windows resize dynamically. Every dimension should be represented through three distinct sizing modes:

| Sizing Mode | CSS Equivalent | Native Behavior |
| :--- | :--- | :--- |
| **Fixed** | `px` | Explicit dimension in logical points: `size = value * dpi_scale`. |
| **Intrinsic** | `fit-content` / `auto` | Driven by content bounds (e.g., text extents, icon size + padding). |
| **Fractional / Stretch** | `flex-grow` / `%` | Absorbs remaining free space on the container's axis. |

### Phase 4: Alignment & Distribution
Once fixed-size and intrinsic items are calculated, distribute remaining space along both axes.

#### Main Axis: `justify-content`
- **`flex-start`**: Pack elements at the start of the layout.
- **`flex-end`**: Push elements to the far end (standard for modal dialog button clusters: `[Cancel] [OK]`).
- **`center`**: Center children along the main axis.
- **`space-between`**: Pin first and last elements to container edges; distribute remaining space evenly between interior elements (ideal for toolbars and titlebars).

#### Cross Axis: `align-items`
- **`stretch`**: Default behavior; forces child controls to match the container's cross-axis dimension.
- **`center`**: Centers elements along the cross axis (keeps labels, icons, and input fields aligned along the same horizontal baseline).
- **`flex-start` / `flex-end`**: Pin children to top/bottom (in row) or left/right (in column).

---

## 3. Recommended Architectural Engine: Two-Pass Traversal

To guarantee determinism and avoid circular dependencies, implement a recursive two-pass layout pipeline:

```
                  Root Node
                     │
    [Pass 1: Measure (Post-Order / Bottom-Up)]
                     │
    1. Measure leaf nodes (Text metrics, Icons).
    2. Aggregate children's min/intrinsic sizes into parents.
    3. Apply padding and explicit constraints upwards.
                     │
                     ▼
    [Pass 2: Arrange (Pre-Order / Top-Down)]
                     │
    1. Resolve parent's actual dimensions from window/screen.
    2. Deduct fixed sizes, padding, and gaps to find free space.
    3. Distribute free space among stretch/flex items.
    4. Compute final absolute coordinates (x, y, w, h).
                     │
                     ▼
             Render / Paint Tree
```

---

## 4. Minimal C Data Structures

Below is a lean, cache-friendly struct layout for a C GUI node:

```c
#include <stdint.h>
#include <stdbool.h>

typedef enum {
    AXIS_ROW,
    AXIS_COLUMN
} FlexDirection;

typedef enum {
    JUSTIFY_START,
    JUSTIFY_END,
    JUSTIFY_CENTER,
    JUSTIFY_SPACE_BETWEEN
} JustifyContent;

typedef enum {
    ALIGN_START,
    ALIGN_END,
    ALIGN_CENTER,
    ALIGN_STRETCH
} AlignItems;

typedef enum {
    SIZE_AUTO,       // Measured from content
    SIZE_FIXED,      // Explicit pixels
    SIZE_PERCENT,    // Percentage of parent
    SIZE_STRETCH     // Flex grow / fill remainder
} SizingType;

typedef struct {
    SizingType type;
    float value;
} Dimension;

typedef struct {
    float top;
    float right;
    float bottom;
    float left;
} Insets;

typedef struct {
    float x;
    float y;
    float width;
    float height;
} Rect;

typedef struct UINode {
    // Style & Constraints
    FlexDirection  direction;
    JustifyContent justify;
    AlignItems     align;
    
    Dimension      width;
    Dimension      height;
    Insets         padding;
    Insets         margin;
    float          gap;

    // Computed Output (written during Arrange pass)
    Rect           bounds;

    // Hierarchy
    struct UINode* first_child;
    struct UINode* next_sibling;
} UINode;
```

---

## 5. Non-Essential Features (Defer for Future Milestones)

Avoid implementing these features initially, as they exponentially increase layout complexity:

1. **`flex-wrap`**: Introduces multi-line management and dynamic cross-axis expansion.
2. **CSS Grid**: Requires track calculation, span matrices, and multi-pass resolution.
3. **`position: relative` offsets**: Manual `top`/`left` offsets break the predictability of flow layouts.
4. **Percentage padding/margins**: In CSS, percentage padding is calculated relative to parent width even on the vertical axis, causing confusion. Restrict percentages solely to `width` and `height`.
5. **Arbitrary `z-index`**: Enforce paint order by depth-first tree traversal order before adding stacking context complexity.