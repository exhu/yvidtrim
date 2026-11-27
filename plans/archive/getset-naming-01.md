# Phase 1: Remove `Widget` Setters

Remove the dirty-tracking setters from `Widget`
(`yguilib/source/yguilib/widget/package.d`, ~lines 366-461) and replace every
use with an explicit assignment plus `update(WidgetUpdateScope.<scope>)`.

## Rules & Conventions
- Read `codestyle.md` and `AGENTS.md` first. 2-space indent, max 80 cols.
- Keep existing comments/docstrings (move the setters' docs on which scope
  each property needs to the field/component docs, see task 2).
- Build/test: `ninja -C _build && timeout 300 meson test -C _build`.

## Mapping

```
removed setter      assignment                           update scope
------------------  -----------------------------------  ------------
setCaption          components.textLabel.caption = v     content
setBackgroundColor  components.background.color = v      visuals
setTextColor        components.textLabel.color = v       visuals
setBorderColor      components.border.color = v          visuals
setVisible          visible = v                          layout
setInputEnabled     inputEnabled = v                     visuals
setScrollOffset     components.scrollableArea.offset = v layout
```

## Tasks

### 1. Rewrite call sites
List them with:
```bash
rdmd .agents/skills/rename-symbol/scripts/rename_symbol.d \
  --owner Widget --member-only setCaption x
```
(dry-run; repeat per setter) or a plain search. Files: `yguilib/source/
yguilib/{controls,widget}/**`, `source/guidemo/**`, `source/yvidtrim/**`.

For each call:
- Assign and call `update` with the scope from the table.
- If the call ran every frame / every model sync / in an animation step, or
  relied on the "unchanged -> no-op" behaviour, keep a change guard:
  ```d
  if (w.components.textLabel.caption != text) {
    w.components.textLabel.caption = text;
    w.update(WidgetUpdateScope.content);
  }
  ```
- The setters were no-ops when the component was `null`; keep a `null` check
  only where the component may really be absent.
- Several changes on one widget: one `update` with the widest scope
  (`layout` > `content` > `visuals`) is enough.
- Where a small helper would repeat the same 4 lines many times in one file
  (e.g. `virtlist_providers.d`, `tabcontrol_page.d`), add a file-private
  helper named for the action (e.g. `updateCaption(Widget w, string text)`),
  not a `set*` name.
- `tabcontrol.d` `setArrowsVisible` keeps its name in this phase (renamed in
  phase 2); only its body changes.

### 2. Remove the setters and adjust docs
- Delete the 7 methods from `Widget`.
- Add one-line doc notes on `visible`, `inputEnabled` fields saying which
  `update` scope to call after changing them on a live widget.
- Rewrite the unit tests in `widget/package.d` (~lines 960-1010) and
  `controls/button.d:756` that assert setter return values: test that the
  assignment + `update` marks the expected dirty flags instead.

### 3. Audit direct field writes
`grep -rnE '\.(visible|inputEnabled)\s*=[^=]'` in `source/` and
`yguilib/source/` (~25 hits). For writes to a live (attached) widget that
miss `update` - e.g. `source/yvidtrim/view.d:41` - add the `update` call.
Leave builder code (`widget/builder.d`) and test setup that writes before
the first layout as is.

### 4. Docs
- `ARCHITECTURE.md`: replace the `setInputEnabled` mention.
- `.agents/skills/define-gui-widget/SKILL.md`: replace the `setCaption`,
  `setVisible`, `setBackgroundColor`, `setTextColor`, `setBorderColor`
  guidance with the assignment + `update` pattern.

## Verification
```bash
ninja -C _build && timeout 300 meson test -C _build
grep -rnE '\bset(Caption|BackgroundColor|TextColor|BorderColor|InputEnabled|ScrollOffset)\b' source yguilib/source   # no hits
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
```
`setVisible` still exists on guidemo pages (phase 3); verify no
`Widget`-typed `.setVisible(` remains.
