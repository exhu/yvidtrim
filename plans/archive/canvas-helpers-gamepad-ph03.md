# Phase 3: `guidemo` Page 11 (Gamepad) + Docs & `TODO.md` Cleanup

Overview: [canvas-helpers-gamepad.md](canvas-helpers-gamepad.md).

## Goal
Add `guidemo` Page 11 (`Gamepad`) translating the 600x400 canvas gamepad from
`documentation/gamepad-canvas-by-gemini.html` using `Path2d.fromSvgPath`,
`colorFromString`, and `FillStyle.solidFromString`, then update docs & `TODO.md`.

## Files & Steps

### 1. `source/guidemo/model.d`
- Add `gamepad,` to `enum DemoPage : size_t` after `canvas,`.
- Add `DemoPage.gamepad: DemoPageMeta("Gamepad", "Gamepad"),` to `demoPages`.
- Add `final class GamepadPageModel : VersionedModel {}`.

### 2. `source/guidemo/demo_model_helpers.d`
- Fix `formatGlobalHints(DebugDrawMode mode)`:
  - When `demoPages.length >= 10`, format `"[Tab/1-0] Page | [F1] Debug draw: %s | [F12] Screenshot | [Q/Esc] Quit"`.
  - When `demoPages.length < 10`, format `"[Tab/1-%d] Page | [F1] Debug draw: %s | [F12] Screenshot | [Q/Esc] Quit"`.
- Update `unittest` assertions for `pageCount() == 11`, `tabs.length == 11`,
  `tabs[10] == "[11] Gamepad"`, and `formatGlobalHints`.

### 3. `source/guidemo/pages/gamepad_page.d` (NEW)
- Module `guidemo.pages.gamepad_page;`.
- `final class GamepadPage`:
  - `@disable this();`, asserts `ui !is null` and `parent !is null`,
    `invariant { assert(root !is null); assert(canvasWidget !is null); }`.
  - `root`: `Widget` named `"gamepadPage"`, `RectF(0, 0, 1280, 720)`, added
    to `parent`.
  - Card via `makeSectionCard(ui, root, RectF(20, 68, 1240, 572),
    "Canvas 2D Gamepad Vector", "gamepadCard")`.
  - Centered 600x400 canvas widget inside `card`:
    - `.name("gamepadCanvas")`
    - `.rect(RectF(320, 98, 600, 400))`
    - `.roundBg(colorFromString("#12141a"))`
    - `.bgRadius(12.0f)`
    - `.border(colorFromString("#2d3342"))`
    - `.borderStyle(Border.Style.roundDashed)`
    - `.borderRadius(12.0f)`
    - `.borderWidth(1.0f)`
    - `.borderDashLen(6.0f)`
    - `.borderDashGap(4.0f)`
    - `.clipContents(true)`
    - `.onDraw(&drawGamepad)`
  - Prebuild all `Path2d` shapes once in `buildPaths()` matching
    `documentation/gamepad-canvas-by-gemini.html`:
    1. Bumpers: `leftBumper` (`"M 155 112 C 165 88, 225 88, 235 106 Z"`),
       `rightBumper` (`"M 365 106 C 375 88, 435 88, 445 112 Z"`), fill
       `"#1f2430"`.
    2. Main body: `bodyPath` via `Path2d.fromSvgPath(...)` with exact body
       SVG string, fill `"#2b3140"`, stroke `"#4b556b"`, `lineWidth(4)`.
    3. D-Pad: `dpad` (`roundRect(RectF(180, 145, 20, 60), 4)` +
       `roundRect(RectF(160, 165, 60, 20), 4)`, fill `"#151821"`), `dpadCenter`
       (`arc(PointF(190, 175), 5, 0, 2 * PI, false)`, fill `"#2b3140"`).
    4. Face buttons: `(410, 150)` `"#f59e0b"`, `(435, 175)` `"#ef4444"`,
       `(410, 200)` `"#10b981"`, `(385, 175)` `"#3b82f6"`, radius `11`.
    5. Analog sticks at `(248, 212)` and `(352, 212)`: `socket` (r=24, fill
       `"#151821"`), `cap` (r=16, fill `"#3c4457"`, stroke `"#5a657d"`,
       `lineWidth(2)`).
    6. Menu buttons: `roundRect(RectF(268, 152, 18, 7), 3.5f)` +
       `roundRect(RectF(314, 152, 18, 7), 3.5f)`, fill `"#64748b"`.
       Home button: `arc(PointF(300, 178), 9, 0, 2 * PI, false)`, fill
       `"#151821"`, stroke `"#64748b"`, `lineWidth(2)`.
  - In `drawGamepad`: do NOT call `c.clearRect(...)` (widget `.roundBg` already
    paints `#12141a`). Set `LineJoin.round` and `LineCap.round`.
  - Expose `update()`, `formatStatus()` (`"Path2d SVG & color helpers (600x400)"`),
    `rootWidget()`, `drawWidget()`, `isVisible() const`.
  - Headless `unittest` verifying recursive widget names (`verifyAllNamed`),
    `600x400` canvas dimensions, and non-empty prebuilt paths within
    `RectF(0, 0, 600, 400)`.

### 4. `source/guidemo/pages/gamepad_controller.d` (NEW)
- Module `guidemo.pages.gamepad_controller;`.
- `alias GamepadPageControllerParams =
    PageControllerParams!(GamepadPage, ModelTracker!GamepadPageModel);`
- `final class GamepadPageController : DefaultController` (no timers):
  - Constructor syncs `syncPageShellView` and `syncPageStatus` for
    `DemoPage.gamepad`.
  - `update()` and `updateView()` follow `KnobPageController`.
- Headless `unittest` verifying visibility toggling and status updates when
  switching `DemoModel.activePage`.

### 5. `source/guidemo/guidemoapp.d` & `meson.build`
- `guidemoapp.d`: import `GamepadPageModel`, `GamepadPage`,
  `GamepadPageController`; add `registerGamepadPage` and call it in
  `registerDemoPages`; update docstring Page 11 listing.
- `meson.build`: add `'source/guidemo/pages/gamepad_controller.d'` and
  `'source/guidemo/pages/gamepad_page.d'` alphabetically to `guidemo_lib_src`.

### 6. `ARCHITECTURE.md` & `TODO.md`
- `ARCHITECTURE.md`: mention `svg_path_parser` (under `render/internal/`) and
  `gamepad_page.d` (under `source/guidemo/pages/`), keeping total lines < 250.
- `TODO.md`: remove the first two completed items (lines 1-2) and trim any
  leading blank line.

## Verification
```bash
ninja -C _build && timeout 300 meson test -C _build
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d --audit
```
Check `ARCHITECTURE.md` has `< 250` lines and `git status` is clean.
