# Phase 3: Migrate Remaining Hand-Rolled Sites & Update Docs

## Objective

Migrate the remaining hand-rolled reusable-array, LIFO-pool, unique-list, and
per-layout scratch-buffer sites across `yguilib` to `yguilib.allochelpers`,
leaving `std.array.Appender` sites untouched. Update `ARCHITECTURE.md` and
remove the completed first item from `TODO.md`.

## Prerequisite

Phases 1 and 2 are complete and passing tests.

## Target Files

1. `yguilib/source/yguilib/widget/internal/input_system.d`
2. `yguilib/source/yguilib/controls/hover_button_system.d`
3. `yguilib/source/yguilib/widget/internal/system_pipeline.d`
4. `yguilib/source/yguilib/widget/virtlist_components.d`
5. `yguilib/source/yguilib/widget/internal/virtlist_system.d`
6. `ARCHITECTURE.md`
7. `TODO.md`

## Detailed Steps

### 1. Migrate `input_system.d`

Import `yguilib.allochelpers : ReusableArray;`.
- Replace `HoverEntry[] hoveredWidgets; HoverEntry[] hoverScratch;` with
  `ReusableArray!HoverEntry hoveredWidgets;` and
  `ReusableArray!HoverEntry hoverScratch;`.
- In `onWidgetReleased(Widget w)`:
  - Replace `std.algorithm.mutation.remove` calls with:
    ```d
    hoveredWidgets.compact((const ref e) => e.widget !is w);
    hoverScratch.compact((const ref e) => e.widget !is w);
    ```
  - Remove the now-unused `import std.algorithm.mutation : remove;`.
- In `updateHoverState`:
  - Replace the 3-line swap with `hoveredWidgets.swapWith(hoverScratch);`.
- In `collectHovered`:
  - Replace `hoverScratch.length = 0; hoverScratch.assumeSafeAppend();` with
    `hoverScratch.clear();`.
  - Replace `hoverScratch ~= HoverEntry(...)` with
    `hoverScratch.push(HoverEntry(...))`.
- Update `notifyDepartedWidgets` and `notifyEnteredAndMovedWidgets` to slice
  `hoveredWidgets[]` / `hoverScratch[]` where passed to `containsWidget`.

### 2. Migrate `hover_button_system.d`

Import `yguilib.allochelpers : ReusableArray;`.
- Replace `Widget[] activeButtons;` with `ReusableArray!Widget activeButtons;`.
- In `trackActiveButton(Widget w)`:
  - Keep `if (w is null) { return; }`, then replace the manual dedup loop and
    append with `activeButtons.addUnique(w);`.
- Delete `removeActiveButtonAt(size_t index)` and replace its callers with
  `activeButtons.removeAt(cast(size_t) i)` (fixes missing `assumeSafeAppend()`
  and clears GC reference).
- In `onWidgetReleased(Widget w)`:
  - Replace the reverse removal loop with
    `activeButtons.compact((const ref item) => item !is w);`.
- Keep `isAnyAnimating() const nothrow @safe` returning
  `!activeButtons.empty` (or `activeButtons.length > 0`).

### 3. Migrate `system_pipeline.d`

Import `yguilib.allochelpers : ReusableArray;`.
- Replace `WidgetSystem[] systems;` with
  `ReusableArray!WidgetSystem systems;`.
- In `registerSystem(WidgetSystem system)`:
  - Replace manual dedup loop with `if (systems.contains(system)) { return; }`.
  - Update `insertSorted` to take `ref ReusableArray!WidgetSystem list` and
    call `list.insertAt(insertPos, item);` (eliminating manual shift-right).
- In `unregisterSystem(WidgetSystem system)`:
  - Replace manual find + shift-left loop with:
    ```d
    if (!systems.removeFirst(system)) {
      return;
    }
    ```
- Iterate `systems[]` in `findSystem`, `findSystemByType`, `filterByPhase`,
  etc.
- Leave `Appender!(RectF[]) oldRectBuf;` untouched.

### 4. Migrate `virtlist_components.d` & `virtlist_system.d`

In `virtlist_components.d`:
- Import `yguilib.allochelpers : ReusableArray;`.
- Replace `Widget[] fFreePool;` with `ReusableArray!Widget fFreePool;`.
- Keep `pooledWidgetsCount() const nothrow @safe` returning
  `fFreePool.length`.

In `virtlist_system.d`:
- Import `yguilib.allochelpers : ReusableArray, SmallBuffer;`.
- Replace `Widget[] nodeBuf;` with `ReusableArray!Widget nodeBuf;`.
  - In `measureItemSubtree`: replace `nodeBuf.length = 0;
    nodeBuf.assumeSafeAppend();` with `nodeBuf.clear();`.
  - Update `collectVisibleNodes` to take `ref ReusableArray!Widget buf` and
    call `buf.push(node);`.
  - Iterate `nodeBuf[]` in `measureItemSubtree` and `recomputeAutoMainSizes`.
- Migrate `vc.fFreePool` usages:
  - `clearComponentRuntime`: `vc.fFreePool.releaseMemory();`
  - `detachReleasedItem`:
    `vc.fFreePool.compact((const ref item) => item !is w);`
  - `recycleAllAndReset`, `trimLeadingOffscreen`, `recycleUnclaimed`:
    `vc.fFreePool.push(...)`
  - `acquireItemWidget`: replace manual LIFO pop + `assumeSafeAppend()` with:
    ```d
    auto reused = vc.fFreePool.tryPop();
    if (!reused.isNull) {
      return reused.get();
    }
    ```
- Replace per-layout scratch allocations:
  - In `handleVirtListLayout`: replace
    `bool[] claimed = new bool[prevActive.length];` with:
    ```d
    SmallBuffer!(bool, 32) claimedBuf;
    claimedBuf.fillWith(prevActive.length, false);
    bool[] claimed = claimedBuf[];
    ```
  - In `handleBottomUnderflow`: replace `VirtListActiveItem[] backfill;` with
    `SmallBuffer!(VirtListActiveItem, 16) backfill;`, call
    `backfill.push(entry);`, and when `backfill.length > 0`, reverse
    `backfill[]` and combine `active = backfill[] ~ active;`.

### 5. Update `ARCHITECTURE.md` and `TODO.md`

- In `ARCHITECTURE.md`:
  - Add `allochelpers.d` entry under `yguilib/source/yguilib/` in Directory &
    Package Topology.
  - Update the Memory & Safety Enforcements bullet to mention
    `yguilib.allochelpers` (`SmallBuffer`, `RingBuffer`, `ReusableArray`).
  - Keep `ARCHITECTURE.md` strictly under 250 lines and <= 80 chars/line.
- In `TODO.md`:
  - Remove the completed first item (lines 1-10 about `yguilib.allochelpers`).

## Verification

Run:
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
```
All commands must pass with 0 errors and 0 warnings.
