# ph03: `controller` Stack Safety, Encapsulation & Tests (`controller` 1.1-6.2)

Overview: `plans/yguilib-review-fixes.md`.
Review: `documentation/yguilib-review-report-controller.md` (commit `7a96feaa`).
Paths below are relative to `yguilib/source/yguilib/`.

Goal: Address all 11 findings (2H, 5M, 4L) in `controller/`. Full modal
event-blocking / multi-layer suspension rules remain deferred to `TODO.md`.

## Files

- `controller/package.d`, `controller/internal/controller_stack.d`
- `internal/uisystem_impl.d` (callers of `ControllerStackStorage`)
- `DefaultController` subclasses in `controls/` and `source/guidemo/` if
  any assign `uiSystem` directly or call `modal(bool)`

## Steps

1. **Snapshot `opApply` & safe slice access (`1.2`, `3.3`)**:
   - In `controller/internal/controller_stack.d`, snapshot stack entries into
     a local `SmallBuffer!(Controller, 16)` inside `opApply` before iterating.
   - Replace mutable `controllers()` slice with `void snapshot(ref
     SmallBuffer!(Controller, 16) dst) const` (update `uisystem_impl.d`).
2. **Modal state, re-entrancy & duplicate-push (`1.1`, `3.1`, `3.2`, `3.4`)**:
   - Rename internal `ControllerStack` struct to `ControllerStackStorage`
     (updating `uisystem_impl.d` selective import).
   - Store `struct StackEntry { Controller ctrl; bool isModal; Controller
     suspendedTarget; }`.
   - Guard re-entrant `push`/`pushModal`/`pop` during lifecycle callbacks
     (`bool inTransition` assert), push entry before `onPush()`, and on
     `pop()` resume the exact `suspendedTarget` if still on stack.
   - Add `assert(!contains(c))` in `push()` and `pushModal()`.
   - Remove public `Controller.modal(bool)` setter (or mark
     `package(yguilib):`), keeping read-only `@property bool modal() const`.
   - Document that modal event-blocking relies on `HandleResult.consume`
     (full modal barrier deferred to `TODO.md`).
3. **Encapsulate `DefaultController.uiSystem` (`1.3`)**:
   - Make `private UiSystem fUiSystem;` with `protected UiSystem uiSystem()`.
   - Add `invariant { assert(fUiSystem !is null); }` and remove redundant
     `uiSystem is null` checks in `startTimer()`/`stopTimer()`.
   - Update any subclass access that fails with `uiSystem()` getter.
4. **Codestyle (`5.1`, `5.2`)**:
   - Document nullable return on `activeOrNull()`.
   - Add braces to `DefaultController.handleEvent` `if`s and blank lines
     between consecutive methods.
5. **Tests (`6.1`, `6.2`)**:
   - Add `unittest` block in `controller/package.d` testing
     `DefaultController` fallbacks, `HandleResult` helpers, and timers.
   - Expand `controller_stack.d` unittests: empty `pop`, non-modal
     `push`+`pop`, `pushModal` on empty stack, nested modals, `opApply`
     order + early `break`, `opIndex`, and duplicate/re-entrancy guards.

## Verification

- `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`
