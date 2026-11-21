# Phase 3: `guidemo` Page 7 (`VirtListPage`), App Wiring, and Docs

Implement Page 7 in `guidemo` showcasing vertical (10,000 items) and horizontal
heterogeneous virtual lists with dynamic insertions, removals, row size updates,
oversized items, and animation recycling, then update `ARCHITECTURE.md` and
`TODO.md`.

## Rules & Conventions
- Adhere to `codestyle.md`: 2-space indent, LF, max 80 chars/line, opening `{`
  on same line, visibility sections (`public:`, `private:`), no overloaded
  functions/methods, no default parameter values, no consecutive capital letters,
  non-null assertions in constructors, `invariant` blocks, functions `<= ~50`
  lines.
- Keep `ARCHITECTURE.md` under 250 lines.
- Every `WidgetBuilder.make` / `.child` chain must set `.name(...)` and
  `.rect(...)`.

## Tasks

### 1. Update `source/guidemo/model.d` and `source/guidemo/demo_model_helpers.d`
- In `source/guidemo/model.d`:
  - Add `virtList` to `enum DemoPage`.
  - Add `DemoPage.virtList: DemoPageMeta("VirtList", "VirtList")` to
    `demoPages`.
  - Update `defaultHeaderTabNames` / `HeaderTabsModel` if kept in sync, or keep
    `headerTabNames()` driving `DemoView`.
  - Add `final class VirtListPageModel : VersionedModel` holding:
    - `size_t vItemsCount = 10000;`
    - `size_t vFirstVisible = 0;`
    - `size_t vVisibleCount = 0;`
    - `size_t hItemsCount = 1200;`
    - `size_t hFirstVisible = 0;`
    - `size_t hVisibleCount = 0;`
    - `size_t recycledStopsCount = 0;`
    - `size_t activeVideosCount = 0;`
- In `source/guidemo/demo_model_helpers.d`:
  - Update `unittest` assertions from `pageCount() == 6` to `pageCount() == 7`.

### 2. Create `source/guidemo/pages/virtlist_page.d`
- Module `guidemo.pages.virtlist_page`.
- Implement a heterogeneous single-template `VirtListProvider` for the vertical
  media & file browser list (`VerticalMediaProvider : VirtListProvider`):
  - Single reusable row widget created in `createWidget(Widget parent)` with
    internal subtrees:
    - `headerSubtree` (compact section header band, e.g. 34px tall)
    - `videoSubtree` (animated video clip card with live pulsing border/progress
      bar; supports `expanded` toggle increasing height to 210px and width
      to 700px to exceed the viewport on both axes!)
    - `imageSubtree` (image thumbnail + EXIF metadata card, 84px tall, wide
      enough to test cross-axis scrolling when metadata is long)
    - `fileSubtree` (compact file browser row, 38px tall)
  - `updateWidgetAt(Widget w, size_t index)` toggles subtree visibility based on
    item metadata (heterogeneous mix across 10,000 items plus dynamic inserts,
    removals, and expanded flags), updates text captions/colors, and registers
    active video rows in an animated set.
  - `onWidgetRecycled(Widget w)` removes `w` from the active video animation set
    and increments `recycledStopsCount` whenever an animated video row is
    recycled.
  - Provide `tickAnimations(float dt)` to animate visible video clip widgets
    (only running a timer when the page is visible and at least one video clip
    widget is active, stopping cleanly when idle or hidden).
- Implement a heterogeneous single-template `VirtListProvider` for the
  horizontal filmstrip list (`HorizontalStripProvider : VirtListProvider`):
  - Single reusable column card widget switching internal subtrees for
    keyframe cards (140px wide), wide multi-GOP audio/video segments (up to
    340px wide, exceeding viewport width), and narrow chapter markers (76px
    wide), with variable heights exceeding viewport height for cross-axis scroll.
- Build two sections on `VirtListPage`:
  - **Left/Top Card**: Vertical 10,000-item media/file `VirtList` + interactive
    buttons (`Expand Row`, `+ Ins Above`, `+ Ins Here`, `- Rem Here`,
    `10K / 50`, `Jump 5000`) + live telemetry label (`Items`, `FirstVis`,
    `VisCount`, `Active`, `Pooled`, `AnimsStopped`).
  - **Right Card**: Horizontal 1,200-item filmstrip `VirtList` + interactive
    buttons (`Resize Item`, `+ Ins Clip`, `- Rem Clip`, `- Narrow`, `+ Widen`,
    `Reset`) + live telemetry label.

### 3. Create `source/guidemo/pages/virtlist_controller.d`
- Module `guidemo.pages.virtlist_controller`.
- `final class VirtListPageController : DefaultController`:
  - `@disable this();` and `this(UiSystem ui, ref ModelTracker!DemoModel demoTracker, VirtListPage page)`
  - `static VirtListPageController createStandalone(UiSystem ui, VirtListPage page)`
  - Drives animation timer (`startTickTimer(33, TimerMode.repeat)`) only while
    the page is active and has active animated video rows (`stopTickTimer` when
    inactive or idle so `SDL_WaitEvent` sleeps at 0% CPU).
  - Handles button events (`Expand Row`, `+ Ins Above`, `+ Ins Here`,
    `- Rem Here`, `10K / 50`, `Jump 5000`, `Resize Item`, `+ Ins Clip`,
    `- Rem Clip`, `- Narrow`, `+ Widen`, `Reset`) and `VirtList` change events.
  - Include headless `unittest` verifying initialization, mutations (`insert`,
    `remove`, `update`), and `DemoModel.activePage = DemoPage.virtList` shell
    visibility sync.

### 4. Wire `guidemoapp.d`, `meson.build`, `ARCHITECTURE.md`, and `TODO.md`
- In `source/guidemo/guidemoapp.d`:
  - Register `app.ui.pushController(registerVirtList(app.ui));` in `main()`.
  - Instantiate `VirtListPage` and push `VirtListPageController` in
    `registerDemoPages`.
- In `source/guidemo/controller.d`:
  - Update `unittest` if needed (`pageCount()` is now 7; `[1-7]` works with
    existing `keycodes` array).
- In `meson.build`:
  - Add `source/guidemo/pages/virtlist_page.d` and
    `source/guidemo/pages/virtlist_controller.d` to `guidemo_lib_src`.
- In `ARCHITECTURE.md`:
  - Add `virtlist.d` under `source/guidemo/` and note `virtlist_components.d` /
    `virtlist_system.d` under `yguilib/widget/` (staying strictly `< 250` lines).
- In `TODO.md`:
  - Remove the completed first item (lines 1-17).

## Verification (Phase 3)
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d --audit
```
