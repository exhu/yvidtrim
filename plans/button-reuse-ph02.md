# Phase 2 - TabControl on ButtonBuilder, delete tab_button.d

Context: see [overview](button-reuse.md). Phase 1 added to
`controls/button.d`: `ButtonTrigger { release, press }`,
`ButtonBuilder.trigger/visible/disabledColors/sink`,
`setButtonRestColors(Widget, WidgetColors)`; `emitButtonAction` routes via
`passViewEvent`; ButtonSystem is built into UiSystemImpl. Read `AGENTS.md`,
`codestyle.md`, and `controls/button.d` first.

## Files
- `yguilib/source/yguilib/controls/tabcontrol.d`
- `yguilib/source/yguilib/controls/tab_button.d` (delete)
- `yguilib/meson.build` (remove tab_button.d line ~23)
- `dub.json` / `yguilib/dub.json` if they list files

## Steps
1. Move `TabButtonStyle`, `defaultTabButton*` enums and `tab*` colour enums
   from `tab_button.d` into `tabcontrol.d` (keep docstrings). Add
   `ButtonStyle press` (pressed colours / timing / sink) field to
   `TabButtonStyle` defaulting to `ButtonStyle.init`.
2. Rename `tabButtonMouseDownEvent` -> `tabButtonPressEvent` (value
   `"tabBtnPress"`); update `renameMap`, `translateEventForViewWidget`,
   docs and tests. Grep repo for other uses.
3. `TabButtonsProvider.addWidget`: build via `ButtonBuilder`:
   name "tabButton", `fixedSize(width,height)`, `radius(cornerRadius)`,
   `border(inactive.border, 1)`, `fontSize`, `padding(5,8)` (from
   `style.button.padding`), `style(style.button.press)` then
   `bg/border` = inactive colours, text colour inactive,
   `disabledColors(style.disabled)`, `captionTooltip()`,
   `trigger(ButtonTrigger.press)`, `action(tabButtonPressEvent)`,
   `.build(ui, parent, RectF(0,0,w,h))`. Ensure the TextLabel caption can be
   empty/updated later (`w.setCaption`). Keep tooltip resolving to caption.
4. `updateWidgetAt`: name, caption, then
   `setButtonRestColors(w, isActive ? style.button.active :
   style.button.inactive)`. Remove mouseEvent assert/assignment.
5. `buildArrowButton`: ButtonBuilder with press trigger,
   `action(eventName)`, normal colours `style.button.inactive`,
   `disabledColors(style.disabled)`, `padding(2,4)`, radius/fontSize from
   style, `.enabled(false).visible(false)`, fixed size w x h.
6. `updateArrowButtonStates`: use `btn.setInputEnabled(can)` (null-check)
   instead of `applyEnabledState`. Remove unused imports
   (`ButtonFace`, `styledButton`, `applyEnabledState`, ...).
7. Tests: port useful `tab_button.d` tests (default size, name, tooltip,
   active/inactive colours via provider) into tabcontrol unittests. Existing
   tests asserting `inputEnabled` of arrows must still pass. Add a check
   that arrow and tab widgets carry `ButtonComponent` with
   `trigger == press`. Add a headless ButtonSystem test if practical: a
   mouseButtonDown over a tab sends the renamed custom event (use
   `ButtonSystem` with a host + VisibleWidget list like button.d tests).
8. Delete `tab_button.d`; remove from meson (and dub.json if listed).
   `ARCHITECTURE.md` line mentioning tab_button.d: remove it.

## Verify
`ninja -C _build && meson test -C _build`. Grep for `tab_button` (no hits
except plans/archive).
