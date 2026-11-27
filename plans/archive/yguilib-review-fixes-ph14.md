# ph14: `controls` Composites, `ARCHITECTURE.md`, `TODO.md` & Final Verification

Overview: `plans/yguilib-review-fixes.md`.
Review: `documentation/yguilib-review-report-controls.md` (commit `7a96feaa`).
Paths below are relative to `yguilib/source/yguilib/controls/` unless noted.

Goal: Address all findings in `tabcontrol.d`, `scrollbars.d`, and
`virtlist.d` (`1.9`-`1.14`, `1.16`, `1.20`, `2.2`, `2.4`, `3.3`, `4.2`,
`5.1`-`5.5`, `6.2`), update `ARCHITECTURE.md` and `TODO.md`, and run final
verification.

## Files

- `tabcontrol.d`, `scrollbars.d`, `virtlist.d`
- `source/guidemo/pages/virtlist_page.d`
- `ARCHITECTURE.md`, `TODO.md`

## Steps

1. **`tabcontrol.d` (`1.9`, `1.10`, `1.13`, `1.14`, `1.20`, `2.2`, `2.4`, `3.3`, `4.2`, `5.1`-`5.2`, `5.4`-`5.5`, `6.2`)**:
   - Add `package(yguilib) void bindModel(const(TabsModel) newModel)` on
     `TabButtonsProvider` and call it in `TabControlWidgetView.bindModel`
     (`1.9`).
   - Store configured `eventName` on `TabControlEntry`, match it in
     `TabControlWidgetViewController.handleEvent`, and return
     `super.handleEvent(ev)` for all other events (`1.10`).
   - Infer direction from `viewWidget.components.flexContainer.direction`
     in fallback `bindModel` (`1.13`); track `bool found` in
     `translateEventForViewWidget` (`1.14`); operate on `entry.tracker` in
     `selectTab` (`1.20`).
   - Only format `w.name` on creation/index change (`2.2`); drop `.dup` on
     local `renameMap` (`2.4`); mark `TabControlEntry` `private` (`3.3`);
     reuse `setWidgetInputEnabled` (`4.2`).
   - Split `handleScrollChanged` <= 50 lines (`5.1`); rename private
     `revealActiveTab` -> `revealActiveTabForEntry` (`5.2`); group >5-param
     functions into param structs (`5.4`); doc nullable returns & consolidate
     repeated imports (`5.5`); add missing tests (`6.2`).
2. **`scrollbars.d` (`1.12`, `1.13`, `1.20`, `2.4`, `3.3`, `4.2`, `5.4`-`5.5`, `6.2`)**:
   - Clear `entry.isDragging = false` when `tm.range == 0` and preserve
     visual drag offset when `entry.isDragging && m.reportOnReleaseOnly`
     (`1.12`).
   - Infer direction in fallback `bindModel` (`1.13`); cast operands before
     `range + vis` (`1.20`); drop `.dup` on `renameMap` (`2.4`); mark
     `ScrollbarEntry` `private` (`3.3`); reuse `setWidgetInputEnabled`
     (`4.2`); group >5-param functions (`5.4`); doc/import nits (`5.5`);
     split 298-line unittest and add missing tests (`6.2`).
3. **`virtlist.d` & `virtlist_page.d` (`1.11`, `1.16`, `1.20`, `2.4`, `3.3`, `5.3`-`5.5`, `6.2`)**:
   - Bind created `ScrollbarModel` trackers to `parts.mainScrollbar` and
     `parts.crossScrollbar` via `ScrollbarWidgetView` in `bindNewEntryFromTree`
     (`1.11`).
   - Route `syncModelToViewport` mutations through `entry.tracker.edit()` or
     a monotonic change-sequence cursor instead of `cast(VirtListModel)`
     (`1.16`).
   - Fix `findVirtListParts` child count check & `leftBar` name (`1.20`);
     drop `.dup` on `renameMap` (`2.4`); mark `VirtListEntry` `private`
     (`3.3`).
   - Replace `VirtListModel.this(size_t)` with `static VirtListModel
     withCount(size_t)` and update `source/guidemo/pages/virtlist_page.d`
     (`5.3`).
   - Group >5-param functions (`5.4`); doc/import nits (`5.5`); add missing
     tests (`6.2`).
4. **Docs & `TODO.md`**:
   - Update `ARCHITECTURE.md` (< 250 lines) for `render/package_test.d`,
     `makeHeadlessUiSystem()`, `TimerControl` split, `Window` deterministic
     `destroy()`, `ButtonSystem` `preLayout`, and `UiSystemController`
     bottom placement.
   - Remove `- review other modules in yguilib` from `TODO.md`.

## Verification

- `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks --style-all --audit-widgets --keep-going`
- `rdmd .agents/skills/search-code/scripts/search_code.d --expect-none -e 'uisystem_impl' source/ yguilib/examples/`
