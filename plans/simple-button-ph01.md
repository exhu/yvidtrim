# simple-button phase 1: extract shared button helpers

Overview: [simple-button.md](simple-button.md). Read `AGENTS.md` and
`codestyle.md` first. **No behaviour change** in this phase: all existing
unittests in `yguilib/source/yguilib/controls/hover_button_system.d` must
pass unchanged (only adapt them if a moved symbol needs a new import).

## Source to extract from
`yguilib/source/yguilib/controls/hover_button_system.d`:
- `HoverButtonConfig` struct (text, normalBg, borderColor, textColor,
  cornerRadius, borderWidth, fontSize, padding, actionEvent).
- `AnimatedHoverButtonBuilder`: fluent setters name, text, bg, border,
  radius, padding, fontSize, size, fixedSize, autoSize, anchor,
  captionTooltip, tooltipText; `build()` sizing/anchor/padding/face-style/
  tooltip/inputEnabled code; private `applyVisualStyle`.
- `AnimatedHoverButtonSystem`: `triggerAction`, `trackActiveButton` +
  `activeButtons` (`ReusableArray!Widget`), `cleanInvisibleButtons`,
  `pressedWidget` handling and release-inside hit test in
  `handleMouseButtonUp`, `onWidgetReleased` compaction.

## Steps
1. Create `yguilib/source/yguilib/controls/internal/button_support.d`
   (module `yguilib.controls.internal.button_support`), add it to the
   sources list in `yguilib/meson.build` (next to `internal/axis.d`).
   Doc comment on every public symbol. Contents:
   - `struct ButtonBaseConfig` with exactly the `HoverButtonConfig` fields
     and defaults. In `hover_button_system.d` replace the struct with
     `alias HoverButtonConfig = ButtonBaseConfig;` (keep doc comment).
   - `mixin template ButtonBuilderCommon()` declaring fields
     `ButtonBaseConfig config; Size customSize; Anchor customAnchor;
     string widgetName; bool hasTooltip; string tooltipHint;` and the fluent
     setters listed above, each `ref typeof(this) xxx(...) return`.
     Also a method
     `WidgetBuilder makeButtonBase(UiSystem ui, Widget parent, RectF rect,
     string defaultName)` that does what `AnimatedHoverButtonBuilder.build`
     does today except the component attach: name (orDefault), rect,
     sizeComponent or fixedSize fallback (100x36 when rect empty), anchor,
     padding, `applyButtonFaceStyle` from `config` colours/face, tooltip
     (`Tooltip.withText(tooltipHint)`), `inputEnabled(true)`. Note
     `WidgetBuilder` is a class in this code base (check
     `yguilib/widget/builder.d`); component attach after `makeButtonBase`
     must still work (`b.component(...)` then `b.build()`).
     `action()` is NOT in the mixin (each builder defines its own).
   - `struct ActiveWidgets` wrapping `ReusableArray!Widget` with `track(w)`
     (addUnique, null-safe), `remove(w)`, `empty`, `length`, `opIndex`,
     `removeAt`, and
     `void removeInvisible(scope void delegate(Widget) onRemoved)` (iterate
     backwards, drop `!isEffectivelyVisible(w)` calling `onRemoved(w)`).
   - `struct PressTracker(C)` (C = component type): `Widget pressed;`
     `static Widget hitTest(ref WidgetSystemContext ctx, PointF p)` using
     `findTopmostWithComponent!C(ctx.visibleWidgets, p)`;
     `void begin(Widget w)`; `Widget end()` (returns and clears pressed);
     `void forget(Widget w)` (clear if `pressed is w`);
     `void forgetInvisible()`.
   - `void emitButtonAction(ref WidgetSystemContext ctx, Widget target,
     string actionEvent)` = today's `triggerAction` (no-op on null host or
     empty event; `ViewAppEventBuilder(actionEvent).widget(target)`).
2. Refactor `hover_button_system.d`: `AnimatedHoverButtonBuilder` uses
   `mixin ButtonBuilderCommon;`, keeps `animConfig`, its own `action()` and
   `anim()`, and `build()` = `makeButtonBase(...)` + component attach.
   `AnimatedHoverButtonSystem` uses `ActiveWidgets`, `PressTracker!
   AnimatedHoverButtonComponent`, and `emitButtonAction`. Keep public names
   and behaviour (tests access `sys.animTimerId`, `isAnyAnimating`,
   `hoverPulsePeak`, builder fields `config`/`animConfig`).
   Preserve existing comments/docstrings.
3. Add unittests in `button_support.d` (use `UiSystemImpl(null)`,
   `DummyWidgetSystemHost` from `yguilib.controls.testing`, and a tiny
   marker component): mixin setters + `makeButtonBase` tree (bg, border,
   text label, size, tooltip), `ActiveWidgets` track/remove/removeInvisible,
   `PressTracker` begin/end/forget, `emitButtonAction` sends one view event
   with `view.widget is target` and nothing for empty name.
4. Verify: `ninja -C _build && meson test -C _build` (all suites green),
   lines <= 80 chars, 2-space indent.
