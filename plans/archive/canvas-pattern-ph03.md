# Phase 3: guidemo Showcase, Docs & Final Verification

## Scope
Add the `"11. Patterns"` showcase card to `guidemo`'s Canvas page (slot 7,
cycled with `[I]`), update `ARCHITECTURE.md` and `TODO.md`, and run all
project quality and test checks.

## Constraints
- Follow `codestyle.md` (2-space indent, LF, max 80 chars/line, opening `{` on
  same line).
- Keep `ARCHITECTURE.md` strictly under 250 lines.
- Preserve existing docstrings and comments; update only what changed.

## Steps

### 1. Add `CanvasSlot7.patterns` in `source/guidemo/model.d`
Add `patterns` to `enum CanvasSlot7`:
```d
enum CanvasSlot7 {
  interop,
  images,
  offscreen,
  patterns,
}
```

### 2. Add Section 11 (`"11. Patterns"`) in `source/guidemo/pages/canvas_page.d`
- Import `Pattern` and `PatternRepeat` from `yguilib.render.canvas`.
- Add `Widget patternsWidget;` and any prebuilt paths needed (e.g.
  `patternTileRect`, `patternStripX`, `patternStripY`, `patternOnceRect`,
  `patternRotCircle`, `patternStrokeWave`, `patternRtRect`).
- In `buildSections()`, add slot-7 card:
  ```d
  patternsWidget = addSection(
    2, 1, "11. Patterns", "canvasPatterns", &drawPatterns
  );
  ```
- In `syncSlot7()`, toggle `patternsWidget.parent.setVisible(s == CanvasSlot7.patterns)`.
- In `update()`, also mark `patternsWidget.update(WidgetUpdateScope.visuals)`
  (since the rotated pattern animates with `tracker.model.rotation`).
- In `formatStatus()`, update the `next` table for the 4-way `[I]` cycle:
  - `interop` -> `" | [I] Show images"`
  - `images` -> `" | [I] Show offscreen"`
  - `offscreen` -> `" | [I] Show patterns"`
  - `patterns` -> `" | [I] Show interop"`
- Implement `drawPatterns(Renderer r, in Widget w)`:
  - Lazily create `sampleTexture` (if `sampleImage !is null`) and `syncOffscreen(r)`.
  - Showcase within the 266x232 card:
    1. `repeat` (scaled 0.4x) filling a rounded rect with a soft drop shadow,
    2. `repeatX` horizontal strip and `noRepeat` single tile (scaled 0.5x),
    3. Animated rotated `Pattern.transform` (using `tracker.model.rotation`)
       with a blue-ish `tint` filling a circle,
    4. Pattern stroke (`lineWidth(10)`, `LineCap.round`) along a short wave,
    5. `offscreen.texture()` (`RenderTarget`) tiled as a `repeat` pattern
       (scaled to ~32x32 logic units) in the bottom-right corner.
  - Keep concise labels (`labelAt`) so each sample is self-explanatory.
- Update the `CanvasPage` unittest (`drawWidgets().length == 11`, verify
  `patternsWidget.parent` visibility and `formatStatus()` across all 4 states).

### 3. Update `source/guidemo/pages/canvas_controller.d`
- Update module/class doc comment to mention `patterns` in the `[I]` cycle.
- Update the `[I]` cycle unittest:
  `images -> offscreen -> patterns -> interop -> images`.

### 4. Update `ARCHITECTURE.md` and `TODO.md`
- `ARCHITECTURE.md`:
  - Mention `Pattern` / patterns in the `Canvas` summary (and `canvas_page.d`
    note if concise). Ensure total line count stays < 250 lines.
- `TODO.md`:
  - Remove the completed first item:
    `- Canvas Pattern (image fill/stroke paint, canvas.d Pattern stub)`

## Verification
Run all build, test, and quality scripts:
```bash
ninja -C _build && timeout 300 meson test -C _build
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-codestyle/scripts/check_codestyle.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
```
Fix any reported issues and re-verify.
