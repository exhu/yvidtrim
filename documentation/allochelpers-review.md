# Review: `yguilib/source/yguilib/allochelpers.d`

Reviewed file: `yguilib/source/yguilib/allochelpers.d` (963 lines, of which
~500 are implementation and ~460 are unit tests).

Scope: correctness, memory/GC safety, API design, performance, code style
(`codestyle.md`) and test coverage of `SmallBuffer`, `RingBuffer` and
`ReusableArray`, plus their call sites in `yguilib`.

## 1. Summary

The module is compact, well documented and generally careful: moved-from
slots are cleared so the GC does not retain stale references, `RingBuffer`
moves elements without postblits (verified by tests), the power-of-two
masking is correct, and allocation is lazy.

The main weakness is that all three containers are **implicitly copyable
structs that own a GC slice**, while `SmallBuffer` and `ReusableArray`
also call `assumeSafeAppend()`. A copy plus a later `clear()`/`push()`
silently overwrites the other copy's data. No current call site does this
(all pass containers by `ref` or keep them as class fields), but nothing
prevents it. Most other findings concern edge cases, destructor
semantics, naming, and hot-path performance.

| Severity | Count | Items                          |
|----------|-------|--------------------------------|
| High     | 1     | H1                             |
| Medium   | 6     | M1 - M6                        |
| Low      | 10    | L1 - L10                       |

## 2. Usage Context

```
SmallBuffer  <- uisystem_impl.d   (Controller, 16)  snapshot + dirty list
             <- timer_service.d   (TimerId, 32)     due timer ids
             <- virtlist_system.d (bool, 32), (VirtListActiveItem, 16)
RingBuffer   <- message_bus.d     AppEvent queue (guarded by synchronized)
ReusableArray<- timer_service.d, controller_stack.d, input_system.d,
                system_pipeline.d, virtlist_system.d,
                virtlist_components.d, hover_button_system.d
```

All call sites pass containers by `ref` or hold them as fields of classes,
so the aliasing hazards below are latent, not active bugs.

Note: `AppEvent` has a destructor (`events/package.d`) and its own comment
already warns that copies may run `releaseData` more than once. That makes
destructor handling in these containers relevant (see M3).

## 3. Findings

### H1. Implicit struct copies alias storage -> silent data corruption

All three containers lack `@disable this(this)`. Copying one copies only
the slice header, so both copies share the GC block. `SmallBuffer` and
`ReusableArray` then call `assumeSafeAppend()` in `clear()`, `popBack()`,
`removeAt()`, `compact()`, which tells the runtime that the block is
exclusively theirs. The next `push()` writes over the other copy's data.

Verified with a scratch program (ldc2):

```d
ReusableArray!int a;
a.push(1); a.push(2); a.push(3);
auto b = a;          // compiles, shares buffer
a.clear();
a.push(99);
// b[] == [99, 2, 3]   <- b was silently modified

SmallBuffer!(int, 2) s;   // spilled to heap
foreach (i; 0 .. 4) s.push(i);
auto t = s;
s.clear();
foreach (i; 10 .. 14) s.push(i);
// t[] == [10, 11, 12, 13]
```

For `RingBuffer!AppEvent`, a copy would also duplicate `AppEvent` values
that own `releaseData`, so a double release would follow.

Recommendation:

- Add `@disable this(this);` to all three structs. Returning a local
  (NRVO) and `move()` still work, so the existing `makeSmallBuf()` test
  keeps compiling.
- If an explicit copy is ever needed, add a named method such as
  `dupFrom(ref const ...)` (no overloads, per `codestyle.md`).
- Add a `static assert(!__traits(compiles, { auto b = a; }))` test so the
  property cannot regress.

### M1. Slices from `opSlice()` are unchecked views

`opSlice()` returns the internal slice. Any later mutation invalidates it:

- After `clear()` + `push()`, an earlier slice of a `ReusableArray` sees
  new data (verified: `view` changed from `[5, 6]` to `[7, 6]`).
- For `SmallBuffer` in stack mode, the slice points into `stackBuf`. It
  dangles once the buffer is moved or goes out of scope. The struct doc
  ("Never stores an internal pointer to `stackBuf`") is correct about the
  struct itself, but readers may assume returned slices are safe too.
- Removing or inserting while iterating over `opSlice()` skips or repeats
  elements.

Recommendation: document on each `opSlice()` that the slice is valid only
until the next mutating call or move of the container. Consider enabling
`-preview=dip1000` for `yguilib` and marking `opSlice`/`opIndex`/`back`
consistently with `return scope`. Today only `SmallBuffer` uses `return`.

### M2. `SmallBuffer.assignSlice` breaks on self-aliasing input

`assignSlice(src)` calls `clear()` before copying from `src`:

- Heap path with reference types: `clear()` sets the source slots to
  `T.init` first, so `sb.assignSlice(sb[])` leaves only `null` values
  (verified).
- Stack path: `stackBuf[0 .. n] = src[]` copies between overlapping
  arrays, which fails the runtime overlap check. Verified: the process
  dies with `SIGILL`, so even `catch (Throwable)` cannot recover.

No current caller does this (`snapshotControllers` copies from the
controller stack). Recommendation: add an `assert` that `src` does not
overlap the active storage, or return early when
`src.ptr is opSlice().ptr && src.length == length`. Document the
precondition.

### M3. Destructor semantics are not handled consistently

`clearSlot`/`clearRange` only act when `hasIndirections!T`. For element
types with a destructor but no indirections (for example a handle struct
holding an `int` with `~this`):

- `clear()`, `popBack()`, `removeAt()`, `compact()` do not destroy
  removed elements. They are destroyed later, when a slot is overwritten
  or when `stackBuf` goes out of scope, or never for GC slack.

For `SmallBuffer`/`ReusableArray`, growth goes through `~=`. When the
runtime reallocates, it copies elements into a new block and leaves the
old values in the old block. GC finalization of that block then runs
destructors on stale copies. For types like `AppEvent` (whose destructor
calls `releaseData`), this is a double release. Also, `~=` rejects
`@disable this(this)` types, so non-copyable elements work in
`RingBuffer` but not in the other two containers.

`RingBuffer` is fine here: it grows via `new T[]` + `move()`, and `move`
resets sources to `T.init` for types with destructors.

Recommendation (pick one):

- Recommended: add `static assert(!hasElaborateDestructor!T, ...)` to
  `SmallBuffer` and `ReusableArray` and document that RAII types belong
  in `RingBuffer` or a dedicated container.
- Or: change the clearing condition to
  `hasIndirections!T || hasElaborateDestructor!T` and replace `~=` growth
  with explicit move-based reallocation (see M5).

### M4. `tryPop` means FIFO in one type and LIFO in another

`RingBuffer.tryPop()` removes the **front**. `ReusableArray.tryPop()`
removes the **back**. The same name with opposite semantics invites
mistakes when moving code between containers. Recommendation: rename to
`tryPopFront()` and `tryPopBack()` (the `rename-symbol` skill can help).

### M5. Hot-path overhead from `~=` and `assumeSafeAppend()`

Each `push()` on `ReusableArray`/`SmallBuffer` (heap mode) calls the
runtime append hook, and each shrinking call (`popBack`, `tryPop`,
`removeAt`, `clear`, `compact`) calls `assumeSafeAppend()`. Both look up
GC block metadata (cache lookup, possibly a GC lock). These are
per-element costs on per-frame paths (hover lists, timers, layout scratch
buffers), and they make the containers impossible to use from `@nogc`
code.

Recommendation: store `T[] storage` plus `size_t len` and treat
`storage.length` as capacity:

```
push:     if (len == storage.length) grow();  storage[len++] = move(x);
popBack:  clearSlot(storage[--len]);
clear:    clearRange(storage[0 .. len]); len = 0;
grow:     auto n = new T[max(4, 2 * storage.length)];
          move elements; clearRange(old); storage = n;
opSlice:  storage[0 .. len]
```

This removes every `assumeSafeAppend()` call, so H1 can no longer stomp
memory (H1 still causes aliasing, but `@disable this(this)` fixes that).
Push and pop become a branch plus a store, and this is the same scheme
`RingBuffer` already uses. `SmallBuffer`'s heap part could reuse it, or
simply embed a `ReusableArray!T`.

Related: `compact()` takes a `scope bool delegate(const ref T)`. A
template alias parameter (`void compact(alias keep)()`) would let the
predicate inline on these hot paths and propagate attributes.

### M6. Non-templated delegates block `@safe`/`nothrow`/`@nogc` callers

`RingBuffer.opApply(int delegate(ref T))` and `ReusableArray.compact`
use plain delegate types. A `foreach` over a `RingBuffer` inside a
`nothrow` or `@safe` function will not compile. Recommendation: make
`opApply` a template over the delegate type
(`int opApply(Dg)(scope Dg dg)`), or add attribute-specific overloads.
Templating also merges the mutable and `const` `opApply` overloads into
one, which fits better with the "no overloads" rule in `codestyle.md`.

### L1. `nextPowerOfTwo` can loop forever in release builds

The overflow guard is an `assert`. With `-release`, `cap <<= 1`
overflows to `0` and `while (cap < n)` never ends. This is unrealistic
in practice but easy to fix: compute with `core.bitop.bsr` and use an
explicit check that survives `-release` (or saturate).

### L2. No `invariant` blocks

`codestyle.md` section 3 prefers invariants over scattered checks. These
would document and enforce the internal state machine:

```d
// SmallBuffer
invariant {
  assert(stackCount <= stackCap);
  assert(!usingHeap || stackCount == 0);
  assert(usingHeap || heapBuf.length == 0);
}
// RingBuffer
invariant {
  assert(buffer.length == 0 || (buffer.length & (buffer.length - 1)) == 0);
  assert(count <= buffer.length);
  assert(buffer.length == 0 || head < buffer.length);
}
```

### L3. Duplicated logic between `SmallBuffer` and `ReusableArray`

`contains`, `addUnique`, `removeFirst` and the shift loop in `removeAt`
are implemented twice. A private `mixin template SliceOps()` (built on
`opSlice()`/`removeAt()`), or module-private free functions over `T[]`,
would remove the duplication. That reduces the risk of one copy getting
fixed while the other is not.

### L4. Redundant work in `SmallBuffer`

- `assignSlice` (heap branch) and `spillToHeap()` both run
  `heapBuf.length = 0; heapBuf.assumeSafeAppend();`, but whenever
  `!usingHeap` the code already guarantees `heapBuf.length == 0`.
- `spillToHeap()` calls `heapBuf.reserve(stackCap * 2)` on every spill,
  even when capacity was retained from an earlier spill. This is cheap
  but still a runtime call.

### L5. `RingBuffer` internals

- `clear()` duplicates `clearSlot` logic inline instead of reusing the
  helper.
- `reallocate()` does not clear class/pointer slots in the old buffer
  after moving (`move` does not reset types without destructors). The
  old block is unreachable, so this only matters if a conservative false
  pointer pins it. Harmless, but `clearRange(buffer)` before replacing it
  would be consistent with the rest of the module.
- There is no way to give memory back. The message-bus queue keeps its
  peak capacity forever. A `releaseMemory()` (matching `ReusableArray`)
  or a `shrinkTo()` would be cheap to add if bursty events are expected.

### L6. API asymmetries

- `SmallBuffer` has no `popBack`, `back`, `reserve` or `insertAt`.
  `ReusableArray` has no `capacity`, while `RingBuffer` does.
- `return` attributes appear only on `SmallBuffer` accessors.
- `fillWith` heap path uses `heapBuf.length = count`, which needs `T` to
  be default-constructible (`@disable this()` types fail to compile).
- No `opApply`/index-aware `foreach (i, ref v; rb)` for `RingBuffer`.

None of these block current users. List them only so additions follow a
consistent naming scheme.

### L7. `sameItem` equality is only shallow-identity

Classes, interfaces and pointers use `is`. Everything else uses `==`,
which for a struct such as `HoverEntry { Widget widget; RectF absRect; }`
recursively calls `Widget.opEquals`. If `Widget` ever overrides it,
`contains`/`removeFirst` on such structs would switch to value equality.
Also, `float.nan` elements are never found. Recommendation: document
this in the `contains` comment, or allow callers to supply a comparison
predicate.

### L8. `compact` is not exception-safe

If `keep` throws mid-loop, already-moved elements remain duplicated in
the array (class references appear twice), and the tail is not cleared.
Either require a `nothrow` predicate (natural once M5/M6 templating is
done) or document that the array is unspecified after an exception.

### L9. Minor style notes

- Two `opApply` overloads (mutable/`const`) arguably fall under the
  operator exemption from "No overloaded functions", but templating them
  (M6) removes the question.
- `removeFirst` in `SmallBuffer` binds `const slice = opSlice();` and
  then mutates through `removeAt` before returning. This is correct
  because it returns right away, but iterating `this[]` directly as in
  `ReusableArray` would be clearer.
- `RingBuffer.opIndex`/`ReusableArray.back` lack the `return` attribute
  that `SmallBuffer.opIndex` has (see M1).

### L10. Thread-safety is implicit

None of the containers are thread-safe. This is fine (`MessageBus` wraps
every `RingBuffer` access in `synchronized (lock)`), but the module
docs should say so, given the project rule that threads communicate only
via `sendAppEvent`.

## 4. Test Coverage

Strengths: tests cover stack/heap transitions, heap reuse after `clear()`,
identity vs value semantics with an overriding `opEquals`, FIFO order
across wrap-around and growth, postblit counting for moves, early
`break` in `opApply`, and GC slot clearing for `RingBuffer` and
`ReusableArray`. The module is part of `yguilib_test` via
`yguilib/meson.build`.

Gaps worth adding:

- Copy prevention (`static assert` that copies do not compile) after H1.
- `SmallBuffer` GC clearing: stack slots after `spillToHeap()`, and heap
  slots after `clear()`/`removeAt()` in heap mode.
- `SmallBuffer!(T, 1)` (smallest capacity), `fillWith(0, ...)`,
  `assignSlice([])`.
- Heap-mode `removeAt` down to empty, then `push` (stays in heap mode).
- Self-aliasing `assignSlice` (after the M2 fix, expect an `assert`).
- `ReusableArray.insertAt` with reference types and `swapWith` followed
  by `clear()` on both sides.
- A type with a destructor (counter based), to pin down M3 behaviour.
- `RingBuffer` mutable `opIndex` writes after wrap-around.

## 5. Recommended Action Order

```
1. H1  @disable this(this) on all three containers (+ test)
2. M2  assert/guard self-aliasing in assignSlice
3. M3  static assert(!hasElaborateDestructor!T) for SmallBuffer and
       ReusableArray
4. M4  rename tryPop -> tryPopFront / tryPopBack
5. M5  length+capacity storage (drops assumeSafeAppend), template
       compact predicate
6. M6  templated opApply
7. L2  invariants, L1 bsr-based nextPowerOfTwo, L3 dedupe, docs (M1, L7,
       L10), extra tests from section 4
```

Items 1-4 are small and low-risk. Item 5 is the largest change. It
mostly touches this module, because the public API (`push`, `opSlice`,
`clear`, ...) can stay the same.
