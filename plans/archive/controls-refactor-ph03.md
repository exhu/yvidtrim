# Phase 3: Refactor `hover_button_system.d` and `scrollbars.d`

## Objective

Migrate `yguilib.controls.hover_button_system` and `yguilib.controls.scrollbars`
(plus `source/guidemo/pages/scrollbars_page.d` for `ScrollbarStyle` grouping)
to use the Phase 1-2 helpers and eliminate in-module duplication.

## Reference Files

- `yguilib/source/yguilib/controls/hover_button_system.d`
- `yguilib/source/yguilib/controls/scrollbars.d`
- `source/guidemo/pages/scrollbars_page.d`
- `yguilib/source/yguilib/controls/common.d`
- `yguilib/source/yguilib/controls/composite_view.d`
- `yguilib/source/yguilib/controls/internal/axis.d`
- `yguilib/source/yguilib/controls/testing.d`

## Detailed Steps

### 1. Refactor `yguilib/source/yguilib/controls/hover_button_system.d`

- Remove private `lerpColor`, `isWidgetVisible`, and `findHitButton`; import
  and call:
  - `lerpColor` and `normalizedIn` from `yguilib.render.render_types`
  - `isEffectivelyVisible` from `yguilib.widget`
  - `findTopmostWithComponent!AnimatedHoverButtonComponent` from
    `yguilib.widget.visible`
  - `orDefault`, `ButtonFace`, `applyButtonFaceStyle`, and
    `applyBgAndBorderColors` from `yguilib.controls.common`
- On `AnimatedHoverButtonComponent`:
  - Add `void releaseInteraction()` setting
    `isHovered = false; isPressed = false;`.
  - Add `void resetToNormal(Widget w)` resetting hover/press flags, stopping
    `hoverTimer` and `pressTimer`, zeroing `hoverProgress`/`pressProgress`, and
    calling `applyBgAndBorderColors(w, normalBg, normalBorder)` if
    `colorsInitialized`.
  - Reuse `releaseInteraction()` in `handleMouseMotion` and
    `handleWindowMouseLeave`, and `resetToNormal(w)` in `cleanInvisibleButtons`.
- In `AnimatedHoverButtonBuilder`:
  - Use `orDefault(widgetName, "animatedHoverButton")`.
  - Replace `applyVisualStyle` manual background/border/text chain with
    `ButtonFace` + `applyButtonFaceStyle`.
- In `stepComponent`:
  - Compute `const bool isGradBusy = ...` once before the `if` and reuse it in
    the return expression.
- In `unittest`:
  - Import `DummyWidgetSystemHost` from `yguilib.controls.testing` and remove
    the inline `DummyHost` class.

### 2. Refactor `yguilib/source/yguilib/controls/scrollbars.d`

- **`ScrollbarModel`:**
  - Add `long effMax() const nothrow @safe @nogc`
  - Add `long range() const nothrow @safe @nogc`
  - Add `long clampValue(long v) const`
  - Add `setMetrics`:
    `bool setMetrics(long minVal, long maxVal, long vis, long step, long val)`
    updates `min`, `max`, `visibleSize`, `stepSize`, `value` (clamped) and
    returns `true` if any field changed.
- **`ScrollbarStyle`:**
  - Regroup color fields into `WidgetColors`:
    ```d
    WidgetColors arrow = WidgetColors(
      ColorF(0.16f, 0.19f, 0.25f, 1.0f),
      ColorF(0.28f, 0.33f, 0.42f, 1.0f),
      ColorF(0.88f, 0.92f, 0.98f, 1.0f)
    );
    WidgetColors thumb = WidgetColors(
      ColorF(0.32f, 0.46f, 0.68f, 1.0f),
      ColorF(0.45f, 0.62f, 0.88f, 1.0f),
      ColorF(1.0f, 1.0f, 1.0f, 1.0f)
    );
    WidgetColors thumbDrag = WidgetColors(
      ColorF(0.42f, 0.62f, 0.92f, 1.0f),
      ColorF(0.62f, 0.80f, 1.0f, 1.0f),
      ColorF(1.0f, 1.0f, 1.0f, 1.0f)
    );
    WidgetColors disabled = defaultDisabledColors;
    ```
- **`ScrollbarWidgetView`:**
  - Use `ensureViewWidgetRegistered`, `findEntry`, `getEntryField`,
    `bindCompositeModel`, `unregisterCompositeWidget`, and
    `updateCompositeEntries` from `yguilib.controls.composite_view`.
  - Use `orDefault`, `firstPositive`, `applyBgAndBorderColors`,
    `applyEnabledState`, and `findArrowComposite` from
    `yguilib.controls.common`.
  - Delete pass-through `translateEventForViewWidget` override.
  - Merge `stepDecrement` and `stepIncrement` into
    `bool stepBy(Widget viewWidget, int dir, out long newValue)` and keep
    `stepDecrement` / `stepIncrement` as 1-line wrappers.
  - Extract `ThumbMetrics` (`effMin`, `effMax`, `range`, `trackLen`,
    `thumbLen`, `maxTravel`) and
    `ThumbMetrics computeThumbMetrics(ScrollbarEntry entry)` used by both
    `updateThumbDrag` and `syncEntryVisuals`.
  - Make `computeDraggedOffset` `private static`.
  - Replace all `isRow` axis ternaries with `Axis.of(entry.direction)`.
  - Deduplicate scoped `std.algorithm.comparison` imports (at most one per
    function where needed).
- **`ScrollbarWidgetViewController`:**
  - Remove redundant `override bool update()`.
  - Use `findOwningView!ScrollbarWidgetView(views, ev.view.viewWidget)` in
    `handleEvent`.
  - Replace `emitPositionChanged` with `emitViewValueEvent` from
    `yguilib.controls.common`.
- **`ScrollbarBuilder`:**
  - Use `setBuilderModel`, `setBuilderTracker`, `resolveBuilderRegistry`,
    `ensureDefaultModelTracker`, `orDefault`, `Axis`, `styledButton`, and
    `findWidgetView!ScrollbarWidgetView`.
- **`registerScrollbars`:**
  - Replace body with:
    ```d
    return registerWidgetViewPair!(
      ScrollbarWidgetView,
      ScrollbarWidgetViewController
    )(ui);
    ```
- **`unittest`:**
  - Use `RecordingUiSystem` and `verifyAllNamed` from
    `yguilib.controls.testing`.

### 3. Update `source/guidemo/pages/scrollbars_page.d`

- Update `amberStyle` and `emeraldStyle` field assignments in
  `buildReportingModeSection` and `buildPlaygroundSection` to use
  `.thumb.bg`, `.thumb.border`, `.thumbDrag.bg`, `.thumbDrag.border`.
- Verify no other files in `source/` or `yguilib/` reference the old flat
  `ScrollbarStyle` color field names.

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
