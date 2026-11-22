# Phase 2: Remove `sendUpdate()` from Page Controllers and Update `TODO.md`

Remove `if (statusChanged) { sendUpdate(); }` from `update()` in all 7 page
controllers under `source/guidemo/pages/` and keep each controller's own
`ModelTracker` synchronized after self-commits.

## Steps

1. Update `update()` in:
   - `source/guidemo/pages/button_controller.d`
   - `source/guidemo/pages/button_system_controller.d`
   - `source/guidemo/pages/layout_painter_controller.d`
   - `source/guidemo/pages/scrollbars_controller.d`
   - `source/guidemo/pages/tabcontrol_controller.d`
   - `source/guidemo/pages/textlabel_controller.d`
   Remove `if (statusChanged) { sendUpdate(); }` and add
   `if (statusChanged) { demoTracker.update(); }` so self-commits do not leave
   `demoTracker.lastSeenVersion` stale.
2. Update `source/guidemo/pages/virtlist_controller.d`:
   - Move `tracker.update()` after `page.syncTelemetry()` so telemetry commits
     do not leave `tracker.lastSeenVersion` stale.
   - Remove `if (statusChanged) { sendUpdate(); }` and add
     `if (statusChanged) { demoTracker.update(); }`.
3. Add headless unit test assertions verifying:
   - `ctrl.update()` enqueues no pending events (`!ui.hasPendingAppEvents()`).
   - A second consecutive `ctrl.update()` returns `false`.
   - End-to-end single `UiSystemImpl.runEventLoopStep()` updates both page
     content and `DemoView`'s `statusLabel` when `DemoController` is pushed
     below `ButtonPageController`.
4. Remove the completed first item from `TODO.md`.

## Verification

```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
```
