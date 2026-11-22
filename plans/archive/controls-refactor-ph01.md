# Phase 1: Foundation Helpers and `controls/internal/axis.d`

## Objective

Add low-risk pure helpers to `yguilib.render.render_types`, `yguilib.widget`,
`yguilib.widget.visible`, and `yguilib.widget.widget_view`, and create the
package-internal `yguilib.controls.internal.axis` module.

## Reference Files

- `yguilib/source/yguilib/render/render_types.d`
- `yguilib/source/yguilib/widget/package.d`
- `yguilib/source/yguilib/widget/visible.d`
- `yguilib/source/yguilib/widget/widget_view.d`
- `yguilib/source/yguilib/widget/internal/layout_axis.d`
- `yguilib/meson.build`

## Detailed Steps

### 1. Modify `yguilib/source/yguilib/render/render_types.d`

Add two free functions and unit tests:
- `ColorF lerpColor(in ColorF a, in ColorF b, float t)`:
  - Scoped `import std.algorithm.comparison : clamp;`.
  - Clamps `t` to `[0.0f, 1.0f]` and linearly interpolates `r`, `g`, `b`, `a`.
- `PointF normalizedIn(in RectF r, in PointF p)`:
  - If `r.width <= 0.0f || r.height <= 0.0f`: return `PointF(0.5f, 0.5f)`.
  - Otherwise clamp `(p.x - r.x) / r.width` and `(p.y - r.y) / r.height`
    to `[0.0f, 1.0f]`.
- Add `unittest` verifying `lerpColor` (0, 0.5, 1, clamped <0 and >1) and
  `normalizedIn` (center, corners, out-of-bounds clamping, zero-size rect).

### 2. Modify `yguilib/source/yguilib/widget/package.d`

- Add free function:
  ```d
  /// Returns true if `w` and all of its ancestors have `visible == true`.
  bool isEffectivelyVisible(const Widget w) nothrow @safe @nogc {
    for (const(Widget) curr = w; curr !is null; curr = curr.parent) {
      if (!curr.visible) {
        return false;
      }
    }
    return w !is null;
  }
  ```
- Add `unittest` covering `null`, visible chain, hidden self, and hidden
  ancestor.

### 3. Modify `yguilib/source/yguilib/widget/visible.d`

- Import `PointF` from `yguilib.render.render_types` and `WidgetComponent`
  from `yguilib.widget.component`.
- Add template free function:
  ```d
  Widget findTopmostWithComponent(C : WidgetComponent)(
    VisibleWidgets widgets,
    PointF p
  ) {
    foreach_reverse (ref vw; widgets) {
      if (vw.widget is null || !vw.widget.components.has!C()) {
        continue;
      }
      if (vw.hasClip && !vw.clipRect.contains(p)) {
        continue;
      }
      if (vw.absRect.contains(p)) {
        return vw.widget;
      }
    }
    return null;
  }
  ```
- Add `unittest` verifying topmost selection, missing-component skipping, and
  `hasClip` / `clipRect` rejection.

### 4. Modify `yguilib/source/yguilib/widget/widget_view.d`

- In `WidgetViewControllerBase`, add default `update()` implementation:
  ```d
  override bool update() {
    return true;
  }
  ```
- Remove the redundant `override bool update()` from
  `DefaultWidgetViewController`.

### 5. Create `yguilib/source/yguilib/controls/internal/axis.d`

- Declare `module yguilib.controls.internal.axis;` and `package(yguilib):`.
- Import `PointF`, `RectF` from `yguilib.render.render_types` and
  `Dimension`, `FlexDirection`, `Size`, `SizingMode` from
  `yguilib.widget.layout_components`.
- Implement `struct Axis` with non-overloaded methods (per `codestyle.md`):
  - `bool isRow = true;`
  - `static Axis of(FlexDirection d) nothrow @safe @nogc`
  - `float mainCoord(PointF p) const nothrow @safe @nogc`
  - `float crossCoord(PointF p) const nothrow @safe @nogc`
  - `float mainPos(RectF r) const nothrow @safe @nogc`
  - `float crossPos(RectF r) const nothrow @safe @nogc`
  - `float mainSize(RectF r) const nothrow @safe @nogc`
  - `float crossSize(RectF r) const nothrow @safe @nogc`
  - `PointF makePoint(float main, float cross) const nothrow @safe @nogc`
  - `PointF withMainCoord(PointF p, float main) const nothrow @safe @nogc`
  - `Size fillMain() const`
  - `void setFixedCrossSize(Size sz, float crossLen) const`
    (asserts `sz !is null`)
  - `Size fillMainFixedCross(float crossLen) const`
  - `string decArrow() const nothrow @safe @nogc` (`"<"` / `"^"`)
  - `string incArrow() const nothrow @safe @nogc` (`">"` / `"v"`)
- Add `unittest` covering both `FlexDirection.row` and
  `FlexDirection.column`.

### 6. Register in `yguilib/meson.build`

- Add `'source/yguilib/controls/internal/axis.d',` in alphabetical order under
  `yguilib/controls/` in `yguilib_src`.

## Verification

Run:
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
```
All commands must pass with 0 errors.
