# input-flags ph02: call sites, templates, docs

Overview: [input-flags.md](input-flags.md). Phase 1 is already done:
- `Widget.handleInput` (default false) means hittable/blocking for pointer
  input. `WidgetBuilder` `onMouse*` and `cursorCapture` set it.
- `Widget.inputEnabled` (default true) is the enabled state: disabled
  visuals, and no mouse events, drag or capture when it is false.

Follow AGENTS.md and codestyle.md (2-space indent, max 80 cols, keep
existing comments).

## Steps
1. `yguilib/source/yguilib/controls/internal/button_support.d` (~line 179):
   change `b.inputEnabled(true)` to `b.handleInput(true)`, or drop it if
   `onMouse*` already sets it. Keep a widget hittable even if it has no mouse
   events (e.g. a tooltip-only button).
2. `controls/tabcontrol.d` (~line 985): keep `.inputEnabled(false)` (the
   arrow button starts disabled). `onMouseDown` makes it hittable.
3. `controls/scrollbars.d` (~line 688) and `controls/common.d` (~line 62):
   keep them (enabled state). Check that the scrollbar thumb, track and
   buttons get `handleInput` (through `onMouse*` builder calls, or set it
   explicitly if their mouse events are attached by hand).
4. Search every `.d` source (`yguilib/`, `source/guidemo/`,
   `source/yvidtrim/`) for widgets that attach `components.mouseEvent`
   directly or set `inputEnabled = true` to make them clickable or blocking.
   Switch these to `handleInput = true`.
5. `controls/button.d` header doc (~lines 23-25): explain that
   `inputEnabled` is the enabled flag and that `handleInput` makes a widget
   hittable, so a disabled button still blocks clicks.
6. `.agents/skills/define-gui-widget/scripts/define_gui_widget.d`
   (~line 917): change the template's `.inputEnabled(true)` to
   `.handleInput(true)`. Check the skill's SKILL.md and docs for the old
   wording and update them.
7. `yguilib/source/yguilib/widget/internal/focus_system.d`: add a doc
   comment on `FocusSystem` with the planned keyboard rule. Keys go to the
   focused widget that has a `KeyboardEvent`, and only if `inputEnabled`.
   Disabled widgets can't take focus. `handleInput` affects pointer input
   only.
8. `ARCHITECTURE.md`, section "Phased Main Event Loop & Input Dispatch": add
   a short paragraph on the two-flag rule (`handleInput` = hittable/blocking,
   `inputEnabled` = enabled) and the keyboard rule. The file must stay under
   250 lines and 80 cols.
9. `TODO.md`: remove the first item (the "Decide on Widget.handleInput vs
   Widget.inputEnabled..." bullet, lines 1-6).

## Verify
`ninja -C _build && meson test -C _build`: everything passes.
