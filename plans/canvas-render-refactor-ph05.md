# ph05: Canvas state layout (review 1.6, 1.8, 1.9)

Overview: `plans/canvas-render-refactor.md`. Review:
`documentation/canvas-render-review.md`. Paths are relative to
`yguilib/source/yguilib/render/`.

## Steps

1. Clip storage (1.6) in `canvas/package.d`:
   - `State.clips` (`ClipEntry[]`) becomes `size_t clipCount`.
   - Canvas owns `Appender!(ClipEntry[]) fClips` and
     `Appender!(float[]) fClipTris`. `ClipEntry` becomes
     `{ size_t triStart; size_t triCount; FillRule rule; }`. It holds
     fan triangles already flattened and transformed to logic
     coordinates, ready for the stencil pass `applyClip` does today.
   - `clip(path)` flattens `path` with `st.xf` into `fContours` and
     builds the fan into `fClipTris`, the same way the current
     `applyClip` does. It records the entry, bumps `st.clipCount` and
     applies it. There is no `new Path2d` and no `addPath`.
   - Saved states are always a prefix of the current clip list. The
     clip list is append-only between `save` and `restore`. Write that
     invariant down in a comment.
   - `save()` copies `st` and needs no `.dup`. `restore()`: if the
     restored `clipCount` is smaller than `fClips[].length`, shrink
     `fClips` and `fClipTris` (to the first dropped entry's
     `triStart`) and call `rebuildClip()`. `rebuildClip()` replays the
     stored triangles without flattening again.
   - `resetFrame()` clears both buffers.
   - If the flatten tolerance depends on scaling, note in a comment that
     clips keep the tolerance from when they were created. That is
     acceptable.
2. FrameState pool (1.8):
   - `FrameState` holds the saved `st` plus the Appenders `stack`,
     `clips` and `clipTris`. `saveFrameState(ref FrameState slot)`
     swaps the Canvas `fStack`/`fClips`/`fClipTris` with the slot's
     (cleared) buffers (`std.algorithm.mutation.swap`).
     `restoreFrameState(ref FrameState slot)` swaps them back. Nothing
     is copied.
   - `Renderer` (`package.d`, around lines 803-841) keeps
     `Appender!(FrameState[])`, or a plain array indexed by target
     depth, grown on demand. Do the same for the per-target
     `ClipStack`: keep a per-depth slot whose Appender is cleared, not
     replaced by `ClipStack.init`.
   - Appender copies share storage. Make sure no two slots, and no slot
     and the Canvas, alias the same Appender after a swap. Add an
     assert in debug builds.
3. FillStyle (1.9) in `canvas/types.d`:
   - Keep `Kind kind` and `Pattern pattern` outside the union. Pattern
     holds a `Rebindable` pointer, and keeping it out lets the struct
     stay `@safe`.
   - Put `union { ColorF fColor; LinearGradient fLinear;
     RadialGradient fRadial; }` behind accessors. The `color()`,
     `linear()` and `radial()` getters assert `kind` and are `@trusted`
     only where needed. The factory functions set the right member.
     The default value is the solid color black, so `FillStyle.init`
     keeps today's meaning.
   - Update every reader of `.color`, `.linear` and `.radial` (Canvas,
     pipelines, tests).
   - Add `static assert(State.sizeof < <old size> * 6 / 10)`. Print the
     old size once with `pragma(msg)` and remove the pragma afterwards.

## Tests

- Nested `save/clip/clip/restore/restore` inside `beginTarget`, and
  across a target boundary, gives the same pixels as before (the
  existing clip tests plus one new test).
- After a warm-up, a loop of `save(); clip(rect); fill; restore();`
  does not grow the GC heap.
- 50 repeated `beginTarget`/`endTarget` passes do not grow the GC heap
  after warm-up.

## Verification

`ninja -C _build && timeout 300 meson test -C _build` is green. Run
`./_build/guidemo` and look at the canvas demo (clips, patterns).
