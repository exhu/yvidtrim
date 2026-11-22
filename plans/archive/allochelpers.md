# Extract Allocation Helpers to `yguilib.allochelpers`

Overview for extracting duplicated stack-buffer, ring-buffer, and
capacity-preserving array patterns across `yguilib` into a new public module
`yguilib.allochelpers`, migrating all hand-rolled sites (leaving
`std.array.Appender` sites as-is), updating `ARCHITECTURE.md`, and removing
the completed first item from `TODO.md`.

## Architecture Overview

```
+--------------------------------------------------------------------------+
|                    yguilib/source/yguilib/allochelpers.d                 |
|                        (public module yguilib.allochelpers)              |
|                                                                          |
|  +-- SmallBuffer!(T, stackCap)  stack T[N] with heap T[] spill           |
|  +-- RingBuffer!T               power-of-two circular FIFO with move     |
|  +-- ReusableArray!T            T[] wrapper with assumeSafeAppend + GC   |
|                                 slot clearing, LIFO pop, unique, compact |
+------------------------------------+-------------------------------------+
                                     ^
                                     | imported by
+------------------------------------+-------------------------------------+
|  Phase 2 (Event Loop & Core)       |  Phase 3 (Widget & Control Systems) |
|  +-- internal/timer_service.d      |  +-- widget/internal/input_system.d |
|  +-- internal/uisystem_impl.d      |  +-- controls/hover_button_system.d |
|  +-- events/internal/message_bus.d |  +-- widget/internal/system_pipeline|
|  +-- controller/internal/          |  +-- widget/virtlist_components.d   |
|      controller_stack.d            |  +-- widget/internal/virtlist_system|
+------------------------------------+-------------------------------------+
```

## Design Rules

- Public module `yguilib.allochelpers` (matching `yguilib.serhelpers`).
- Element comparison in `contains`, `addUnique`, and `removeFirst` uses an
  internal `sameItem` helper: identity (`is`) for classes, interfaces, and
  pointers; value equality (`==`) for value types.
- Shrink operations (`clear`, `popBack`, `tryPop`, `removeAt`, `compact`)
  reset vacated slots to `T.init` when `hasIndirections!T` to avoid GC
  retention of stale object references.
- Strict adherence to `codestyle.md`: 2-space indent, <=80 chars/line, no
  overloaded regular methods, no default parameter values, section visibility
  labels (`public` then `private:`), scoped imports for heavy `std.*`.

## Phases

- Phase 1: [allochelpers-ph01.md](allochelpers-ph01.md)
  - Create `yguilib/source/yguilib/allochelpers.d` with `SmallBuffer`,
    `RingBuffer`, `ReusableArray`, and thorough unit tests.
  - Register `allochelpers.d` in `yguilib/meson.build`.
- Phase 2: [allochelpers-ph02.md](allochelpers-ph02.md)
  - Migrate `timer_service.d`, `uisystem_impl.d`, `message_bus.d`, and
    `controller_stack.d` to `yguilib.allochelpers`.
- Phase 3: [allochelpers-ph03.md](allochelpers-ph03.md)
  - Migrate `input_system.d`, `hover_button_system.d`, `system_pipeline.d`,
    `virtlist_components.d`, and `virtlist_system.d` to
    `yguilib.allochelpers`.
  - Update `ARCHITECTURE.md` and remove the completed first item from
    `TODO.md`.
