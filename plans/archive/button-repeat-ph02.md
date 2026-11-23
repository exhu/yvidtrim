# Phase 2: Repeat on TabControl / Scrollbar arrows; docs

Overview: [button-repeat.md](button-repeat.md). Read AGENTS.md and
codestyle.md first. Phase 1 added to `controls/button.d`:
`struct ButtonRepeat { bool enabled; uint delayMs = 400;
uint intervalMs = 80; }`, `ButtonComponent.repeat`, and builder
`ButtonBuilder.repeatWithTiming(uint delayMs, uint intervalMs)` /
`repeat(in ButtonRepeat r)` (requires `ButtonTrigger.press`).

## Steps
1. `yguilib/source/yguilib/controls/tabcontrol.d`:
   - `TabControlStyle`: add documented
     `ButtonRepeat arrowRepeat = ButtonRepeat(true);`.
   - `buildArrowButton` (uses `btnStyle`): add
     `.repeat(btnStyle.arrowRepeat)` after `.trigger(...)`.
   - Import `ButtonRepeat`. Tab buttons (`TabButtonsProvider.addWidget`)
     stay without repeat.
2. `yguilib/source/yguilib/controls/scrollbars.d`:
   - `ScrollbarStyle`: add documented
     `ButtonRepeat arrowRepeat = ButtonRepeat(true, 400, 50);`.
   - `buildArrowBtn` (uses `cfg`): add `.repeat(cfg.arrowRepeat)`.
3. Tests: in tabcontrol.d unittest near "Arrow buttons: press trigger"
   assert `comp.repeat.enabled` for arrows and `!comp.repeat.enabled`
   for tab buttons; in scrollbars.d assert dec/inc arrows'
   `ButtonComponent.repeat.enabled` (add to an existing builder test).
4. `ARCHITECTURE.md` "Buttons" paragraph: mention optional
   `ButtonRepeat` auto-repeat (press trigger, delay then interval timer)
   used by TabControl and Scrollbar arrows. Keep file < 250 lines.
5. `TODO.md`: remove the first item (repeat mode to button ...),
   including its continuation line.

## Verify
`ninja -C _build && meson test -C _build` passes; lines <= 80 chars.
