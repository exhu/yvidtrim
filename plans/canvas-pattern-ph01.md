# Phase 1: Shader & PatternPipeline

## Scope
Add the fragment shader, embedded shader asset, `PatternUniforms` +
`PatternPipeline` in `yguilib.render.internal.pipelines`, and `Renderer`
wiring in `yguilib.render`.

## Constraints
- Follow `codestyle.md` (2-space indent, LF, max 80 chars/line, opening `{` on
  same line, lowercase filenames).
- `internal/` modules must stay `package(yguilib):` (never `public:`).
- Use `glad2.gles2` for GLES calls (including `glGenSamplers`,
  `glDeleteSamplers`, `glSamplerParameteri`, `glBindSampler`, `GL_REPEAT`,
  `GL_CLAMP_TO_EDGE`, `GL_LINEAR`).
- Do NOT use `discard` in `pattern.frag.glsl`: `Canvas` cover passes rely on
  every covered fragment running `glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO)` to
  clear stencil bits 0..6. Output `fragColor = vec4(0.0); return;` outside
  `[0.0, 1.0)` on non-repeating axes instead.

## Steps

### 1. Create `yguilib/assets/yguilib/shaders/pattern.frag.glsl`
- `#version 300 es`, `precision highp float;`.
- Uniforms:
  - `uniform sampler2D uTexture;`
  - `uniform mat3 uInvXf;` (logic coords -> normalized tile UV, top-left `[0,1]`)
  - `uniform vec4 uTint;` (straight-alpha tint)
  - `uniform int uRepeat;` (bit 0 = repeat X, bit 1 = repeat Y: 0..3)
  - `uniform int uMode;` (matches `TextureMode`: 0 straight, 1 premultiplied,
    2 alphaMask)
  - `uniform int uBottomUp;` (non-zero flips `uv.y = 1.0 - uv.y` for GL
    bottom-up render target textures)
- Input `in vec2 vPos;` (reuses `paint.vert.glsl`), output `out vec4 fragColor;`.
- Logic in `main()`:
  1. `vec2 uv = (uInvXf * vec3(vPos, 1.0)).xy;`
  2. If `(uRepeat & 1) == 0 && (uv.x < 0.0 || uv.x >= 1.0)` or
     `(uRepeat & 2) == 0 && (uv.y < 0.0 || uv.y >= 1.0)`, set
     `fragColor = vec4(0.0); return;`.
  3. If `uBottomUp != 0`, `uv.y = 1.0 - uv.y;`.
  4. `vec4 texColor = texture(uTexture, uv);`
  5. Combine with `uTint` using the exact same `uMode` branches as
     `texture.frag.glsl`:
     - `uMode == 1`: `texColor * vec4(uTint.rgb * uTint.a, uTint.a)`
     - `uMode == 2`: `vec4(1.0, 1.0, 1.0, texColor.a * uTint.a)`
     - else: `texColor * uTint`

### 2. Embed shader in `yguilib/source/yguilib/internal/assets.d`
Add:
```d
enum string patternFragmentShaderSource =
  import("yguilib/shaders/pattern.frag.glsl");
```

### 3. Add `PatternUniforms` and `PatternPipeline` in `pipelines.d`
File: `yguilib/source/yguilib/render/internal/pipelines.d`
- `struct PatternUniforms`:
  - `GLuint textureId;`
  - `float[9] invXf = [1, 0, 0, 0, 1, 0, 0, 0, 1];`
  - `ColorF tint = ColorF(1, 1, 1, 1);`
  - `int repeat;` (bit 0 = repeat X, bit 1 = repeat Y)
  - `TextureMode mode = TextureMode.straight;`
  - `bool bottomUp;`
- `struct PatternPipeline`:
  - Fields: `GLuint program`, `GLuint vao`, `GLuint vbo`, `GLuint[4] samplers`,
    uniform locations (`uResolutionLoc`, `uTextureLoc`, `uInvXfLoc`,
    `uTintLoc`, `uRepeatLoc`, `uModeLoc`, `uBottomUpLoc`, all `-1`).
  - `initialize()`:
    - `program = buildProgram(paintVertexShaderSource, patternFragmentShaderSource);`
    - Query all uniform locations.
    - `createVec2VertexArray()` for `vao`/`vbo`.
    - `glGenSamplers(4, samplers.ptr);` and configure each `i` in `0 .. 4`:
      - `GL_TEXTURE_MIN_FILTER` = `GL_LINEAR`
      - `GL_TEXTURE_MAG_FILTER` = `GL_LINEAR`
      - `GL_TEXTURE_WRAP_S` = `(i & 1) ? GL_REPEAT : GL_CLAMP_TO_EDGE`
      - `GL_TEXTURE_WRAP_T` = `(i & 2) ? GL_REPEAT : GL_CLAMP_TO_EDGE`
  - `destroy()`:
    - If `samplers[0] != 0`, `glDeleteSamplers(4, samplers.ptr); samplers = 0;`.
    - `destroyProgramAndBuffers(program, vao, vbo);`.
  - `drawTriangles(const(float)[] vertices, in PatternUniforms u, float vw, float vh)`:
    - Early return if `u.textureId == 0 || vertices.length < 6`.
    - `TexturePipeline.setupBlendForMode(u.mode);`
    - `drawTrianglesWithCurrentState(vertices, u, vw, vh);`
  - `drawTrianglesWithCurrentState(...)`:
    - Early return if `u.textureId == 0 || vertices.length < 6`.
    - `glUseProgram(program)` and upload uniforms (`uTexture` = 0,
      `uBottomUp` = `u.bottomUp ? 1 : 0`, `uMode` = `cast(GLint)u.mode`,
      `uRepeat` = `u.repeat & 3`).
    - `glActiveTexture(GL_TEXTURE0);`
    - `glBindTexture(GL_TEXTURE_2D, u.textureId);`
    - `glBindSampler(0, samplers[u.repeat & 3]);`
    - `uploadAndDrawDynamic(GL_TRIANGLES, vao, vbo, vertices, cast(GLsizei)(vertices.length / 2));`
    - `glBindSampler(0, 0);`
    - `glBindTexture(GL_TEXTURE_2D, 0);`

### 4. Wire `PatternPipeline` into `Renderer`
File: `yguilib/source/yguilib/render/package.d`
- Import `PatternPipeline` from `yguilib.render.internal.pipelines`.
- Add `PatternPipeline patternPipeline;` field to `Renderer`.
- Call `patternPipeline.initialize();` in `initialize()` and
  `patternPipeline.destroy();` in `destroy()`.
- Expose in `package(yguilib.render):`:
  ```d
  /// Shared image pattern paint pipeline (used by `Canvas`).
  ref PatternPipeline patternPipelineRef() return {
    return patternPipeline;
  }
  ```

## Verification
Run:
```bash
ninja -C _build && timeout 300 meson test -C _build
```
All targets must build cleanly and all existing tests must pass.
