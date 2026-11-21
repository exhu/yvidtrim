# Phase 1: Implement `yguilib.allochelpers` and Wire Build

## Objective

Create the new public module `yguilib/source/yguilib/allochelpers.d`
containing `SmallBuffer`, `RingBuffer`, and `ReusableArray`, register it in
`yguilib/meson.build`, and verify with unit tests and all code-quality checks.

## Reference Files

- Style & conventions: `codestyle.md`, `yguilib/source/yguilib/serhelpers.d`
- Build config: `yguilib/meson.build`

## Detailed Steps

### 1. Create `yguilib/source/yguilib/allochelpers.d`

Declare `module yguilib.allochelpers;` with minimal top-level imports
(`core.lifetime : move`, `std.traits : hasIndirections, isPointer`,
`std.typecons : Nullable`). Keep all lines <= 80 chars, 2-space indent,
opening `{` on same line, no default parameter values, no overloaded regular
methods (standard `op*` operators are exempt), and section visibility labels
(`public` first, then `private:`).

Implement these three public structs and private helpers:

#### A. `struct SmallBuffer(T, size_t stackCap)`
- `static assert(stackCap > 0, "SmallBuffer stackCap must be > 0");`
- Fields (under `private:`):
  - `T[stackCap] stackBuf;`
  - `size_t stackCount = 0;`
  - `T[] heapBuf;`
  - `bool usingHeap = false;`
  - Never store an internal pointer to `stackBuf` so NRVO/value moves stay
    safe.
- Public methods:
  - `@property size_t length() const nothrow @safe`
  - `@property bool empty() const nothrow @safe`
  - `@property bool isOnHeap() const nothrow @safe`
  - `void push(T item)`:
    - If `usingHeap`: `heapBuf ~= move(item);`
    - Else if `stackCount < stackCap`: `stackBuf[stackCount++] = move(item);`
    - Else: call `spillToHeap()`, then `heapBuf ~= move(item);`.
  - `bool contains(in T item) const`: linear scan over active slice using
    `sameItem`.
  - `bool addUnique(T item)`: if `contains(item)` return `false`; else
    `push(move(item))` and return `true`.
  - `void assignSlice(T[] src)`:
    - Calls `clear()`.
    - If `src.length <= stackCap`: copies `src` into
      `stackBuf[0 .. src.length]`, sets `stackCount = src.length`.
    - Else: sets `usingHeap = true`, `heapBuf.length = 0`,
      `heapBuf.assumeSafeAppend()`, `heapBuf ~= src`.
  - `void fillWith(size_t count, T value)`:
    - Calls `clear()`.
    - If `count <= stackCap`: sets `stackBuf[0 .. count] = value;`,
      `stackCount = count;`.
    - Else: sets `usingHeap = true`, `heapBuf.length = count;`,
      `heapBuf.assumeSafeAppend();`, `heapBuf[0 .. count] = value;`.
  - `void removeAt(size_t index)`:
    - Asserts `index < length`.
    - Shifts elements left in active storage, clears vacated tail slot with
      `clearSlot`, decrements length (`heapBuf.length -= 1;
      heapBuf.assumeSafeAppend();` when `usingHeap`, else `stackCount--`).
  - `bool removeFirst(in T item)`:
    - Finds first element where `sameItem(elem, item)`, calls `removeAt(i)`,
      returns `true`; returns `false` if absent.
  - `void clear()`:
    - Calls `clearRange` on active elements when `hasIndirections!T`.
    - If `usingHeap`: `heapBuf.length = 0; heapBuf.assumeSafeAppend();
      usingHeap = false;` (retains heap buffer capacity for future spills).
    - `stackCount = 0;`.
  - `inout(T)[] opSlice() inout return`:
    - Returns `usingHeap ? heapBuf : stackBuf[0 .. stackCount]`.
  - `ref inout(T) opIndex(size_t idx) inout return`:
    - Asserts `idx < length`, returns active element by `ref`.
  - `size_t opDollar() const nothrow @safe`: returns `length`.
- Private helper `spillToHeap()`:
  - `heapBuf.length = 0; heapBuf.assumeSafeAppend();`
  - `heapBuf.reserve(stackCap * 2);`
  - Moves `stackBuf[0 .. stackCount]` into `heapBuf` (clearing `stackBuf`
    indirections via `clearSlot`), sets `stackCount = 0; usingHeap = true;`.

#### B. `struct RingBuffer(T)`
- Fields (under `private:`):
  - `enum size_t defaultInitialCapacity = 16;`
  - `T[] buffer;`
  - `size_t head = 0;`
  - `size_t count = 0;`
- Public methods:
  - `@property size_t length() const nothrow @safe`
  - `@property bool empty() const nothrow @safe`
  - `@property size_t capacity() const nothrow @safe`
  - `void reserve(size_t minCapacity)`:
    - If `minCapacity == 0`: return.
    - Compute `const size_t target = nextPowerOfTwo(minCapacity);`
    - If `target <= buffer.length`: return.
    - Call `reallocate(target)`.
  - `void push(T item)`:
    - If `buffer.length == 0`: `reallocate(defaultInitialCapacity);`
    - Else if `count == buffer.length`: `reallocate(buffer.length * 2);`
    - `const size_t tailIdx = (head + count) & (buffer.length - 1);`
    - `buffer[tailIdx] = move(item);`
    - `count++;`
  - `Nullable!T tryPop()`:
    - If `count == 0`: return `Nullable!T.init`.
    - `T item = move(buffer[head]);`
    - `head = (head + 1) & (buffer.length - 1);`
    - `count--;`
    - Return `Nullable!T(move(item))`.
  - `void clear()`:
    - If `count > 0 && hasIndirections!T`: clear live slots `(head + i) & mask`
      to `T.init`.
    - `head = 0; count = 0;` (retains `buffer` capacity).
  - `ref inout(T) opIndex(size_t idx) inout`:
    - Asserts `idx < count`.
    - Returns `buffer[(head + idx) & (buffer.length - 1)]`.
  - `size_t opDollar() const nothrow @safe`: returns `count`.
  - `int opApply(scope int delegate(ref T) dg)` and
    `int opApply(scope int delegate(const ref T) dg) const`:
    - Iterates `0 .. count` in FIFO order via `(head + i) & mask`.
- Private helper `reallocate(size_t newCap)`:
  - Allocates `auto newBuf = new T[newCap];`.
  - Unwraps `0 .. count` via `move(buffer[(head + i) & mask])` when
    `count > 0`.
  - Sets `buffer = newBuf; head = 0;`.

#### C. `struct ReusableArray(T)`
- Fields (under `private:`):
  - `T[] buf;`
- Public methods:
  - `@property size_t length() const nothrow @safe`
  - `@property bool empty() const nothrow @safe`
  - `void reserve(size_t count)` -> `buf.reserve(count);`
  - `void push(T item)` -> `buf ~= move(item);`
  - `void popBack()`:
    - Asserts `buf.length > 0`.
    - `clearSlot(buf[$ - 1]);`
    - `buf.length -= 1; buf.assumeSafeAppend();`
  - `Nullable!T tryPop()`:
    - If `buf.length == 0`: return `Nullable!T.init`.
    - `T item = move(buf[$ - 1]);`
    - `buf.length -= 1; buf.assumeSafeAppend();`
    - Return `Nullable!T(move(item))`.
  - `ref inout(T) back() inout`:
    - Asserts `buf.length > 0`; returns `buf[$ - 1]`.
  - `void clear()`:
    - `clearRange(buf);`
    - `buf.length = 0; buf.assumeSafeAppend();`
  - `void releaseMemory()` -> `buf = null;`
  - `bool contains(in T item) const`
  - `bool addUnique(T item)`
  - `void insertAt(size_t index, T item)`:
    - Asserts `index <= buf.length`.
    - Appends `move(item)`, shifts right from `buf.length - 1` down to
      `index + 1` using `move` (or swaps/assignments).
  - `void removeAt(size_t index)`:
    - Asserts `index < buf.length`.
    - Shifts elements left from `index` to `buf.length - 2` using `move`.
    - `clearSlot(buf[$ - 1]);`
    - `buf.length -= 1; buf.assumeSafeAppend();`
  - `bool removeFirst(in T item)`
  - `void compact(scope bool delegate(const ref T) keep)`:
    - Asserts `keep !is null`.
    - Stable in-place compaction preserving order (`writeIdx`).
    - Clears vacated tail `buf[writeIdx .. $]` via `clearRange`.
    - `buf.length = writeIdx; buf.assumeSafeAppend();`
  - `void swapWith(ref ReusableArray!T other)`:
    - Swaps `buf` and `other.buf` in O(1).
  - `inout(T)[] opSlice() inout`: returns `buf`.
  - `ref inout(T) opIndex(size_t idx) inout`:
    - Asserts `idx < buf.length`; returns `buf[idx]`.
  - `size_t opDollar() const nothrow @safe`: returns `buf.length`.

#### D. Private Module Helpers
- `sameItem(T)(const ref T a, const ref T b)`:
  - `static if (is(T == class) || is(T == interface) || isPointer!T)` ->
    `return a is b;`
  - `else` -> `return a == b;`
- `clearSlot(T)(ref T slot)`:
  - `static if (hasIndirections!T) { slot = T.init; }`
- `clearRange(T)(T[] slice)`:
  - `static if (hasIndirections!T) { slice[] = T.init; }`
- `size_t nextPowerOfTwo(size_t n)`:
  - Rounds `n` up to the smallest power of two >= `n` (minimum 1).

#### E. Unit Tests in `allochelpers.d`
Add focused `unittest` blocks verifying:
1. `SmallBuffer` stack-only mode, exact `stackCap`, spill to heap (`isOnHeap`),
   `clear()` returning to stack and reusing heap capacity on re-spill,
   `assignSlice` (stack and heap paths), `fillWith`, `removeAt`,
   `removeFirst`, value return (NRVO).
2. `SmallBuffer` & `ReusableArray` `contains` / `addUnique` / `removeFirst`
   with `interface`, `class` (including overridden `opEquals` proving `is`
   is used), pointer, and value types (`ulong`, `string`, `struct`).
3. `RingBuffer` lazy init, `reserve` (non-power-of-two rounding & order
   preservation), wrap-around at constant capacity, `push`/`tryPop` FIFO
   ordering across `grow()`, `opIndex`, mutable and `const` `opApply`,
   `clear()` preserving capacity, and move semantics (non-copyable struct
   `@disable this(this)` if supported, or move counter).
4. `ReusableArray` `push`/`popBack`/`tryPop`/`back`, `clear()` preserving
   buffer pointer (`ptr` stability), `releaseMemory()`, `insertAt`
   (front/middle/end), `removeAt`, `removeFirst`, `compact` (all/none/mixed),
   `swapWith`, and GC reference clearing on shrink.

### 2. Register in `yguilib/meson.build`

Add `'source/yguilib/allochelpers.d',` in alphabetical order at the top of
`yguilib_src` (before `'source/yguilib/app.d',`).

## Verification

Run:
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
```
All commands must pass with 0 errors and 0 warnings on added lines.
