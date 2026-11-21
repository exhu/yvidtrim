# Phase 2: Migrate Core Event-Loop & Service Modules

## Objective

Replace duplicated stack-buffer, ring-buffer, and capacity-preserving array
implementations in the core event-loop and service modules with
`yguilib.allochelpers` types (`SmallBuffer`, `RingBuffer`, `ReusableArray`).

## Prerequisite

Phase 1 (`yguilib/source/yguilib/allochelpers.d` registered in
`yguilib/meson.build`) is complete and passing tests.

## Target Files

1. `yguilib/source/yguilib/internal/timer_service.d`
2. `yguilib/source/yguilib/internal/uisystem_impl.d`
3. `yguilib/source/yguilib/events/internal/message_bus.d`
4. `yguilib/source/yguilib/controller/internal/controller_stack.d`

## Detailed Steps

### 1. Migrate `timer_service.d`

Import `yguilib.allochelpers : ReusableArray, SmallBuffer;`.
- Replace `TimerEntry[] entries;` with `ReusableArray!TimerEntry entries;`.
  - In `addEntry`: `entries.push(entry);`
  - In loops (`stopTimer`, `isTimerActive`, `stopTimersForController`,
    `stopTimersForSystem`, `nextWaitTimeoutMs`, `hasDueTimers`, `activeCount`,
    `findActiveIndex`, `collectDueIds`): iterate `entries[]` (e.g.,
    `foreach (ref e; entries[])` / `foreach (const ref e; entries[])`).
  - In `compactIfIdle()`: replace the manual `writeIdx` loop and
    `assumeSafeAppend()` with:
    ```d
    entries.compact((const ref e) => e.active);
    ```
- Replace `TimerId[32] stackIds; TimerId[] dueIds = collectDueIds(...)` in
  `fireDueTimers` with:
  ```d
  SmallBuffer!(TimerId, 32) dueIds;
  collectDueIds(now, dueIds);
  if (dueIds.empty) {
    return;
  }
  ```
  and iterate `foreach (id; dueIds[])`.
- Change `collectDueIds` to:
  ```d
  void collectDueIds(long now, ref SmallBuffer!(TimerId, 32) dueIds) const {
    foreach (const ref e; entries[]) {
      if (e.active && e.nextFireNs <= now) {
        dueIds.push(e.id);
      }
    }
  }
  ```
- Verify existing `TimerService` unit tests pass, and add a small test case
  with >32 simultaneous due timers (if not already covered) to exercise the
  `SmallBuffer` heap-spill path in `fireDueTimers`.

### 2. Migrate `uisystem_impl.d`

Import `yguilib.allochelpers : SmallBuffer;`.
- Delete `struct ControllerDirtyList` completely.
- Replace it with:
  ```d
  alias ControllerDirtyList = SmallBuffer!(Controller, 16);
  ```
- At all `dirtyViews.add(...)` call sites (`dispatchDiscreteEvent`,
  `runPhase2Updates`): call `dirtyViews.addUnique(c)` (verify `c !is null`,
  which is already guaranteed at all 3 sites).
- Replace `snapshotControllers`:
  ```d
  void snapshotControllers(ref SmallBuffer!(Controller, 16) outBuf) {
    outBuf.assignSlice(controllers.getAll());
  }
  ```
- Update all 3 call sites (`dispatchDiscreteEvent`, `runPhase2Updates`,
  `runPhase3Render`) to declare `SmallBuffer!(Controller, 16) activeBuf;`,
  call `snapshotControllers(activeBuf);`, and iterate `activeBuf[]`.

### 3. Migrate `message_bus.d`

Import `yguilib.allochelpers : RingBuffer;`.
- Replace `AppEvent[] buffer; size_t head = 0; size_t count = 0;` and `grow()`
  with `RingBuffer!AppEvent queue;`.
- In `this(Object lockObj)`: call `this.queue.reserve(initialCapacity);`.
- In `send(AppEvent ev)`:
  - If `queue.capacity == 0`: `queue.reserve(initialCapacity);`
  - Replace manual `grow()`, `tailIdx`, `buffer[tailIdx] = move(ev)`, `count++`
    with `queue.push(move(ev));`.
- In `get()`:
  - Call `Nullable!AppEvent ev = queue.tryPop();`
  - If `ev.isNull`: return `ev`.
  - Decrement `pendingKindCounts[ev.get().kind]--` and return `ev`.
- Update `hasPending()`, `prepareToWait()`, `length()`, `capacity()` to query
  `queue.empty`, `queue.length`, `queue.capacity`.
- In `isDuplicateNoRepeat(in AppEvent ev) const`:
  - Replace manual bitmask loop with:
    ```d
    foreach (const ref item; queue) {
      if (item.equalsContent(ev)) {
        return true;
      }
    }
    ```
- Preserve all existing `MessageBus` unit tests unchanged (including constant
  capacity and wrap-around growth tests).

### 4. Migrate `controller_stack.d`

Import `yguilib.allochelpers : ReusableArray;`.
- Replace `Controller[] stack;` with `ReusableArray!Controller stack;`.
- Update `push` and `pushModal` to call `stack.push(c);`.
- Update `pop` to call `stack.popBack();` (fixing missing `assumeSafeAppend()`
  and clearing GC slot).
- Update `getActiveOrNull`, `empty`, `length`, `getAll`, `opIndex`, `opApply`
  to delegate to `stack` (`stack.back()`, `stack.empty`, `stack.length`,
  `stack[]`, `stack[i]`).

## Verification

Run:
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
```
All commands must pass with 0 errors and 0 warnings on modified lines.
