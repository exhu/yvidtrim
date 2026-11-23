# ph03: TextCache and stroker GC churn (review 1.1, 2.5, 1.2)

Overview: `plans/canvas-render-refactor.md`. Review:
`documentation/canvas-render-review.md`. Paths are relative to
`yguilib/source/yguilib/render/`.

## Steps

1. TextCache LRU (1.1) in `internal/text_cache.d`:
   - Remove `std.container.dlist` and `orderRef`. `TextCacheEntry`
     becomes `{ TextTexture texture; ulong lastUse; }`.
   - Add `ulong fTick`. Each hit and each insert does `++fTick` and
     stores it in `lastUse`. A hit must not allocate. Look the key up
     with `key in cache` and do not rebuild strings.
2. Frame protection (2.5):
   - `void beginFrame()` records `fFrameStartTick = fTick + 1`.
     `Renderer.clearFrame` calls it only when no render target is
     active (`!inTarget()`), so a target pass inside a frame doesn't
     reset it.
   - Eviction runs when `cache.length >= maxEntries`. It collects the
     `(lastUse, key)` pairs with `lastUse < fFrameStartTick` into a
     reused member `Appender!(EvictCandidate[]) fEvictScratch`
     (`clear()` it first), and evicts the oldest
     `max(1, maxEntries / 4)` using `std.algorithm.sorting.topN` or
     `sort`.
   - If there are no candidates (every entry was used this frame), skip
     eviction and let the cache grow, up to `2 * maxEntries`. At the
     hard cap, evict the oldest entries anyway, even those used this
     frame.
   - Document this policy in the class doc comment.
3. Stroker (1.2) in `internal/path_stroker.d`: `tri()` builds
   `const float[6] v = [...]; tris.put(v[]);`. Search
   `path_stroker.d`, `path_flatten.d` and `canvas/package.d` for any
   other array literal passed to `put` or `~=`, and fix it the same way.
4. Compile `path_stroker.d` and `path_flatten.d` once with `-vgc`. For
   example, add `'-vgc'` to the yguilib `d_args` temporarily, or run
   `ninja -C _build -v` and rerun that one compile line by hand with
   `-vgc`. Fix the hidden allocations it reports. Allocations from
   `Appender` growth are allowed. Revert the temporary flag.
5. Remove the default parameter `outlinePx = 0` from the TextCache
   methods (`contains`, `getOrCreate`, `createTextTexture`) and pass it
   explicitly at every call site (5.1, partial).

## Tests

- After a warm-up, 1000 `getOrCreate` hits on the same key do not grow
  the GC heap. Use `GC.stats()`, and `GC.collect()` before measuring.
- With `maxEntries = 8`, call `beginFrame()`, insert 8 keys, insert a
  9th in the same frame: all 9 are present. Call `beginFrame()` again,
  touch 2 keys, and insert a new one: only untouched keys are evicted.
- The hard cap holds: inserting more than `2 * maxEntries` keys in one
  frame keeps the cache at or below the cap.
- The stroker produces the same output as before (existing tests). Add
  a GC test: a warmed-up round-join stroke into a cleared `Appender`
  does not grow the heap.

## Verification

`ninja -C _build && timeout 300 meson test -C _build` is green.
