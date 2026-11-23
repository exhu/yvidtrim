# Auto-repeat mode for Button (TabControl / Scrollbar arrows)

## Goal
TODO.md item 1: holding a TabControl arrow (`tabScrollLeft/Right`) or a
Scrollbar arrow (`scrollbarDec/Inc`) keeps repeating its action event
instead of firing once per press. Idle must stay at 0% CPU.
Tab buttons themselves keep single press; track page-click repeat is out
of scope.

## Decisions
- `struct ButtonRepeat { bool enabled = false; uint delayMs = 400;
  uint intervalMs = 80; }` in `controls/button.d`, stored as
  `ButtonComponent.repeat`.
- Builder: `repeatWithTiming(uint delayMs, uint intervalMs)` (enables)
  and `repeat(in ButtonRepeat r)`.
- Repeat only with `ButtonTrigger.press` (asserted in `build()`).
- Timeline: press -> event; after `delayMs` -> event; every `intervalMs`
  -> event, until release.
- Dragged off: timer keeps running, events skipped while not
  `isPressed`; dragging back resumes.
- Repeat stops on release, disable (arrow at scroll end), hide, widget
  release, system unregister.
- One oneShot delay timer, then one repeat interval timer; a single
  `repeatTimerId` (only one button pressed at a time).

## Phases
```
ph01  ButtonRepeat in ButtonSystem (+ unit tests)
  |
ph02  Arrows of TabControl / Scrollbar repeat; styles; docs; TODO
```
Details:
- [ph01](button-repeat-ph01.md)
- [ph02](button-repeat-ph02.md)

## Verification (every phase)
`ninja -C _build && meson test -C _build` must pass; lines <= 80 chars.
Manual after ph02: `./_build/guidemo` hold TabControl / Scrollbar /
VirtList arrows; release stops; idle CPU 0%.
