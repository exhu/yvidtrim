# Phase 2: Controller, App Wiring, Build, and Docs

Extract `MainController` into `source/yvidtrim/controller.d`, refactor
`source/yvidtrim/app.d` to construct `ModelTracker!MainModel` and `MainView`
before `MainController`, wire `yvidtrim_test` in `meson.build`, and update
`ARCHITECTURE.md` and `TODO.md`.

## Rules & Conventions
- Adhere to `codestyle.md`: 2-space indent, LF, max 80 chars/line, opening `{`
  on same line, visibility sections (`public:`, `private:`), no default args,
  non-null assertions in constructors, `invariant` blocks.
- Keep `ARCHITECTURE.md` under 250 lines.

## Tasks

### 1. Create `source/yvidtrim/controller.d`
Extract `MainController` into `yvidtrim.controller`:
- `@disable this();`
- `this(UiSystem ui, ref ModelTracker!MainModel otherTracker, MainView view)`
  asserting `ui !is null` and `view !is null`, calling `super(ui)`, and
  attaching `this.t = ModelTracker!MainModel.from(otherTracker)`.
- `invariant { assert(view !is null); }`
- `override bool updateView()`, `override bool update()`, and
  `override HandleResult handleEvent(AppEvent ev)` preserving existing behavior
  (including `super.handleEvent(ev)` fallback).
- Add a headless `unittest` block using `UiSystemImpl(null)` verifying:
  - `handleEvent` on `Keycode.a` (`AppEvent.Kind.keyUp`) sets `aPressed`,
    returns `HandleResult(HandleResult.Result.update, true)`, and `update()`
    advances `alignItems` and clears `aPressed`.
  - `updateView()` calls `view.update()` and updates the view's container
    `FlexContainer.alignItems`.
  - `handleEvent` on `Keycode.q` sets `qPressed` and returns `Result.update`.
  - Unhandled events delegate to `super.handleEvent(ev)`.

### 2. Refactor `source/yvidtrim/app.d`
Update `source/yvidtrim/app.d` to keep only `main()`:
```d
module yvidtrim.app;

import yguilib.app : App;
import yguilib.model : ModelTracker;
import yvidtrim.controller : MainController;
import yvidtrim.model : MainModel;
import yvidtrim.view : MainView;

void main() {
  // TODO parse cmdline arguments
  auto app = App.makeAppWithTitleWh("yvidtrim", 1280, 720);
  auto tracker = ModelTracker!MainModel(new MainModel());
  auto view = new MainView(app.ui, tracker);
  app.ui.mainWindow().rootWidget = view.rootWidget();
  auto controller = new MainController(app.ui, tracker, view);
  app.run(controller);
}
```

### 3. Update `meson.build`
Split `yvidtrim_src` into `yvidtrim_lib_src` + `source/yvidtrim/app.d` and add
the `yvidtrim_test` executable and test target:
- `yvidtrim_lib_src` contains `clibs/sdl3.d`, `controller.d`, `model.d`,
  `uitree/mainview.d`, `view.d`.
- `yvidtrim_test_exe` builds `yvidtrim_lib_src + files('source/yvidtrim/test_main.d')`
  with `d_unittest : true`, `include_directories : yvidtrim_inc`,
  `d_import_dirs : yvidtrim_inc`, `dependencies : [yguilib_dep, yvidtrim_sdl3_dep]`.
- `test('yvidtrim_test', yvidtrim_test_exe)`.

### 4. Update `ARCHITECTURE.md` and `TODO.md`
- In `ARCHITECTURE.md`, update the `source/yvidtrim/` directory listing to
  include `app.d`, `controller.d`, `model.d`, `view.d`, `uitree/`, and
  `clibs/sdl3.d`. Verify total line count stays under 250 lines.
- In `TODO.md`, update the first item to note that view-controller separation
  is implemented for `source/yvidtrim` and remains to be applied to
  `source/guidemo` (`DemoController`/`DemoView`).

## Verification (Phase 2)
Run full build, test suite, and all verification scripts:
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d --audit
```
