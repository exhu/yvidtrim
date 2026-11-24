# Canvas Helpers and Gamepad Demo Page

## Goal
Implement the first two items from `TODO.md`:
1. Canvas API string helpers in `yguilib`:
   - `parseColor` / `colorFromString` (`yguilib.render.render_types`) and
     `FillStyle.solidFromString` (`yguilib.render.canvas.types`) to decode
     hex, `rgb()`/`rgba()`, and `"transparent"` strings.
   - `Path2d.fromSvgPath` / `Path2d.addSvgPath` (`yguilib.render.canvas.path2d`)
     backed by a full W3C SVG path data parser (`svg_path_parser.d`).
2. New `guidemo` Page 11 (`Gamepad`) translating the 600x400 vector gamepad from
   `documentation/gamepad-canvas-by-gemini.html` using the new helpers.

## Phases
```
ph01  Color string decoding helpers (render_types.d, canvas/types.d)
  |
ph02  Full SVG Path2d parser (svg_path_parser.d, path2d.d, GL test, meson)
  |
ph03  guidemo Page 11 (Gamepad), global hints fix, ARCHITECTURE.md, TODO.md
```

Details:
- [ph01](canvas-helpers-gamepad-ph01.md)
- [ph02](canvas-helpers-gamepad-ph02.md)
- [ph03](canvas-helpers-gamepad-ph03.md)

## Shared Verification
After every phase:
```bash
ninja -C _build && timeout 300 meson test -C _build
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
```
Phase 3 also runs `define_gui_widget.d --audit` and checks `ARCHITECTURE.md`
is under 250 lines.
