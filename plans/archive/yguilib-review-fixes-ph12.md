# ph12: `widget` `VirtListSystem` & Components

Overview: `plans/yguilib-review-fixes.md`.
Review: `documentation/yguilib-review-report-widget.md` (commit `7a96feaa`).
Paths below are relative to `yguilib/source/yguilib/widget/`.

Goal: Address all `VirtListSystem` & `VirtListComponent` findings
(`1.8`-`1.9`, `1.17`-`1.18`, `2.2`-`2.4`, `4.1`-`4.2`, `5.1`-`5.2`,
`6.1`-`6.2`).

## Files

- `virtlist_components.d`, `internal/virtlist_system.d`

## Steps

1. **Wheel occlusion & `inputEnabled` (`1.8`)**:
   - In `VirtListSystem` `mouseWheel`, scan `visibleWidgets` in reverse
     Z-order using `VisibleWidget.containsPoint`: stop on any hittable
     (`handleInput`) widget that is not the list or a descendant of it, and
     require `listWidget.inputEnabled` before scrolling.
2. **Overflow, cache invalidation & layout coupling (`1.9`, `1.17`, `1.18`, `2.4`)**:
   - Extract shared `saturatingAdd(size_t idx, size_t count)` and use it in
     `applyRemoveChange`, `shiftSizeCachesRemove`, and `applyUpdateChange`
     (`1.9`).
   - Prune stale size-cache entries when `itemsCount` shrinks or resets to
     `0` (`1.17`).
   - Fix `applyInsertChange` anchor-shift heuristic for multi-batch inserts
     into an empty list (`1.17`).
   - Update `fVisibleItemsCount` & dirty parent layout in
     `detachReleasedItem`, and clamp `size_t` -> `uint` in
     `handleVirtListPostLayout` (`1.18`).
   - Resolve `LayoutSystem` (priority 0) vs `VirtListSystem` (priority 5)
     `stretchCrossAxis` fight (`2.4`).
3. **Zero per-scroll GC & O(`fItemMainSizes.length`) offset (`2.2`, `2.3`, `2.4`)**:
   - Store `fActiveItems` as `ReusableArray!VirtListActiveItem` with a
     reusable scratch buffer on `VirtListSystem` (`2.2`).
   - Rewrite `computeCurrentMainOffset` as `fAnchorIndex * (avgMain + gap) +
     sum(v - avgMain)` over `k < fAnchorIndex` (`2.3`).
   - Convert `VirtListComponent.fPendingChanges` to
     `ReusableArray!VirtListChange` (`2.4`).
4. **Reuse & codestyle (`4.1`, `4.2`, `5.1`, `5.2`)**:
   - Group 8-10 param functions (`pack`, `fillVisibleRange`,
     `acquireAndMeasureItem`, `handleBottomUnderflow`) into parameter
     structs (`5.1`).
   - Reuse `MockWidgetSystemHost`, `VisibleWidget.containsPoint`, and
     shared `AppEventViewValue` helper (`4.1`, `4.2`).
   - Drop unused `Widget w` param and fix per-declaration `private` (`5.2`).
5. **Regression tests (`6.1`, `6.2`)**:
   - Add tests for wheel gating (disabled & occluding overlay), empty-list
     cache reset, removal overflow, `LayoutSystem`+`VirtListSystem`
     `stretchCrossAxis`, and `VirtListComponent` `NaN`/scroll guards.

## Verification

- `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`
