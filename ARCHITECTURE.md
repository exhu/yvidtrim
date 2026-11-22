# yvidtrim Architecture

## System Overview
`yvidtrim` is a frame-accurate, keyboard-driven video trimming tool built in D.
It targets lossless cut workflows (smart cuts re-encoding only GOP boundaries)
with private C wrappers for external media libraries.

Key architectural separation:
- `yvidtrim`: Video editor application, domain logic, playback, and export.
- `yguilib`: Independent, retained-mode GUI library with an ECS-style
  widget tree, flexbox/anchor layout, OpenGL ES 2/3.1 rendering, and loops.
- `guidemo`: Standalone interactive testbed showcasing GUI widgets and layout.
- `*-clibs`: Minimal C static libraries isolating external C/C++ dependencies.

## Directory & Package Topology
```
yvidtrim/
├── source/
│   ├── yvidtrim/          # Video trimmer entry point, models, controllers
│   │   ├── app.d          # Application entry point wiring model/view/ctrl
│   │   ├── controller.d   # MainController handling events and model sync
│   │   ├── model.d        # MainModel state
│   │   ├── view.d         # MainView widget tree and model synchronization
│   │   ├── uitree/        # Declarative widget tree construction
│   │   └── clibs/sdl3.d   # extern(C) D bindings for yvidtrim-clibs
│   └── guidemo/           # Interactive GUI showcase and verification app
│       ├── guidemoapp.d   # guidemo entry point and system registration
│       ├── controller.d   # Shared demo controller, quit, F12, page switch
│       ├── hover_button.d # Controller-based hover button demo
│       └── pages/         # Showcase views and per-page controllers
├── yguilib/               # Independent GUI library (no yvidtrim dependency)
│   ├── source/yguilib/
│   │   ├── allochelpers.d # SmallBuffer, RingBuffer, ReusableArray containers
│   │   ├── app.d          # Application wrapper running event loop
│   │   ├── window.d       # Window, OpenGL context, display scaling
│   │   ├── uisystem.d     # UiSystem, ControllerStack, EventControl interfaces
│   │   ├── serhelpers.d   # Generic JSON reflection serialization helpers
│   │   ├── model.d        # VersionedModel and ModelTracker state tracking
│   │   ├── clibs/         # extern(C) D bindings for yguilib-clibs
│   │   ├── controller/    # Controller interfaces and ControllerStack
│   │   ├── controls/      # Reusable UI controls (no package.d facade)
│   │   │   ├── hover_button_system.d # ECS hover button & animation system
│   │   │   ├── scrollbars.d          # Composite Scrollbar widget & view
│   │   │   ├── tab_button.d          # Styled tab button factory & helpers
│   │   │   ├── tabcontrol.d          # Composite TabControl widget & view
│   │   │   └── virtlist.d            # Composite VirtList widget & view
│   │   ├── events/        # AppEvent, builder, and thread-safe MessageBus
│   │   ├── render/        # Hardware Renderer, FontManager, shader pipelines
│   │   ├── widget/        # Widget entity, components, builder, WidgetSystem
│   │   │   ├── virtlist_components.d # VirtListProvider & VirtListComponent
│   │   │   └── internal/virtlist_system.d # Recycling, layout & wheel scroll
│   │   └── internal/      # UiSystemImpl, TimerService, UiSystemController
│   ├── yguilib-clibs/     # Private C wrappers around SDL3 and SDL3_ttf
│   └── assets/            # Embedded resources (fonts, shaders) via import("")
├── yvidtrim-clibs/        # Private C wrappers for editor (SDL3, FFmpeg future)
└── subprojects/           # Meson subprojects (glad2gles31, glad2gles31d)
```

## Architectural Invariants & Boundaries
- `yguilib` Independence: `yguilib/` (D source & C wrappers) must never import
  or link `source/yvidtrim/` or `yvidtrim-clibs/`. Enforced by check-boundaries.
- Private C Wrappers: Never import third-party C headers directly in D. Wrap
  dependencies in private static C libs (`<proj>-clibs/<proj>_<libname>.[c|h]`)
  using opaque handles, explicit NULL docs, and matching D bindings in `clibs/`.
- Graphics & Threading Boundary:
  - GUI changes, widget mutations, and OpenGL ES calls (`glad2.gles2`) are
    strictly restricted to the main thread.
  - Background threads (playback decode, export) communicate exclusively via
    message passing by calling `UiSystem.sendAppEvent(AppEvent)`.
  - `MessageBus.send()` is a thread-safe ring buffer (`synchronized`) that
    signals `yguilib_sdl3_send_wake_event()` from background threads when the
    main thread is waiting, and preserves raw `mouseMotion` samples without
    merging.
- Memory & Safety Enforcements:
  - Hot paths use `yguilib.allochelpers` (`SmallBuffer`, `RingBuffer`,
    `ReusableArray`) to minimize GC churn in event, timer, and layout loops.
  - GC is permitted for widget graph construction, models, and UI event strings.
  - C handles (SDL windows, GL contexts, TTF fonts) follow strict RAII cleanup
    in explicit `destroy()` and destructors (`~this()`).
- Encapsulation & Scoping:
  - No `public import` re-exports; multi-module packages like
    `yguilib.controls` import modules explicitly without `package.d`.
  - Internal modules (`internal/`) must declare `package(<root_pkg>):` or
    `private:`; `public:` declarations inside `internal/` are strictly banned.
  - Scoped imports defer parsing for heavy stdlib modules (e.g., `std.format`).

## Primary Data Flows

### 1. Phased Main Event Loop & Input Dispatch
```
[SDL3 Event / Background Thread Wake]
  │
  ▼ (wait_event if idle, then drain SDL via poll_event -> MessageBus)
Phase 1: UiSystemImpl.drainMessageBus()
  │ (top-to-bottom through ControllerStack; bounded batch, no rendering)
  ├─► User Controllers (e.g. DemoController, MainController)
  │     └─► handleEvent() ──► collects dirtyViews & needModelUpdate
  │
  └─► UiSystemController
        └─► WidgetSystemPipeline.handleEvent()
              ├─► FocusSystem (priority -100)
              └─► InputSystem (priority 0) ──► bubbles MouseEvent through
                    ViewComponent.renameEvents ──► UiSystem.sendAppEvent()
```

### 2. Phase 2 Sync, Timers & Model-View-Controller Loop
```
Phase 2: UiSystemImpl.runPhase2Updates()
  │
  ├─► Phase 2a (if needModelUpdate):
  │     ├─► Controller.update()
  │     └─► SystemPhase.update: WidgetSystem.update(ctx)
  ├─► Phase 2b (due timers in TimerService):
  │     ├─► Controller timer   ──► Controller.onTimer(id, dt)
  │     └─► WidgetSystem timer ──► WidgetSystem.onTimer(ctx, id, dt)
  │
  ▼
Phase 3: dirty Controller.updateView() (oldest-to-newest) ──► View.update()
  └─► tracker.update() / view mutates widgets ──► widget.update(scope)
```

### 3. Layout & Render Pipeline Pass
```
Phase 3 (if dirty): UiSystemImpl ──► WidgetSystemPipeline.updateAndRender()
  │
  ├─► 1. PreLayout Phase: preLayoutSystems.preLayout(ctx)
  │
  ├─► 2. Layout Phase (if rootWidget.isTreeLayoutDirty()):
  │     ├─► VisibleWidgetsCollector collects unclipped visible widgets
  │     ├─► LayoutSystem resolves flexbox, axes, auto text size, anchors
  │     ├─► ScrollSystem offsets & clamps child rect in ScrollableArea
  │     ├─► VisibleWidgetsCollector collects clipped visible widgets
  │     └─► postLayoutSystems.postLayout(ctx) (ScrollSystem feedback)
  │
  ├─► 3. Render Phase (if rootWidget.isTreeDirty()):
  │     ├─► WidgetPainterSystem draws backgrounds, borders, text, customDraw
  │     └─► DebugDrawSystem (debug only) draws unclipped outlines & labels
  │
  └─► 4. Buffer Swap: Window.swapBuffers() (at most once per frame tick)
```

## Idiomatic Patterns
- Null Safety: Non-null references by default. Missing checks are flagged by
  tooling. Constructor arguments enforce `assert(arg !is null)` and structs/
  classes assert invariants `invariant { assert(field !is null); }`.
- Zero-CPU Idle Sleep: Controllers and `WidgetSystem`s register owner-bound
  wall-clock timers via `TimerControl` (`startTimer` / `stopTimer`) during
  active animations and stop them when settled (`TimerService` returns `-1`
  when idle so `yguilib_sdl3_wait_event()` blocks without spinning).
- ECS-Style Widgets: `Widget` is an entity with geometry (`RectF`), hierarchy,
  and a `WidgetComponents` bag (`Background`, `Border`, `Size`, `FlexContainer`,
  `MouseEvent`, custom components via `components.set!C(...)`).
- Widget Lifecycle & Release: Disposing a widget hierarchy must be done via
  `UiSystem.releaseWidget(w)`, which traverses bottom-up, unregisters views,
  notifies controllers via `onWidgetReleased`, purges input/pipeline caches,
  and calls `w.release()` to detach and clear components.
- Invalidation Scopes: Fine-grained `WidgetUpdateScope` flags (`visuals`,
  `content`, `layout`, `parentView`, `all`) prevent redundant layout passes.
- Embedded Assets: Fonts and shaders live under `assets/<package_name>/` and
  are imported at compile time using `import("...")` in `internal/assets.d`.

## Extension Recipes

### Adding a Private C Wrapper Library
1. Create C header & source: `<proj>-clibs/<proj>_<libname>.[h|c]`. Use opaque
   handles and prefix symbols with `<proj>_<libname>_`. Document NULL rules.
2. Add standalone C test: `<proj>-clibs/<proj>_<libname>_test.c`.
3. Configure build: Declare static library, test, and dependency in
   `<proj>-clibs/meson.build`.
4. Add D binding: Create matching `extern(C)` module in
   `source/<proj>/clibs/<libname>.d` (or `yguilib/source/yguilib/clibs/`).
5. Link dependency in top-level `meson.build` and run:
   `ninja -C _build && meson test -C _build`.

### Adding a Custom GUI Widget System & Component
1. Component: Create `MyComponent : WidgetComponent` in a domain module.
2. System: Create `MySystem : WidgetSystem`, specify `phases` (`event`,
   `preLayout`, `layout`, `postLayout`, `render`), and override phase methods.
3. Priority: Set system execution priority (e.g. `defaultPriority`).
4. Registration: Register system via `app.ui.registerWidgetSystem()`.
5. Attachment: Attach component via `widget.components.set(new MyComponent())`.

### Adding a Subsystem with Package Facade
1. Create directory `<root_pkg>/<subsystem>/`.
2. Move entry points and public API into `<subsystem>/package.d`.
3. Place internal logic and private helpers into `<subsystem>/internal/*.d`.
4. Use `package(<root_pkg>):` for symbols shared inside the package; never use
   `public:` inside `internal/`.
5. Verify boundaries using:
   `rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d`.
