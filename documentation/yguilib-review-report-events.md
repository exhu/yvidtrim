# `yguilib` Events Package Review

```
  date    2026-11-27
  branch  main
  commit  7a96feaa25bba66718bc02d342f18c7c42932731 (fix composite_view after review)
```

Line numbers below refer to that commit.

Scope: `yguilib/source/yguilib/events/` (`package.d`, `builder.d`, `keyboard.d`,
`internal/message_bus.d`, `internal/sdl_events.d`) — 5 modules total.

Paths below are relative to `yguilib/source/yguilib/events/`.
Severity: **H** high, **M** medium, **L** low.

```
  Summary
  -------
  correctness, safety & lifecycle .. 8 findings (2 H, 3 M, 3 L)
  memory allocations & perf ........ 4 findings (0 H, 2 M, 2 L)
  architecture & API design ........ 2 findings (0 H, 1 M, 1 L)
  code reuse & duplication ......... 1 finding  (0 H, 0 M, 1 L)
  codestyle & maintainability ...... 3 findings (0 H, 0 M, 3 L)
  tests & verification gaps ........ 3 findings (0 H, 1 M, 2 L)
  -------------------------------------------------------------
  total ............................ 21 findings (2 H, 7 M, 12 L)
```

Architectural invariants verified: `MessageBus.send()` guards queue/flags/stats
with `synchronized (lock)`, invokes `yguilib_sdl3_send_wake_event()` outside
the lock, never coalesces `mouseMotion` events, and preserves FIFO waypoint
order. Both `internal/` modules use `package(yguilib):` + `private:` with zero
`public` leaks. `check_style.d` warning at `internal/message_bus.d:180`
(`statsEnabled`) is a valid `@property` getter/setter pair.

---

## Module Coverage

| Module | Lines | Role | Findings (`H/M/L`) |
|---|---:|---|---|
| `package.d` | 566 | `AppEvent` tagged-union struct, `Kind`, payloads, factories | `1H / 2M / 3L` |
| `builder.d` | 182 | Fluent `ViewAppEventBuilder` for `Kind.view` events | `0H / 0M / 1L` |
| `keyboard.d` | 7 | Public `Scancode` and `Keycode` aliases from `clibs.sdl3` | `0H / 1M / 0L` |
| `internal/message_bus.d` | 477 | Thread-safe FIFO `RingBuffer`, SDL wake, `noRepeat`, stats | `1H / 3M / 4L` |
| `internal/sdl_events.d` | 347 | Translation from `yguilib_sdl3_Event` to `Nullable!AppEvent` | `0H / 1M / 4L` |

---

## 1. Correctness, Safety & Lifecycle

### 1.1 [H] `AppEvent.~this()` double-invokes `releaseData` on value copies
`package.d:343-351`

`AppEvent` defines a destructor calling `payload.view.releaseData(payload.view)`
without disabling copying or implementing copy semantics. Because `AppEvent` is
passed by value through `sendAppEvent(AppEvent)` -> `MessageBus.send(AppEvent)`
and `dispatchDiscreteEvent(AppEvent)` -> `Controller.handleEvent(AppEvent)`,
any `Kind.view` event with `releaseData` invokes cleanup multiple times
(starting immediately when `sendAppEvent` returns, while still queued).

Fix: `releaseData` is unused in production (only in `builder.d` unittests).
Remove `releaseData` and `~this()` (relying on GC-managed `Object data`), or
require ref-counted wrappers for manually-owned payloads.

### 1.2 [H] `yguilib_sdl3_send_wake_event()` return value ignored after arming `wakeSent`
`internal/message_bus.d:94-103`

`send()` sets `wakeSent = true` under `lock`, then calls
`yguilib_sdl3_send_wake_event()` outside `lock` without checking its return
value (`0` ok, `-1` failure). If pushing the wake fails, `wakeSent` stays
`true` and subsequent background-thread sends skip waking, potentially leaving
the main thread asleep in `SDL_WaitEvent`.

Fix: If `yguilib_sdl3_send_wake_event() != 0`, reset `wakeSent = false` under
`lock` (optionally logging a warning) so subsequent sends retry waking.

### 1.3 [M] `AppEvent.kind` is a `public` mutable field
`package.d:257`

External mutation of `ev.kind` breaks tagged-union safety and enables union
type confusion (including `~this()` reading float bits as pointers).

Fix: Make `fKind` private with a read-only `@property Kind kind() const nothrow @safe`.

### 1.4 [M] `isIdempotentNoRepeatKind` ignores `windowId` for `Kind.windowRedraw`
`internal/message_bus.d:235-245`

Suppresses any `noRepeat` `windowRedraw` whenever `pendingKindCounts[windowRedraw] > 0`,
ignoring `window.windowId`, which would drop redraws for a second window.

Fix: Restrict `isIdempotentNoRepeatKind` to `Kind.update` only, or check
`ev.window.windowId == 0` before taking the count-only fast path.

### 1.5 [M] `makeWindowEvent` `default:` silently maps unknown types to `windowMouseLeave`
`internal/sdl_events.d:84-131`

Adding a window event case in `appEventFromSdlEvent` (`:15-21`) without
updating `makeWindowEvent` silently misclassifies it as `windowMouseLeave`.

Fix: Add explicit `case yguilib_sdl3_EventType.windowMouseLeave:` and
`default: assert(false, "Unexpected window event type");`. Consider
`final switch (sdlEv.type)` in `appEventFromSdlEvent`.

### 1.6 [L] `Thread.getThis().id` null-dereferences on unattached C/OS threads
`internal/message_bus.d:58, 81`

If a non-D-registered thread (e.g., FFmpeg/audio callback) calls `sendAppEvent`
without `thread_attachThis()`, `Thread.getThis()` returns `null`.

Fix: Assert `Thread.getThis() !is null` and document the D-thread requirement.

### 1.7 [L] `windowExposed` drops `sdlEv.window.scale`
`internal/sdl_events.d:101-109`

`yguilib_sdl3.c:45` populates `sdlEv.window.scale` for `windowExposed`, but
`makeWindowEvent` omits it, leaving `scale == 1.0f` on HiDPI displays.

Fix: Pass `sdlEv.window.scale` to `AppEvent.WindowData(...)` and update the
comment in `package.d:105`.

### 1.8 [L] Repeated `build()` on `ViewAppEventBuilder` with `releaseData`
`builder.d:80-82`

Calling `build()` twice produces two `AppEvent`s sharing `releaseData`.

Fix: Resolved if `releaseData` is removed; otherwise clear `viewData.releaseData`
on `build()`.

---

## 2. Memory Allocations & Performance

### 2.1 [M] `AppEvent` size (~96B), union GC scanning, and destructor unwinding
`package.d:243-254, 456-466`

`ViewData` inflates `AppEvent` to ~96 bytes (copied by value on every
`mouseMotion`). Overlapping GC references with POD fields forces conservative
GC scanning, and `~this()` adds destructor unwinding frames on every stack copy.

Fix: Removing `releaseData`/`~this()` eliminates destructor overhead
immediately; passing `const ref AppEvent` through dispatch reduces copy traffic.

### 2.2 [M] Unbounded `RingBuffer` growth with no cap or shrink policy
`internal/message_bus.d:83-93`

`RingBuffer.push()` doubles storage indefinitely under bursts and never shrinks
back to `initialCapacity`.

Fix: Document burst expectations or add a max-capacity / shrink-when-empty
policy.

### 2.3 [L] `tracef()` on every `keyDown` in `appEventFromSdlEvent`
`internal/sdl_events.d:40-47`

`App` configures `LogLevel.trace`, so every key press formats and logs a trace
string.

Fix: Gate behind `debug` or remove once no longer needed.

### 2.4 [L] Dead `if (queue.capacity == 0)` branch on every `send()`
`internal/message_bus.d:83-85`

`MessageBus` reserves `initialCapacity` in `this(Object)` and never calls
`releaseMemory()`, so `queue.capacity` is always `>= 64`.

Fix: Replace with `invariant { assert(queue.capacity > 0); }`.

---

## 3. Architecture, Encapsulation & API Design

### 3.1 [M] `events/keyboard.d` omits `Keymod` while `KeyData.mod` exposes `ushort`
`keyboard.d:1-6`, `package.d:206`

External consumers (`yvidtrim`, `guidemo`) cannot inspect `ev.keyData.mod`
without hardcoding SDL modifier bitmasks because `yguilib.clibs.sdl3` is
`package(yguilib)`.

Fix: Add `alias Keymod = yguilib_sdl3_Keymod;` to `yguilib.events.keyboard`.

### 3.2 [L] `equalsContent()` invokes virtual `opEquals` under `MessageBus` lock
`package.d:428-452`

`payload.user == other.payload.user` and `payload.view == other.payload.view`
call virtual `Object.opEquals` while `MessageBus` holds `synchronized (lock)`.

Fix: Compare references with `is` if identity semantics are intended, or
document value-equality semantics.

---

## 4. Code Reuse & Duplication

### 4.1 [L] `Kind` group predicates duplicated 3x in `AppEvent`
`package.d:50-86, 268-293, 365-390`

Window and mouse `Kind` lists are repeated across predicates, accessors, and
factories.

Fix: Reuse `isWindowEvent()` inside `window()`/`windowEvent()`, and extract a
private `isMousePointerKind(Kind)` helper.

---

## 5. Codestyle & Maintainability

### 5.1 [L] Stale/missing doc comments and minor indentation nits in `package.d`
`package.d:52, 127-128, 235, 239, 246-253, 326, 350`

- `UserData`/`user()` still say `Valid when: Kind.user or Kind.view`.
- `MouseData.state` claims validity for button events, but `sdl_events.d:182`
  always sets `0`.
- `ViewData` nullable reference fields lack nullability docs (`codestyle.md` §3).
- Inconsistent `case` indentation (`:52` vs `:61`) and 4-space indent at `:350`.

### 5.2 [L] `MessageBus` `@property` and `f`-prefix inconsistencies
`internal/message_bus.d:143-153, 293-298, 334, 351`

`length()`/`capacity()` lack `@property` yet unittests omit `()`. Private
stats fields use `f` prefix without clashing with accessor names
(`codestyle.md` §2).

Fix: Mark `length()`/`capacity()` `@property` and drop unnecessary `f` prefixes.

### 5.3 [L] `stringFromCstr` nullability undocumented
`internal/sdl_events.d:148-154`

Accepts and returns `null`; add a brief doc comment (`codestyle.md` §3).

---

## 6. Tests & Verification Gaps

### 6.1 [M] Missing multi-threaded tests and non-idempotent `noRepeat` coverage
`internal/message_bus.d:246-250, 301-477`

All 6 unittests are single-threaded, and the `equalsContent` dedup loop
(`:246-250`) has 0% test coverage because only `Kind.update`/`windowRedraw`
are tested with `noRepeat`.

Fix: Add a multi-producer/single-consumer thread test and a `noRepeat` test for
a non-idempotent event kind (e.g., `Kind.user`).

### 6.2 [L] 1-second wall-clock `Thread.sleep(1050.msecs)` in `MessageBus` unittest
`internal/message_bus.d:456-477`

Adds >1s to every `meson test` run. Support an injectable clock delegate.

### 6.3 [L] Incomplete branch coverage in `sdl_events.d` and `package.d` unittests
`internal/sdl_events.d:210-347`, `package.d:469-566`

Untested: `quit`, `windowClose`, `windowResized`, `windowExposed`,
`mouseButtonUp`, `keyUp`, null C-strings, ignored SDL types, `equalsContent()`,
and `makeNoRepeat()`.

---

## Prioritized Action List

- **High**
  1. Remove `releaseData` / `~this()` from `AppEvent` (`package.d:343-351`).
  2. Check `yguilib_sdl3_send_wake_event()` return value and reset `wakeSent`
     on failure (`internal/message_bus.d:94-103`).
- **Medium**
  3. Make `AppEvent.kind` read-only (`package.d:257`) and export `Keymod` in
     `keyboard.d`.
  4. Tighten `makeWindowEvent` `default:` (`internal/sdl_events.d:84-131`) and
     `isIdempotentNoRepeatKind` (`internal/message_bus.d:235-245`).
  5. Add multi-threaded and non-idempotent `noRepeat` tests for `MessageBus`.
- **Low**
  6. Replace `Thread.sleep(1050.msecs)` with an injectable clock and clean up
     docs/style nits.
