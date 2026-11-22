# Tooltip Popup Layer, Component & System Plan

## Overview
Implement a reusable tooltip (text hint) popup layer widget, `Tooltip`
component, and `TooltipSystem` in `yguilib.controls`, and demonstrate it in
`guidemo` on buttons and tabs.

## Architecture Summary
```
rootWidget (last child)
  └── tooltipLayer (TooltipLayerComponent, visible=true, inputEnabled=false,
        no Background/Border, Size.autoSize(), Anchor(0,0,0,0))
        └── tooltipLayerPopup (visible=false, inputEnabled=false,
              Size.autoSize(), Background.round, Border.round,
              TextLabel(multiline=true, overflowEllipsis=true))
```

Pipeline integration (`TooltipSystem`, priority `20`, phases
`event | preLayout | layout | postLayout`):
- `event`: unobstructed hit-test (checking ONLY `visible` and `inputEnabled`,
  never painting/background components), dwell delay timer, leave/click fade.
- `preLayout`: set `popup.components.size.maxWidth`/`maxHeight` from layer size
  minus `edgeMargin`.
- `layout` (after `LayoutSystem` priority `0` and `ScrollSystem` priority `10`):
  position `popup.rect.x/y` near cursor in layer-local coords, flip above cursor
  if bottom overflows, clamp inside layer bounds.
- `postLayout` / `onWidgetReleased`: hide/cancel if target becomes invisible,
  obstructed, or released; clear cached layer references on release.

## Phases
- [Phase 1: Core Tooltip Control & System](tooltip-ph01.md)
  Create `yguilib.controls.tooltip` (`Tooltip`, `TooltipStyle`, `TooltipTiming`,
  `TooltipLayerComponent`, `TooltipLayerBuilder`, `TooltipSystem`) with
  comprehensive headless unit tests and wire into `yguilib/meson.build`.
- [Phase 2: Builder Ergonomics & guidemo Integration](tooltip-ph02.md)
  Add `.tooltip(...)` to button builders, attach `Tooltip` to tab buttons,
  register `TooltipSystem` + last-child tooltip layer in `guidemo`, and
  demonstrate on buttons (including truncated long captions) and tabs.
- [Phase 3: Documentation & Cleanup](tooltip-ph03.md)
  Update `ARCHITECTURE.md` (under 250 lines), remove completed item from
  `TODO.md`, and run full verification suite.
