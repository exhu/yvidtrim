# Split Widget.handleInput (hittable) vs Widget.inputEnabled (enabled)

## Goal
TODO.md item 1. Today `Widget.handleInput` is never read, and
`Widget.inputEnabled` does two jobs: it makes a widget hittable (it blocks
clicks to what is behind it) and it is the enabled/disabled flag. Split them:

| flag           | default | meaning                                         |
|----------------|---------|-------------------------------------------------|
| `handleInput`  | false   | takes part in pointer hit-tests and blocks      |
|                |         | click/hover-through to widgets behind it        |
| `inputEnabled` | true    | enabled state: disabled visuals, and whether    |
|                |         | view events / drag / cursor capture are emitted |

- A disabled widget with `handleInput` still swallows clicks and sends no
  events.
- Keyboard: `handleInput` covers pointer input only. For now this is only
  documented (to be built with the TODO "focus system" item): keys go to the
  focused widget that has a `KeyboardEvent`, and only if `inputEnabled`;
  disabled widgets can't take focus. The `KeyboardEvent` click-through
  special case in `InputSystem` is removed.

## Phases
```
ph01  core semantics: Widget defaults, WidgetBuilder, InputSystem
      hit-testing, tooltip hit-test + unit tests
  |
ph02  control call sites, define-gui-widget template, docs
      (button.d, FocusSystem, ARCHITECTURE.md), TODO.md
```
Details:
- [ph01](input-flags-ph01.md)
- [ph02](input-flags-ph02.md)

Verify after each phase: `ninja -C _build && meson test -C _build`.
