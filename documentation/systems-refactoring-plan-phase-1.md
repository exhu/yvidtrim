# Phase 1: Public `VisibleWidget` API & Custom `WidgetComponents`

Part of `documentation/systems-refactoring-plan-overview.md`.

## Goal

1. Move `VisibleWidget` and `VisibleWidgets` out of the internal module
   `yguilib.widget.internal.collect_visible` into a dedicated public module
   `yguilib.widget.visible` (`yguilib/source/yguilib/widget/visible.d`) so
   user-defined widget systems can inspect resolved screen rects and clipping
   bounds.
2. Keep `VisibleWidgetsCollector` internal (`package(yguilib)`) inside
   `yguilib.widget.internal.collect_visible`.
3. Extend `WidgetComponents` in `yguilib/source/yguilib/widget/package.d` with
   dynamic storage for user-defined `Component` subclasses (`set!C` and
   `get!C`), and add a `.component!C` convenience method to `WidgetBuilder` in
   `yguilib/source/yguilib/widget/builder.d`.

---

## Step-by-Step Instructions

### Step 1.1: Create `yguilib/source/yguilib/widget/visible.d`

Create a new public module `yguilib/source/yguilib/widget/visible.d` containing
`VisibleWidget` and `VisibleWidgets`:

```d
module yguilib.widget.visible;

import yguilib.render.render_types : RectF;
import yguilib.widget : Widget;

/// Represents a visible widget in pre-order (root-to-leaf, back-to-front)
/// traversal along with its resolved screen-space rectangle and active
/// ancestor clip rectangle.
struct VisibleWidget {
  Widget widget;
  RectF absRect;
  bool hasClip;
  RectF clipRect;
}

/// Contiguous slice of visible widgets in pre-order (root-to-leaf).
alias VisibleWidgets = VisibleWidget[];
```

### Step 1.2: Update `yguilib/source/yguilib/widget/internal/collect_visible.d`

In `yguilib/source/yguilib/widget/internal/collect_visible.d`:
1. Remove the definitions of `struct VisibleWidget` and `alias VisibleWidgets`.
2. Import `VisibleWidget` and `VisibleWidgets` from `yguilib.widget.visible`:
   ```d
   module yguilib.widget.internal.collect_visible;

   import std.array : Appender;
   import yguilib.render : Renderer;
   import yguilib.render.render_types : RectF, intersectRects;
   import yguilib.widget : Widget;
   import yguilib.widget.visible : VisibleWidget, VisibleWidgets;

   package(yguilib):

   final class VisibleWidgetsCollector {
   ```

### Step 1.3: Update Internal Imports of `VisibleWidget` / `VisibleWidgets`

Update all internal modules that previously imported `VisibleWidget` or
`VisibleWidgets` from `yguilib.widget.internal.collect_visible` to import them
from `yguilib.widget.visible`:

1. **`yguilib/source/yguilib/widget/internal/focus_system.d`**:
   Replace the `collect_visible` import with:
   ```d
   import yguilib.widget.visible : VisibleWidget, VisibleWidgets;
   ```

2. **`yguilib/source/yguilib/widget/internal/input_system.d`**:
   Replace the `collect_visible` import with:
   ```d
   import yguilib.widget.visible : VisibleWidget, VisibleWidgets;
   ```

3. **`yguilib/source/yguilib/widget/internal/layout_system.d`**:
   Replace the top-level `collect_visible` import with:
   ```d
   import yguilib.widget.visible : VisibleWidget, VisibleWidgets;
   ```
   *(Keep `import yguilib.widget.internal.collect_visible :
   VisibleWidgetsCollector;` inside `unittest` blocks in `layout_system.d`.)*

4. **`yguilib/source/yguilib/widget/internal/widget_painter.d`**:
   Replace the top-level `collect_visible` import with:
   ```d
   import yguilib.widget.visible : VisibleWidgets;
   ```
   *(Keep `import yguilib.widget.internal.collect_visible :
   VisibleWidgetsCollector;` inside the `unittest` block.)*

5. **`yguilib/source/yguilib/internal/uisystem_controller.d`**:
   Update imports to explicitly import `VisibleWidgets` from
   `yguilib.widget.visible` and `VisibleWidgetsCollector` from
   `yguilib.widget.internal.collect_visible`:
   ```d
   import yguilib.widget.visible : VisibleWidgets;
   import yguilib.widget.internal.collect_visible : VisibleWidgetsCollector;
   ```

6. **`yguilib/source/yguilib/internal/uisystem_impl.d`**:
   Remove unused `import yguilib.widget.internal.collect_visible;`.

### Step 1.4: Register `visible.d` in `yguilib/meson.build`

In `yguilib/meson.build`, add `'source/yguilib/widget/visible.d'` to
`yguilib_src` in alphabetical order:

```meson
  'source/yguilib/widget/layout_components.d',
  'source/yguilib/widget/package.d',
  'source/yguilib/widget/visible.d',
  'source/yguilib/window.d',
```

### Step 1.5: Add Custom Component Storage to `WidgetComponents`

In `yguilib/source/yguilib/widget/package.d`, extend `struct WidgetComponents`
to store and retrieve user-defined `Component` subclasses by their static class
type (`typeid(C)`), adhering to visibility ordering (`public` methods/fields
first, `private:` section last):

```d
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
```

### Step 1.6: Add `.component!C` Helper to `WidgetBuilder`

In `yguilib/source/yguilib/widget/builder.d`:
1. Import `Component` from `yguilib.widget.component`:
   ```d
   import yguilib.widget.component : Component;
   ```
2. Add a fluent builder method to `WidgetBuilder`:
   ```d
   /// Attaches a custom user-defined Component of type C to the widget.
   ref WidgetBuilder component(C : Component)(C comp) return {
     widget.components.set!C(comp);
     return this;
   }
   ```

### Step 1.7: Add Unit Tests for Custom Components

1. In `yguilib/source/yguilib/widget/package.d`, add a `unittest` verifying:
   - Defining two custom `Component` subclasses (e.g., `TooltipComponent` and
     `BadgeComponent`).
   - Querying `w.components.get!TooltipComponent()` returns `null` and
     `w.components.has!TooltipComponent()` returns `false` initially.
   - Calling `w.components.set(new TooltipComponent("Info"))` stores the
     component and `get!TooltipComponent()` retrieves it (including on a
     `const(Widget)` reference).
   - Setting a second custom component type does not overwrite the first.
   - Replacing an existing custom component of the same type updates the stored
     instance.
   - Calling `w.components.set!TooltipComponent(null)` removes the entry.
2. In `yguilib/source/yguilib/widget/builder.d`, add a `unittest` verifying
   `WidgetBuilder(RectF(0, 0, 50, 50)).component(myComp).build()`.

---

## Verification

Run the following commands and ensure zero errors or warnings:

```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
```
