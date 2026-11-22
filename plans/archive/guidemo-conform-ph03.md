# guidemo-conform phase 3: scrollbars and tabcontrol pages

Overview: [guidemo-conform.md](guidemo-conform.md). Read `codestyle.md`,
`AGENTS.md` first. Phases 1-2 done: `PageControllerParams(P, T)` in
`source/guidemo/common.d`; simple pages wired like `knob_page.d` /
`textlabel_page.d` (tracker created in `guidemoapp.d registerDemoPages`,
passed to both view and controller).

## Rule
A model the controller modifies is passed to both and edited by the
controller via its tracker; models used only by the view stay in the view.

## Shared pattern
In the page module define
```D
/// Trackers shared between <X>Page and <X>PageController.
struct <X>PageTrackers {
  ModelTracker!<X>PageModel page;
  ModelTracker!SomeControlModel someControl;
  /// Creates trackers with default models.
  static <X>PageTrackers make() {...}
  /// Copies `other` with independent per-holder versions.
  static <X>PageTrackers from(ref <X>PageTrackers other) {...}
}
```
View: `this(UiSystem ui, Widget parent, ref <X>PageTrackers trackers)`;
drop the redundant `UiRegistry registry` param (UiSystem extends
UiRegistry). Controller: `ref PageControllerParams!(<X>Page,
<X>PageTrackers)`. Remove `getTracker()` and `createStandalone()`.

## scrollbars (`pages/scrollbars_page.d`, `scrollbars_controller.d`)
- Lift page model + `playgroundTracker` (ScrollbarModel) into
  `ScrollbarsPageTrackers`. `hScroll/vScroll/live/release` trackers stay in
  the view.
- Move `shrinkVisibleSize`, `growVisibleSize`, `togglePlaygroundRange`,
  `narrowPlaygroundBar`, `widenPlaygroundBar`, `resetPlayground` logic into
  the controller (edit trackers). Bar width belongs in a model
  (add field to `ScrollbarsPageModel` in `source/guidemo/model.d` if not
  present); the view applies it in `update()`. Replace
  `playgroundValue()` accessor use by reading the tracker.
## tabcontrol (`pages/tabcontrol_page.d`, `tabcontrol_controller.d`)
- Lift page model + `dynamicTabsTracker` (TabsModel) into
  `TabControlPageTrackers`. `subTabs/verticalTabs` stay in the view.
- Move `addDynamicTab`, `removeDynamicTab`, `resetDynamicTabs`,
  `narrowDynamicViewport`, `widenDynamicViewport` into the controller
  (`TabControlPageModel.viewportWidth` holds the width; view applies it).
  Replace `dynamicActiveTab()` accessor use with tracker reads.

Keep view-side widget sync in `View.update()`; keep event names and
behavior identical. Update `guidemoapp.d` and unittests (assert on the
test's trackers). Keep functions < ~50 lines.

## Verify
`ninja -C _build && meson test -C _build` and the 4 check skills from the
overview.
