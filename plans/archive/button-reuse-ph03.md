# Phase 3 - Scrollbar arrows, cleanup, docs

Context: see [overview](button-reuse.md). Phases 1-2 added
`ButtonTrigger.press`, `ButtonBuilder.trigger/visible/disabledColors/sink`,
`setButtonRestColors`; ButtonSystem is built in; TabControl now builds tab
and arrow buttons with ButtonBuilder (see `buildArrowButton` in
`controls/tabcontrol.d` as the pattern). Read `AGENTS.md`, `codestyle.md`.

## Files
- `yguilib/source/yguilib/controls/scrollbars.d`
- `yguilib/source/yguilib/controls/common.d`
- `ARCHITECTURE.md`, `TODO.md`

## Steps
1. `scrollbars.d` `buildArrowBtn`: ButtonBuilder with
   `trigger(ButtonTrigger.press)`, `action(eventName)`, name, fixed size,
   normal colours `cfg.arrow`, `disabledColors(cfg.disabled)`,
   `radius(cfg.cornerRadius)`, `fontSize(cfg.fontSize)`, `padding(0,0)`,
   `sink(1.0f)`, border width 1.
2. `updateArrowStates`: `setInputEnabled(canDec/canInc)` (null-safe)
   instead of `applyEnabledState`. Initial build state must match what
   tests expect (dec disabled at min): either build with correct enabled
   flag or rely on the existing initial `updateArrowStates` call.
   Thumb/track untouched.
3. Fix scrollbar and virtlist unittests expecting arrow colours set
   immediately (disabled colours now come from ButtonSystem.postLayout);
   assert `inputEnabled` and/or run ButtonSystem.postLayout.
4. `common.d`: if `styledButton` and `applyEnabledState` have no users left
   (grep `source/` and `yguilib/source/`), remove them and their tests.
   Keep `ButtonFace`/`applyButtonFaceStyle` (button_support uses them).
5. `ARCHITECTURE.md`: note ButtonSystem is a built-in pipeline system and
   drives plain, tab and arrow buttons (press/release trigger); ensure no
   `tab_button.d` mention; keep < 250 lines.
6. `TODO.md`: remove the first item ("reuse simple button ...").

## Verify
`ninja -C _build && meson test -C _build`.
