# Move Common Controls to `yguilib.controls` Implementation Plan

Overview for moving the reusable GUI control modules (`hover_button_system.d`,
`scrollbars.d`, `tab_button.d`, `tabcontrol.d`, and `virtlist.d`) from
`source/guidemo/` into `yguilib/source/yguilib/controls/` under the
`yguilib.controls` package (first item in `TODO.md`), updating `codestyle.md`
and project skills to prohibit `public import` re-exports, and consolidating
control unit tests into `yguilib_test`.

## Architecture Overview

```
+--------------------------------------------------------------------------+
|                        yguilib/source/yguilib/                           |
|                                                                          |
|  controls/ (no package.d; explicit module imports, no public re-exports) |
|  +-- hover_button_system.d  (module yguilib.controls.hover_button_system)|
|  +-- scrollbars.d           (module yguilib.controls.scrollbars)         |
|  +-- tab_button.d           (module yguilib.controls.tab_button)         |
|  +-- tabcontrol.d           (module yguilib.controls.tabcontrol)         |
|  +-- virtlist.d             (module yguilib.controls.virtlist)           |
+------------------------------------+-------------------------------------+
                                     ^
                                     | imports yguilib.controls.*
+------------------------------------+-------------------------------------+
|                             source/guidemo/                              |
|  +-- guidemoapp.d, view.d, controller.d, model.d                         |
|  +-- hover_button.d (controller-pattern demo, remains in guidemo)        |
|  +-- pages/ (button_system_page, tabcontrol_page, scrollbars_page,       |
|              virtlist_page, virtlist_controller)                         |
+--------------------------------------------------------------------------+
```

## Phases

- Phase 1: [yguilib-controls-ph01.md](yguilib-controls-ph01.md)
  - Update `codestyle.md` to forbid `public import` re-exports and clarify
    that multi-module packages (like `yguilib.controls`) do not require a
    `package.d`.
  - Update skills (`check-boundaries`, `check-codestyle`, `rename-module`,
    and `define-gui-widget`) to enforce no `public import` re-exports, allow
    multi-module directories without `package.d`, check that `yguilib` never
    imports `guidemo`, and support cross-root (`source/` -> `yguilib/source/`)
    module moves in `rename_module.d`.
- Phase 2: [yguilib-controls-ph02.md](yguilib-controls-ph02.md)
  - Decouple `tab_button.d` from `guidemo.model` by removing unused
    `HeaderTabButtonsProvider`, `HeaderTabsModel`, and
    `defaultHeaderTabNames`.
  - Update `package(guidemo):` in `virtlist.d` to `package(yguilib):`.
  - Move `hover_button_system.d`, `scrollbars.d`, `tab_button.d`,
    `tabcontrol.d`, and `virtlist.d` into `yguilib/source/yguilib/controls/`
    under `yguilib.controls.*` and update all imports across `yguilib` and
    `guidemo`.
  - Add the 5 modules to `yguilib_src` in `yguilib/meson.build`, remove them
    from `guidemo_lib_src` in `meson.build`, and remove the 5 standalone test
    targets (`hover_button_system_test`, `tab_button_test`, `tabcontrol_test`,
    `scrollbars_test`, `virtlist_test`) from `meson.build`.
  - Update `ARCHITECTURE.md` and remove the completed first item from
    `TODO.md`.
