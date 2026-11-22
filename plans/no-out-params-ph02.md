# Phase 2: `yguilib.controls`

Replace all `out` parameters in `yguilib/source/yguilib/controls/` (`common.d`,
`scrollbars.d`, `tabcontrol.d`, and `virtlist.d`).

## Files & Changes

### 1. `yguilib/source/yguilib/controls/common.d`
- Add public struct:
  ```d
  struct ArrowCompositeParts {
    Widget dec;
    Widget middle;
    Widget inner;
    Widget inc;
  }
  ```
- Change `findArrowComposite(Widget root, out Widget dec, ...)` to:
  ```d
  Nullable!ArrowCompositeParts findArrowComposite(Widget root)
  ```
  Return `Nullable!ArrowCompositeParts.init` when `root is null`,
  `root.children.length != 3`, or `middle.children.length == 0`; otherwise
  return `Nullable!ArrowCompositeParts(ArrowCompositeParts(...))`.
- Update the `unittest` block in `common.d` to verify `.isNull` and `.get()`
  fields.

### 2. `yguilib/source/yguilib/controls/scrollbars.d`
- Update `findArrowComposite` call site in `ScrollbarWidgetView.registerWidget`.
- Change the following methods to return `Nullable!long` (`Nullable!long.init`
  when unchanged, `Nullable!long(clamped)` when changed):
  - `Nullable!long stepBy(Widget viewWidget, int dir)`
  - `Nullable!long stepDecrement(Widget viewWidget)`
  - `Nullable!long stepIncrement(Widget viewWidget)`
  - `Nullable!long handleTrackClick(Widget viewWidget, in MouseEvent.AppEventViewValue mouseVal)`
  - `Nullable!long updateThumbDrag(Widget viewWidget, in MouseEvent.AppEventViewValue mouseVal)`
  - `Nullable!long endThumbDrag(Widget viewWidget)`
  - Private `Nullable!long applyModelValue(ScrollbarEntry entry, long candidateVal)`
- Update `ScrollbarWidgetViewController` event dispatch to receive
  `Nullable!long newValue` and emit the view value event when
  `!newValue.isNull` using `newValue.get()`.
- In `ScrollbarBuilder`, add private struct:
  ```d
  struct TrackBuildResult {
    Widget track;
    float estWidth;
    float estHeight;
  }
  ```
  Change `buildTrack(...)` to return `TrackBuildResult` (removing
  `out float estTrackW, out float estTrackH`) and update its caller in `build()`.

### 3. `yguilib/source/yguilib/controls/tabcontrol.d`
- Update `findArrowComposite` call site in `TabControlWidgetView.registerWidget`.
- In `TabControlWidgetView`, add private struct:
  ```d
  struct ScrollMetrics {
    float currentOffset;
    float contentMain;
    float viewportMain;
    float maxScroll;
  }
  ```
  Change `static void getScrollMetrics(TabControlEntry entry, out ...)` to
  `static ScrollMetrics getScrollMetrics(TabControlEntry entry)` and update
  its caller.
- In `TabControlBuilder`, add private struct:
  ```d
  struct ViewportBuildResult {
    Widget scrollViewport;
    Widget tabsContainer;
  }
  ```
  Change `buildViewport(...)` to return `ViewportBuildResult` (removing
  `out Widget tabsContainer`) and update its caller in `build()`.

### 4. `yguilib/source/yguilib/controls/virtlist.d`
- Change `package(yguilib): bool takePendingScrollIndex(out size_t index)` to
  `Nullable!size_t takePendingScrollIndex()` and update its caller in
  `VirtListWidgetView.syncModelToComponent`.
- In `VirtListWidgetView`, add private struct:
  ```d
  struct VirtListParts {
    Widget viewport;
    Widget mainScrollbar;
    Widget crossScrollbar;
    Widget cornerBox;
    FlexDirection dir = FlexDirection.column;
  }
  ```
  Change `static void findVirtListParts(Widget viewWidget, out ...)` to
  `static VirtListParts findVirtListParts(Widget viewWidget)` and update its
  caller.
- In `VirtListWidgetViewController`, add private struct:
  ```d
  struct RootEventResult {
    bool handled;
    bool needModelUpdate;
  }
  ```
  Change `bool handleRootEvent(VirtListWidgetView vlv, AppEvent ev, out bool needModelUpdate)`
  to `RootEventResult handleRootEvent(VirtListWidgetView vlv, AppEvent ev)`
  and update `handleEvent`.

## Rules & Verification
- Follow `codestyle.md` (2-space indent, <= 80 chars/line, opening `{` on same
  line, section visibility labels, no default parameters, non-null assertions).
- Check if any tests in `scrollbars.d`, `tabcontrol.d`, `virtlist.d`, or
  `guidemo` call the updated `ScrollbarWidgetView` / `findArrowComposite`
  methods and update them if needed.
- Run:
  ```bash
  ninja -C _build && meson test -C _build
  rdmd .agents/skills/check-line-length/scripts/check_line_length.d
  rdmd .agents/skills/check-codestyle/scripts/check_style.d
  ```
