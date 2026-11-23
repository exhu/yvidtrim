# Phase 1: blend state, texture flags, texture pipeline modes

Overview: [offscreen.md](offscreen.md). Read `AGENTS.md`, `codestyle.md`
and the Canvas/Images notes in `ARCHITECTURE.md` first.

## Context
- `yguilib/source/yguilib/render/internal/gl_util.d` has the
  `setupAlphaBlendState()` -> `glBlendFunc(SRC_ALPHA, ONE_MINUS_SRC_ALPHA)`.
  Applied to a transparent target, this squares alpha.
- `render/texture.d` `Texture` is a straight-alpha, top-down copy of an
  `Image`.
- `render/internal/pipelines.d` `TexturePipeline.drawTexturedQuad` uses
  the shader `assets/yguilib/shaders/texture.frag.glsl`
  (`fragColor = tex * uColor`).
- `render/package.d` `Renderer.drawImage` / `drawImageRegion`.

## Steps
1. `setupAlphaBlendState()`: use `glBlendFuncSeparate(GL_SRC_ALPHA,
   GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA)`. Update its doc
   to say the destination alpha accumulates correctly (premultiplied result
   on a transparent target). Grep for any other `glBlendFunc` callers and
   make them match.
2. Add `setupPremultipliedBlendState()` (`glBlendFunc(GL_ONE,
   GL_ONE_MINUS_SRC_ALPHA)`) next to it.
3. `Texture`: add `package(yguilib)` flags `premultiplied` and `bottomUp`
   (both false for Image uploads), and a package constructor that wraps an
   existing GL texture id + size + flags. `RenderTarget` uses it in ph02;
   such a texture is "borrowed": add a `borrowed` flag. `update()` and
   `destroy()` assert `!borrowed`. Give the target a package
   `releaseBorrowed()` instead. Document this in the class doc.
4. `TexturePipeline`:
   - add a `uMode` int uniform to `texture.frag.glsl`: 0 = straight
     (`tex * uColor`), 1 = premultiplied (`tex * vec4(uColor.rgb *
     uColor.a, uColor.a)`), 2 = alpha mask (`vec4(1, 1, 1, tex.a *
     uColor.a)`, used by ph03 shadows). The blur pass shares the vertex
     shader only; check that it is unaffected.
   - `drawTexturedQuad(texId, q, vw, vh, TextureMode mode)` (add an enum
     `TextureMode { straight, premultiplied, alphaMask }`). Keep the
     existing call sites on `straight` (add an overload or update the
     callers).
   - `drawTexturedTriangles(texId, const(float)[] xyuv, color, mode, vw,
     vh)` for arbitrary interleaved (x, y, u, v) triangles, and
     `...WithCurrentState` variants that skip `setupAlphaBlendState` (the
     ph03 shadow mask disables blending; follow the
     `ColorPipeline.drawArraysWithCurrentState` pattern).
   - premultiplied mode selects `setupPremultipliedBlendState()`.
5. `Renderer.drawImageRegion`: when `t.bottomUp`, flip v (`uv.y + uv.h`,
   negative height, as `Canvas.compositeShadow` does). Pick the mode from
   `t.premultiplied`. Add a package helper `textureUv(t, srcPx)` returning
   the uv rect, for ph03 to reuse.
6. Tests (GL unittests follow the window pattern in `canvas.d` near the
   shadow tests, `new Window(320, 240, ...)`):
   - a semi-transparent rect drawn onto a cleared-transparent framebuffer
     gives alpha = a (not a*a), and opaque results are unchanged.
   - a borrowed texture asserts on `update`/`destroy` (skip if asserts are
     hard to test; at least test that the flags default to false).
   - a premultiplied texture drawn through `drawImage` gives the same
     pixels as the equivalent straight texture.
7. Run `ninja -C _build && meson test -C _build`. All existing canvas
   shadow tests must still pass (they read RGB only; also check alpha
   expectations if any).

## Done when
Build and tests pass. No visual change on screen (the guidemo Canvas page
looks the same).
