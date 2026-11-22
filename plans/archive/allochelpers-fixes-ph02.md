# Phase 2: Expand Unit Tests and Full Verification

Add all missing unit tests identified in Section 4 of
`documentation/allochelpers-review.md` to
`yguilib/source/yguilib/allochelpers.d` and run the full verification suite.

## Tasks

### 1. Add Section 4 Unit Tests in `yguilib/source/yguilib/allochelpers.d`

1. **Copy prevention (`H1`)**:
   - `static assert(!__traits(compiles, ...))` for copying `SmallBuffer`,
     `RingBuffer`, and `ReusableArray`.
2. **Destructor semantics (`M3`)**:
   - Verify `static assert(!__traits(compiles, SmallBuffer!(WithDtor, 4)))`
     and `static assert(!__traits(compiles, ReusableArray!WithDtor))`.
   - Test `RingBuffer` with a counter-based destructor struct (no pointer
     indirections) verifying `tryPopFront()`, `clear()`, and
     `releaseMemory()` invoke destructors on active elements without
     double-destroying moved elements.
3. **`SmallBuffer` GC reference clearing**:
   - Verify `stackBuf[0 .. stackCap]` slots are `null` after
     `spillToHeap()`.
   - Verify `heapBuf` slots are cleared to `null` after `removeAt()` and
     `clear()` in heap mode.
4. **`SmallBuffer` edge cases**:
   - `SmallBuffer!(int, 1)`: stack push, spill on 2nd push, clear, reuse.
   - `fillWith(0, 42)` and `assignSlice([])`.
   - Heap-mode `removeAt` down to empty (`length == 0`, `isOnHeap == true`),
     then `push` stays in heap mode until `clear()`.
5. **Self-aliasing `assignSlice` (`M2`)**:
   - Using `core.exception : AssertError` and `std.exception : assertThrown`,
     verify `assertThrown!AssertError(sb.assignSlice(sb[]))` in both stack
     and heap modes when non-empty.
6. **`ReusableArray` reference `insertAt`, `swapWith` + `clear`, `@nogc`**:
   - Test `insertAt` (front, middle, back, and across growth) with class
     references, plus `removeAt` and `clear` slot clearing.
   - Test `swapWith` followed by `clear()` on both sides, confirming swapped
     capacities and empty lengths.
   - Test `compact` inside a `@safe nothrow @nogc` helper function.
7. **`RingBuffer` wrap-around writes, `releaseMemory()`, `@nogc` `foreach`**:
   - Wrap around a `RingBuffer!int`, mutate elements via `rb[i] = ...`, and
     verify FIFO order via `opIndex` and `foreach`.
   - Test `rb.releaseMemory()` resets `length == 0`, `capacity == 0`, and
     clears GC references.
   - Test `foreach (ref v; rb)` and `foreach (const ref v; crb)` inside a
     `@safe nothrow @nogc pure` helper function.
8. **`nextPowerOfTwo` edge cases (`L1`)**:
   - Verify `nextPowerOfTwo` for `0`, `1`, `2`, `3`, `4`, `5`, `15`, `16`,
     `17`, and `size_t(1) << (size_t.sizeof * 8 - 1)`.

## Verification

Run the complete build, test, and skill verification suite:
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
```
