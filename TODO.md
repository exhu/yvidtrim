- implement hover button that animates background on mouse enter/leave to test View component concept

- widget builders, see documentation/yguilib_api_improvements.md

  ### 9. render/internal/text_cache.d — cache eviction is all-or-nothing

  text_cache.d L59-L61

    if (cache.length >= maxCacheEntries) {
      clear();
    }

  When the cache hits 512 entries, it destroys all GL textures and
  starts from scratch. This causes a frame stutter ("texture storm")
  as all visible text is re-rasterized simultaneously. An LRU eviction
  or partial flush would be significantly smoother.

  │ Tip
  │ Consider tracking an access-order list and evicting the oldest
  │ 25% when the cap is reached.

  ### 10. text_cache.d — cache key uses raw void* pointer

  text_cache.d L28-L32

    private struct TextCacheKey {
      void* fontHandle;
      float ptSize;
      string text;
    }

  Using a raw void* as part of an AA key is fragile — if the font is
  destroyed and its handle reused by SDL_ttf, stale cache entries
  become invalid. The clear() call on scaling changes mitigates this,
  but it's a subtle invariant.

- assets management (transparent mapping to embedded import string and file stream data)
- extended font management (proper name, styles)
- define modal controller rules (some controllers must still handle events, when modal is active)
- add modal dialog displayed by model on key (and closed by click)
- button
- focus
- modal dialog
- text input
