# guidemo-conform phase 1: mechanical style fixes

Overview: [guidemo-conform.md](guidemo-conform.md). Read `codestyle.md` and
`AGENTS.md` first. No behavior change in this phase.

## Steps
1. Drop `get` prefix on view accessors (match `source/yvidtrim/view.d`
   `rootWidget()`): `getRootWidget` -> `rootWidget`,
   `getHeaderTabControl` -> `headerTabControl`, `getValueBox` -> `valueBox`,
   `getVerticalListRoot` -> `verticalListRoot`, `getHorizontalListRoot` ->
   `horizontalListRoot`, `getDynamicActiveTab` -> `dynamicActiveTab`,
   `getPlaygroundValue` -> `playgroundValue`, and any other `get*` accessor
   in `source/guidemo/**`. Do NOT rename `getTracker()` (removed in ph02).
   If a new accessor name collides with a private field, rename the field
   (e.g. `valueBox` field -> `valueBoxWidget`). Update all callers/tests.
2. Tooltip overload (codestyle: no overloads). In
   `source/guidemo/hover_button.d` (`HoverButtonBuilder`) and
   `yguilib/source/yguilib/controls/hover_button_system.d`
   (`AnimatedHoverButtonBuilder`): `tooltip()` -> `captionTooltip()`
   (tooltip text taken from caption), `tooltip(string)` ->
   `tooltipText(string)`. If a field is already named `tooltipText`, rename
   the field (e.g. `tooltipHint`). Update every call site in `source/`,
   `yguilib/` (grep `\.tooltip(`), docs/comments, and ARCHITECTURE.md if
   mentioned. Check other builders with `tooltip` (e.g. tab buttons) only
   if they also overload.
3. `const` for locals that never change (e.g. `controller.d`
   `toggleDebugDraw` `next`, `textlabel_controller.d` `nextAlign`,
   `textlabel_page.d` `alignStr`). Sweep all guidemo files.
4. Add `@disable this();` to every guidemo class/struct with only a
   parameterized constructor where missing (page classes, etc.).
5. Add `///` doc comments to undocumented public methods (`update`,
   `formatStatus`, accessors) in guidemo views/controllers.
6. Add to `source/guidemo/common.d` a generic fluent params struct:
   ```D
   /// Parameters for constructing a page controller.
   struct PageControllerParams(P, T) {
     UiSystem ui;
     ModelTracker!DemoModel demoTracker;
     T trackers;   // page tracker or <Page>Trackers struct
     P page;
     ref PageControllerParams withUi(UiSystem ui) return {...}
     ref PageControllerParams withDemoTracker(
       ref ModelTracker!DemoModel t) return {
       demoTracker = ModelTracker!DemoModel.from(t); ...}
     ref PageControllerParams withTrackers(ref T t) return {...}
     ref PageControllerParams withPage(P page) return {...}
   }
   ```
   `withTrackers` copies via `T.from(t)` (ModelTracker has `from`; ph02/03
   Trackers structs will define `static from(ref)` too).
   Use it to fix `KnobPageController` (4 params ->
   `this(ref PageControllerParams!(KnobPage, ModelTracker!KnobPageModel))`),
   following `DemoControllerParams` in `source/guidemo/controller.d`.
   Update `guidemoapp.d` and the knob unittest.

## Verify
`ninja -C _build && meson test -C _build` and the 4 check skills listed in
the overview; codestyle checker must report 0 warnings for guidemo and the
touched yguilib file.
