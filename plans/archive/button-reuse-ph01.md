# Phase 1 - ButtonSystem infrastructure

Context: see [overview](button-reuse.md). Later phases rebuild tab buttons
and arrow buttons on `ButtonBuilder`; this phase adds what they need.
Read `AGENTS.md` and `codestyle.md` first (2-space indent, <= 80 chars,
keep existing comments/docstrings).

## Files
- `yguilib/source/yguilib/controls/button.d`
- `yguilib/source/yguilib/controls/internal/button_support.d`
- `yguilib/source/yguilib/controls/testing.d` (DummyWidgetSystemHost)
- `yguilib/source/yguilib/internal/uisystem_impl.d`
- `source/guidemo/guidemoapp.d`

## Steps
1. `button.d`: add
   ```d
   /// When a button sends its `actionEvent`.
   enum ButtonTrigger { release, press }
   ```
   - `ButtonComponent.trigger` (default `release`), copied by
     `ButtonBuilder.build`; builder setter `trigger(ButtonTrigger t)`.
   - `handleMouseButtonDown`: after starting the press, if
     `comp.trigger == press` call `emitButtonAction(ctx, hit,
     comp.actionEvent)`.
   - `handleMouseButtonUp`: emit only when `comp.trigger == release`
     (release still un-sinks / restarts animation).
   - Update the module DESIGN comment accordingly.
2. `ButtonBuilder.visible(bool)`: initial visibility (apply via the
   WidgetBuilder `.visible(false)` in build, as tabcontrol's old arrow
   builder did). Add `paddingInsets(Insets)` to the `ButtonBuilderCommon`
   mixin only if needed (tab padding `Insets(5,8,5,8)` == `vh(5,8)`, arrow
   `Insets(2,4,2,4)` == `vh(2,4)`, so likely not needed - skip if so).
   Also add `ButtonBuilder.disabledColors(in WidgetColors)` and
   `ButtonBuilder.sink(float px)` setters on `buttonStyle`.
3. Free function in `button.d`:
   ```d
   /// Sets the resting (normal) colours of button `w` (must carry a
   /// ButtonComponent). Applies them at once when enabled and idle;
   /// a running press animation lerps from the new colours.
   void setButtonRestColors(Widget w, in WidgetColors c)
   ```
   Set `comp.style.normal = c`; always set text colour; if
   `w.inputEnabled && comp.pressProgress == 0` call `applyColors(w, c)`.
   If disabled, leave disabled colours.
4. `button_support.d` `emitButtonAction`: replace
   `ctx.host.sendAppEvent(ev)` with
   `passViewEvent(ctx.host, target, ev)` (from `yguilib.widget.widget_view`,
   `package(yguilib)`). Make sure `DummyWidgetSystemHost` supplies
   `widgetViews` (whatever `WidgetSystemHost` requires) and that existing
   tests still pass.
5. `uisystem_impl.d`: register `new ButtonSystem()` in the default pipeline
   next to the other built-in systems (around line 43-47). Check for import
   cycles (`yguilib.controls.button` imports uisystem; uisystem_impl is
   internal - should be fine). Remove
   `app.ui.registerWidgetSystem(new ButtonSystem());` and the now-unused
   import from `source/guidemo/guidemoapp.d`. Grep `source/` and
   `yguilib/source/` for other `new ButtonSystem()` registered on a
   UiSystemImpl (e.g. guidemo simple button page/controller tests) and
   remove duplicate registrations.
6. Unit tests in `button.d`:
   - press trigger: exactly one event on mouseDown, none on mouseUp; press
     animation still runs and settles (timer stops).
   - `setButtonRestColors` idle (colours applied) and mid-press (normal
     updated, after settle background equals new normal).
   - routing: a button whose parent has a ViewComponent with
     `renameEvents[action] = "renamed"` (no widgetViewName) emits
     `"renamed"` with `view.viewWidget` = parent.

## Verify
`ninja -C _build && meson test -C _build`. Run guidemo Button page briefly
if a display is available (optional).
