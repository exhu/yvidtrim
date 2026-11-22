# Phase 2: Parameterless `App.run()`, Caller Migration, and `TODO.md`

Change `App.run()` to parameterless `void run()`, migrate all applications and
tests to use `app.withRootWidget(...)` and `app.run()`, and update `AGENTS.md`
and `TODO.md`.

## Steps

1. Update `yguilib/source/yguilib/app.d`:
   - Remove `import yguilib.controller : Controller;`.
   - Update the class docstring example to use `app.withRootWidget(...)`,
     `app.ui.pushController(...)`, and `app.run()`.
   - Replace `void run(Controller mainController)` with:
     ```d
     /// Runs the application main event loop. Push controllers via
     /// `ui.pushController(...)` before calling `run()`.
     void run() {
       ui.mainEventLoop();
     }
     ```
2. Update `source/guidemo/guidemoapp.d`:
   - Replace `app.ui.mainWindow().rootWidget = rootWidget;` with
     `app.withRootWidget(rootWidget);`.
   - Remove `scope (exit) app.ui.popController();` after
     `app.ui.pushController(demoController);`.
   - Change `registerDemoPages(...)` return type from `size_t` to `void` and
     remove the `pushedCount` counter and `scope (exit)` pop loop in `main()`.
   - Replace `app.ui.mainEventLoop();` with `app.run();`.
3. Update `source/yvidtrim/app.d`:
   - Replace `app.ui.mainWindow().rootWidget = view.rootWidget();` with
     `app.withRootWidget(view.rootWidget());`.
   - Push `controller` via `app.ui.pushController(controller);` and call
     `app.run();`.
4. Update `yguilib/examples/helloworld/app.d`:
   - Replace `app.ui.mainWindow().rootWidget = view.rootWidget();` with
     `app.withRootWidget(view.rootWidget());`.
   - Push `controller` via `app.ui.pushController(controller);` before
     `view.update();` and call `app.run();`.
5. Update `yguilib/source/yguilib/controls/virtlist.d`:
   - In `runVirtListPipelineTest()`, replace
     `ui.mainWindow().rootWidget = vlRoot;` with `app.withRootWidget(vlRoot);`.
   - Replace `app.run(testCtrl);` with `ui.pushController(testCtrl);` followed
     by `app.run();`.
6. Update `source/guidemo/pages/button_controller.d`:
   - In the end-to-end `App` `unittest`, replace
     `ui.mainWindow().rootWidget = root;` with `app.withRootWidget(root);`.
   - Remove `scope (exit) ui.popController();` lines.
   - Replace `app.run(harness);` with `ui.pushController(harness);` followed by
     `app.run();`.
7. Update `source/guidemo/pages/virtlist_controller.d`:
   - In the end-to-end `App` `unittest`, replace
     `ui.mainWindow().rootWidget = root;` with `app.withRootWidget(root);`.
   - Replace `app.run(harness);` with `ui.pushController(harness);` followed by
     `app.run();`.
8. Update `AGENTS.md` and `TODO.md`:
   - In `AGENTS.md` line 53, replace
     `app.ui.mainWindow().rootWidget = view.rootWidget()` with
     `app.withRootWidget(view.rootWidget())`.
   - Remove the completed first item (lines 1-3) from `TODO.md`.

## Verification

```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
```
