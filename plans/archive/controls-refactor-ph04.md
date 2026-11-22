# Phase 4: Refactor `tabcontrol.d`, `virtlist.d`, and Update Docs

## Objective

Refactor `yguilib.controls.tabcontrol` (and `tabcontrol_page.d`) and
`yguilib.controls.virtlist` to use the shared modules from Phases 1-3, update
`ARCHITECTURE.md` (keeping < 250 lines), and update `TODO.md`.

## Reference Files

- `yguilib/source/yguilib/controls/tabcontrol.d`
- `source/guidemo/pages/tabcontrol_page.d`
- `yguilib/source/yguilib/controls/virtlist.d`
- `yguilib/source/yguilib/controls/common.d`
- `yguilib/source/yguilib/controls/composite_view.d`
- `yguilib/source/yguilib/controls/internal/axis.d`
- `yguilib/source/yguilib/controls/testing.d`
- `ARCHITECTURE.md`
- `TODO.md`

## Detailed Steps

### 1. Refactor `yguilib/source/yguilib/controls/tabcontrol.d`

- **`TabControlStyle`:**
  - Embed `TabButtonStyle button;` and
    `WidgetColors disabled = defaultDisabledColors;` plus `arrowButtonSize` and
    `arrowGap`.
- **`TabButtonsProvider`:**
  - `addWidget` calls `createTabButton` with `tabButtonMouseDownEvent`,
    `false`, `style.button`, `"tabButton"`.
  - `updateWidgetAt` updates name, caption, `mouseDown`, and calls
    `updateTabButtonState(w, isActive, style.button)`.
- **`TabControlWidgetView`:**
  - Use `ensureViewWidgetRegistered`, `findEntry`, `getEntryField`,
    `bindCompositeModel`, `unregisterCompositeWidget`, and
    `updateCompositeEntries` from `yguilib.controls.composite_view`.
  - Use `findArrowComposite`, `firstPositive`, and `applyEnabledState` from
    `yguilib.controls.common`, and `Axis` from `yguilib.controls.internal.axis`.
  - Extract `syncTabsCount(TabControlEntry entry)` and call it from
    `registerTabControl`, `bindModel`, and `update`'s callback.
  - Simplify `bindModel`: use `findArrowComposite` on `viewWidget` to choose
    `(lBtn, sv, tc, rBtn)` vs `(null, null, viewWidget, null)` and call
    `registerTabControl` once.
  - Merge `scrollNext` and `scrollPrev` into
    `scrollStep(Widget viewWidget, int dir)` and keep `scrollNext` /
    `scrollPrev` as 1-line wrappers.
  - Unify `findNextOrigin`, `findPrevOrigin`, and `findNearestOrigin` using an
    internal `enum OriginSearchMode { next, prev, nearest }` and
    `findOrigin(Widget tabsContainer, Axis axis, float currentOffset,
    float maxScroll, OriginSearchMode mode)`.
- **`TabControlWidgetViewController`:**
  - Remove redundant `override bool update()`.
  - Flatten `handleEvent` using
    `findOwningView!TabControlWidgetView(views, ev.view.viewWidget)`.
- **`TabControlBuilder`:**
  - Use `setBuilderModel`, `setBuilderTracker`, `resolveBuilderRegistry`
    (ensuring `assert(ui !is null)`), `ensureDefaultModelTracker`, `orDefault`,
    `renameMap.dup`, `Axis`, `styledButton`, and
    `findWidgetView!TabControlWidgetView`.
- **`registerTabControl`:**
  - Replace body with:
    ```d
    return registerWidgetViewPair!(
      TabControlWidgetView,
      TabControlWidgetViewController
    )(ui);
    ```

### 2. Update `source/guidemo/pages/tabcontrol_page.d`

- Update `emeraldStyle` in `buildVerticalSection` to assign
  `emeraldStyle.button.width`, `emeraldStyle.button.height`,
  `emeraldStyle.button.active.bg`, and `emeraldStyle.button.active.border`.
- Verify no other files reference old `TabControlStyle` flat fields.

### 3. Refactor `yguilib/source/yguilib/controls/virtlist.d`

- Extract constants `enum defaultVirtListItemMainSize = 48.0f;` and
  `enum defaultVirtListCrossStep = 24.0f;`.
- **`VirtListWidgetView`:**
  - Use `ensureViewWidgetRegistered`, `findEntry`, `getEntryField`,
    `bindCompositeModel`, `unregisterCompositeWidget`, and
    `updateCompositeEntries` from `yguilib.controls.composite_view`, plus
    `orDefault` from `yguilib.controls.common`.
  - Delete pass-through `translateEventForViewWidget` override.
  - Unify `applyMainScrollOffset` and `applyCrossScrollOffset` via private
    `bool applyScrollOffset(Widget viewWidget, long value, bool isMain)`.
  - Simplify `syncScrollbarTracker` by calling `ScrollbarModel.setMetrics` via
    `sbTracker.edit()` / `sbTracker.commit()` only when changed.
- **`VirtListWidgetViewController`:**
  - Remove redundant `override bool update()`.
  - Extract
    `bool routeScrollEvent(VirtListWidgetView vlv, Widget root, AppEvent ev)`
    shared by `handleRootEvent` and `handleOwnedScrollbarEvent`.
  - Use `findOwningView!VirtListWidgetView` and `emitViewValueEvent` (remove
    `emitVisibleChanged`).
- **`VirtListBuilder`:**
  - Use `setBuilderModel`, `setBuilderTracker`, `resolveBuilderRegistry`,
    `ensureDefaultModelTracker`, `orDefault`, `float effItemSize() const`,
    `makeScrollTracker(long step)`, merged
    `buildScrollbar(..., FlexDirection dir, ...)`, and
    `findWidgetView!VirtListWidgetView`.
  - Replace `buildVerticalScrollbar` / `buildHorizontalScrollbar` with
    `buildScrollbar` using `Axis.of(dir).fillMainFixedCross(thickness)`.
- **`registerVirtList`:**
  - Replace body with:
    ```d
    return registerWidgetViewPair!(
      VirtListWidgetView,
      VirtListWidgetViewController
    )(ui);
    ```
- **`unittest`:**
  - Import `calcAbsRect` and `verifyAllNamed` from `yguilib.controls.testing`.

### 4. Update `ARCHITECTURE.md` and `TODO.md`

- Update `yguilib/source/yguilib/controls/` entries in `ARCHITECTURE.md` to
  list `common.d`, `composite_view.d`, `internal/axis.d`, and `testing.d`,
  keeping total lines strictly under 250.
- Update `TODO.md` lines 8-10 by removing the completed code-level reusable
  composite widgets clause and leaving:
  `- invent a text format to construct widget trees to allow for visual editing`

## Verification

Run:
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
```
All commands must pass with 0 errors.
