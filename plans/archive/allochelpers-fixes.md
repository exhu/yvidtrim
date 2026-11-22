# Fix `yguilib.allochelpers` Review Findings

Overview for addressing all findings (`H1`, `M1`-`M6`, `L1`-`L10`) and
Section 4 test coverage gaps from `documentation/allochelpers-review.md`
across `yguilib/source/yguilib/allochelpers.d` and its call sites in
`yguilib`.

## Architecture Overview

```
+------------------------------------------------------------------------+
|                 yguilib/source/yguilib/allochelpers.d                  |
|                                                                        |
|  SmallBuffer!(T, stackCap)                                             |
|    - @disable this(this), !hasElaborateDestructor!T, invariant         |
|    - unified count + heapBuf capacity (no ~= or assumeSafeAppend)      |
|    - non-overlap assert in assignSlice, return accessors               |
|                                                                        |
|  RingBuffer!T                                                          |
|    - @disable this(this), invariant, bsr nextPowerOfTwo                |
|    - tryPopFront(), releaseMemory(), opSlice(this This)() -> Range     |
|    - clearSlot handles hasIndirections!T || hasElaborateDestructor!T   |
|                                                                        |
|  ReusableArray!T                                                       |
|    - @disable this(this), !hasElaborateDestructor!T, invariant         |
|    - buf capacity + count (no ~= or assumeSafeAppend), tryPopBack()    |
|    - compact(Pred)(scope Pred keep) for @safe nothrow @nogc inlining   |
+------------------------------------+-----------------------------------+
                                     ^
                                     | updated callers
+------------------------------------+-----------------------------------+
|  uisystem_impl.d       ref const ControllerDirtyList in runPhase3Render |
|  message_bus.d         queue.tryPopFront()                              |
|  timer_service.d       typed lambda in entries.compact                  |
|  hover_button_system.d typed lambda in activeButtons.compact            |
|  input_system.d        typed lambdas in hoveredWidgets/hoverScratch     |
|  virtlist_system.d     tryPopBack() + typed lambda in fFreePool.compact |
+------------------------------------------------------------------------+
```

## Key Decisions

- **Non-copyable containers (`H1`, `L2`)**: Add `@disable this(this);` and
  `invariant` blocks to `SmallBuffer`, `RingBuffer`, and `ReusableArray`.
- **Destructor rules (`M3`)**: Forbid `hasElaborateDestructor!T` in
  `SmallBuffer` and `ReusableArray` via `static assert`; allow RAII types
  in `RingBuffer` and clear slots when
  `hasIndirections!T || hasElaborateDestructor!T`.
- **Zero runtime append/shrink hooks (`M5`, `L4`, `L6`)**: Track explicit
  `count` + capacity slice in `SmallBuffer` and `ReusableArray`, eliminating
  all `~=` and `assumeSafeAppend()` calls and adding `capacity`.
- **Naming (`M4`)**: Rename `RingBuffer.tryPop` -> `tryPopFront` and
  `ReusableArray.tryPop` -> `tryPopBack`.
- **Attribute-friendly iteration & compaction (`M5`, `M6`, `L8`, `L9`)**:
  Replace `RingBuffer.opApply` overloads with `opSlice(this This)()`
  returning `Range!Elem`; template `ReusableArray.compact(Pred)(scope Pred)`.

## Phases

- Phase 1: [allochelpers-fixes-ph01.md](allochelpers-fixes-ph01.md)
  - Refactor `allochelpers.d` and update all 6 `yguilib` call-site files.
- Phase 2: [allochelpers-fixes-ph02.md](allochelpers-fixes-ph02.md)
  - Add expanded unit tests from Section 4 of the review and run full
    build, test, style, boundary, and null-safety verification.
