# Phase 2: `DemoController`, `guidemoapp.d`, and `TODO.md`

Refactor `DemoController` to accept `DemoControllerParams` (removing `App` and
internal `DemoView` instantiation), update `guidemoapp.d` to create `DemoView`
and all 6 page views before their controllers, and remove the completed first
item from `TODO.md`.

## Rules & Conventions
- Adhere to `codestyle.md`: 2-space indent, LF, max 80 chars/line, opening `{`
  on same line, visibility sections (`public:`, `private:`), no default args,
  no consecutive caps, non-null assertions in constructors, `invariant` blocks,
  functions `<= 50` lines.

## Tasks

### 1. Update `source/guidemo/controller.d`
- Replace `import yguilib.app : App;` with `import yguilib.uisystem : UiSystem;`.
- Update the `guidemo.view` import to remove `createHeaderTabsModel` from the
  module top-level import (move `createHeaderTabsModel` into `unittest`).
- Define `DemoControllerParams` struct before `DemoController`:
  ```d
  /// Parameters for constructing DemoController.
  struct DemoControllerParams {
    UiSystem ui;
    ModelTracker!DemoModel tracker;
    DemoView view;
    ModelTracker!TabsModel tabsTracker;

    ref DemoControllerParams withUi(UiSystem ui) return {
      this.ui = ui;
      return this;
    }

    ref DemoControllerParams withTracker(
      ref ModelTracker!DemoModel otherTracker
    ) return {
      this.tracker = ModelTracker!DemoModel.from(otherTracker);
      return this;
    }

    ref DemoControllerParams withView(DemoView view) return {
      this.view = view;
      return this;
    }

    ref DemoControllerParams withTabsTracker(
      ref ModelTracker!TabsModel otherTabsTracker
    ) return {
      this.tabsTracker = ModelTracker!TabsModel.from(otherTabsTracker);
      return this;
    }
  }
  ```
- Refactor `DemoController`:
  - Remove `App app;` field.
  - Add `@disable this();`.
  - Replace `this(App app)` with:
    ```d
    this(ref DemoControllerParams params) {
      assert(params.ui !is null, "UiSystem must not be null");
      assert(params.view !is null, "DemoView must not be null");
      super(params.ui);
      this.view = params.view;
      this.tracker = ModelTracker!DemoModel.from(params.tracker);
      this.tabsTracker = ModelTracker!TabsModel.from(params.tabsTracker);
    }

    invariant {
      assert(view !is null);
    }
    ```
  - Keep `getTracker()` and `getView()` if needed, or remove unused ones only
    if nothing calls them (check `source/guidemo/` first).
- Convert `unittest` in `source/guidemo/controller.d` to headless mode using
  `yguilib.internal.uisystem_impl : UiSystemImpl` (`new UiSystemImpl(null)`),
  creating `demoTracker`, `tabsTracker`, and `demoView` externally and passing
  them via `DemoControllerParams` to `new DemoController(params)`. Keep all
  existing behavioral assertions (unrelated events, `headerTabSwitchEvent`,
  F12 `DebugDrawMode` cycling, `Keycode.key6`).

### 2. Update `source/guidemo/guidemoapp.d`
- Import `createHeaderTabsModel`, `DemoModel`, `ModelTracker`, `TabsModel`,
  `DemoControllerParams`, `DemoView`, `UiSystem`, `Widget`, and the 6 page
  classes (`LayoutPainterPage`, `TextLabelPage`, `ButtonPage`,
  `ButtonSystemPage`, `TabControlPage`, `ScrollbarsPage`).
- In `main()`:
  1. Create `app`, register `AnimatedHoverButtonSystem`, `tabControlController`,
     `scrollbarController`, and `hoverButtonController`.
  2. Create `demoTracker = ModelTracker!DemoModel(new DemoModel())` and
     `tabsTracker = ModelTracker!TabsModel(createHeaderTabsModel())`.
  3. Create `demoView = new DemoView(app.ui, demoTracker, tabsTracker)`.
  4. Get `rootWidget = demoView.getRootWidget()` and assign
     `app.ui.mainWindow().rootWidget = rootWidget`.
  5. Build `DemoControllerParams` and create
     `demoController = new DemoController(params)`.
  6. Call `registerDemoPages(app.ui, demoTracker, rootWidget,
     hoverButtonController)`.
  7. Log tree info and run `app.run(demoController)`.
- Extract helper `registerDemoPages(...)` (keeping both `main` and
  `registerDemoPages` <= 50 lines) that constructs each `*Page` view before
  pushing its `*PageController`:
  - `new LayoutPainterPage(ui, rootWidget)` -> `new LayoutPainterPageController(...)`
  - `new TextLabelPage(ui, rootWidget)` -> `new TextLabelPageController(...)`
  - `auto buttonPage = new ButtonPage(ui, rootWidget); buttonPage.registerWithController(hoverButtonController);` -> `new ButtonPageController(...)`
  - `new ButtonSystemPage(ui, rootWidget)` -> `new ButtonSystemPageController(...)`
  - `new TabControlPage(ui, rootWidget, ui)` -> `new TabControlPageController(...)`
  - `new ScrollbarsPage(ui, rootWidget, ui)` -> `new ScrollbarsPageController(...)`

### 3. Update `TODO.md`
- Remove the completed first item (the view-controller separation bullet at
  lines 1-4 of `TODO.md`).

## Verification (Phase 2)
Run full build, test suite, and all repository verification scripts:
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d --audit
```
