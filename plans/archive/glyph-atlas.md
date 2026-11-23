# Glyph atlas for text

Source: TODO.md item 1, `documentation/canvas-render-review.md` 3.7
(and 2.5).

## Problem

`yguilib/source/yguilib/render/internal/text_cache.d` keeps one GL
texture per (font id, raster size, outline, string), rasterized with
`TTF_RenderText_Blended`. Each distinct label costs its own texture,
upload and bind, and the LRU entry count limits a frame.

## Goal

Glyphs are rasterized once per (font, size, outline, glyph index) into
one shared RGBA8 atlas texture. Each label is drawn as glyph quads from
that texture in one draw call.

## Decisions

- One draw per label. No cross-label batching (TODO.md follow-up).
- A single atlas page that grows: 512x512 doubling up to
  min(4096, GL_MAX_TEXTURE_SIZE). When it is full at max size it is
  cleared and repacked lazily. A `generation` counter invalidates the
  cached slots.
- Shaping uses a custom no-op `TTF_TextEngine` in the C wrapper, so
  glyph positions match `TTF_RenderText_Blended` and `measureText`
  (HarfBuzz and kerning included).

## Data flow

```
  Font + text + outlinePx
        |
        v
  TextRunCache (LRU by tick, key = font id, size, outline, text)
        |  miss: yguilib_sdl3_ttf_layout_text -> GlyphQuad[]
        v
  TextRun { w, h, glyphs[dst rect, glyph index, slot], atlasGen }
        |  gen mismatch / miss: GlyphAtlas.slotFor
        v
  GlyphAtlas (one RGBA8 texture, ShelfPacker, generation)
        |  miss: yguilib_sdl3_ttf_render_glyph -> glTexSubImage2D
        v
  Renderer.drawTextWithFont / Canvas.drawTextBitmap
        -> one drawTexturedTriangles(atlas texture, glyph quads)
```

## Phases

```
  phase  file                    content
  -----  ----------------------  ------------------------------------
  ph01   glyph-atlas-ph01.md     C wrapper: layout + glyph image
  ph02   glyph-atlas-ph02.md     GlyphAtlas (packer, grow, reset)
  ph03   glyph-atlas-ph03.md     TextRunCache + Renderer text
  ph04   glyph-atlas-ph04.md     Canvas fillText / strokeText
  ph05   glyph-atlas-ph05.md     docs, TODO.md, cleanup
```

Each phase ends with a green
`ninja -C _build && timeout 300 meson test -C _build` and a commit
`glyph-atlas phNN: <summary>`.

Baseline: local tag `before-font-atlas` marks the pre-implementation commit.
