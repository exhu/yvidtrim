# Phase 1: Refactor `yguilib.allochelpers` and Update Call Sites

Implement all code fixes for `H1`, `M1`-`M6`, and `L1`-`L10` in
`yguilib/source/yguilib/allochelpers.d` and update the 6 affected caller
modules in `yguilib`.

## Tasks

### 1. Refactor `yguilib/source/yguilib/allochelpers.d`

- **Module doc & imports (`L10`, `L1`, `M3`, `M6`)**:
  - Add module-level doc comment stating all three containers are
    single-threaded and require external synchronization (e.g., `MessageBus`)
    for cross-thread use.
  - Imports:
    ```d
    import core.bitop : bsr;
    import core.lifetime : move;
    import std.traits : CopyTypeQualifiers, hasElaborateDestructor,
      hasIndirections, isPointer;
    import std.typecons : Nullable;
    ```

- **`SmallBuffer(T, size_t stackCap)`**:
  - Add `static assert(!hasElaborateDestructor!T, ...)` (`M3`),
    `@disable this(this);` (`H1`), and `invariant`:
    ```d
    invariant {
      assert(usingHeap || count <= stackCap);
      assert(!usingHeap || count <= heapBuf.length);
    }
    ```
  - Replace `stackCount` with unified `size_t count = 0;` (`heapBuf.length`
    is heap capacity; `usingHeap` selects active storage) (`M5`, `L4`).
  - Add `@property size_t capacity() const nothrow @safe` returning
    `usingHeap ? heapBuf.length : stackCap` (`L6`).
  - Implement `push` using `count` and `ensureHeapCapacity(count + 1)` /
    `spillToHeap()` without `~=` or `assumeSafeAppend()`.
  - Delegate `contains` and `removeFirst` to `sliceContains` /
    `findItemIndex` (`L3`, `L9`); document `sameItem` (`is` vs `==`) (`L7`).
  - In `assignSlice(T[] src)`, assert
    `!slicesOverlap(src, stackBuf[]) && !slicesOverlap(src, heapBuf)`
    before `clear()` (`M2`). Support both stack and heap paths via
    `ensureHeapCapacity`.
  - In `fillWith(size_t newCount, T value)`, support stack and heap paths
    via `ensureHeapCapacity`.
  - In `removeAt(size_t index)`, call
    `shiftLeftAndClearTail(opSlice(), index); count--;` (`L3`).
  - In `clear()`, call `clearRange` on active slice, set
    `usingHeap = false`, `count = 0` (`L4`, `M5`).
  - Return `heapBuf[0 .. count]` or `stackBuf[0 .. count]` from `opSlice()`,
    and document that slices/refs are valid only until the next mutating
    call or move (`M1`). Keep `return` on `opSlice` and `opIndex`.
  - Private `ensureHeapCapacity(size_t minCap)` allocates via
    `reallocateSlice` only when `minCap > heapBuf.length`, growing by 2x
    from `stackCap * 2` (or `heapBuf.length * 2`).
  - Private `spillToHeap()` calls `ensureHeapCapacity(stackCap * 2)`,
    moves `stackBuf[0 .. count]` into `heapBuf`, clears `stackBuf` slots
    via `clearSlot`, and sets `usingHeap = true`.

- **`RingBuffer(T)`**:
  - Add `@disable this(this);` (`H1`) and `invariant` (`L2`):
    ```d
    invariant {
      assert(
        buffer.length == 0 || (buffer.length & (buffer.length - 1)) == 0
      );
      assert(count <= buffer.length);
      assert(buffer.length == 0 ? head == 0 : head < buffer.length);
    }
    ```
  - Rename `tryPop()` -> `tryPopFront()` (`M4`).
  - Update `clear()` to call `clearSlot(buffer[(head + i) & mask])` (`L5`).
  - Add `void releaseMemory()` calling `clear()` and `buffer = null` (`L5`).
  - Add `return` attribute to `opIndex` (`M1`, `L9`).
  - Replace both `opApply` overloads with `static struct Range(Elem)`
    (`empty`, `ref Elem front() return`, `popFront`) and a single
    `auto opSlice(this This)() nothrow @safe @nogc pure return` (`M6`, `L9`).
  - In `reallocate(size_t newCap)`, call `clearSlot` on moved-from slots in
    the old `buffer` (`L5`).

- **`ReusableArray(T)`**:
  - Add `static assert(!hasElaborateDestructor!T, ...)` (`M3`),
    `@disable this(this);` (`H1`), and
    `invariant { assert(count <= buf.length); }` (`L2`).
  - Store `T[] buf; size_t count = 0;` where `buf.length` is capacity (`M5`).
  - Expose `length`, `empty`, `capacity`, `reserve`, `push`, `popBack`,
    `tryPopBack` (renamed from `tryPop`, `M4`), `back` (with `return`),
    `clear`, `releaseMemory`, `contains` (via `sliceContains`), `addUnique`,
    `insertAt`, `removeAt` (via `shiftLeftAndClearTail`), `removeFirst`
    (via `findItemIndex`), `swapWith`, `opSlice` (with `return` and
    lifetime doc), `opIndex` (with `return`), `opDollar`.
  - Add private `ensureCapacityForPush()` using `reallocateSlice` with
    initial cap `4` and `2x` growth (with overflow assert).
  - Template `compact(Pred)(scope Pred keep)` constrained by
    `if (is(typeof(keep(buf[0])) == bool))` with null check when `Pred` is
    a delegate/function, plus doc note on exception safety (`M5`, `M6`, `L8`).

- **Module-private helpers (`L1`, `L3`, `M3`)**:
  - `sameItem`, `sliceContains`, `findItemIndex`, `shiftLeftAndClearTail`,
    `reallocateSlice`, `slicesOverlap`.
  - Update `clearSlot` and `clearRange` to check
    `static if (hasIndirections!T || hasElaborateDestructor!T)`.
  - Implement `nextPowerOfTwo` using `core.bitop.bsr` with overflow
    `assert` and release trap (`if (n > maxPow2) assert(0, ...);`) (`L1`).
  - Update existing `allochelpers.d` unit tests for `tryPopFront` and
    `tryPopBack`.

### 2. Update Call Sites in `yguilib`

1. `yguilib/source/yguilib/internal/uisystem_impl.d`:
   - Change `runPhase3Render(in ControllerDirtyList dirtyViews, ...)` to
     `runPhase3Render(ref const ControllerDirtyList dirtyViews, ...)` (`H1`).
2. `yguilib/source/yguilib/events/internal/message_bus.d`:
   - Change `queue.tryPop()` to `queue.tryPopFront()` (`M4`).
3. `yguilib/source/yguilib/internal/timer_service.d`:
   - Change `entries.compact((const ref e) => e.active)` to
     `entries.compact((const ref TimerEntry e) => e.active)` (`M5`).
4. `yguilib/source/yguilib/controls/hover_button_system.d`:
   - Change `activeButtons.compact((const ref item) => item !is w)` to
     `activeButtons.compact((const ref Widget item) => item !is w)` (`M5`).
5. `yguilib/source/yguilib/widget/internal/input_system.d`:
   - Change `hoveredWidgets.compact` and `hoverScratch.compact` lambdas to
     use `(const ref HoverEntry e) => e.widget !is w` (`M5`).
6. `yguilib/source/yguilib/widget/internal/virtlist_system.d`:
   - Change `vc.fFreePool.compact((const ref item) => item !is w)` to
     `vc.fFreePool.compact((const ref Widget item) => item !is w)` (`M5`).
   - Change `vc.fFreePool.tryPop()` to `vc.fFreePool.tryPopBack()` (`M4`).

## Verification

Run all build, test, and style checks (<= 80 chars/line, codestyle):
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
```
