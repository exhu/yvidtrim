# Phase 1: `yguilib` Core & Widget Internals

Refactor output-flag `ref` parameters in `uisystem_impl.d` and all `out`
parameters in `yguilib/source/yguilib/widget/internal/`.

## Files & Changes

### 1. `yguilib/source/yguilib/internal/uisystem_impl.d`
- Add private `struct EventBatchResult`:
  ```d
  struct EventBatchResult {
    bool keepRunning = true;
    bool needModelUpdate = false;
    bool needRender = false;
  }
  ```
- Change `void handleMainWindowEvent(in AppEvent event, ref bool needRender)`
  to `bool handleMainWindowEvent(in AppEvent event)`, returning `true` when
  a redraw is triggered and `false` otherwise.
- Change `dispatchDiscreteEvent` to:
  ```d
  EventBatchResult dispatchDiscreteEvent(
    AppEvent event,
    ref ControllerDirtyList dirtyViews
  )
  ```
  (Keep `ref ControllerDirtyList dirtyViews` as a zero-alloc stack buffer.)
- Change `drainMessageBus` to:
  ```d
  EventBatchResult drainMessageBus(ref ControllerDirtyList dirtyViews)
  ```
  Accumulate `needModelUpdate` and `needRender` across events and return
  immediately with `keepRunning = false` if a controller requests quit.
- Update `runEventLoopStep()` to consume `EventBatchResult`:
  - Return `false` if `!batch.keepRunning`.
  - Pass `batch.needModelUpdate` to `runPhase2Updates`.
  - Pass `needRender || batch.needRender` to `runPhase3Render`.

### 2. `yguilib/source/yguilib/widget/internal/layout_content_size.d`
- Import `std.typecons : Nullable` (scoped or module-level as appropriate).
- Change `bool tryCalcFlexContentSize(const Widget w, const FlexContainer flexComp, out PointF size)`
  to `Nullable!PointF tryCalcFlexContentSize(const Widget w, const FlexContainer flexComp)`.
- Change `bool tryCalcChildrenBoundingBox(const Widget w, out PointF size)`
  to `Nullable!PointF tryCalcChildrenBoundingBox(const Widget w)`.
- Update both call sites in `calcAutoContentSize`:
  check `!res.isNull` and return `res.get()`.

### 3. `yguilib/source/yguilib/widget/internal/layout_flex.d` & `layout_system.d`
- In `layout_flex.d` (`package(yguilib):`), add:
  ```d
  struct JustifyOffsets {
    float startOffset;
    float gapBetween;
  }
  ```
- Change `computeJustifyOffsets(...)` to return `JustifyOffsets` (removing
  `out float startOffset, out float gapBetween`).
- Update the caller in `layout_system.d` to use `offsets.startOffset` and
  `offsets.gapBetween`.

### 4. `yguilib/source/yguilib/widget/internal/input_system.d`
- Add private `struct WidgetHitInfo { RectF targetRect; bool inside; }`.
- Change `static void resolveWidgetRectAndHit(..., out RectF targetRect, out bool inside)`
  to `static WidgetHitInfo resolveWidgetRectAndHit(VisibleWidgets widgets, Widget target, PointF p)`.
- Update both callers in `input_system.d`.

### 5. `yguilib/source/yguilib/widget/internal/virtlist_system.d`
- Add private structs:
  ```d
  struct MeasuredItemSize {
    float main;
    float cross;
  }

  struct AcquiredItem {
    Widget widget;
    bool newlyBound;
    bool needsRebind;
  }
  ```
- Change `cacheMeasuredItemSize(...)` to return `MeasuredItemSize` (removing
  `out float measuredMain, out float measuredCross`).
- Change `acquireItemWidget(...)` to return `AcquiredItem` (removing
  `out bool newlyBound, out bool needsRebind`).
- Update both call sites in `virtlist_system.d`.

## Rules & Verification
- Follow `codestyle.md` (2-space indent, <= 80 chars/line, opening `{` on same
  line, section visibility labels, no default parameters, non-null assertions).
- Run:
  ```bash
  ninja -C _build && meson test -C _build
  rdmd .agents/skills/check-line-length/scripts/check_line_length.d
  rdmd .agents/skills/check-codestyle/scripts/check_style.d
  ```
