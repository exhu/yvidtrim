# Fix `sendUpdate()` in `update()` Across `guidemo`

Remove erroneous `sendUpdate()` calls inside `Controller.update()` across all
seven page controllers in `source/guidemo/pages/`, eliminate redundant
`sendUpdate()` calls in `DemoController.handleEvent()`, and ensure
`DemoController` updates `DemoView` in the same frame by positioning it below
the page controllers on `ControllerStack`.

## Target Data Flow

```
Before (2-frame cascade):
  ControllerStack: [Controls..., PageCtrls..., DemoController, UiSystemCtrl]
  Phase 2a (top->bottom):
    1. DemoController.update()  -> misses PageCtrl's statusText edit
    2. PageCtrl.update()        -> syncPageStatus() + sendUpdate() -> Frame 2!

After (1-frame sync, 0 sendUpdate()):
  ControllerStack: [Controls..., DemoController, PageCtrls..., UiSystemCtrl]
  Phase 2a (top->bottom):
    1. PageCtrl.update()        -> syncPageStatus() + demoTracker.update()
    2. DemoController.update()  -> sees statusText edit immediately
  Phase 3:
    DemoController.updateView() + PageCtrl.updateView() in same frame
```

## Phases

- Phase 1: [guidemo-send-update-ph01.md](guidemo-send-update-ph01.md)
  - Update `DemoController` (`source/guidemo/controller.d`) to return
    `HandleResult.Result.update` instead of `Result.updateView` +
    `sendUpdate()`.
  - Update `source/guidemo/guidemoapp.d` to push `DemoController` before
    `registerDemoPages(...)`, call initial `demoView.update()`, run
    `app.ui.mainEventLoop()`, and pop pushed controllers cleanly on exit.
- Phase 2: [guidemo-send-update-ph02.md](guidemo-send-update-ph02.md)
  - Remove `if (statusChanged) { sendUpdate(); }` from `update()` across all 7
    page controllers in `source/guidemo/pages/` and sync `demoTracker` /
    `tracker` after self-commits.
  - Add headless regression tests and remove the completed first item from
    `TODO.md`.
