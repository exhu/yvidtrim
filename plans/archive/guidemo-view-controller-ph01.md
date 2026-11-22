# Phase 1: `DemoView` and Page Controllers

Update `DemoView` to require a non-null `UiSystem` first argument with
`@disable this()` and a class `invariant`, and remove `createWithParent` from
all 6 page controllers in `source/guidemo/pages/`.

## Rules & Conventions
- Adhere to `codestyle.md`: 2-space indent, LF, max 80 chars/line, opening `{`
  on same line, visibility sections (`public:`, `private:`), no default args,
  no consecutive caps, non-null assertions in constructors, `invariant` blocks,
  functions `<= 50` lines.
- Do not modify `source/guidemo/controller.d`, `source/guidemo/guidemoapp.d`,
  or `TODO.md` in Phase 1 (those belong to Phase 2).
- Note: `guidemo_test` will temporarily not compile until Phase 2 updates
  `source/guidemo/controller.d` and `source/guidemo/guidemoapp.d`; verify
  Phase 1 using the style, line-length, and null-safety scripts.

## Tasks

### 1. Update `source/guidemo/view.d`
- Remove the top-level `import yguilib.internal.uisystem_impl : UiSystemImpl;`
  and place it inside the `unittest` block.
- Add `@disable this();` and update the constructor signature and doc comment:
  ```d
  @disable this();

  /// Constructs DemoView with non-null `ui` and external trackers.
  this(
    UiSystem ui,
    ref ModelTracker!DemoModel modelTracker,
    ref ModelTracker!TabsModel tabsModelTracker
  ) {
    assert(ui !is null, "UiSystem must not be null");
    this.ui = ui;
    tracker = ModelTracker!DemoModel.from(modelTracker);
    tabsTracker = ModelTracker!TabsModel.from(tabsModelTracker);
    ...
  ```
- Add a class `invariant`:
  ```d
  invariant {
    assert(ui !is null);
    assert(view !is null);
    assert(tabControl !is null);
    assert(statusLabel !is null);
  }
  ```
- In the `unittest` block at the bottom of `source/guidemo/view.d`, import
  `yguilib.internal.uisystem_impl : UiSystemImpl`, create
  `auto ui = new UiSystemImpl(null);`, and instantiate
  `auto demoView = new DemoView(ui, tracker, tabsTracker);`.

### 2. Remove `createWithParent` from the 6 Page Controllers
For each of the 6 page controller files:
- `source/guidemo/pages/layout_painter_controller.d`
- `source/guidemo/pages/textlabel_controller.d`
- `source/guidemo/pages/button_controller.d`
- `source/guidemo/pages/button_system_controller.d`
- `source/guidemo/pages/tabcontrol_controller.d`
- `source/guidemo/pages/scrollbars_controller.d`

Make these changes in each file:
- Add `@disable this();` before `this(...)` (in the `public:` section, keeping
  `static createStandalone` where present before `this(...)`).
- Remove `static <Page>Controller createWithParent(...)`.
- Remove unused top-level `import yguilib.widget : Widget;` (it is still
  imported inside `unittest`).
- In `source/guidemo/pages/button_controller.d`, also remove the now-unused
  top-level `import guidemo.hover_button : HoverButtonController;`.

## Verification (Phase 1)
Run style, line-length, and null-safety checks on all modified files:
```bash
rdmd .agents/skills/check-line-length/scripts/check_line_length.d \
  source/guidemo/view.d \
  source/guidemo/pages/layout_painter_controller.d \
  source/guidemo/pages/textlabel_controller.d \
  source/guidemo/pages/button_controller.d \
  source/guidemo/pages/button_system_controller.d \
  source/guidemo/pages/tabcontrol_controller.d \
  source/guidemo/pages/scrollbars_controller.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d \
  source/guidemo/view.d \
  source/guidemo/pages/layout_painter_controller.d \
  source/guidemo/pages/textlabel_controller.d \
  source/guidemo/pages/button_controller.d \
  source/guidemo/pages/button_system_controller.d \
  source/guidemo/pages/tabcontrol_controller.d \
  source/guidemo/pages/scrollbars_controller.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d \
  source/guidemo/view.d \
  source/guidemo/pages/layout_painter_controller.d \
  source/guidemo/pages/textlabel_controller.d \
  source/guidemo/pages/button_controller.d \
  source/guidemo/pages/button_system_controller.d \
  source/guidemo/pages/tabcontrol_controller.d \
  source/guidemo/pages/scrollbars_controller.d
```
