# Phase 2: Move Common Controls into `yguilib.controls`

Move `hover_button_system.d`, `scrollbars.d`, `tab_button.d`, `tabcontrol.d`,
and `virtlist.d` from `source/guidemo/` into
`yguilib/source/yguilib/controls/` under `yguilib.controls`, update imports and
Meson build targets, and update `ARCHITECTURE.md` and `TODO.md`.

## Rules & Conventions
- Adhere to `codestyle.md`: 2-space indent, LF, max 80 chars/line, opening `{`
  on same line, no `public import` re-exports, no `package.d` in
  `yguilib/source/yguilib/controls/`.
- Maintain `yguilib` independence (no imports from `yvidtrim` or `guidemo`).

## Tasks

### 1. Decouple `tab_button.d` and `source/guidemo/model.d`
- In `source/guidemo/tab_button.d`:
  - Remove `import guidemo.model : HeaderTabsModel;` and
    `import yguilib.widget.data_components : WidgetArrayProvider;`.
  - Remove `HeaderTabButtonsProvider` (lines 96-137) and its `unittest` block
    (lines 233-275).
  - Keep the style constants, `createTabButton`, `updateTabButtonState`, and
    the remaining two `unittest` blocks.
- In `source/guidemo/model.d`:
  - Remove unused `defaultHeaderTabNames` and `HeaderTabsModel` (lines
    123-146).

### 2. Update Package Visibility in `source/guidemo/virtlist.d`
- In `source/guidemo/virtlist.d` line 120, change `package(guidemo):` to
  `package(yguilib):`.

### 3. Move the 5 Modules into `yguilib/source/yguilib/controls/`
Run `rename_module.d` for each of the 5 modules:
```bash
rdmd .agents/skills/rename-module/scripts/rename_module.d --apply \
  guidemo.hover_button_system yguilib.controls.hover_button_system
rdmd .agents/skills/rename-module/scripts/rename_module.d --apply \
  guidemo.scrollbars yguilib.controls.scrollbars
rdmd .agents/skills/rename-module/scripts/rename_module.d --apply \
  guidemo.tab_button yguilib.controls.tab_button
rdmd .agents/skills/rename-module/scripts/rename_module.d --apply \
  guidemo.tabcontrol yguilib.controls.tabcontrol
rdmd .agents/skills/rename-module/scripts/rename_module.d --apply \
  guidemo.virtlist yguilib.controls.virtlist
```

### 4. Wrap Long Import Lines (`<= 80` chars)
Fix any import lines exceeding 80 characters in:
- `yguilib/source/yguilib/controls/tabcontrol.d`:
  ```d
  import yguilib.controls.tab_button : defaultTabButtonFontSize,
    defaultTabButtonHeight, defaultTabButtonRadius, defaultTabButtonWidth,
    tabActiveBg, tabActiveBorder, tabActiveText, tabInactiveBg,
    tabInactiveBorder, tabInactiveText;
  ```
- `yguilib/source/yguilib/controls/virtlist.d`:
  ```d
  import yguilib.controls.scrollbars : ScrollbarBuilder, ScrollbarModel,
    ScrollbarStyle;
  ```
  and inside `version (unittest)`:
  ```d
  import yguilib.controls.scrollbars : registerScrollbars,
    ScrollbarWidgetView;
  ```
- `source/guidemo/pages/scrollbars_page.d`:
  ```d
  import yguilib.controls.scrollbars : ScrollbarBuilder, ScrollbarModel,
    ScrollbarStyle;
  ```
- `source/guidemo/pages/tabcontrol_page.d`:
  ```d
  import yguilib.controls.tabcontrol : TabControlBuilder, TabControlStyle,
    TabsModel;
  ```
- `source/guidemo/pages/virtlist_page.d`:
  ```d
  import yguilib.controls.virtlist : VirtListBuilder, VirtListModel,
    VirtListWidgetView, virtListWidgetViewName;
  ```

### 5. Update `yguilib/meson.build` and `meson.build`
- In `yguilib/meson.build`, add to `yguilib_src` (in alphabetical order):
  - `'source/yguilib/controls/hover_button_system.d',`
  - `'source/yguilib/controls/scrollbars.d',`
  - `'source/yguilib/controls/tab_button.d',`
  - `'source/yguilib/controls/tabcontrol.d',`
  - `'source/yguilib/controls/virtlist.d',`
- In root `meson.build`:
  - Remove `'source/guidemo/hover_button_system.d'`,
    `'source/guidemo/scrollbars.d'`, `'source/guidemo/tab_button.d'`,
    `'source/guidemo/tabcontrol.d'`, and `'source/guidemo/virtlist.d'` from
    `guidemo_lib_src`.
  - Remove the 5 standalone test targets (`hover_button_system_test`,
    `tab_button_test`, `tabcontrol_test`, `scrollbars_test`, `virtlist_test`),
    keeping `hover_button_test` for `source/guidemo/hover_button.d`.

### 6. Update `ARCHITECTURE.md` and `TODO.md`
- In `ARCHITECTURE.md`:
  - Under `Directory & Package Topology`:
    - Under `source/guidemo/`: keep `hover_button.d` (controller-based hover
      button demo) and remove `scrollbars.d`, `tab_button.d`, `tabcontrol.d`,
      and `virtlist.d`.
    - Under `yguilib/source/yguilib/`: add `controls/` listing
      `hover_button_system.d`, `scrollbars.d`, `tab_button.d`, `tabcontrol.d`,
      and `virtlist.d`.
  - Under `Encapsulation & Scoping`: update the `package.d` bullet to state
    that `public import` re-exports are prohibited and multi-module packages
    like `yguilib.controls` import modules explicitly without `package.d`.
  - Keep `ARCHITECTURE.md` under 250 lines and <= 80 chars/line.
- In `TODO.md`:
  - Remove the completed first item (lines 1-7: `- move common controls from`
    `guidemo into yguilib ... under yguilib.controls package.`).

## Verification (Phase 2)
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d --all
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d --audit
```
