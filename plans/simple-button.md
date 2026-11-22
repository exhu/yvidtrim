# Simple push Button control + guidemo page

## Goal
Add a plain push button to `yguilib/source/yguilib/controls/`:
- no hover animation / hover visuals at all,
- press animation: pressed colours fade in/out and the caption "sinks"
  1-2 px (padding shift, widget size unchanged),
- emits a view event on mouse release over the same button that was
  pressed (drag-off cancels),
- disabled state with muted colours (builder `.enabled(false)` and runtime
  `Widget.setInputEnabled(bool)`; see "Post-review change" below).

Common code is extracted from the existing animated hover button
(`controls/hover_button_system.d`) as **shared helpers only** (free
functions, structs, a builder mixin); the hover system keeps its own class.
A new guidemo page (Page 9, "Button") demonstrates the control.

## Phases
```
ph01  extract shared helpers -> controls/internal/button_support.d,
      refactor hover_button_system.d onto them (no behaviour change)
  |
ph02  new controls/button.d: ButtonStyle, ButtonComponent,
      ButtonBuilder, setButtonEnabled, ButtonSystem + unittests
  |
ph03  guidemo Page 9 (simple_button_page/controller), register
      ButtonSystem, meson, ARCHITECTURE.md
```
Details:
- [ph01](simple-button-ph01.md)
- [ph02](simple-button-ph02.md)
- [ph03](simple-button-ph03.md)

## Verification (every phase)
`ninja -C _build && meson test -C _build` must pass; lines <= 80 chars.

TODO.md: no item covers a push button; nothing to remove.

## Post-review change
`setButtonEnabled` / `isButtonEnabled` / `ButtonComponent.enabled` were
removed: `Widget.inputEnabled` is the enabled flag. New
`Widget.setInputEnabled(bool)` (marks visuals-dirty); `ButtonSystem`
ignores buttons with `inputEnabled == false` and in `postLayout` syncs
visible buttons whose flag changed (muted colours, press cancelled).
