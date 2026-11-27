# ph10: `widget` `InputSystem` Reliability (`widget` 1.5-1.7, 1.17, 3.1, 4.1-4.2, 5.2, 6.1)

Overview: `plans/yguilib-review-fixes.md`.
Review: `documentation/yguilib-review-report-widget.md` (commit `7a96feaa`).
Paths below are relative to `yguilib/source/yguilib/widget/`.

Goal: Fix all cursor-capture/lock, hover, disable, hide, and cleanup bugs
in `internal/input_system.d` and add regression tests.

## Files

- `internal/input_system.d`

## Steps

1. **Cursor lock & `postLayout` (`1.5`)**:
   - Return early in `refreshHover` when `hasCursorLock` is `true` so layout
     changes during locked drags do not fire spurious hover events.
   - Call `syncCursorCapture()` in `postLayout` so disabling or hiding a
     pressed widget while stationary releases SDL capture/lock.
2. **Disable & visibility hygiene (`1.6`, `1.7`)**:
   - In `notifyDepartedWidgets`, guard with
     `entry.widget.inputEnabled && !entry.widget.released`.
   - Check `isEffectivelyVisible(w)` in `syncCursorCapture`,
     `dispatchMouseDrag`, and `handleMouseUp`.
   - Null stale `pressedWidgets[i]` in `dispatchMouseDrag` so re-enabled
     widgets cannot revive an aborted press.
   - Override `onWindowClosed` and `onUnregister` to clear pressed/hovered
     state and call `syncCursorCapture()`.
3. **Locked press & hover bubbling (`1.17`)**:
   - In `handleMouseDown`, do not hit-test raw relative coordinates or
     overwrite `lastPressPos` while `hasCursorLock` is active.
   - In `collectHovered`, stop bubbling hover to ancestors with
     `handleInput == false`.
4. **Cleanup & reuse (`3.1`, `4.1`, `4.2`, `5.2`)**:
   - Remove dead duplicate `FocusSystem` and shadowed `host` field (`3.1`).
   - Use `VisibleWidget.containsPoint` (`4.2`) and `MockWidgetSystemHost`
     from `test_fixture.d` (`4.1`).
   - Prune unused module imports (`5.2`).
5. **Regression tests (`6.1`)**:
   - Add tests for: disable-while-hovered, hide-while-captured/locked,
     `postLayout` while locked, secondary press while locked, and
     `onWindowClosed`/`onUnregister` capture release.

## Verification

- `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`
