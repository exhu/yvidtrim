# sdl-image ph04: guidemo, docs

Overview: [sdl-image.md](sdl-image.md). Read `AGENTS.md` (View/Controller
rules, ARCHITECTURE.md rules) and `codestyle.md` first.

## Context
- ph01–ph03 added `Image` (`yguilib.render.image`), `Texture`
  (`yguilib.render.texture`), `Renderer.createTexture/drawImage/
  readPixels/captureFrame` and `UiSystem.requestScreenshot(path)`.
- `source/guidemo/controller.d` is the shared demo controller. F12 cycles
  `DebugDrawMode` (see the doc comment around line 54, the key handling, and
  the unittest around line 240). `source/guidemo/model.d:11` has a comment
  that mentions F12.
- The Canvas page is `source/guidemo/pages/canvas_page.d` (drawing via
  `onDraw` delegate(Renderer, in Widget)).
- Renderer image API (codestyle.md bans overloads and default params):
  `drawImage(tex, dest, tint)` and `drawImageRegion(tex, dest, srcPx,
  tint)`. `Texture` has no destructor, so call `destroy()` on the main
  thread. ARCHITECTURE.md already documents that RAII rule (from ph02).
- guidemo sources and import dirs are in the root `meson.build`
  (`guidemo_lib_src`; d_import_dirs). The top-level `assets/` only has
  `assets/yvidtrim/`.

## Steps
1. Move debug-draw cycling from F12 to F11. Update the controller doc
   comment, `model.d:11`, the existing unittest (now F11), and every other
   mention (grep for F12 in source/, README.md, documentation/ and
   ARCHITECTURE.md).
2. F12 calls `ui.requestScreenshot(name)`, where name is
   `screenshot-YYYYMMDD-HHMMSS.png` in the current directory (use
   `std.datetime.Clock.currTime`). It consumes the event. Check how the
   controller reaches `UiSystem` (the field passed to the constructor). Add a
   unittest with a recording mock that checks the path pattern. Also show the
   F12/F11 keys in the status bar or help text if keys are listed there.
3. Sample image: add a small PNG (for example 64x64, with a visible
   orientation such as a colored corner and a gradient) at
   `assets/guidemo/images/sample.png`. Generate it with a throwaway D program
   in the scratchpad using `Image.savePng`, or with ImageMagick if available.
   Add the import dir to guidemo's meson targets.
4. Canvas page: decode `import("guidemo/images/sample.png")` once with
   `Image.loadFromMemory`, create the `Texture` lazily on first draw, and
   destroy it on teardown if a hook exists. Draw it as-is, scaled 2x, as a
   src sub-rect via `drawImageRegion` (one quadrant), and tinted at 50%
   alpha. Add captions with drawText. Keep idle CPU at 0% (no timers).
5. ARCHITECTURE.md: add image.d and texture.d to the render tree, the
   SDL3_image wrapper to the clibs line, and a short screenshot data flow
   (request -> render -> captureFrame -> savePng -> swap). The file must
   stay under 250 lines. Update guidemo's controller.d description to
   F11/F12.
6. TODO.md: remove the first item "add image support" and its two
   sub-items.

## Verification
`ninja -C _build && meson test -C _build`. Lines must be at most 80 chars.
Manual check: run `./_build/guidemo`. F11 cycles debug draw, F12 writes a
screenshot PNG that is upright and correctly colored, and the Canvas tab
shows the 4 image draws.
