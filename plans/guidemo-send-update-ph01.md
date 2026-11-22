# Phase 1: `DemoController` and `guidemoapp.d` Stack Ordering

Ensure `DemoController` sits below the 7 page controllers on `ControllerStack`
and uses `HandleResult.Result.update` instead of `Result.updateView` +
`sendUpdate()`.

## Steps

1. Update `source/guidemo/controller.d`:
   - In `handleEvent()`, return
     `HandleResult(HandleResult.Result.update, false)` for
     `handleHeaderTabEvent` and `HandleResult(HandleResult.Result.update, true)`
     for `handleGlobalKeyDown`.
   - Remove `sendUpdate()` calls from `handleHeaderTabEvent` and
     `handleGlobalKeyDown`.
   - Update `DemoController` unit tests to assert `HandleResult.Result.update`,
     verify `demoCtrl.update()`, and verify `!ui.hasPendingAppEvents()`.
2. Update `source/guidemo/guidemoapp.d`:
   - Push `demoController` onto `app.ui` before `registerDemoPages(...)` and
     pop it on `scope (exit)`.
   - Return the pushed controller count from `registerDemoPages(...)` and pop
     all pushed page controllers in `scope (exit)` (LIFO order).
   - Call `demoView.update()` once before `app.ui.mainEventLoop()` so initial
     render shows Page 1's status text.

## Verification

```bash
ninja -C _build && meson test -C _build
```
