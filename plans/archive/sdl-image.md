# SDL_image + screenshots (TODO.md item 1)

## Goal
TODO.md item 1: integrate SDL_image to load, save and draw images in the
Renderer, and support screenshots in the Renderer with saving to file.
This unblocks later items (offscreen-to-image, the Canvas `Pattern` stub in
`canvas.d`). SDL3_image 3.4.4 is installed (`pkg-config sdl3-image`).

## Decisions
- `Image`: CPU, RGBA8, straight alpha, top-down rows, tight pitch `w*4`;
  load from file/memory, save as PNG. It needs no GL context.
- `Texture`: GPU copy (RAII), created only by `renderer.createTexture(img)`,
  drawn with `renderer.drawImage(tex, dest[, srcPx], tint)` through the
  existing `TexturePipeline` (straight alpha blend).
- Screenshots: sync `renderer.readPixels(x, y, w, h)` and
  `renderer.captureFrame()` return an `Image`.
  `UiSystem.requestScreenshot(path)` captures after the next render and
  before swap. The PNG is encoded on the main thread.
- Save format: PNG only.
- guidemo: F12 takes a screenshot, and debug-draw cycling moves to F11.

## Phases
```
ph01  C wrapper yguilib_sdl3_image + C test + D bindings
  |
ph02  Image, Texture, Renderer.createTexture/drawImage, shared upload
  |
ph03  readPixels/captureFrame, Window/UiSystem.requestScreenshot
  |
ph04  guidemo F12 screenshot / F11 debug draw, Canvas page images,
      ARCHITECTURE.md, TODO.md
```
Details:
- [ph01](sdl-image-ph01.md)
- [ph02](sdl-image-ph02.md)
- [ph03](sdl-image-ph03.md)
- [ph04](sdl-image-ph04.md)

## Verification (every phase)
`ninja -C _build && meson test -C _build` must pass, and lines must be at most
80 chars. Manual check after ph04: run `SDL_LOGGING=app=trace
./_build/guidemo`, open the Canvas tab and check the images. Check that F11
cycles debug draw. Press F12, then confirm the PNG matches the window (upright,
correct colors). CPU stays at 0% when idle.
