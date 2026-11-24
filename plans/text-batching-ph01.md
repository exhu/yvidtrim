# Phase 1: Shaders, IndexedQuadArray, TextPipeline & TextBatch

## Scope & Target Files

- `yguilib/assets/yguilib/shaders/text.vert.glsl` [NEW]
- `yguilib/assets/yguilib/shaders/text.frag.glsl` [NEW]
- `yguilib/source/yguilib/internal/assets.d` [MODIFY]
- `yguilib/source/yguilib/render/internal/gl_util.d` [MODIFY]
- `yguilib/source/yguilib/render/internal/pipelines.d` [MODIFY]
- `yguilib/source/yguilib/render/internal/text_batch.d` [NEW]
- `yguilib/source/yguilib/render/internal/glyph_atlas.d` [MODIFY]
- `yguilib/source/yguilib/render/internal/text_cache.d` [MODIFY]
- `yguilib/meson.build` [MODIFY]

Read only these files (plus `stencil_ops.d`, `allochelpers.d` if needed).
Follow `codestyle.md` strictly: 2-space indent, LF, max 80 chars/line,
`{` on same line, `f` prefix for private fields, visibility section labels,
no default parameters, no `public:`.

## Implementation Steps

1. **`yguilib/assets/yguilib/shaders/text.vert.glsl`** [NEW]:
   No `#version` line (loaded via `vertPrelude` which supplies `#version 300 es`
   and `logicToClip`):
   ```glsl
   layout(location = 0) in vec2 aPosition;
   layout(location = 1) in vec2 aTexCoord;
   layout(location = 2) in vec4 aColor;
   uniform vec2 uResolution;
   out vec2 vTexCoord;
   out vec4 vColor;

   void main() {
     gl_Position = logicToClip(aPosition, uResolution);
     vTexCoord = aTexCoord;
     vColor = aColor;
   }
   ```

2. **`yguilib/assets/yguilib/shaders/text.frag.glsl`** [NEW]:
   ```glsl
   #version 300 es

   precision highp float;

   uniform sampler2D uTexture;
   in vec2 vTexCoord;
   in vec4 vColor;
   out vec4 fragColor;

   void main() {
     fragColor = texture(uTexture, vTexCoord) * vColor;
   }
   ```

3. **`yguilib/source/yguilib/internal/assets.d`** [MODIFY]:
   Add `textVertexShaderSource` and `textFragmentShaderSource`:
   ```d
   enum string textVertexShaderSource =
     vertPrelude ~ import("yguilib/shaders/text.vert.glsl");
   enum string textFragmentShaderSource =
     import("yguilib/shaders/text.frag.glsl");
   ```

4. **`yguilib/source/yguilib/render/internal/gl_util.d`** [MODIFY]:
   Add indexed-quad streaming helpers:
   - `enum size_t maxIndexedQuads = 16383;`
   - `enum size_t minIndexedQuadCapacity = 64;`
   - `size_t indexedQuadCapacityFor(size_t quads) nothrow @safe @nogc pure`:
     `assert(quads <= maxIndexedQuads);` Start at `minIndexedQuadCapacity`,
     double while `< quads`, clamp to `maxIndexedQuads`.
   - `struct IndexedQuadArray`:
     `GLuint vao; GLuint vbo; GLuint ebo; size_t vboCapacity; size_t eboQuadCapacity;`
   - `IndexedQuadArray createTextQuadArray()`:
     - `glGenVertexArrays(1, &h.vao); glBindVertexArray(h.vao);`
     - `glGenBuffers(1, &h.vbo); glBindBuffer(GL_ARRAY_BUFFER, h.vbo);`
     - `glGenBuffers(1, &h.ebo); glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, h.ebo);`
     - Stride `const GLsizei stride = 8 * float.sizeof;`
     - Attr 0: 2 floats, offset 0 (`null`)
     - Attr 1: 2 floats, offset `2 * float.sizeof`
     - Attr 2: 4 floats, offset `4 * float.sizeof`
     - Unbind VAO FIRST (`glBindVertexArray(0)`), then unbind `GL_ARRAY_BUFFER`
       and `GL_ELEMENT_ARRAY_BUFFER`.
   - `void uploadAndDrawIndexedQuads(ref IndexedQuadArray qa, const(void)[] vertexBytes, size_t quadCount)`:
     - If `quadCount == 0 || vertexBytes.length == 0`, return.
     - `assert(quadCount <= maxIndexedQuads);`
     - `glBindVertexArray(qa.vao);`
     - `glBindBuffer(GL_ARRAY_BUFFER, qa.vbo);`
     - Grow VBO via `vboCapacityFor(vertexBytes.length)` + `glBufferData(null, GL_DYNAMIC_DRAW)`
       if `vertexBytes.length > qa.vboCapacity`.
     - `glBufferSubData(GL_ARRAY_BUFFER, 0, cast(GLsizeiptr)vertexBytes.length, vertexBytes.ptr);`
     - If `quadCount > qa.eboQuadCapacity`:
       - `const size_t newQuads = indexedQuadCapacityFor(quadCount);`
       - `auto indices = new ushort[newQuads * 6];`
       - Fill per quad `q`: `const ushort b = cast(ushort)(q * 4);`
         `[b, b + 1, b + 2, b + 2, b + 1, b + 3]`.
       - `glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, qa.ebo);`
       - `glBufferData(GL_ELEMENT_ARRAY_BUFFER, cast(GLsizeiptr)(indices.length * ushort.sizeof), indices.ptr, GL_STATIC_DRAW);`
       - `qa.eboQuadCapacity = newQuads;`
     - `glDrawElements(GL_TRIANGLES, cast(GLsizei)(quadCount * 6), GL_UNSIGNED_SHORT, null);`
   - `void destroyIndexedQuadArray(ref IndexedQuadArray qa)`:
     Delete non-zero `ebo`, `vbo`, `vao`, reset `qa = IndexedQuadArray.init`.
   - Add unittest covering `indexedQuadCapacityFor`.

5. **`yguilib/source/yguilib/render/internal/pipelines.d`** [MODIFY]:
   - Add `struct TextVertex { float x, y, u, v, r, g, b, a; }` and
     `static assert(TextVertex.sizeof == 8 * float.sizeof);`.
   - Add `struct TextPipeline`:
     - `GLuint program; IndexedQuadArray qa; GLint uResolutionLoc = -1; GLint uTextureLoc = -1;`
     - `private: ProgramTracker* fPrograms; Vec2UniformCache fResolution;`
     - `void initialize(ProgramTracker* programs)`:
       `assert(programs !is null); fPrograms = programs;`
       `program = buildProgram(textVertexShaderSource, textFragmentShaderSource);`
       `qa = createTextQuadArray();`
       `uResolutionLoc = glGetUniformLocation(program, "uResolution\0".ptr);`
       `uTextureLoc = glGetUniformLocation(program, "uTexture\0".ptr);`
     - `void destroy()`: `destroyIndexedQuadArray(qa);` and if `program != 0`,
       `glDeleteProgram(program); program = 0;`.
     - `void drawGlyphQuads(GLuint texId, const(TextVertex)[] vertices, size_t quadCount, in Viewport vp)`:
       - If `texId == 0 || quadCount == 0`, return.
       - `assert(vertices.length == quadCount * 4);`
       - `setupAlphaBlendState();`
       - `fPrograms.use(program);`
       - `fResolution.upload(uResolutionLoc, vp.vw, vp.vh, fPrograms.epoch());`
       - `glUniform1i(uTextureLoc, 0);`
       - `glActiveTexture(GL_TEXTURE0); glBindTexture(GL_TEXTURE_2D, texId);`
       - `uploadAndDrawIndexedQuads(qa, cast(const(void)[])vertices, quadCount);`
       - `glBindTexture(GL_TEXTURE_2D, 0);`

6. **`yguilib/source/yguilib/render/internal/text_batch.d`** [NEW]:
   - `module yguilib.render.internal.text_batch;`
   - `package(yguilib):`
   - `version (unittest) struct TextBatchStats { size_t flushes; size_t flushedQuads; }`
   - `struct TextBatch { @disable this(this); ... }`:
     - `bool empty() const nothrow @safe`
     - `size_t quadCount() const nothrow @safe`
     - `GLuint texture() const nothrow @safe`
     - `bool stencilClip() const nothrow @safe`
     - `bool needsFlushFor(GLuint texId, bool stencilClip) const nothrow @safe`:
       `return fQuadCount > 0 && (fTexture != texId || fStencilClip != stencilClip || fQuadCount >= maxIndexedQuads);`
     - `void pushQuad(GLuint texId, bool stencilClip, in TextVertex[4] quad)`:
       `assert(texId != 0); assert(!needsFlushFor(texId, stencilClip));`
       If `fQuadCount == 0`: `fTexture = texId; fStencilClip = stencilClip;`.
       Push the 4 vertices via `foreach (ref v; quad) fVerts.push(v);`
       (never call `fVerts.reserve(len + 4)`). `++fQuadCount;`.
     - `void flush(ref TextPipeline pipeline, in Viewport vp)`:
       If `fQuadCount == 0`, return.
       Capture `tex = fTexture`, `clip = fStencilClip`, `quads = fQuadCount`,
       `verts = fVerts[]`.
       Reset `fQuadCount = 0; fTexture = 0; fStencilClip = false;` BEFORE GL.
       If `clip`, `beginClipTest(true);`.
       `pipeline.drawGlyphQuads(tex, verts, quads, vp);`
       If `clip`, `endStencil();`.
       `fVerts.clear();`
       Under `version (unittest)`: `++fStats.flushes; fStats.flushedQuads += quads;`.
     - `void clear()` and `void releaseMemory()`
     - Under `version (unittest)`: `TextBatchStats stats() const nothrow @safe` and
       `void resetStats() nothrow @safe`.
   - Unit tests: `needsFlushFor` on texture mismatch, `stencilClip` mismatch,
     `maxIndexedQuads` boundary, `clear`/`releaseMemory`, and zero GC allocation
     across warm push+clear loops.

7. **`yguilib/source/yguilib/render/internal/glyph_atlas.d`** [MODIFY]:
   - Add `alias BeforeResetCallback = void delegate();`
   - Add `void onBeforeReset(BeforeResetCallback cb)` (`cb` may be `null`).
   - Add private `void notifyBeforeReset()` calling
     `if (fTexture != 0 && fOnBeforeReset !is null) fOnBeforeReset();`.
   - Call `notifyBeforeReset()` at the very top of `makeRoom()` (before
     mutating `fSize`), `clear()`, and `destroy()`.
   - Add unittest verifying callback fires before texture deletion/growth
     with old `texture()` and `size()` still valid.

8. **`yguilib/source/yguilib/render/internal/text_cache.d`** [MODIFY]:
   - Add `void onBeforeAtlasReset(void delegate() cb)` forwarding to
     `fAtlas.onBeforeReset(cb);` (null allowed).

9. **`yguilib/meson.build`** [MODIFY]:
   - Add `'source/yguilib/render/internal/text_batch.d',` in `yguilib_src`.

## Verification

```bash
ninja -C _build && timeout 300 meson test -C _build
```
