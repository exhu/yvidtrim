# Phase 1: Core Tooltip Control & System (`yguilib`)

## Goal
Implement `yguilib.controls.tooltip` in
`yguilib/source/yguilib/controls/tooltip.d` with `Tooltip`, `TooltipStyle`,
`TooltipTiming`, `TooltipLayerComponent`, `TooltipLayerBuilder`,
`createTooltipLayer`, and `TooltipSystem`, wire it into `yguilib/meson.build`,
and verify with headless unit tests and all repository checks.

## Constraints & Style Rules
- Follow `codestyle.md` & `.editorconfig`: 2-space indent, LF, max 80 chars/line,
  opening `{` on same line, lowercase filenames, D naming (`PascalCase` types,
  `camelCase` funcs/vars).
- Null safety: `assert(arg !is null)` on non-null params, `invariant` on
  classes where appropriate, document nullable params explicitly.
- No `public import`. Scope heavy stdlib imports (`std.algorithm.comparison`,
  `std.math`, etc.) locally inside functions if appropriate.
- `yguilib/` must not depend on `source/yvidtrim/` or `source/guidemo/`.
- Hot paths should avoid unnecessary GC churn.
- Zero-CPU idle: stop all timers when `idle` or fully `visible`.

## Files to Create / Modify

### 1. NEW `yguilib/source/yguilib/controls/tooltip.d`
Module `yguilib.controls.tooltip`.

#### Public API & Types
1. `final class Tooltip : WidgetComponent`
   - `string text;` (when null/empty, falls back to owner's `TextLabel.caption`)
   - `bool enabled = true;`
   - `this(string text = null, bool enabled = true) nothrow @safe`
   - `string resolveText(const Widget owner) const nothrow @safe`:
     returns `""` if `!enabled`; if `text.length > 0` returns `text`; else if
     `owner !is null && owner.components.textLabel !is null` returns
     `owner.components.textLabel.caption`; else `""`.

2. `struct TooltipStyle`
   - `WidgetColors colors = WidgetColors(bg, border, text)`:
     - `bg`: `ColorF(0.10f, 0.12f, 0.16f, 0.94f)`
     - `border`: `ColorF(0.36f, 0.42f, 0.54f, 0.96f)`
     - `text`: `ColorF(0.95f, 0.96f, 0.98f, 1.0f)`
   - `float cornerRadius = 5.0f;`
   - `float borderWidth = 1.0f;`
   - `float fontSize = 12.0f;`
   - `Insets padding = Insets.vh(6.0f, 10.0f);`
   - `float maxWidth = 360.0f;`
   - `float maxHeight = float.infinity;`
   - `float edgeMargin = 8.0f;`
   - `PointF cursorOffset = PointF(12.0f, 18.0f);`

3. `struct TooltipTiming`
   - `uint showDelayMs = 450;`
   - `float fadeInDuration = 0.12f;`
   - `float fadeOutDuration = 0.22f;`
   - `float moveResetThreshold = 3.0f;`

4. `final class TooltipLayerComponent : WidgetComponent`
   - `Widget popupWidget;`
   - `TooltipStyle style;`
   - `this(Widget popupWidget, in TooltipStyle style)`:
     `assert(popupWidget !is null, "popupWidget must not be null");`
   - `invariant { assert(popupWidget !is null); }`

5. `struct TooltipLayerBuilder` & helper `createTooltipLayer`
   - Fluent setters: `.name(string)`, `.style(in TooltipStyle)`.
   - `Widget build(UiSystem ui, Widget parent)`:
     - `assert(ui !is null, "ui must not be null");`
     - `parent` allowed to be null in headless tests (document in docstring).
     - `layerName = orDefault(widgetName, "tooltipLayer")`.
     - Layer widget:
       - `parent(parent)`, `name(layerName)`, `rect(RectF(0, 0, 0, 0))`
       - `visible = true`, `inputEnabled(false)` (passes through all events)
       - NO `Background`, NO `Border`
       - `Size.autoSize()` + `Anchor` with `left=0, top=0, right=0, bottom=0`
         so `LayoutSystem` stretches it to cover the whole `parent` root widget
         automatically (and ignores it in any `FlexContainer`).
     - Popup child widget (child of layer):
       - `name(layerName ~ "Popup")`, `rect(RectF(0, 0, 0, 0))`
       - `visible(false)`, `inputEnabled(false)`
       - `Size.autoSize()` with `padding = cfg.padding`,
         `maxWidth = cfg.maxWidth`, `maxHeight = cfg.maxHeight`
       - `roundBg(cfg.colors.bg).bgRadius(cfg.cornerRadius)` (or `bg` if 0)
       - `border(cfg.colors.border).borderWidth(cfg.borderWidth)` + round style
       - `text("").textColor(cfg.colors.text).fontSize(cfg.fontSize)`
         `.textAlign(TextLabel.Alignment.left).textMultiline(true)`
         `.textEllipsis(true)`
     - Attach `new TooltipLayerComponent(popup, cfg)` to layer widget.
     - Return `layer`.
   - `Widget createTooltipLayer(UiSystem ui, Widget parent, in TooltipStyle style = TooltipStyle.init, string name = null)`.

6. `final class TooltipSystem : WidgetSystem`
   - Priority: `enum int tooltipSystemPriority = 20;` (set via `setPriority`).
   - Phases: `SystemPhase.event | SystemPhase.preLayout | SystemPhase.layout | SystemPhase.postLayout`.
   - `this(in TooltipTiming timing = TooltipTiming.init) nothrow @safe`.
   - Lifecycle: `onRegister`, `onUnregister`, `onWidgetReleased`.
   - Unobstructed hit-testing `findUnobstructedTooltipTarget(VisibleWidgets widgets, PointF p, Widget tooltipLayer)`:
     - Walk `widgets` in reverse (front-to-back).
     - Ignore `w is null`, `!w.visible`, or `isDescendantOrSelf(w, tooltipLayer)`.
     - Ignore if not hit (`!vw.absRect.contains(p)` or `(vw.hasClip && !vw.clipRect.contains(p))`).
     - Check ONLY `w.inputEnabled` and `w.components.has!Tooltip()` (NEVER check
       `Background` or any painting component!).
     - If `!w.inputEnabled && !w.components.has!Tooltip()`, continue (pass-through).
     - Otherwise `w` is the topmost obstructing/tooltip widget:
       - If `auto tt = w.components.get!Tooltip()`: if `tt.enabled && tt.resolveText(w).length > 0` return `w`.
       - Otherwise return `null` (obstructed by `w`, e.g., transparent modal
         backdrop with `visible = true, inputEnabled = true`, or overlapping
         button without tooltip).
   - State machine (`enum State { idle, waitingDelay, showing, visible, hiding }`):
     - `handleEvent`:
       - `mouseMotion`: update `lastCursorPos`, `hasCursorPos = true`. Find
         unobstructed target `hit`.
         - If `state == idle`: if `hit !is null`, start `waitingDelay` for `hit`
           (record `dwellOrigin = p`, start one-shot timer `timing.showDelayMs`).
         - If `state == waitingDelay`:
           - If `hit !is activeTarget`: cancel delay timer; if `hit !is null`
             restart `waitingDelay` for `hit`, else go `idle`.
           - Else if cursor moved `> moveResetThreshold` from `dwellOrigin`:
             update `dwellOrigin = p`, restart one-shot delay timer.
         - If `state == showing || state == visible`:
           - If `hit !is activeTarget`: transition to `hiding` (start 60 FPS
             repeat timer), record `pendingTarget = hit`, `pendingCursorPos = p`.
         - If `state == hiding`:
           - If `hit is activeTarget && activeTarget !is null`:
             reverse smoothly back to `showing` (keep current `alpha`, ensure
             60 FPS timer running), clear `pendingTarget`.
           - Else update `pendingTarget = hit`, `pendingCursorPos = p`.
       - `mouseButtonDown` / `windowMouseLeave`:
         - If `state == waitingDelay`: stop delay timer -> `idle`.
         - If `state == showing || state == visible`: clear `pendingTarget`,
           transition to `hiding` (start 60 FPS timer).
         - If `state == hiding`: clear `pendingTarget`.
       - Never consume events (`return SystemEventResult(false, false)`).
     - `onTimer(ctx, id, dt)`:
       - If `id == delayTimerId`:
         - `delayTimerId = invalidTimerId;`
         - Verify `activeTarget` is still valid, visible, and unobstructed at
           `lastCursorPos` (or if `ctx.visibleWidgets.length == 0`, check
           `isEffectivelyVisible(activeTarget)`).
         - Discover layer (`discoverLayer(ctx)`). If missing, go `idle`.
         - Resolve text; if empty, go `idle`.
         - Set `popup.setCaption(text)`, apply `alpha = 0.0f`, set
           `popup.setVisible(true)`, `popup.update(WidgetUpdateScope.layout)`.
         - Transition to `showing`, start 60 FPS repeat timer.
       - If `id == animTimerId`:
         - If `state == showing`: advance `alpha += dt / fadeInDuration`;
           clamp to `1.0f`; apply alpha to `popup` (`Background`, `Border`,
           `TextLabel` base colors scaled by `alpha`). When `alpha >= 1.0f`:
           `state = State.visible`, stop `animTimerId` (0% CPU).
         - If `state == hiding`: advance `alpha -= dt / fadeOutDuration`;
           clamp to `0.0f`; apply alpha. When `alpha <= 0.0f`:
           hide `popup` (`setVisible(false)`, `update(WidgetUpdateScope.layout)`),
           stop `animTimerId`, clear `activeTarget`.
           If `pendingTarget !is null`: promote `pendingTarget` to `waitingDelay`
           (start one-shot delay timer). Else `state = State.idle`.
     - `preLayout(ctx)`:
       - Discover layer if needed.
       - If `popup` is visible: compute layer available width/height from
         `layer.rect` (falling back to `ctx.root.rect` if `layer.rect` has 0
         width/height). Clamp `popup.components.size.maxWidth` to
         `min(style.maxWidth, max(0, layerW - 2 * margin))` and `maxHeight` to
         `min(style.maxHeight, max(0, layerH - 2 * margin))`.
     - `layout(ctx)`:
       - Runs after `LayoutSystem` (priority 20 > 0).
       - If `layer !is null && popup !is null && popup.visible`:
         - Compute layer absolute origin (`layerAbsOrigin` from `unclippedWidgets`
           or `layer.rect`).
         - Local cursor `lx = anchorCursorPos.x - layerOrigin.x`,
           `ly = anchorCursorPos.y - layerOrigin.y`.
         - Desired `x = lx + style.cursorOffset.x`,
           `y = ly + style.cursorOffset.y`.
         - If `y + popup.rect.height > layerH - margin`:
           flip above cursor: `y = ly - popup.rect.height - 8.0f`.
         - Clamp `x` to `[margin, max(margin, layerW - margin - popup.rect.width)]`.
         - Clamp `y` to `[margin, max(margin, layerH - margin - popup.rect.height)]`.
         - Set `popup.rect.x = x; popup.rect.y = y;`.
     - `postLayout(ctx)`:
       - If `activeTarget !is null && !isEffectivelyVisible(activeTarget)`:
         - Cancel delay or transition to `hiding`.
       - Also if `state == waitingDelay || state == showing || state == visible`
         and `hasCursorPos && ctx.visibleWidgets.length > 0`:
         - Re-verify `findUnobstructedTooltipTarget(ctx.visibleWidgets, lastCursorPos, cachedLayer) is activeTarget`;
           if no longer unobstructed, cancel delay / transition to `hiding`.
     - `onWidgetReleased(w)`:
       - If `w is activeTarget`: clear `activeTarget`, stop delay timer, hide
         popup immediately if visible, stop anim timer, go `idle`.
       - If `w is pendingTarget`: `pendingTarget = null`.
       - If `w is cachedLayer || w is cachedPopup`: clear cached layer/popup,
         stop timers, go `idle`.

#### Required Unit Tests in `tooltip.d`
1. `TooltipLayerBuilder` structure: `layer.visible == true`,
   `!layer.inputEnabled`, `layer.components.background is null`,
   `layer.components.border is null`, `layer.components.anchor !is null`,
   `popup.visible == false`, `!popup.inputEnabled`,
   `popup.components.textLabel.multiline == true`, `verifyAllNamed(layer)`.
2. `Tooltip.resolveText`: explicit text, caption fallback when text is empty,
   disabled tooltip returns `""`.
3. Unobstructed hit-testing:
   - Pass-through container (`inputEnabled = false`, no `Tooltip`) on top does
     NOT obstruct.
   - Visually transparent modal backdrop (`visible = true`, `inputEnabled = true`,
     no `Background`, no `Tooltip`) on top DOES obstruct (returns `null`).
   - Clipped widget outside `clipRect` is not hit.
   - Tooltip layer & popup themselves do not obstruct.
4. Full state machine lifecycle with `DummyWidgetSystemHost`:
   - Hover -> `waitingDelay` (one-shot timer active, popup still hidden).
   - Cursor jitter > threshold resets delay timer.
   - Delay fires -> `showing`, popup visible, 60 FPS timer active, alpha ramps
     up fast to `1.0` -> `visible`, 60 FPS timer stopped (0% CPU).
   - Mouse leaves -> `hiding`, 60 FPS timer active, alpha ramps down to `0.0` ->
     popup hidden, 60 FPS timer stopped, `idle`.
   - Re-enter during `hiding` -> smoothly reverses back to `showing`.
   - Click (`mouseButtonDown`) or `windowMouseLeave` dismisses/cancels.
5. Layout clamping & multiline wrapping (with `LayoutSystem` or `WidgetFixture`):
   - Layer stretches via `Anchor(0,0,0,0)` to cover `rootWidget`.
   - Popup `maxWidth`/`maxHeight` limited by layer size.
   - Popup position flipped/clamped when cursor is near bottom-right corner.
6. `onWidgetReleased` safely clears active target and cached layer without
   dangling pointers or active timers.

### 2. MODIFY `yguilib/meson.build`
Add `'source/yguilib/controls/tooltip.d'` in alphabetical order inside
`yguilib_src`.

## Verification
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d --audit
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
```
