# Phase 3: guidemo/yvidtrim Renames, Style Check, Cleanup

Rename the remaining `get*`/`set*` symbols in `source/`, make
`check_style.d` flag such names, and close the `TODO.md` item.

## Rules & Conventions
- Read `codestyle.md` and `AGENTS.md` first. 2-space indent, max 80 cols.
- Use the `rename-symbol` skill; on a collision pick a verb or
  `<returnMeaning>From<ArgMeaning>` name and report it.
- Skill scripts are D + stdlib, run with `rdmd`.
- Build/test: `ninja -C _build && timeout 300 meson test -C _build`.

## Tasks

### 1. Renames in `source/`
```
file (source/guidemo/)            old                         new
--------------------------------  --------------------------  ----------------------
pages/*_page.d (button,           setVisible / isVisible      visible pair
  button_system, textlabel,                                   (visible(bool) setter,
  scrollbars, virtlist,                                       visible() getter)
  layout_painter, tabcontrol, ...)
pages/knob_controller.d           setDragging                 commitDragging
pages/scrollbars_controller.d     setBarWidth                 commitBarWidth
pages/tabcontrol_controller.d     setViewportWidth            commitViewportWidth
pages/virtlist_controller.d       setHorizontalViewportWidth  commitHorizontalViewportWidth
```
- `isVisible` on pages: rename every page (and any interface/caller, e.g.
  in `guidemoapp.d`) together so all pages share `visible()`/`visible(bool)`.
  Do not rename `isVisible` on non-page types.
- Then search `source/` for any other `\b(get|set)[A-Z]` D identifiers and
  rename them with the plan overview's rules.

### 2. `check_style.d`: flag `get*`/`set*` names
In `.agents/skills/check-codestyle/scripts/check_style.d`, next to the
consecutive-caps function-name check (~line 1059):
- Warn when a declared D function/method name matches `^(get|set)[A-Z]`.
  Message: `'<name>' uses get/set prefix; use a property pair or a verb
  (codestyle.md section 2).`
- Skip `clibs/` bindings (as the caps check does).
- Add the rule to the numbered list in the script help text (~line 1172)
  and to `.agents/skills/check-codestyle/SKILL.md` "Checks Enforced".
- Confirm `rdmd .agents/skills/check-codestyle/scripts/check_style.d --all`
  reports no get/set warnings, and that a scratch file declaring
  `void setFoo(int v) {}` is flagged.

### 3. Docs and TODO
- `TODO.md`: remove the item "decide `setCaption`/`setVisible`/... naming
  vs codestyle ..." (lines 4-6).
- `ARCHITECTURE.md`: update any renamed symbol mentions; keep < 250 lines.
- Update the overview `plans/getset-naming.md` status table.

## Verification
```bash
ninja -C _build && timeout 300 meson test -C _build
grep -rnE '\b(get|set)[A-Z]' source yguilib/source   # only getMember/getThis
rdmd .agents/skills/check-codestyle/scripts/check_style.d --all
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d --audit
```
