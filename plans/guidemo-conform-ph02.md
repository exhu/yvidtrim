# guidemo-conform phase 2: lift page models (simple pages)

Overview: [guidemo-conform.md](guidemo-conform.md). Read `codestyle.md`,
`AGENTS.md` (View-Controller Separation) first. Phase 1 is done: accessors
are `rootWidget()` etc., and `PageControllerParams(P, T)` exists in
`source/guidemo/common.d`; `KnobPage`/`KnobPageController` are the reference
wiring (tracker created outside, passed to both).

## Pages
`layout_painter`, `textlabel`, `button`, `button_system` in
`source/guidemo/pages/` (`*_page.d` + `*_controller.d`).

## Steps (per page)
1. View ctor becomes `this(UiSystem ui, Widget parent,
   ref ModelTracker!<X>PageModel modelTracker)`, copies via
   `ModelTracker!M.from`, `@disable this();`, asserts `parent !is null`.
   Remove the internal `new <X>PageModel()` and the `getTracker()`
   accessor. Remove "parent allowed to be null in tests" branches/docs.
2. Controller ctor takes
   `ref PageControllerParams!(<X>Page, ModelTracker!<X>PageModel) params`;
   assert `params.ui`/`params.page` non-null. Remove `createStandalone()`.
3. The controller must change page state only through its tracker. If the
   controller calls a view method that mutates a model the controller
   owns, move that logic into the controller. Views may keep pure
   read/format helpers (`formatStatus`).
4. `guidemoapp.d` `registerDemoPages`: create tracker -> view -> params ->
   controller for these pages (knob already). Split into small helpers
   (one per page or a generic helper) to keep functions < ~50 lines.
5. Update unittests (they create the trackers explicitly, a root
   `new Widget(ui.nextWidgetId())` as parent, and assert on the test's own
   tracker instead of `page.getTracker()`). Any tests elsewhere
   (e.g. `button_controller.d` harness using DemoView) must still pass.

Leave scrollbars, tabcontrol, virtlist pages for ph03/ph04 (they keep
`getTracker()` until then; that is fine).

## Verify
`ninja -C _build && meson test -C _build` and the 4 check skills from the
overview.
