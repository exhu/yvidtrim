# `yguilib` Full Module Review Report

```
  date    2026-11-27
  branch  main
  commit  7a96feaa25bba66718bc02d342f18c7c42932731 (fix composite_view after review)
```

Line numbers across all package reports refer to that commit.

Scope: complete module-by-module review of all **93 D modules** (~45.7k LOC) in
`yguilib/source/yguilib/` and all descendant packages, split into 8 per-package
reports.

Severity: **H** high, **M** medium, **L** low.

---

## Package Reports

| Package | Report File | Modules | Lines | High | Med | Low | Total |
|---|---|---:|---:|---:|---:|---:|---:|
| `core` (root + `internal/`) | [yguilib-review-report-core.md](yguilib-review-report-core.md) | 18 | 5,553 | 4 | 21 | 36 | 61 |
| `clibs` | [yguilib-review-report-clibs.md](yguilib-review-report-clibs.md) | 3 | 894 | 0 | 3 | 6 | 9 |
| `controller` | [yguilib-review-report-controller.md](yguilib-review-report-controller.md) | 2 | 329 | 2 | 5 | 4 | 11 |
| `events` | [yguilib-review-report-events.md](yguilib-review-report-events.md) | 5 | 1,579 | 2 | 7 | 12 | 21 |
| `controls` | [yguilib-review-report-controls.md](yguilib-review-report-controls.md) | 11 | 7,807 | 11 | 24 | 22 | 57 |
| `render` (core + text) | [yguilib-review-report-render.md](yguilib-review-report-render.md) | 16 | 9,221 | 5 | 26 | 29 | 60 |
| `render/canvas` | [yguilib-review-report-render-canvas.md](yguilib-review-report-render-canvas.md) | 8 | 7,832 | 1 | 7 | 12 | 20 |
| `widget` | [yguilib-review-report-widget.md](yguilib-review-report-widget.md) | 30 | 12,506 | 17 | 58 | 39 | 114 |
| **Total** | **8 package reports** | **93** | **45,721** | **42** | **151** | **160** | **353** |

---

## Automated Static Baseline

Executed at commit `7a96feaa25bba66718bc02d342f18c7c42932731`:

- `check_boundaries.d`: **0 errors** (all architectural boundary rules pass;
  note `internal/uisystem_impl.d` omits `package(yguilib):`, which is flagged
  in `core` Finding 3.1).
- `check_null_safety.d`: **0 errors**.
- `check_style.d yguilib/source/yguilib/`: **0 errors, 34 warnings**:
  - 28 warnings are valid `@property` / getter-setter pairs (`codestyle.md` §2).
  - 2 warnings are dead private getter/setter pairs in
    `internal/uisystem_impl.d:548,562`.
  - 1 warning is a GLES call pair in `render/internal/stencil_ops.d:33`.
  - 3 genuine style warnings confirmed in `controls`:
    `tabcontrol.d:424` (63-line function), `tabcontrol.d:603` (overloaded
    `revealActiveTab`), and `virtlist.d:77` (multiple constructors).
- ABI cross-check of `yguilib/clibs/*.d` vs `yguilib/yguilib-clibs/*.h`:
  **60/60 functions, 9/9 structs, 1/1 union match 1:1 (0 ABI mismatches)**.

---

## Cross-Cutting Themes & Top Priorities

### 1. Input, Occlusion & Lifecycle State Machines (`widget`, `controls`, `controller`, `core`)
- **Event ordering & quit interception**: `mainEventLoop()` pushes
  `UiSystemController` on top of user controllers (`core` 1.2), inverting
  `ARCHITECTURE.md` dispatch order and swallowing `appQuit`/`windowClose`.
- **Occlusion & `inputEnabled` gaps**: `PressTracker.hitTest` (`controls` 1.8)
  and `VirtListSystem` `mouseWheel` (`widget` 1.8) ignore `handleInput`
  occlusion; `AnimatedHoverButtonSystem` ignores `inputEnabled` (`controls`
  1.5); `ButtonSystem.syncEnabledStates` runs in `postLayout` which is skipped
  on `WidgetUpdateScope.visuals` (`controls` 1.1).
- **Cursor capture/lock & repeat-timer leaks**: `InputSystem` (`widget` 1.5-1.7)
  and `ButtonSystem`/`AnimatedHoverButtonSystem` (`controls` 1.2-1.4, 1.6) can
  leak SDL cursor capture/lock or repeat timers on hide, disable, or
  `windowMouseLeave` — breaking zero-CPU idle sleep.
- **Re-entrancy & release hygiene**: `ControllerStack.opApply`/`pushModal`/
  `pop` (`controller` 1.1-1.2), `UiSystemImpl.releaseWidget` (`core` 1.13),
  `Widget.release` (`widget` 1.3), and `WidgetComponents.clear` (`widget` 1.2).

### 2. Buffer Aliasing, Caching & Hot-Path Performance (`widget`, `render`, `core`)
- **Aliased visibility buffer**: `VisibleWidgetsCollector` reuses one
  `Appender` for both `ctx.unclippedWidgets` and `fLastVisibleWidgets`,
  clobbering `ctx.unclippedWidgets` before `postLayout` (`widget` 1.1).
- **Broken text layout caches**: `calcContentSize` bypasses
  `TextLabel.contentSizeCache` (`widget` 2.1), and both text caches miss
  `Font.scale` / `font.id` changes and empty results (`widget` 1.12-1.13).
- **`VirtListSystem` scaling**: O(`anchorIndex`) AA lookups and per-scroll GC
  array allocations on every scroll frame (`widget` 2.2-2.3).
- **Debug telemetry lock contention**: `telemetrySampleHeap()` calls
  `GC.stats()` + `mallinfo2()` on every event loop step (`core` 2.1).

### 3. Rendering, GL/SDL Lifecycle & Memory Safety (`render`, `render/canvas`, `core`, `events`)
- **GC finalizer GL/SDL teardown**: `Window.~this()` calls `destroy()` from GC
  finalization (`core` 1.1).
- **Uninitialized glyph atlas gutters**: `allocRgbaTexture()` leaves texels
  undefined per GLES spec (`render` 1.1).
- **Overlapping text shadow erasure**: `drawImageShadowMask` disables blending,
  causing overlapping glyph quads (`strokeText`, kerned text) to erase neighbor
  shadows (`render/canvas` 1.1).
- **Value-copy destructor & wake loss**: `AppEvent.~this()` double-fires
  `releaseData` on value copies (`events` 1.1); `MessageBus.send()` ignores
  `yguilib_sdl3_send_wake_event()` failure (`events` 1.2).
- **Overflow & unchecked allocation**: `RunGlyph.dx`/`dy` `short` overflow
  (`render` 1.5), `RenderTarget` pixel dimension overflow (`render` 1.4), and
  unchecked `malloc` in `uploadAndDrawIndexedQuads()` (`render` 1.2).

### 4. Encapsulation & Module Hygiene
- `internal/uisystem_impl.d` lacks `package(yguilib):`, leaking `UiSystemImpl`
  to ~20 external files (`core` 3.1).
- `controls/internal/button_support.d` leaks `ButtonBaseConfig` and mixin
  internals (`controls` 3.1); `widget/test_fixture.d` is compiled into
  `yguilib_lib` (`widget` 3.1).

---

## Suggested Remediation Order

1. **Critical lifecycle & correctness fixes** (1-2 PRs):
   `Window.~this()`, `UiSystemController` stack order, `VisibleWidgetsCollector`
   dual buffers, `AppEvent.~this()` + `MessageBus` wake retry, `ControllerStack`
   re-entrancy/snapshot, `allocRgbaTexture` zero-init, `uploadAndDrawIndexedQuads`
   null check, `RunGlyph` `int` offsets, `drawImageShadowMask` blending.
2. **Input, focus & controls reliability** (1-2 PRs):
   `InputSystem` lock/disable/hide/cleanup, `PressTracker.hitTest` occlusion,
   `ButtonSystem` `preLayout` + repeat timer stops, `AnimatedHoverButtonSystem`
   `inputEnabled`/pulse latch, `TabControl` rebind + `super.handleEvent`,
   `VirtListWidgetView.bindModel` scrollbar wiring + wheel gating.
3. **Layout & hot-path performance** (1 PR):
   `calcContentSize` cache wiring, `TextLayoutCache` `font.id`/`scaledSize`/
   `valid`, `layout_flex` fraction margins, `layout_text` vertical ellipsis,
   `VirtListSystem` O(`fItemMainSizes.length`) offset + reusable active buffer,
   `telemetrySampleHeap` throttling.
4. **Encapsulation, codestyle & test gaps** (1-2 PRs):
   `makeHeadlessUiSystem()` + `package(yguilib):` on `uisystem_impl.d`,
   `nothrow @nogc` on `clibs/*.d`, `render/package_test.d` split, shared mock
   hosts, and targeted regression tests for all fixed issues.
