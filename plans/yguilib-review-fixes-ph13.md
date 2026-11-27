# ph13: `controls` Buttons, HoverButton, `ButtonSupport` & `Tooltip`

Overview: `plans/yguilib-review-fixes.md`.
Review: `documentation/yguilib-review-report-controls.md` (commit `7a96feaa`).
Paths below are relative to `yguilib/source/yguilib/controls/`.

Goal: Address all findings in `internal/button_support.d`, `common.d`,
`button.d`, `hover_button_system.d`, `tooltip.d`, and `testing.d`
(`1.1`-`1.8`, `1.15`, `1.17`-`1.20`, `2.1`, `2.3`, `2.5`, `3.1`-`3.2`,
`3.4`-`3.5`, `4.1`-`4.3`, `5.5`, `6.1`-`6.3`).

## Files

- `internal/button_support.d`, `common.d`, `button.d`,
  `hover_button_system.d`, `tooltip.d`, `testing.d`

## Steps

1. **`button_support.d` & `common.d` (`1.8`, `1.19`, `1.20`, `2.3`, `3.1`, `3.5`, `4.1`, `4.2`)**:
   - Update `PressTracker.hitTest` to find the topmost visible widget with
     `handleInput == true` first, returning `Nullable!VisibleWidget` only if
     that widget has component `C` (`1.8`, `2.3`).
   - Move `ButtonBaseConfig` to `common.d`; mark `ButtonBuilderCommon`
     internal fields/helpers `private:` / `package(yguilib):` (`3.1`).
   - Add `assert(... !is null)` in `size`, `anchor`, and `emitButtonAction`
     (`1.19`); call `items.removeAt(i)` before `onRemoved(w)` (`1.20`).
   - Change `ref WidgetBuilder b` -> `WidgetBuilder b` (`3.5`).
   - Extract shared `package(yguilib)` animation-timer lifecycle &
     active-button stepping helper (`4.1`) and `setWidgetInputEnabled(Widget,
     bool)` in `common.d` (`4.2`).
2. **`button.d` (`1.1`-`1.4`, `1.18`, `1.20`, `4.3`)**:
   - Add `SystemPhase.preLayout` to `ButtonSystem.phases` and run
     `syncEnabledStates(ctx)` in `preLayout` (`1.1`).
   - Clean up `activeButtons`, `press.end()`, `stopRepeat()`, and idle
     `animTimerId` when disabling a button (`1.2`), on a second
     `mouseButtonDown` (`1.3`), and in `handleWindowMouseLeave` (`1.4`).
   - Guard `ButtonSystem.onTimer` with `if (id != invalidTimerId && id ==
     animTimerId)` (`1.18`).
   - Fix `applySink` when `basePadding.bottom < sinkPx` and assert
     `repeat.intervalMs > 0` / `sinkPx >= 0` in `ButtonBuilder.build` (`1.20`).
   - Deduplicate `mouseEv` helper (`4.3`).
3. **`hover_button_system.d` (`1.5`-`1.7`, `1.17`, `1.20`, `2.3`, `5.5`)**:
   - Enforce `w.inputEnabled` across motion/press/release/step and reset
     state on disable (`1.5`).
   - Clear `press.pressed` in `handleWindowMouseLeave` and on second
     `mouseButtonDown`, and restore `comp.isPressed = (hoveredWidget is
     press.pressed)` on drag re-entry (`1.6`).
   - Recompute `const nextHoverForward = comp.isHovered ||
     comp.hoverPulsePending;` after clearing `hoverPulsePending` (`1.7`).
   - Call `comp.resetToNormal` on settled hovered/pressed widgets in
     `cleanInvisibleButtons` (`1.17`), check `id == animTimerId` in
     `onTimer` (`1.20`), pass `absRect` from `Nullable!VisibleWidget` (`2.3`).
   - Remove dead `cursorNormY`, split `stepComponent` <= 50 lines, document
     nullable `parent`, fix module docstring (`5.5`).
4. **`tooltip.d` (`1.15`, `2.1`, `2.5`, `3.2`, `3.4`, `5.5`)**:
   - Cache negative `discoverLayer` result invalidated on `preLayout` (`2.1`).
   - Hide `fCachedPopup`, clear cached refs, and call `resetToIdle()` in
     both `onUnregister()` and host-switching `onRegister()` (`1.15`).
   - Require `onRegister(host)` instead of silent `ensureHost` (`3.2`).
   - Fast-path `fadeInDuration <= 0.0f` / `fadeOutDuration <= 0.0f` (`2.5`).
   - Move `TooltipLayerBuilder` `config`/`widgetName` to `private:` (`3.4`)
     and move hardcoded `8.0f` flip gap to `TooltipStyle` (`5.5`).
5. **`testing.d` & tests (`5.5`, `6.1`-`6.3`)**:
   - Remove `cast(Widget)` in `calcAbsRect`; record `intervalMs` and `mode`
     in `DummyWidgetSystemHost` (`5.5`, `6.3`).
   - Add pipeline-level & edge-case tests across `button.d`,
     `hover_button_system.d`, `tooltip.d`, `common.d`, and `button_support.d`
     (`6.1`-`6.3`).

## Verification

- `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`
