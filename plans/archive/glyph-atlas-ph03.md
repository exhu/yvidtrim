# Glyph atlas ph03: TextRunCache + Renderer text

Overview: `plans/glyph-atlas.md`. Read `AGENTS.md` and `codestyle.md`
first. Depends on ph01 (`yguilib_sdl3_ttf_layout_text` binding) and
ph02 (`render/internal/glyph_atlas.d`).

## Goal

Replace the per-string textures in
`yguilib/source/yguilib/render/internal/text_cache.d` with cached
glyph runs over the shared `GlyphAtlas`. Switch `Renderer` text drawing
(`yguilib/source/yguilib/render/package.d`) to glyph quads. Canvas is
handled in ph04, but it must still compile and its tests must pass
after this phase (see "Canvas bridge" below).

## text_cache.d rewrite

Keep the module name. Keep the existing docstrings and update their
content.
- Keep `TextCacheKey` (font id, scaledSize, outlinePx, text), the tick
  LRU, `beginFrame` protection, the hard cap (`2 * maxEntries`),
  `removeFont`, `contains`, `length`, `countForFont` and `clear`.
- The entry value becomes:
  ```d
  struct RunGlyph { short dx, dy, dw, dh; uint glyph; GlyphSlot slot; }
  struct TextRun {
    int width, height;     // text area px (includes outline)
    RunGlyph[] glyphs;     // GC array owned by the entry
    ulong atlasGen;        // atlas generation the slots belong to
  }
  ```
- The class name becomes `TextRunCache` (update the references). The
  main lookup is
  `const(TextRun)* runFor(Font font, string text, int outlinePx)`.
  It returns null for a null or destroyed font, empty text, or a
  failure.
  - Miss: set the outline on the shared font (scope(exit) resets it to
    0, the same pattern as the old `createTextTexture`). Call
    `yguilib_sdl3_ttf_layout_text` into a reused
    `Appender!(yguilib_sdl3_ttf_GlyphQuad[])` scratch, calling twice if
    the count exceeds the capacity. Build the `RunGlyph[]` and resolve
    the slots.
  - Hit: stamp the tick. If `run.atlasGen != atlas.generation`,
    re-resolve the slots (set the outline around it again). A hit with
    a matching generation must not allocate.
  - Resolve: `atlas.slotFor` for each glyph. If the generation changes
    in the middle of the loop (the atlas was cleared or grew), restart
    the loop once. If it changes again, keep what resolved, mark the
    unresolved slots empty (w = 0) and log once with `std.logger`.
  - `dst` sizes: use the glyph quad dst w/h, which equal the slot w/h
    for unscaled glyphs. Use the src rect when it is a sub-area: the
    uv is `slot.x + src_x`, and so on. Store what the draw needs.
- `TextRunCache` owns a `GlyphAtlas` created in the constructor with
  sizes passed in. `Renderer.initialize` passes 512 and
  `min(4096, maxTextureSize())`. `removeFont` forwards to
  `atlas.removeFont`. `clear()` clears the runs and calls
  `atlas.destroy()`. Add `GLuint atlasTexture()` and
  `int atlasSize()`.
- Delete `TextTexture` and `createTextTexture` once nothing uses them.
  Keep the C/D `render_text_blended` binding: tests use it as an
  oracle.

## Renderer (`render/package.d`)

- `drawTextWithFont` (~line 857) and `drawTextTexture` (~line 1134):
  get the run, snap the origin to device pixels as today (`round` of
  `pixelsFromLogicFloat`), then for each glyph with w > 0 append two
  triangles (xyuv) at origin + (dx, dy) px. Convert to logic units with
  `logicFromPixelsFloat`. Use a reused `Appender!(float[])` member.
  Draw everything with one
  `texPipeline.drawTexturedTriangles(cache.atlasTexture(), verts,
  color, TextureMode.straight, logicViewport())`. uv = slot px / atlas
  size, with no v-flip (the atlas is top-down like the old text
  textures). Check `drawTexturedTriangles` for the vertex layout.
- Replace `textTextureFor` (~line 1023) with
  `const(TextRun)* textRunFor(Font f, string text, int outlinePx)` and
  `GLuint glyphAtlasTexture()` / `int glyphAtlasSize()`.
- `onFontDestroyed`, `clearTextCache` and the `beginFrame` call in
  `clearFrame` stay, retargeted.
- Update the existing Renderer test (~line 2142, "Destroyed fonts take
  their TextCache textures") to the new type.

## Canvas bridge (temporary)

`render/canvas/package.d` (~lines 1316-1392, `drawTextBitmap`,
`TextBitmap`, `buildTextVerts`) uses `textTextureFor` and
`TextTexture`. In this phase, do the smallest port that keeps
behaviour: build glyph quads from the run instead of one bitmap quad.
Alternatively, keep a private helper that returns the run plus the
atlas id, and let `buildTextVerts` loop over the glyphs. If the full
port is small, do it here and say so in the report. ph04 then only
adds tests and polish. All tests in `render/canvas/package_test.d`
must pass at the end of this phase.

## Tests

- Retarget all existing `text_cache.d` unittests (eviction, frame
  protection, hard cap, no allocation on a hit, outline sizes: an
  outline-3 run is 6 px larger than the fill run).
- Oracle pixel test: in an offscreen target, draw "Hello, Ag" with
  `drawTextWithFont` at an integer position. In a second target, draw
  the `render_text_blended` surface of the same font and string,
  uploaded with `uploadRgbaTexture` and drawn as one quad at the same
  position. Read both back. The max channel difference must be <= 2,
  or the smallest tolerance that passes; if it is larger, report the
  reason.
- 600 distinct strings in one frame: all draw, and there is still one
  atlas texture (review 2.5 scenario).
- `removeFont` drops the runs of that font and the atlas keys.
- Use the `gl_test_util.d` fixture and the AGENTS.md scope(exit)
  target cleanup.

## Verify

`ninja -C _build && timeout 300 meson test -C _build`, all green. Run
`SDL_LOGGING=app=trace ./_build/guidemo` briefly if possible and check
that labels render. Commit `glyph-atlas ph03: text runs over glyph
atlas`.
