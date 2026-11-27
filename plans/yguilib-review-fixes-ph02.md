# ph02: `events` Lifecycle, Wake Reliability & API (`events` 1.1-6.3)

Overview: `plans/yguilib-review-fixes.md`.
Review: `documentation/yguilib-review-report-events.md` (commit `7a96feaa`).
Paths below are relative to `yguilib/source/yguilib/`.

Goal: Address all 21 findings (2H, 7M, 12L) in `events/`.

## Files

- `events/package.d`, `events/builder.d`, `events/keyboard.d`
- `events/internal/message_bus.d`, `events/internal/sdl_events.d`
- `controls/button.d` (unittest update for read-only `AppEvent.kind`)

## Steps

1. **Remove `releaseData` and `AppEvent.~this()` (`1.1`, `1.8`, `2.1`)**:
   - Remove `ViewData.releaseData`, `ViewAppEventBuilder.withReleaseData`,
     and `AppEvent.~this()` in `events/package.d` and `events/builder.d`.
   - Update `events/builder.d` unittests accordingly.
2. **Wake failure recovery (`1.2`)**:
   - In `MessageBus.send()`, check `if (yguilib_sdl3_send_wake_event() != 0)`
     outside `lock`, then re-acquire `synchronized (lock)` to reset
     `wakeSent = false` and log a warning.
3. **Read-only `AppEvent.kind` (`1.3`)**:
   - Rename `kind` field to `private Kind fKind;` and expose
     `@property Kind kind() const nothrow @safe`.
   - Search for `.kind =` across the repo (`search_code.d`) and update
     `controls/button.d` unittest to use `AppEvent` factories/ctors.
4. **`MessageBus` & `sdl_events` correctness (`1.4`, `1.5`, `1.6`, `1.7`)**:
   - Restrict `isIdempotentNoRepeatKind` to `Kind.update` (or check
     `ev.window.windowId == 0` for `windowRedraw`).
   - In `makeWindowEvent`, add explicit `case
     yguilib_sdl3_EventType.windowMouseLeave:` and `default: assert(false,
     "Unexpected window event type");`; consider `final switch` in
     `appEventFromSdlEvent`.
   - Pass `sdlEv.window.scale` for `windowExposed` and update `package.d`
     comment.
   - Assert `Thread.getThis() !is null` in `MessageBus` and document the
     D-attached thread requirement.
5. **Memory & perf (`2.2`, `2.3`, `2.4`)**:
   - Add a shrink-when-empty policy in `MessageBus.drain()` when capacity
     exceeds a burst threshold (e.g. `> 4 * initialCapacity`).
   - Gate `keyDown` `tracef` in `sdl_events.d` behind `debug`.
   - Replace dead `if (queue.capacity == 0)` in `MessageBus.send()` with
     `invariant { assert(queue.capacity > 0); }`.
6. **API, reuse & codestyle (`3.1`, `3.2`, `4.1`, `5.1`-`5.3`)**:
   - Export `alias Keymod = yguilib_sdl3_Keymod;` in `events/keyboard.d`.
   - Compare `Object` refs with `is` in `equalsContent()` (or document
     value-equality semantics).
   - Deduplicate `Kind` group predicates (`isWindowEvent()`,
     `isMousePointerKind(Kind)`).
   - Fix stale docstrings (`UserData`, `MouseData.state`, `ViewData`
     nullability, `stringFromCstr` nullability), `case`/4-space indents,
     `@property` on `length()`/`capacity()`, and unnecessary `f` prefixes.
7. **Tests (`6.1`, `6.2`, `6.3`)**:
   - Add injectable clock delegate to `MessageBus` replacing
     `Thread.sleep(1050.msecs)`.
   - Add multi-producer/single-consumer thread test, non-idempotent
     `noRepeat` (`Kind.user`) test, and missing `sdl_events.d`/`package.d`
     branch tests.

## Verification

- `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`
