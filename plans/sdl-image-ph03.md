# sdl-image ph03: screenshots

Overview: [sdl-image.md](sdl-image.md). Read `AGENTS.md` (threading rules)
and `codestyle.md` first.

## Context
- ph02 added `yguilib.render.image.Image` (RGBA8, top-down, `savePng`,
  `isEmpty`, `pitch`,
  `flipVertical`, `loadFromFile`) and Texture/drawImage.
- `Renderer` (`render/package.d`) knows `getPixelWidth()` and
  `getPixelHeight()` (the viewport in pixels).
- The frame flow is in `widget/internal/system_pipeline.d`:
  `updateAndRender(Window)` calls `updateAndRenderTree` (which returns true
  if it rendered) and then `window.swapBuffers()`.
- `yguilib/source/yguilib/window.d` holds `Window` (renderer, swapBuffers,
  redraw).
- `uisystem.d` defines the `UiSystem` interface, implemented in
  `internal/uisystem_impl.d`. Also update any mock/test UiSystem
  implementations (grep `: UiSystem` / `implements UiSystem`, for example
  `controls/testing.d`). See how `windowExposed` / redraw marks the root
  dirty so that the next loop iteration renders (around
  uisystem_impl.d:507 and :752).

## Steps
1. `Renderer.readPixels(int x, int y, int w, int h)` takes a top-left
   origin rect in pixels and returns an `Image`. It clamps the rect to the
   viewport, sets `glPixelStorei(GL_PACK_ALIGNMENT, 4)`, calls
   `glReadPixels(x, ph - y - h, w, h, GL_RGBA, GL_UNSIGNED_BYTE, ...)`, and
   then calls `flipVertical()`. It returns null if the renderer is not
   initialized or the rect is empty. `Image captureFrame()` covers the full
   viewport. Document that it reads the bound framebuffer, so call it
   after rendering and before swap.
2. `Window`: `void requestScreenshot(string path)` stores a pending path,
   and `package(yguilib)` code takes it. In `SystemPipeline.updateAndRender`,
   when a frame rendered and a path is pending, it runs
   `captureFrame().savePng(path)`, logs `info` on success or `error` on
   failure, and clears the pending path before `swapBuffers()`.
3. `UiSystem.requestScreenshot(string path)` (interface + impl) forwards to
   the main window and marks the root widget dirty, or otherwise ensures
   a render happens on the next iteration even when idle. Add no-op or
   recording implementations to the test mocks.
4. Tests:
   - readPixels orientation: clearFrame black, fill RectF(0,0,10,10) red,
     then check that `captureFrame().pixels[0..4]` is red and the bottom-right
     pixel is black.
   - Headless pipeline test (pattern: uisystem_impl.d tests around 1130/1250
     using `ui.systemPipeline.updateAndRender(win)`): requestScreenshot to a
     tempDir path, run updateAndRender, then check that the file exists,
     `Image.loadFromFile` has the window's pixel size, and the pending path
     is cleared. Delete the file afterwards.

## Verification
`ninja -C _build && meson test -C _build`. Lines must be at most 80 chars.
