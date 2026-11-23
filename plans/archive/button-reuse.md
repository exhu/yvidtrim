# Reuse simple Button for TabControl and Scrollbars arrows

## Goal
TODO.md item 1: tab buttons (`controls/tab_button.d`) and TabControl /
Scrollbar arrow buttons are plain `styledButton()` widgets firing on
`MouseEvent.mouseDown`. Rebuild them on `controls/button.d`
(ButtonBuilder / ButtonComponent / ButtonSystem) for press feedback and
remove `tab_button.d`.

## Decisions
- Tabs and arrows fire on **press** (new `ButtonTrigger.press`); plain
  buttons keep firing on release.
- `ButtonSystem` is **built into** the UiSystemImpl pipeline; guidemoapp no
  longer registers it.
- `emitButtonAction` must route through `passViewEvent` so composite
  ViewComponent renaming works for buttons nested in view widgets.
- Tab active/inactive colours update `ButtonComponent.style.normal` via
  `setButtonRestColors`; arrow enable/disable uses `Widget.setInputEnabled`
  and ButtonSystem applies `ButtonStyle.disabled` in postLayout.

## Phases
```
ph01  ButtonSystem infra (trigger, rest colours, routing, built-in)
  |
ph02  TabControl on ButtonBuilder; delete tab_button.d
  |
ph03  Scrollbar arrows on ButtonBuilder; drop dead helpers; docs, TODO
```
Details:
- [ph01](button-reuse-ph01.md)
- [ph02](button-reuse-ph02.md)
- [ph03](button-reuse-ph03.md)

## Verification (every phase)
`ninja -C _build && meson test -C _build` must pass; lines <= 80 chars.
Manual: `./_build/guidemo` TabControl, Scrollbars, VirtList, Button pages.

Not in scope: auto-repeat while an arrow is held.
