- controller should not create its own view, the view is added by controller.addView()
- addView method may support multiple Views or error if already added view
- update sources to this logic (guidemo etc.)
- add named controller registry and wiring logic, so that View.addToController is used
instead of manually adding views to controllers for HoverButton
- check if it's ergonomically better
- the controller stack is still manipulated manually by the code (View components do not push/pop them),
however named controllers should be created in advance and live in the runtime registry.

- discarded for now:
	- composite controller? e.g. a modal dialog owns several controllers so that the stack can skip
	all events when a modal controller is active?
	- add to View component controller name, so user registers a map of controllers and then
	views and controllers are automatically pushed -- can be problematic if the widget should be
	visible but change behaviour? Modal component?

	if view requests controller push, and controller can hide view, then there's cycle.




- mouse capture component to capture mouse (and hide cursor) to implement
knobs
- build widget library
-- button with hover
-- combobox
- styles
- add image support

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
