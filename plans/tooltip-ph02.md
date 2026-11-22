# Phase 2: Builder Ergonomics & `guidemo` Integration

## Goal
Wire tooltip support into button builders and tab buttons, register
`TooltipSystem` and the topmost tooltip layer in `guidemo`, demonstrate tooltips
on buttons (including long truncated captions) and tabs, and add unit tests.

## Prerequisites
Phase 1 (`yguilib.controls.tooltip`) is complete and passing all tests.

## Constraints & Style Rules
- Follow `codestyle.md` & `.editorconfig`: 2-space indent, LF, max 80 chars/line,
  opening `{` on same line.
- Null safety: enforce `assert(... !is null)` on non-null arguments.
- Every widget built via `WidgetBuilder` must have a non-empty `.name(...)`.
- `yguilib/` must never depend on `source/guidemo/` or `source/yvidtrim/`.

## Files to Modify

### 1. `yguilib/source/yguilib/controls/hover_button_system.d`
- Import `Tooltip` from `yguilib.controls.tooltip`.
- Add fields to `AnimatedHoverButtonBuilder`:
  - `bool hasTooltip = false;`
  - `string tooltipText = null;`
- Add fluent methods (no default parameter values per `codestyle.md`):
  ```d
  ref AnimatedHoverButtonBuilder tooltip() return {
    hasTooltip = true;
    tooltipText = null;
    return this;
  }

  ref AnimatedHoverButtonBuilder tooltip(string hintText) return {
    hasTooltip = true;
    tooltipText = hintText;
    return this;
  }
  ```
- In `AnimatedHoverButtonBuilder.build(...)`: if `hasTooltip`, call
  `b.component(Tooltip.withText(tooltipText))`.
- Add a brief assertion in `hover_button_system.d` `unittest` verifying
  `.tooltip()` attaches `Tooltip` component.

### 2. `yguilib/source/yguilib/controls/tab_button.d`
- Import `Tooltip` from `yguilib.controls.tooltip`.
- In `createTabButton(...)`: attach `.component(new Tooltip())` (caption
  fallback so every tab button automatically exposes its full current caption as
  its tooltip, even when `TabButtonsProvider.updateWidgetAt` updates captions).
- Update `tab_button.d` `unittest` to assert `btnActive.components.has!Tooltip()`
  and `btnActive.components.get!Tooltip().resolveText(btnActive) == "Active Tab"`.

### 3. `source/guidemo/hover_button.d`
- Import `Tooltip` from `yguilib.controls.tooltip`.
- Add `bool hasTooltip = false;` and `string tooltipText = null;` to
  `HoverButtonBuilder`.
- Add overloaded fluent methods `.tooltip()` and `.tooltip(string hintText)`
  (no default parameter values per `codestyle.md`) to `HoverButtonBuilder`.
- In `HoverButtonBuilder.build(...)`: attach `Tooltip.withText(tooltipText)` to
  the visual child widget (the hit-tested widget that holds `TextLabel` and
  `MouseEvent`, `inputEnabled = true`).

### 4. `source/guidemo/guidemoapp.d`
- Import `TooltipLayerBuilder, TooltipSystem` from `yguilib.controls.tooltip`.
- Register `app.ui.registerWidgetSystem(new TooltipSystem());` right after
  `AnimatedHoverButtonSystem`.
- After `registerDemoPages(app.ui, demoTracker, rootWidget, hoverBtnController);`,
  build the tooltip layer as the **last** child of `rootWidget`:
  ```d
  TooltipLayerBuilder tooltipLayerBuilder;
  tooltipLayerBuilder.name("demoTooltipLayer").build(app.ui, rootWidget);
  ```
  (Check if there is a helper or test in `guidemoapp.d` or `view.d` — keep
  `DemoView` tests passing since `DemoView` itself doesn't add pages; the
  tooltip layer is added in `guidemoapp.d` after all pages so it is strictly
  the last/topmost child of `rootWidget`.)

### 5. `source/guidemo/pages/button_page.d` & `source/guidemo/pages/button_system_page.d`
- Enable `.tooltip()` on the showcase buttons (fade buttons, gradient buttons,
  and action/reset buttons).
- Make at least one button on `ButtonPage` and one on `ButtonSystemPage` have a
  descriptive caption longer than its fixed width (so the button text truncates
  with `...` inside the button, and hovering displays the full multiline text in
  the tooltip). Keep existing button names and action events intact so existing
  controller tests continue passing.
- Add unit test assertions in `button_page.d` and `button_system_page.d`
  verifying buttons have `Tooltip` components resolving to their full captions.

### 6. `source/guidemo/pages/tabcontrol_page.d`
- Enable `.tooltip()` on the `AnimatedHoverButtonBuilder` buttons on Page 5
  (Add Tab, Remove Tab, Reset Tabs, Narrow/Widen Viewport).
- Note: the `TabControl` tabs (both header tabs and Page 5 tabs) automatically
  get `Tooltip` via `createTabButton`. Add a unit test assertion confirming tab
  buttons in `TabControlPage` have `Tooltip`.

## Verification
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d --audit
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
```
