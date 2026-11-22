# Virtual List (`VirtList`) Implementation Plan

Overview of the virtualized vertical and horizontal list composite control
(`VirtList`) for `yguilib` and `guidemo` (first item in `TODO.md`).

`VirtList` supports large datasets (10,000+ items) with single-template widget
recycling, heterogeneous row layouts (via internal subtree visibility switching
in a single reusable row widget tree), variable item sizes (including items
exceeding the viewport on both main and cross axes), dynamic `insert` /
`remove` / `update` operations that preserve relative scroll position and
reflow resized rows, `onWidgetRecycled` notifications to stop animations, and
synchronized main-axis and cross-axis scrollbars.

## Architecture Overview

```
+----------------------------------------------------------------------------+
|                   VirtList Composite Root (ViewComponent)                  |
|                        (source/guidemo/virtlist.d)                         |
|                                                                            |
|  +------------------------------------------------------+  +------------+  |
|  | virtListViewport (VirtListComponent, clipChildren)   |  | virtList   |  |
|  |                                                      |  | VBar       |  |
|  |  +------------------------------------------------+  |  | (Scrollbar |  |
|  |  | Active Recycled Item [anchorIndex]             |  |  |  Column)   |  |
|  |  | (Single template tree; active subtree visible) |  |  |            |  |
|  |  +------------------------------------------------+  |  |            |  |
|  |  +------------------------------------------------+  |  |            |  |
|  |  | Active Recycled Item [anchorIndex + 1]         |  |  |            |  |
|  |  +------------------------------------------------+  |  +------------+  |
|  +------------------------------------------------------+                  |
|  +------------------------------------------------------+  +------------+  |
|  | virtListHBar (Scrollbar Row)                         |  | Corner     |  |
|  +------------------------------------------------------+  +------------+  |
+----------------------------------------------------------------------------+
```

## Phases

- Phase 1: [virtlist-ph01.md](virtlist-ph01.md)
  - Implement `yguilib.widget.virtlist_components` (`VirtListProvider`,
    `VirtListChange`, `VirtListComponent`) and
    `yguilib.widget.internal.virtlist_system` (`VirtListSystem`).
  - Wire `WidgetSystem.virtListSystemPriority`, `WidgetComponents.virtList`,
    `WidgetBuilder` helpers, `UiSystemImpl`, and `yguilib/meson.build`.
  - Add headless unit tests in `yguilib_test`.
- Phase 2: [virtlist-ph02.md](virtlist-ph02.md)
  - Implement `source/guidemo/virtlist.d` (`VirtListModel`, `VirtListStyle`,
    `VirtListWidgetView`, `VirtListWidgetViewController`, `VirtListBuilder`,
    `registerVirtList`).
  - Add `virtlist_test` executable and unit tests to `meson.build`.
- Phase 3: [virtlist-ph03.md](virtlist-ph03.md)
  - Implement Page 7 (`source/guidemo/pages/virtlist_page.d` and
    `source/guidemo/pages/virtlist_controller.d`) showcasing a 10,000-item
    heterogeneous vertical media/file list and a horizontal virtual filmstrip.
  - Wire Page 7 into `model.d`, `demo_model_helpers.d`, `guidemoapp.d`,
    `meson.build`, `ARCHITECTURE.md`, and remove the completed item from
    `TODO.md`.
