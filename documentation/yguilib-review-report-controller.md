# `yguilib` Controller Package Review

```
  date    2026-11-27
  branch  main
  commit  7a96feaa25bba66718bc02d342f18c7c42932731 (fix composite_view after review)
```

Line numbers below refer to that commit.

Scope: `yguilib/source/yguilib/controller/` (`package.d` and
`internal/controller_stack.d`) — 2 modules total.

Paths below are relative to `yguilib/source/yguilib/controller/`.
Severity: **H** high, **M** medium, **L** low.

```
  Summary
  -------
  correctness, safety & lifecycle .. 3 findings (2 H, 1 M, 0 L)
  memory allocations & perf ........ 0 findings
  architecture & API design ........ 4 findings (0 H, 2 M, 2 L)
  code reuse & duplication ......... 0 findings
  codestyle & maintainability ...... 2 findings (0 H, 0 M, 2 L)
  tests & verification gaps ........ 2 findings (0 H, 2 M, 0 L)
  -------------------------------------------------------------
  total ............................ 11 findings (2 H, 5 M, 4 L)
```

Static baseline note: `internal/controller_stack.d` properly uses
`package(yguilib):` + `private:` with zero `public` leaks. `check_style.d`
warnings at `package.d:61,110` (`modal`) are false positives for a valid
`@property` getter/setter pair (`codestyle.md` §2).

---

## Module Coverage

| Module | Lines | Role | Findings (`H/M/L`) |
|---|---:|---|---|
| `package.d` | 153 | `Controller` interface, `HandleResult`, `DefaultController` | `0H / 3M / 1L` |
| `internal/controller_stack.d` | 176 | LIFO `ControllerStack` storage & modal lifecycle transitions | `2H / 2M / 3L` |

---

## 1. Correctness, Safety & Lifecycle

### 1.1 [H] Re-entrancy hazard in `pushModal()` / `pop()` and single-layer suspension
`internal/controller_stack.d:16-39`

- In `pushModal()` (`:19-24`), `active.onSuspendByModal()` runs **before**
  `stack.push(c)`. If `onSuspendByModal()` pushes or pops controllers, `c` is
  pushed onto a different controller that was never suspended.
- In `pop()` (`:32-38`), `active.onPop()` runs **before** re-fetching
  `active = activeOrNull()`. If `onPop()` pushes a new controller `c3`, `pop()`
  calls `c3.onResumeByModal()` while leaving the originally suspended
  controller unresumed.
- `pushModal()` also suspends only the single top controller, not any other
  active non-modal controllers beneath it.

Fix: Guard re-entrant stack mutations during lifecycle callbacks (or record the
suspended target per entry), and clarify/enforce whether modal suspension
applies down to the previous modal barrier or strictly to the predecessor.

### 1.2 [H] `ControllerStack.opApply` iterates a live backing slice without snapshot
`internal/controller_stack.d:65-72`

`foreach (c; stack[])` iterates `ReusableArray!Controller`'s live slice. If a
callback (e.g., `UiSystemImpl.releaseWidget` calling `onWidgetReleased`) pops a
controller, `ReusableArray.popBack()` nulls the tail slot in-place, yielding
`null` to subsequent iterations; `push()` can reallocate the backing buffer.

Fix: Snapshot `stack[]` into a local `SmallBuffer!(Controller, 16)` inside
`opApply` before iterating (zero GC allocation for typical stack depths).

### 1.3 [M] Inconsistent `uiSystem` null handling and missing `invariant`
`package.d:72-77, 117-119, 132-149`

`DefaultController` asserts `uiSystem !is null` in `this(UiSystem)` and
disables default construction, yet lacks `invariant { assert(uiSystem !is null); }`
(`codestyle.md` §3), scatters defensive null checks in `startTimer()`/`:136`
and `stopTimer()`/`:143`, dereferences `uiSystem` unconditionally in
`sendAppEvent()`/`:118`, and exposes `uiSystem` as a mutable `protected` field
(`:149`).

Fix: Add `invariant { assert(fUiSystem !is null); }`, make the field
`private UiSystem fUiSystem;` with a `protected UiSystem uiSystem()` getter,
and remove redundant null checks.

---

## 2. Memory Allocations & Performance

No issues found. `ControllerStack` uses `ReusableArray!Controller` (zero
steady-state GC allocations on `push`/`pop`, and clears popped reference slots).

---

## 3. Architecture, Encapsulation & API Design

### 3.1 [M] Public mutable `Controller.modal(bool)` setter can desynchronize `ControllerStack`
`package.d:60-61, 107-112`

Any caller can toggle `c.modal` while `c` is on `ControllerStack`. Because
`pop()` (`internal/controller_stack.d:32`) inspects `active.modal` to decide
whether to call `onResumeByModal()`, external mutation causes missed or
spurious resume callbacks.

Fix: Track `bool isModal` per entry inside `ControllerStack` as the source of
truth, and restrict `modal(bool)` to `package(yguilib)` or remove the public
setter.

### 3.2 [M] No modal dispatch barrier or duplicate-push guard
`internal/controller_stack.d:8-76`

Neither `ControllerStack` nor `UiSystemImpl` enforces modal event/update
blocking (`c.modal` is never checked during top-to-bottom dispatch). Also,
`push()`/`pushModal()` do not assert `!stack.contains(c)`, allowing duplicate
stacking of the same instance.

Fix: Add `assert(!stack.contains(c))` in `push()`/`pushModal()`, and either add
a modal-bounded snapshot helper or document that modal blocking relies on
`HandleResult.consume`.

### 3.3 [L] `controllers()` returns a mutable live slice
`internal/controller_stack.d:56-58`

`inout(Controller[]) controllers() inout` allows `package(yguilib)` callers to
mutate backing slots directly.

Fix: Prefer a `snapshot(ref SmallBuffer!(Controller, 16))` helper or document
the slice as read-only until the next mutation.

### 3.4 [L] Name collision with public `yguilib.uisystem.ControllerStack`
`internal/controller_stack.d:8`

Shares its name with public `interface ControllerStack` (`uisystem.d:16`),
relying on selective-import shadowing in `uisystem_impl.d`.

Fix: Consider renaming the internal struct to `ControllerStackStorage` if
touching callers.

---

## 4. Code Reuse & Duplication

No issues found.

---

## 5. Codestyle & Maintainability

### 5.1 [L] Missing nullable-return doc comment on `activeOrNull()`
`internal/controller_stack.d:41-46`

`codestyle.md` §3 requires documenting nullable return values.

Fix: Add `/// Returns the top controller, or null if the stack is empty.`.

### 5.2 [L] Minor formatting inconsistencies in `DefaultController`
`package.d:87-113`

Braceless `if` statements in `handleEvent` (`:88-92`) and missing blank lines
between consecutive method declarations (`:95-113`).

Fix: Add braces to `if` statements and blank lines between methods.

---

## 6. Tests & Verification Gaps

### 6.1 [M] No unit tests for `DefaultController` or `HandleResult`
`package.d:1-153`

Zero `unittest` blocks in `controller/package.d`. `DefaultController.handleEvent`
fallback (`windowClose`/`appQuit` -> `quit`, redraw -> `updateView`),
`startTimer`/`stopTimer`, `sendUpdate`/`sendQuit`, and `HandleResult` helpers
are untested directly.

Fix: Add a `unittest` block exercising `DefaultController` and `HandleResult`.

### 6.2 [M] Incomplete `ControllerStack` edge-case coverage
`internal/controller_stack.d:79-176`

Only `push(c1)` -> `pushModal(c2)` -> `pop()` -> `pop()` is tested. Missing:
`pop()` on empty stack, non-modal `push`+`pop`, `pushModal()` on empty stack,
nested modals, `opApply` order + early `break`, `opIndex`, and re-entrancy.

Fix: Expand `controller_stack.d` unittests to cover these edge cases.

---

## Prioritized Action List

- **High**
  1. Snapshot `stack[]` into `SmallBuffer` inside `ControllerStack.opApply`
     (`internal/controller_stack.d:65-72`).
  2. Guard re-entrancy in `pushModal()`/`pop()` and store modal state per stack
     entry (`internal/controller_stack.d:16-39`).
- **Medium**
  3. Add `invariant` and encapsulate `uiSystem` in `DefaultController`
     (`package.d:72-149`); add duplicate-push guard.
  4. Add unit tests for `package.d` and expand `controller_stack.d` edge cases.
- **Low**
  5. Document `activeOrNull()` nullability and clean up formatting.
