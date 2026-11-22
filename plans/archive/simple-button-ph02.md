# simple-button phase 2: Button control

Overview: [simple-button.md](simple-button.md). Read `AGENTS.md`,
`codestyle.md`, and the shared helpers created in phase 1:
`yguilib/source/yguilib/controls/internal/button_support.d`
(`ButtonBaseConfig`, `ButtonBuilderCommon` mixin with `makeButtonBase`,
`ActiveWidgets`, `PressTracker!C`, `emitButtonAction`). Use
`yguilib/source/yguilib/controls/hover_button_system.d` as the reference
for WidgetSystem structure, timers (`AnimationTimer`, `startTimer`/
`stopTimer`, `TimerIntervalMs.fps60`, `TimerMode.repeat`) and test style.

Requirements: plain push button, **no hover visuals/animation**, press
animation (colour fade + caption sink), view event on release-inside of the
pressed button (drag-off cancels), disabled state with muted colours.

## Steps
1. Create `yguilib/source/yguilib/controls/button.d`
   (module `yguilib.controls.button`), add to `yguilib/meson.build`.
   Module doc comment explaining the design.
2. `struct ButtonStyle`:
   `WidgetColors normal` (defaults similar to `ButtonBaseConfig`),
   `WidgetColors pressed` (darker bg, brighter border, same text),
   `WidgetColors disabled = defaultDisabledColors` (from
   `yguilib.controls.common`), `float sinkPx = 2.0f`,
   `float pressInSec = 0.06f`, `float pressOutSec = 0.15f`.
   Builder's bg/border/text config overrides `normal`.
3. `final class ButtonComponent : WidgetComponent`: `ButtonStyle style`,
   `string actionEvent`, `bool enabled = true`, `bool isPressed`,
   `float pressProgress`, `AnimationTimer pressTimer`,
   `Insets basePadding`, `int appliedSink` (last applied whole-px sink).
   Helper `resetPress(Widget w)` restoring padding and normal colours.
   Note AnimationTimer has one duration; if separate in/out durations are
   awkward, step with dt scaled by duration ratio, or use a single
   duration — keep it simple and document it.
4. `struct ButtonBuilder { mixin ButtonBuilderCommon; ... }` with
   `.action(string)`, `.style(in ButtonStyle)`,
   `.pressedColors(ColorF bg, ColorF border)`, `.enabled(bool)`;
   `Widget build(UiSystem ui, Widget parent, RectF rect)` via
   `makeButtonBase(ui, parent, rect, "button")`, attaches component
   (basePadding = config.padding), and if disabled applies disabled colours
   (`applyColors`) and `inputEnabled = false`. Also
   `Widget createButton(UiSystem, Widget parent, RectF, in ButtonBaseConfig,
   in ButtonStyle)` convenience function.
5. Free functions:
   `bool setButtonEnabled(Widget w, bool enabled)` - null-safe, no-op
   without component; sets `comp.enabled`, `w.inputEnabled`, cancels any
   press (progress 0, timer stopped, padding restored), applies
   `applyColors(w, enabled ? normal : disabled)` (incl. text colour);
   returns true when state changed. The system must also drop the widget
   from its pressed/active sets on the next event/timer if it became
   disabled (check `comp.enabled` everywhere).
   `bool isButtonEnabled(const Widget w)`.
6. `final class ButtonSystem : WidgetSystem`, phases
   `SystemPhase.event | SystemPhase.postLayout`; lifecycle like the hover
   system (`onRegister`, `onUnregister`, `onWidgetReleased`).
   - mouseButtonDown (button 1): hit-test `PressTracker!ButtonComponent`;
     only if `comp.enabled`: `isPressed = true`, begin press, track active,
     ensure timer.
   - mouseMotion while a press is held: handle **every** motion event (never
     coalesce, see AGENTS.md "Pointer Motion Fidelity"); `isPressed` =
     pointer is over the pressed button (drag-off un-sinks, drag-back
     re-sinks); ensure timer on change.
   - mouseButtonUp (button 1): end press; `isPressed = false`; emit
     `emitButtonAction` only when released over the same button and it is
     still enabled and `actionEvent` non-empty.
   - windowMouseLeave: visual un-press (keep tracking so release cancels).
   - `onTimer`: step press timer toward `isPressed`; colour =
     `lerpColor(normal, pressed, pressProgress)` for bg and border via
     `applyBgAndBorderColors`; sink = `cast(int) round(pressProgress *
     sinkPx)`; when it differs from `appliedSink`, set
     `w.components.size.padding` to basePadding with top += sink and
     bottom -= sink (bottom clamped >= 0) and call
     `w.update(WidgetUpdateScope.layout)` (check the exact API in
     `yguilib/widget/package.d`). Remove settled buttons; stop the timer
     when none are active (0% CPU idle).
   - postLayout: reset and forget invisible buttons.
   SystemEventResult is never consuming (match hover system).
7. Unittests (`UiSystemImpl(null)`, `DummyWidgetSystemHost`,
   `WidgetSystemContext` with `VisibleWidget` list, as in hover tests):
   builder tree & defaults; press -> timer active, progress and sink > 0
   after steps, padding shifted; release inside -> exactly one event named
   as action with `view.widget is btn`; press then motion outside then
   release -> no event, visuals return to normal; disabled button
   (builder and `setButtonEnabled(false)`) -> muted colours,
   `!inputEnabled`, press ignored, no event; re-enable restores normal
   colours; timer stops after settling; `onWidgetReleased` cleanup; hover
   (motion without press) starts no timer.
8. Verify: `ninja -C _build && meson test -C _build`, lines <= 80 chars.
