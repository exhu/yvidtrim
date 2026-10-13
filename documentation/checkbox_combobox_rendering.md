# Checkbox and Combobox Rendering Overview for yguilib

## Question
Is image loading support necessary to implement and draw checkbox and combobox
controls in `yguilib`?

## Answer
**No, image loading support is not necessary.** Both controls can be fully
rendered using the existing rendering capabilities in `yguilib`.

---

## Rendering Approaches

### 1. Vector and Geometric Primitives (Recommended)
`yguilib.render.Renderer` already provides hardware-accelerated 2D vector
drawing primitives:
- `drawFillRect`, `drawRect`
- `drawFillRoundRect`, `drawRoundRect`
- `drawLine(point1, point2, lineWidth, color)`

#### Checkbox Implementation
- **Box container**:
  - `drawRoundRect` or `drawRect` for the outer border.
  - `drawFillRoundRect` or `drawFillRect` for the checked/hover background.
- **Checkmark (✓)**:
  - Two connected line segments using `drawLine` with configurable line width:
    - Segment 1: from `(x + 0.25 * w, y + 0.50 * h)` to
      `(x + 0.45 * w, y + 0.70 * h)`
    - Segment 2: from `(x + 0.45 * w, y + 0.70 * h)` to
      `(x + 0.75 * w, y + 0.30 * h)`
- **Indeterminate state (−)**:
  - A single horizontal line segment via `drawLine`, or a small filled rect
    via `drawFillRect`.

#### Combobox Implementation
- **Input / selection field**:
  - Bounding box and background using `drawRoundRect` / `drawFillRoundRect`.
- **Selected item text**:
  - Rendered via existing `TextLabel` component or `drawTextLine`.
- **Dropdown indicator (chevron / arrow ▼)**:
  - Two angled line segments forming a chevron using `drawLine`:
    - Segment 1: from `(x1, y1)` down to `(x2, y2)`
    - Segment 2: from `(x2, y2)` up to `(x3, y1)`
- **Popup menu / dropdown list**:
  - A child container widget rendered with background, border, item list, and
    optional scroll clipping via `pushClipRect`/`popClipRect`.

---

### 2. Unicode Font Glyphs
`yguilib.render` integrates TrueType font rendering via SDL3_ttf
(`drawTextLine` and `TextLabel`). As an alternative or fallback to manual line
drawing:
- **Checkmark**: Unicode glyphs such as `✓` (`\u2713`) or `✔` (`\u2714`).
- **Dropdown indicator**: Unicode glyphs such as `▼` (`\u25BC`), `▾` (`\u25BE`),
  or `⌄` (`\u2304`).

---

## Benefits of Procedural / Vector Drawing
1. **DPI and scale resilience**: Scales cleanly with `displayScaling` and
   `unitsScaling` without raster pixelation or asset mipmapping.
2. **Dynamic theming**: Colors for checkmarks, arrows, borders, and backgrounds
   can be changed at runtime without creating or loading multiple asset files.
3. **No extra dependencies**: Avoids adding image decoders (PNG, SVG, etc.) or
   asset pipeline dependencies to `yguilib`.
