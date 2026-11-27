# `get*`/`set*` Naming Cleanup Plan

Make all D code follow the `codestyle.md` accessor rule ("Do not use
`get.../set...` naming pattern") and teach `check_style.d` to flag new
violations. Addresses the `TODO.md` tooling item "decide
`setCaption`/`setVisible`/... naming vs codestyle".

## Decisions

- **Widget setters are removed, not renamed.** `Widget.setCaption`,
  `setBackgroundColor`, `setTextColor`, `setBorderColor`, `setVisible`,
  `setInputEnabled`, `setScrollOffset` go away. Call sites assign the field /
  component value and call `w.update(WidgetUpdateScope.<scope>)` explicitly,
  using the same scope the setter used:

  ```
  setter              assigns                              scope
  ------------------  -----------------------------------  --------
  setCaption          components.textLabel.caption         content
  setBackgroundColor  components.background.color          visuals
  setTextColor        components.textLabel.color           visuals
  setBorderColor      components.border.color              visuals
  setVisible          visible                              layout
  setInputEnabled     inputEnabled                         visuals
  setScrollOffset     components.scrollableArea.offset     layout
  ```

  `Widget.update` already ignores released widgets. Where a call site runs
  repeatedly (model sync, `update()`, per-frame/animation code), keep the
  "no-op when unchanged" guard (`if (old != new) { assign; update; }`) so
  layout is not re-dirtied every frame.
- **Property pairs** (`T x()` / `void x(T v)`) replace `getX`/`setX` where a
  value is read/stored. A clashing backing field gets the `f` prefix. When a
  setter is renamed to `x(bool)` and its getter is `isX()`, the getter is
  renamed to `x()` so the pair matches.
- **Non-property setters** (extra arguments, side effects, model commits)
  become verbs: `assign*`, `commit*`, `request*`, `apply*`, `update*`.
- On a name collision (local variable, parameter, `std` symbol), use
  `<returnMeaning>From<ArgMeaning>` (e.g. `lineStepFromFont`).
- Out of scope: `__traits(getMember, ...)`, `Thread.getThis()`, C wrapper
  names (`yguilib_sdl3_get_*`), archived docs (`documentation/archive/`,
  `plans/archive/`).

## Phases

- Phase 1: [getset-naming-01.md](getset-naming-01.md)
  - Remove the 7 `Widget` setters and rewrite all ~110 call sites in
    yguilib, guidemo and yvidtrim; audit direct `visible`/`inputEnabled`
    field writes on live widgets.
- Phase 2: [getset-naming-02.md](getset-naming-02.md)
  - Rename the remaining `get*`/`set*` symbols in `yguilib/`.
- Phase 3: [getset-naming-03.md](getset-naming-03.md)
  - Rename the remaining symbols in `source/guidemo/` and `source/yvidtrim/`,
    add a `get*`/`set*` check to `check_style.d`, update docs/skills, remove
    the `TODO.md` item.

## Status

```
phase  status
-----  -------
01     done
02     done
03     done
```
