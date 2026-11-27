# `yguilib` Core Package Review

```
  date    2026-11-27
  branch  main
  commit  7a96feaa25bba66718bc02d342f18c7c42932731 (fix composite_view after review)
```

Line numbers below refer to that commit.

Scope: root `yguilib/source/yguilib/*.d` (11 modules) and
`yguilib/source/yguilib/internal/*.d` (7 modules) — 18 modules total.

Paths below are relative to `yguilib/source/yguilib/`.
Severity: **H** high, **M** medium, **L** low.

```
  Summary
  -------
  correctness, safety & lifecycle .. 22 findings (3 H, 12 M, 7 L)
  memory allocations & perf ........  6 findings (0 H,  1 M, 5 L)
  architecture & API design ........ 12 findings (1 H,  4 M, 7 L)
  code reuse & duplication .........  2 findings (0 H,  0 M, 2 L)
  codestyle & maintainability ...... 10 findings (0 H,  1 M, 9 L)
  tests & verification gaps ........  9 findings (0 H,  3 M, 6 L)
  ---------------------------------------------------------------
  total ............................ 61 findings (4 H, 21 M, 36 L)
```

Static baseline note: `check_boundaries.d` and `check_null_safety.d` reported
0 errors. `check_style.d` flagged property getter/setter pairs in
`uisystem.d:52`, `timers.d:71,79`, `window.d:47,226`, and
`internal/uisystem_impl.d:98` (all valid per `codestyle.md` §2), plus dead
private getter/setter pairs at `internal/uisystem_impl.d:548,562` (see 3.2).

---

## Module Coverage

| Module | Lines | Role | Findings (`H/M/L`) |
|---|---:|---|---|
| `allochelpers.d` | 1,468 | `SmallBuffer`, `RingBuffer`, `ReusableArray` containers | `0H / 1M / 4L` |
| `app.d` | 68 | Top-level `App` facade launching `mainEventLoop` | `0H / 0M / 3L` |
| `assets.d` | 7 | Embedded default TTF font (`defaultTtfFontData`) | `0H / 0M / 1L` |
| `model.d` | 90 | `VersionedModel` and `ModelTracker!T` state tracking | `0H / 3M / 1L` |
| `object_registry.d` | 130 | Named class/interface lookup (`ObjectRegistry!T`) | `0H / 1M / 3L` |
| `serhelpers.d` | 218 | Reflection JSON serialization and `shortTypeName` | `0H / 3M / 3L` |
| `texthelpers.d` | 27 | Human-readable byte formatting (`formatBytes`) | `0H / 0M / 1L` |
| `timercontrol.d` | 46 | `TimerControl` interface and `TimerId` alias | `0H / 1M / 0L` |
| `timers.d` | 446 | `AnimationTimer`, `StopWatchNs`, `Timer`, `DeltaTimer` | `0H / 3M / 4L` |
| `uisystem.d` | 68 | `UiSystem` and sub-interfaces (`ControllerStack`, etc.) | `0H / 1M / 1L` |
| `window.d` | 368 | SDL3 + GLES3 `Window` wrapper, scaling, screenshot | `1H / 3M / 2L` |
| `internal/assets.d` | 55 | Embedded GLSL shader string imports & `#define MASK` | `0H / 0M / 1L` |
| `internal/logger.d` | 55 | `SdlLogger` forwarding `std.logger` to SDL3 | `0H / 1M / 1L` |
| `internal/memstats.d` | 194 | Optional `version(MemTelemetry)` texture/heap stats | `0H / 2M / 1L` |
| `internal/test_main.d` | 7 | Shared empty `version(unittest) void main()` | Clean |
| `internal/timer_service.d` | 424 | Owner-bound wall-clock timer scheduler & idle `-1` wait | `0H / 0M / 3L` |
| `internal/uisystem_controller.d` | 50 | Built-in `DefaultController` for `WidgetSystemPipeline` | `0H / 0M / 1L` |
| `internal/uisystem_impl.d` | 1,832 | Concrete `UiSystem`: phased event loop, timers, release | `2H / 3M / 7L` |

---

## 1. Correctness, Safety & Lifecycle

### 1.1 [H] `Window.~this()` invokes OpenGL ES and SDL teardown from GC finalizer
`window.d:73-75, 164-178`

`~this()` calls `destroy()`, which dereferences GC-managed `renderer` to issue
GL calls and calls `yguilib_sdl3_gl_destroy_context` /
`yguilib_sdl3_destroy_window`. Dereferencing GC-managed fields in a D finalizer
is undefined behavior (the member may already be finalized), and finalizers may
run off the main thread or after `yguilib_sdl3_quit()`.

Fix: Remove `destroy()` from `~this()` (either drop `~this()` or only
log/assert if `handle !is null` without touching `renderer` or SDL/GL) and rely
on deterministic main-thread `destroy()`.

### 1.2 [H] `mainEventLoop()` pushes `UiSystemController` on top of user controllers
`internal/uisystem_impl.d:223-224`

`App.run()` expects callers to call `ui.pushController(...)` before
`mainEventLoop()`, which then calls `pushController(sysCtrl)`. Because
`dispatchDiscreteEvent` (`internal/uisystem_impl.d:388`) iterates
`foreach_reverse` (newest-to-oldest), `UiSystemController` runs **before** user
controllers, inverting the order documented in `ARCHITECTURE.md`. Because
`UiSystemController` falls back to `DefaultController.handleEvent`, it
intercepts `appQuit`/`windowClose` and returns `Result.quit`, preventing user
controllers from seeing close/quit events and burying pre-pushed modal
controllers.

Fix: Insert `UiSystemController` at the bottom of `ControllerStack` (e.g., via
`pushBottom` or during `UiSystemImpl` construction) or dispatch it as the
bottom-most fallback after user controllers.

### 1.3 [M] Partial-init leak in `Window.create()`
`window.d:119-162`

Failures in `glContext` creation (`:130`) and `gladLoadGLES2` (`:139`) call
`destroy()`, but if `new Renderer(pw, ph, defaultScale)` (`:155`) throws,
`handle` and `glContext` are leaked.

Fix: Add `scope (failure) destroy();` immediately after
`if (handle !is null) return;`.

### 1.4 [M] Unvalidated scaling (`<= 0` or `NaN`) in `Window`
`window.d:34-42, 193-198, 296-303`

`unitsScaling(float)` (`:34`) and `onDisplayScaleChanged(event.window.scale)`
(`:194`) do not validate `scaling > 0.0f && isFinite(scaling)` (unlike
`windowResized` at `:182`), risking division-by-zero or negative viewports in
`Renderer`.

Fix: Guard/assert `scaling > 0.0f && isFinite(scaling)` in both methods.

### 1.5 [M] `ModelTracker` allows default construction with `null` model
`model.d:38-75`

`ModelTracker` holds non-null `private T m;` without `@disable this();` or
`invariant { assert(m !is null); }` (violating `codestyle.md` §3). Default
construction segfaults on `update()`/`edit()`.

Fix: Add `@disable this();` and `invariant { assert(m !is null); }`.

### 1.6 [M] `RingBuffer` double-destructor on `T.init` and missing `~this()`
`allochelpers.d:287-296, 345-357, 615-619`

In `tryPopFront()` (`:292`) and `reallocate()` (`:352`), `clearSlot(...)`
assigns `T.init` after `core.lifetime.move(...)`. For `hasElaborateDestructor!T`,
`move` already blits `T.init` into the source; assigning `T.init` invokes
`~this()` on that `T.init` slot. `RingBuffer` also lacks `~this()`, so RAII
elements are not deterministically destroyed when going out of scope without
explicit `clear()`/`releaseMemory()`.

Fix: Only call `clearSlot` when
`hasIndirections!T && !hasElaborateDestructor!T`, and add `~this() { clear(); }`
(or document mandatory explicit cleanup).

### 1.7 [M] `serhelpers.toJsonValue` corrupts `ulong`/`size_t > long.max`
`serhelpers.d:24-25`

`isIntegral!T` casts all integers to `long` (`JSONValue(cast(long) value)`),
turning large unsigned values negative even though `std.json.JSONValue`
supports `ulong`.

Fix: Branch `static if (isUnsigned!T) return JSONValue(cast(ulong) value);`.

### 1.8 [M] `shortTypeName` fails to strip template arguments
`serhelpers.d:79-95`

The docstring claims `Box!int` becomes `Box`, but lines 93-94 only slice after
`lastIndexOf('.')`, leaving `Box!int` intact and mangling `pkg.Box!(other.Foo)`
into `"Foo)"`.

Fix: Strip from the first `'!'` (if present) before computing `lastIndexOf('.')`.

### 1.9 [M] Reflection serializer omits base-class fields and interface dynamic types
`serhelpers.d:100-129`

`serializeStructOrClass` uses static `T.stringof` and `FieldNameTuple!T`,
omitting inherited fields from base classes and emitting `fields: {}` for
interface references without custom `toJsonValue`/`onSerializeFields`.

Fix: Walk `BaseClassesTuple!T` (or document the direct-fields/static-type
limitation) and consider `shortTypeName(value)` for `"type"`.

### 1.10 [M] `AnimationTimer.duration(float)` breaks `pingPong` return half
`timers.d:79-86`

In `AnimationWrapMode.pingPong`, `elapsed` spans `[0, 2 * fDuration)` (`:50`),
but `duration(float)` clamps `if (elapsed > fDuration) elapsed = fDuration;`,
snapping a returning animation back to peak `1.0`.

Fix: Clamp to `mode == AnimationWrapMode.pingPong ? 2.0f * fDuration : fDuration`.

### 1.11 [M] `StopWatchNs.start()` discards elapsed time if already running
`timers.d:155-158`

Calling `start()` while `running == true` overwrites `startTime` without calling
`updateElapsed()`, silently dropping accumulated elapsed time.

Fix: Guard `if (running) return;` or call `updateElapsed()` first.

### 1.12 [M] `ObjectRegistry.register` allows `null` objects
`object_registry.d:10-17`

Missing `assert(obj !is null)` (`codestyle.md` §3). A registered `null` is
indistinguishable from "not found" in `findByName`.

Fix: Add `assert(obj !is null, "obj must not be null");`.

### 1.13 [M] `releaseWidget()` is not re-entrancy safe
`internal/uisystem_impl.d:169-208`

`releaseWidget` iterates `fWidgetViews` (`:186`), `fWidgetViewControllers`
(`:192`), and `controllers` (`:198`) directly without snapshotting. A callback
mutating any of those containers corrupts iteration. Moreover, `w.release()`
(setting `w.released = true`) runs only at `:207`, so a re-entrant
`releaseWidget(w)` bypasses `if (w is null || w.released)` at `:170`.

Fix: Snapshot `controllers` into a `SmallBuffer!(Controller, 16)`, guard
registry iteration, and mark `w` as releasing before notifications.

### 1.14 [M] Unchecked `yguilib_sdl3_init()` and `yguilib_sdl3_wait_event()` errors
`internal/uisystem_impl.d:211-212, 333-336`

`yguilib_sdl3_init()`'s `-1` failure return is ignored (`:211`), and a `< 0`
return from `yguilib_sdl3_wait_event` (`:333-336`) is silently ignored, risking
a 100% CPU spin loop if waiting fails.

Fix: Check `if (yguilib_sdl3_init() != 0)` before registering
`scope (exit) yguilib_sdl3_quit()`, and log/handle `res < 0` in
`waitForEventsIfIdle()`.

### 1.15 [M] Negative dimensions wrap `ulong` in `TextureStats.bytesOf`
`internal/memstats.d:30-35, 61-63`

`cast(ulong) d.w * d.h * 4` sign-extends negative `w` or `h` to ~`ulong.max`,
corrupting `curBytes`, `peakBytes`, and `maxBytes`.

Fix: Return `0` when `d.w <= 0 || d.h <= 0` and assert `w >= 0 && h >= 0` in
`onAlloc`.

### 1.16 [L] `ReusableArray.compact` null-check misses function pointers and interfaces
`allochelpers.d:495-502`

`isPointer!Pred` is `false` for `bool function(...)`, and `is(Pred == class)`
excludes `interface`.

Fix: Add `|| isFunctionPointer!Pred || is(Pred == interface)`.

### 1.17 [L] `slicesOverlap` compares unrelated pointers with `<`
`allochelpers.d:608-613`

Relational pointer comparisons across distinct allocations are UB under LLVM
pointer-provenance rules.

Fix: Compare `cast(size_t) a.ptr` and `cast(size_t) (b.ptr + b.length)`.

### 1.18 [L] Missing positive-dimension validation in `App` and `Window`
`app.d:37-39`, `window.d:12-18, 61-71`

`makeAppWithTitleWh`, `Window.this`, and `Window.resize` do not assert
`width > 0 && height > 0`.

Fix: Add `assert(width > 0 && height > 0)`.

### 1.19 [L] `NaN` step/duration bypasses `<= 0` guards in `AnimationTimer`
`timers.d:27-53, 89-113`

`fDuration <= 0 || step <= 0` is `false` for `NaN`, poisoning `elapsed`.

Fix: Use `!(fDuration > 0) || !(step > 0)` (with `isFinite` checks).

### 1.20 [L] `withMaskDefine` slices `#version 300 es\n` without verifying prefix
`internal/assets.d:52-54`

Hardcoded length slice silently corrupts the shader if the header ever changes
or uses `\r\n`.

Fix: Replace with a CTFE helper asserting the prefix matches before slicing.

### 1.21 [L] `TimerService.allocateId()` does not check collision on `uint` wrap
`internal/timer_service.d:169-178`

On wrap-around, `allocateId()` skips `0` but does not check whether the wrapped
ID is still active in `entries`.

Fix: Widen `TimerId` to `ulong` or skip active IDs on wrap.

### 1.22 [L] `pipeline.notifyWindowClosed(fMainWindow)` is never called on exit
`internal/uisystem_impl.d:217-221`

`mainEventLoop()` destroys `fMainWindow` without calling
`pipeline.notifyWindowClosed(fMainWindow)`.

Fix: Call `pipeline.notifyWindowClosed(fMainWindow)` in `mainEventLoop()`'s
`scope (exit)` cleanup before `fMainWindow.destroy()`.

---

## 2. Memory Allocations & Performance

### 2.1 [M] `telemetrySampleHeap()` calls `GC.stats()` and `mallinfo2()` every event-loop step
`internal/memstats.d:72-85` (called at `internal/uisystem_impl.d:511`)

`MemTelemetry` is enabled in all debug builds (`yguilib/meson.build:12`).
Sampling on every `runEventLoopStep()` acquires the global GC lock and all
glibc malloc arena locks on every mouse-motion batch or animation tick.

Fix: Throttle `HeapStats.sample()` (e.g., at most once per 250ms-1s via
`MonoTime`) while keeping an unconditional sample in `logMemStats()`.

### 2.2 [L] `releaseWidget()` allocates a GC array via `w.children.dup`
`internal/uisystem_impl.d:175`

Every non-leaf widget in a released subtree triggers a GC heap allocation.

Fix: Use `SmallBuffer!(Widget, 16) childrenSnapshot; childrenSnapshot.assignSlice(w.children);`.

### 2.3 [L] Double GC allocation per log message in `SdlLogger`
`internal/logger.d:38-41`

`format(...)` allocates a string and `logMsg.toStringz` allocates a second copy.

Fix: Append `\0` in the format string (`"%s [%s] %s\0"`) and pass `logMsg.ptr`.

### 2.4 [L] Duplicate AA hash lookups in `ObjectRegistry`
`object_registry.d:10-25`

`register` and `unregister` perform 3 AA lookups per call.

Fix: Use `if (auto p = name in objMap)` to avoid redundant lookups.

### 2.5 [L] Unreserved array growth in `serhelpers.toJsonValue`
`serhelpers.d:41-46`

`arr ~= toJsonValue(elem)` reallocates repeatedly for large arrays.

Fix: Pre-allocate `auto arr = new JSONValue[value.length];` and assign by index.

### 2.6 [L] `enum string` manifest constant for embedded TTF font
`assets.d:5-6`

`enum string defaultTtfFontData = import(...)` can duplicate the embedded font
blob across object files.

Fix: Use `immutable string defaultTtfFontData = import(...);`.

---

## 3. Architecture, Encapsulation & API Design

### 3.1 [H] `internal/uisystem_impl.d` omits `package(yguilib):`, leaking `UiSystemImpl` as `public`
`internal/uisystem_impl.d:1-39`

Because `internal/uisystem_impl.d` lacks `package(yguilib):`, ~20 external files
in `source/guidemo/`, `source/yvidtrim/`, and `yguilib/examples/helloworld/`
import `yguilib.internal.uisystem_impl : UiSystemImpl` directly (mostly for
headless `new UiSystemImpl(null)` tests), violating `ARCHITECTURE.md` and
`codestyle.md` internal-boundary rules.

Fix: Expose a public headless factory (e.g., `UiSystem makeHeadlessUiSystem()`
in `yguilib.uisystem` or `yguilib.app`), migrate external callers to it, and
add `package(yguilib):` at the top of `internal/uisystem_impl.d`.

### 3.2 [M] Dead `private` methods and `fPendingRedraw` state in `UiSystemImpl`
`internal/uisystem_impl.d:523-574, 584`

`hasPendingAppEvents()`, `redraw()`, `unitsScaling`, `displayScaling`,
`defaultScaling`, and `fPendingRedraw` are dead in production (only a
same-module unittest exercises scaling). This also triggers the static checker
warnings at `:548` and `:562`.

Fix: Remove the dead methods/field/test, or promote scaling to `UiSystem` with
`@property` if UI-level scaling is intended.

### 3.3 [M] Untyped `Object owner` in `TimerControl.startTimer`
`timercontrol.d:33-37`

Accepts any `Object` despite only supporting `Controller` and `WidgetSystem` at
runtime, diverging from `codestyle.md` §2 (`startControllerTimer` /
`startSystemTimer`).

Fix: Split into typed `startControllerTimer(Controller, ...)` and
`startSystemTimer(WidgetSystem, ...)` (or introduce a `TimerOwner` interface).

### 3.4 [M] `ModelTracker.lastSeenVersion` is public and mutable
`model.d:65`

External code can overwrite `lastSeenVersion`, breaking dirty detection.

Fix: Move to `private:` and expose a `const` getter if needed.

### 3.5 [M] Missing nullability docs on nullable `UiSystem` methods
`uisystem.d:35-40, 46`

`mainWindow()`, `findWidgetSystem()`, and `findWidgetSystemByType()` can return
`null` without documenting it (`codestyle.md` §3).

Fix: Add `/// May return null ...` doc comments on all three.

### 3.6 [L] `App.fUi` is `package(yguilib)` instead of `private`
`app.d:66`

Already exposed via `public @property UiSystem ui()`. Move `fUi` to `private:`.

### 3.7 [L] Unimplemented stubs in public/internal modules
`timers.d:264-268`, `window.d:236-246`, `internal/uisystem_impl.d:161-167`

- `MeasureScopeTime` (`timers.d:264-268`) is an empty `// TODO` stub.
- `Window.redraw()` (`window.d:236-246`) is unused outside its unittest.
- `FocusControl.pushFocusRoot`/`popFocusRoot` (`internal/uisystem_impl.d:161-167`)
  are empty `// TODO` stubs.

Fix: Remove `MeasureScopeTime` and `Window.redraw()`; track `FocusControl` in
`TODO.md` until wired into `FocusSystem`.

### 3.8 [L] `AnimationTimer.start()` does not unpause and is undocumented
`timers.d:61-65`

Leaves `fPaused` unchanged (`true` initially). Document or rename to `configure`.

### 3.9 [L] `SmallBuffer.assignSlice(T[] src)` rejects `const(T)[]`
`allochelpers.d:88`

Accept `const(T)[]` when `T` is copyable from `const(T)`.

### 3.10 [L] `formatBytes` lacks a `GiB` tier
`texthelpers.d:5-16`

Multi-GB video files format as thousands of `MiB`. Add a `GiB` branch.

---

## 4. Code Reuse & Duplication

### 4.1 [L] Duplicated overflow-checked doubling logic in `allochelpers.d`
`allochelpers.d:176-194, 259-280, 551-564`

`SmallBuffer.ensureHeapCapacity`, `RingBuffer.push`, and
`ReusableArray.ensureCapacityForPush` repeat the same `<= size_t.max / 2`
doubling logic.

Fix: Extract a private `growCapacity` helper.

### 4.2 [L] Verbatim duplicate test controller classes in `uisystem_impl.d`
`internal/uisystem_impl.d:829-854, 876-901`

`PropagationTestController` and `ConsumeTestController` are identical 26-line
classes differing only in `shouldConsume = true`.

Fix: Consolidate into a single test helper.

---

## 5. Codestyle & Maintainability

### 5.1 [M] Multiple `codestyle.md` violations in `model.d`
`model.d:9, 21, 26, 48, 50`

- Trailing underscore `version_` (`:9,21,26,35,87`) violates §2; rename to
  `fModelVersion`.
- Inline `private T m;` inside `public` section (`:48`) violates §4; move to
  trailing `private:`.
- `@property const(T) model()` (`:50`) is missing `const`.

### 5.2 [L] Per-declaration visibility & section ordering in `uisystem_impl.d` and `memstats.d`
`internal/uisystem_impl.d:129-143`, `internal/memstats.d:89, 97, 102, 107-108`

Both files use per-declaration `private`/`package(yguilib)`/`protected`
attributes out of `public` -> `protected` -> `private` section order.

Fix: Group declarations under visibility section labels in canonical order.

### 5.3 [L] Unused imports and >50-line function in `serhelpers.d`, `uisystem.d`, `uisystem_impl.d`
`serhelpers.d:5-8, 15-68`, `uisystem.d:4, 52`, `internal/uisystem_impl.d:3, 5, 11, 13, 16, 19`

- `serhelpers.d`: unused `isFinite`, `isBasicType`, `isSomeChar`; `toJsonValue`
  is 54 lines.
- `uisystem.d`: unused `import yguilib.timercontrol;`; `eventStatsEnabled()`
  missing `const`.
- `internal/uisystem_impl.d`: unused `glad2.gles2`, `Keycode`/`Scancode`,
  `Renderer`; test-only imports at module top.

Fix: Prune unused imports, scope test-only imports, split `toJsonValue`.

### 5.4 [L] Missing `invariant` and undocumented nullable params
`internal/uisystem_impl.d:40-63, 585`, `internal/timer_service.d:22-24, 69-79`

- `UiSystemImpl` lacks `invariant` for non-null `pipeline`,
  `fWidgetViewControllers`, `fWidgetViews`; stale `} // -UiSystem` comment at
  `:585`.
- `TimerService.clock` and `stopTimersForOwner` allow `null` without doc
  comments.

### 5.5 [L] Minor naming/qualifier nits
`object_registry.d:98`, `timers.d:67, 173`

- Leading underscore `int _id;` in `object_registry.d:98` unittest.
- Parameter `aPaused` in `timers.d:67` (use `isPaused`); `StopWatchNs.elapsed()`
  (`:173`) missing `const nothrow @safe`.

---

## 6. Tests & Verification Gaps

### 6.1 [M] `internal/logger.d` unittest mutates global `sharedLog` without restoring
`internal/logger.d:49-54`

`setupSdlLogger(LogLevel.trace)` leaks `SdlLogger(LogLevel.trace)` into all
subsequent `yguilib_test` tests and contains zero assertions.

Fix: Restore `sharedLog` in `scope (exit)` and assert all `LogLevel` mappings.

### 6.2 [M] Sleep-based flaky tests in `timers.d`
`timers.d:328-390, 425-445`

`StopWatchNs`, `Timer`, and `DeltaTimer` tests use `Thread.sleep(2..15.msecs)`,
which flakes under OS preemption; `AnimationTimer.stop()` and `duration(<= 0)`
are untested.

Fix: Support an injectable clock and add `stop()`/`duration()` edge-case tests.

### 6.3 [M] Untested `Window` event/screenshot/resize paths
`window.d:316-367`

`handleWindowEvent`, `requestScreenshot`/`takePendingScreenshotPath`,
`resize()`, and `updateViewRect()` with a non-null `rootWidget` lack unit tests.

### 6.4 [L] Minor unit-test gaps across `core`
`app.d`, `model.d:77-89`, `object_registry.d:48-129`, `serhelpers.d:131-217`,
`internal/uisystem_controller.d`, `internal/timer_service.d:245-423`

- No unit tests for `app.d` or `internal/uisystem_controller.d`.
- Missing edge cases in `model.d` (`from`/`edit`/`commit`), `object_registry.d`
  (2-arg `opApply`, early `break`), `serhelpers.d` (`ulong > long.max`, arrays,
  AAs, pointers, `shortTypeName` templates), and `timer_service.d`
  (`intervalMs == 0`, re-entrant `startTimer`/`stopTimer`, `dt` lag clamping).

---

## Prioritized Action List

- **High**
  1. Remove `destroy()` from `Window.~this()` (`window.d:73-75`).
  2. Fix `UiSystemController` stack placement in `mainEventLoop()`
     (`internal/uisystem_impl.d:223-224`).
  3. Add public headless `UiSystem` factory and `package(yguilib):` to
     `internal/uisystem_impl.d`.
- **Medium**
  4. Make `releaseWidget()` re-entrancy safe and check `yguilib_sdl3_init()` /
     `yguilib_sdl3_wait_event()` errors (`internal/uisystem_impl.d`).
  5. Throttle `telemetrySampleHeap()` in debug builds (`internal/memstats.d`).
  6. Fix `RingBuffer` `clearSlot` on `hasElaborateDestructor!T`
     (`allochelpers.d`), `ModelTracker` `@disable this()` + `invariant`
     (`model.d`), `Window.create()` `scope(failure)` + scaling guards
     (`window.d`), `serhelpers.d` `ulong`/`shortTypeName`, and `timers.d`
     `pingPong`/`StopWatchNs.start`.
  7. Fix `internal/logger.d` unittest leaking global `sharedLog`.
- **Low**
  8. Clean up dead code, codestyle nits, and remaining unit test gaps.
