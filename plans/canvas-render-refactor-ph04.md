# ph04: Dash, path and stroke scratch buffers

Review items 1.3, 1.4, 1.5, 1.7, 3.6, 4.8. Overview:
`plans/canvas-render-refactor.md`. Review:
`documentation/canvas-render-review.md`. Paths are relative to
`yguilib/source/yguilib/render/`.

## Steps

1. Fixed-capacity `LineDash` (1.7) in `canvas/types.d`:
   - `enum size_t maxSegments = 32;`, with `private float[maxSegments]
     fSegs; private ubyte fCount;`.
   - `static LineDash fromSegments(const float[] src)`: same validation
     as today (negative or non-finite gives solid). An odd count is
     doubled. If the normalized length exceeds `maxSegments`, the result
     is solid. Document this as a deviation from HTML, which has no
     limit.
   - `const(float)[] segments() const return`, plus `period()` and
     `isSolid()` as `@nogc`.
   - Update the Canvas `lineDash` setter and getter: no `.dup`, and
     return a slice or a copy of the struct. Update the existing
     LineDash tests (`d.segments == [...]` must still work through the
     getter).
2. Dash period reuse (4.8): `path_stroker.d` takes `in LineDash` instead
   of `const(float)[] dash` in `StrokeParams`, `isDashed`,
   `tooManyDashes` and `DashPattern`. Use `dash.isSolid()` and
   `dash.period()` instead of summing again.
3. Reusable dash output (1.3): replace `Contours applyDash(...)` with
   `void applyDashInto(ref const Contours c, in LineDash dash,
   float offset, ref Contours dst)`. `dst` is cleared first. The solid
   and too-many-dashes cases copy into `dst`. `strokeContours` takes a
   `ref Contours dashScratch`, or `StrokeParams` carries a pointer.
   Pick the cleaner option and document it. Canvas owns
   `Contours fDashContours`. Update the stroker unittests
   (`path_stroker.d` around lines 618-667).
4. `ColorPipeline.drawDashedThickLine` (1.4) in `internal/pipelines.d`:
   add a `Appender!(float[]) fDashScratch` field, `clear()` it per call,
   and remove the local Appender and the function-scope import.
5. `Path2d` (1.5) in `canvas/path2d.d`: `fVerbs` and `fPoints` become
   `Appender!(PathVerb[])` and `Appender!(PointF[])`. `clear()` calls
   `.clear()` on both. `addPath` calls `reserve(len + other.len)` and
   then appends, transforming each point. The `verbs()`/`points()`
   getters return `fVerbs[]`/`fPoints[]`. Keep all methods `@safe`.
6. `Canvas.stroke()` (3.6): transform `fLocalTris` in place and pass it
   to the draw/shadow code, or swap `fLocalTris` and `fVerts` with
   `std.algorithm.mutation.swap`. Do not copy the geometry a second
   time. Check that the shadow path still sees the right buffer.

## Tests

- Clearing and rebuilding a `Path2d` 100 times after a warm-up does not
  grow the GC heap.
- A warmed-up loop of `lineDash(...)` set and get plus a dashed
  `stroke()` (with an initialized renderer, `GlTestWindow`) does not
  grow the GC heap.
- `LineDash.fromSegments` with 17 odd values gives solid. With 16 values
  the 16 are kept. With 3 values the result is 6.
- The existing dash and stroke pixel tests stay green.

## Verification

`ninja -C _build && timeout 300 meson test -C _build` is green.
