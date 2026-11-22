# simple-button phase 3: guidemo Page 9 "Button" + docs

Overview: [simple-button.md](simple-button.md). Read `AGENTS.md`,
`codestyle.md`, and the new control `yguilib/source/yguilib/controls/
button.d` (`ButtonBuilder`, `ButtonStyle`, `ButtonSystem`,
`setButtonEnabled`). Use `source/guidemo/pages/knob_page.d` and
`knob_controller.d` as the template for page/controller structure, and
`source/guidemo/guidemoapp.d` for registration.

## Steps
1. `source/guidemo/model.d`: append `simpleButton` as the LAST entry of
   `enum DemoPage` (becomes key 9, Tab cycles to it) and
   `DemoPage.simpleButton: DemoPageMeta("Button", "Button")`.
   Add `final class SimpleButtonPageModel : VersionedModel {
   size_t clickCount; bool targetEnabled = true; string lastAction = "none";
   }` with doc comment "Page 9 ...". Check other code that enumerates
   pages (e.g. `source/guidemo/view.d` header tabs, controller tests that
   assume page count) still works.
2. `source/guidemo/pages/simple_button_page.d` (`SimpleButtonPage`, ctor
   `(UiSystem, Widget parent, ref ModelTracker!SimpleButtonPageModel)`,
   `update()`, `formatStatus()`, `rootWidget()`, `isVisible()`; accessors
   for widgets used in tests). Sections via `makeSectionCard`:
   1. "1. Styles": Primary / Secondary / Danger buttons (distinct
      `ButtonStyle` colours), each with its own action event; a label
      showing clicks and last action.
   2. "2. Disabled state": target button + "Toggle enabled" button and a
      state label; `update()` calls
      `setButtonEnabled(target, model.targetEnabled)`.
   3. "3. Sizing": a fixed-size button and an `autoSize()` button with
      `captionTooltip()`; short help text explaining press animation,
      drag-off cancel, release-inside semantics.
   View event name enums exported from the page module.
3. `source/guidemo/pages/simple_button_controller.d`
   (`SimpleButtonPageController : DefaultController`, params alias via
   `PageControllerParams`, `syncPageShellView` / `syncPageStatus` with
   `DemoPage.simpleButton`, unhandled events -> `super.handleEvent(ev)`).
   Style buttons increment `clickCount` and set `lastAction`; toggle flips
   `targetEnabled`; target click increments count (it can only arrive
   while enabled). Unittest like knob controller's.
4. `source/guidemo/guidemoapp.d`: `app.ui.registerWidgetSystem(new
   ButtonSystem());` next to the hover system; add
   `registerSimplePage!(SimpleButtonPage, SimpleButtonPageController,
   SimpleButtonPageModel)` at the end of `registerDemoPages` (helper
   `registerSimpleButtonPage` like the others); update header comment:
   `[Tab]/[1-9]` and "Page 9: Button" and feature coverage if appropriate.
5. `meson.build`: add both new page files to `guidemo_lib_src`.
6. `ARCHITECTURE.md`: under `controls/` add
   `button.d  # Push button component & press-anim system` and
   `internal/button_support.d  # Shared button builder/press helpers`
   (keep alignment, file < 250 lines).
7. Verify: `ninja -C _build && meson test -C _build`, lines <= 80 chars.
