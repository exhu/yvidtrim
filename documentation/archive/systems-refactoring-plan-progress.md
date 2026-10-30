# Systems Refactoring Plan: Implementation Progress

Progress tracking for the refactoring plan outlined in
`documentation/systems-refactoring-plan-overview.md`.

## Overall Status
- [x] Phase 1: Public `VisibleWidget` API & Custom `WidgetComponents`
- [x] Phase 2: `WidgetSystem` Base Class, Priority Constants & Context
- [x] Phase 3: Adapt Core Systems to Inherit `WidgetSystem`
- [x] Phase 4: Implement `WidgetSystemPipeline`
- [x] Phase 5: Wire `UiSystem`, `UiSystemImpl` & `UiSystemController`

---

## Phase 1: Public `VisibleWidget` API & Custom `WidgetComponents`
- [x] Step 1.1: Create `yguilib/source/yguilib/widget/visible.d`
- [x] Step 1.2: Update `yguilib/source/yguilib/widget/internal/collect_visible.d`
- [x] Step 1.3: Update internal imports of `VisibleWidget` / `VisibleWidgets`
- [x] Step 1.4: Register `visible.d` in `yguilib/meson.build`
- [x] Step 1.5: Add custom component storage to `WidgetComponents`
- [x] Step 1.6: Add `.component!C` helper to `WidgetBuilder`
- [x] Step 1.7: Add unit tests for custom components
- [x] Phase 1 Verification

---

## Phase 2: `WidgetSystem` Base Class, Priority Constants & Context
- [x] Step 2.1: Create `yguilib/source/yguilib/widget/system.d`
- [x] Step 2.2: Register `system.d` in `yguilib/meson.build`
- [x] Step 2.3: Add unit tests for `WidgetSystem` lifecycle & priority in `system.d`
- [x] Phase 2 Verification

---

## Phase 3: Adapt Core Systems to Inherit `WidgetSystem`
- [x] Step 3.1: Adapt `FocusSystem`
- [x] Step 3.2: Adapt `InputSystem`
- [x] Step 3.3: Adapt `LayoutSystem`
- [x] Step 3.4: Adapt `WidgetPainterSystem`
- [x] Phase 3 Verification

---

## Phase 4: Implement `WidgetSystemPipeline`
- [x] Step 4.1: Create `yguilib/source/yguilib/widget/internal/system_pipeline.d`
- [x] Step 4.2: Register `system_pipeline.d` in `yguilib/meson.build`
- [x] Step 4.3: Add pipeline unit tests
- [x] Phase 4 Verification

---

## Phase 5: Wire `UiSystem`, `UiSystemImpl` & `UiSystemController`
- [x] Step 5.1: Add `WidgetSystemControl` to `yguilib/source/yguilib/uisystem.d`
- [x] Step 5.2: Integrate `WidgetSystemPipeline` into `UiSystemImpl`
- [x] Step 5.3: Update `UiSystemController` to dispatch via pipeline
- [x] Step 5.4: Add end-to-end integration tests
- [x] Phase 5 Verification
