# guidemo: conform to codestyle.md and AGENTS.md architecture

## Goal
Bring `source/guidemo/` in line with `codestyle.md` and the AGENTS.md
View-Controller Separation rule.

## Model ownership rule (agreed)
- A model used only by the view stays inside the view.
- A model the controller modifies is created first (in `registerDemoPages`
  or the test), passed to both View and Controller, and the controller edits
  it directly via its `ModelTracker` (`edit()` / `commit()`). Views expose no
  mutator or tracker-accessor methods for such models.

## Phases
```
ph01  mechanical style fixes (accessor renames, tooltip
      overload, const, @disable, docs, PageControllerParams)
  |
ph02  lift page models: layout_painter, textlabel, button,
      button_system (+ knob uses PageControllerParams)
  |
ph03  scrollbars + tabcontrol: lift page model and
      controller-mutated control trackers, move mutators
  |
ph04  virtlist: extract items models, move mutators,
      split module, update ARCHITECTURE.md
```
Details:
- [ph01](guidemo-conform-ph01.md)
- [ph02](guidemo-conform-ph02.md)
- [ph03](guidemo-conform-ph03.md)
- [ph04](guidemo-conform-ph04.md)

## Verification (every phase)
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-codestyle/scripts/check_style.d source/guidemo/
rdmd .agents/skills/check-line-length/scripts/check_line_length.d -f \
  source/guidemo/*.d source/guidemo/pages/*.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d \
  source/guidemo/*.d source/guidemo/pages/*.d
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
```
