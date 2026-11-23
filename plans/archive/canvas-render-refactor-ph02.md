# ph02: Lifetime and font correctness (review 2.1, 2.2, 2.4, 4.9)

Overview: `plans/canvas-render-refactor.md`. Review:
`documentation/canvas-render-review.md`. Paths are relative to
`yguilib/source/yguilib/render/`.

## Steps

1. Finalizers (2.1). Remove `~this()` from `Renderer` (`package.d`),
   `Font` (`font.d`), `FontManager` (`font_manager.d`) and `TextCache`
   (`internal/text_cache.d`). Follow the rule documented in
   `texture.d:16-20`: GPU and native objects are freed only by an
   explicit `destroy()` on the main thread. An optional `debug`-only
   destructor may log or assert a leak, but it must not touch GL, TTF,
   associative arrays or other GC objects. Make sure that
   `Window.destroy()` -> `Renderer.destroy()` still frees fonts, the
   text cache and pipelines, and add whatever is missing.
2. Stale fonts (2.2) in `font_manager.d`:
   - When `getFont(name, ...)` cannot resolve `name` and falls back to
     the default face, cache the font under the resolved face key
     (`""`), not under the requested name. Apply the same rule to
     `scaledCache`.
   - `registerFont*` / `registerFontFromMemory`: before storing the new
     source, `destroy()` and remove every `cache`/`scaledCache` entry
     whose face name equals the registered name. Also remove fallback
     entries for that name, if any exist.
3. Dead textures (2.4): add `TextCache.removeFont(ulong fontId)`, which
   destroys and removes every entry with that font id. FontManager
   needs a way to report destroyed fonts. Prefer a
   `void delegate(ulong fontId) nothrow fOnFontDestroyed` set by
   `Renderer` after it creates both objects, which keeps FontManager
   independent of TextCache. Call it for each font destroyed by the
   `scaledCache` flush, by step 2, and by `destroy()` (only if the
   cache is still alive; document the order in `Renderer.destroy`).
4. Reuse (4.9): extract `resolveSource(face)` (face name -> registered
   source, or the default face) and `openFont(source, size, scale)`
   (dispatches to `fromMemory`/`fromFile`, sanitizes the size). Use
   both in `getFont` and `getFontAtScale`. Do not rename public methods
   yet; ph09 does that.

## Tests (in `font_manager.d` / `package.d`, using `gl_test_util`)

- Look up `"Foo"` before it is registered, register `"Foo"`, and look it
  up again: the result must be a different font id that uses the new
  data. Use a bundled test font from `assets/` if two distinct faces
  exist. Otherwise compare ids and source identity.
- Re-registering a name with new data replaces the cached font.
- Fill `scaledCache` to the flush threshold. After the flush, the
  TextCache holds no entries for the flushed font ids. Add a
  package-level `TextCache.countForFont(id)` under `version (unittest)`.

## Verification

`ninja -C _build && timeout 300 meson test -C _build` is green. Run
`./_build/guidemo` briefly and quit. It must not crash on exit.
