# yvidtrim Architecture

## System Overview
`yvidtrim` is a frame-accurate, keyboard-driven video trimmer in D targeting
lossless cuts (re-encoding only GOP boundaries) with private C wrappers.

Key architectural separation:
- `yvidtrim`: Video editor application, domain logic, playback, and export.
- `yguilib`: Independent retained-mode GUI library: ECS widget tree,
  flexbox/anchor layout, OpenGL ES 2/3.1 rendering, loops.
- `guidemo`: Interactive testbed showcasing GUI widgets and layout.
- `*-clibs`: Minimal C static libraries isolating external C/C++ dependencies.

## Directory & Package Topology
```
yvidtrim/
├── source/
│   ├── yvidtrim/          # Video trimmer entry point, models, controllers
│   │   ├── app.d          # Entry point wiring model/view/ctrl
│   │   ├── controller.d   # MainController: events and model sync
│   │   ├── model.d, view.d # MainModel state; MainView widget tree
│   │   ├── uitree/        # Declarative widget tree construction
│   │   └── clibs/sdl3.d   # extern(C) D bindings for yvidtrim-clibs
│   └── guidemo/           # Interactive GUI showcase and verification app
│       ├── guidemoapp.d, controller.d # entry/systems; F1 debug, F12 shot
│       ├── common.d       # PageControllerParams, section cards, page sync
│       ├── model.d, view.d, demo_model_helpers.d, hover_button.d
│       │                  # demo models, shell view, helpers, hover demo
│       └── pages/         # Showcase views/controllers (knob_page.d: lock;
│                          # canvas_page.d: Canvas/images/patterns/text;
│                          # gamepad_page.d: SVG Path2d; virtlist_*.d)
├── yguilib/               # Independent GUI library (no yvidtrim dependency)
│   ├── source/yguilib/
│   │   ├── allochelpers.d # SmallBuffer, RingBuffer, ReusableArray containers
│   │   ├── app.d          # Application wrapper running event loop
│   │   ├── window.d       # Window, OpenGL context, display scaling
│   │   ├── uisystem.d     # UiSystem, ControllerStack, EventControl interfaces
│   │   ├── serhelpers.d, texthelpers.d # JSON reflection; byte formatting
│   │   ├── model.d        # VersionedModel and ModelTracker state tracking
│   │   ├── clibs/         # extern(C) D bindings for yguilib-clibs
│   │   ├── controller/    # Controller interfaces and ControllerStack
│   │   ├── controls/      # Reusable UI controls (no package.d facade)
│   │   │   ├── button.d              # Push button component & press-anim sys
│   │   │   ├── common.d              # Shared colors, button face, view helpers
│   │   │   ├── composite_view.d      # Free helpers for composite views
│   │   │   ├── hover_button_system.d # ECS hover button & animation system
│   │   │   ├── internal/             # axis.d (axis helper), button_support.d
│   │   │   ├── scrollbars.d          # Composite Scrollbar widget & view
│   │   │   ├── tabcontrol.d          # Composite TabControl widget & view
│   │   │   ├── testing.d             # Shared unittest helpers & mock hosts
│   │   │   ├── tooltip.d             # Tooltip component, overlay & system
│   │   │   └── virtlist.d            # Composite VirtList widget & view
│   │   ├── events/        # AppEvent, builder, and thread-safe MessageBus
│   │   ├── render/        # Hardware Renderer, FontManager, shader pipelines
│   │   │   ├── canvas/    # Canvas, path2d, types, package_test (GL tests)
│   │   │   ├── image.d, texture.d, render_target.d # Image/Texture/RenderTarget
│   │   │   └── internal/  # pipelines, path_*, svg_path_parser,
│   │   │                  # stencil_ops, offscreen, clip_stack,
│   │   │                  # text_cache, glyph_atlas, gl_util, gl_test_util
│   │   ├── widget/        # Widget entity, components, builder, WidgetSystem
│   │   │   ├── virtlist_components.d # VirtListProvider & VirtListComponent
│   │   │   └── internal/virtlist_system.d # Recycling, layout & wheel scroll
│   │   └── internal/      # UiSystemImpl, TimerService, memstats (telemetry)
│   ├── yguilib-clibs/     # Private C wrappers: SDL3, SDL3_ttf, SDL3_image
│   ├── examples/helloworld/ # Standalone Hello World example executable
│   ├── benchmarks/        # textbench, built only with -Dbenchmarks=true
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
  - `MessageBus.send()`: thread-safe `synchronized` ring buffer; wakes the main
    thread (`yguilib_sdl3_send_wake_event()`), keeps `mouseMotion` unmerged.
- Memory & Safety Enforcements:
  - Hot paths use `yguilib.allochelpers` (`SmallBuffer`, `RingBuffer`,
    `ReusableArray`) in event, timer and layout loops; render code reuses
    `Appender`s and inline fixed-capacity structs (Canvas state is copied).
  - GC is permitted for widget graph construction, models, and UI event strings.
  - SDL windows/GL contexts: `destroy()`/`~this()`; GL objects and TTF fonts
    (`Texture`, `RenderTarget`, `Font`): only main-thread `destroy()`.
- Encapsulation & Scoping:
  - No `public import`; packages like `yguilib.controls` import modules
    explicitly, no `package.d`.
  - `internal/` modules: `package(<root_pkg>):` or `private:`, never `public:`.
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
              ├─► InputSystem (priority 0) ──► bubbles MouseEvent through
              │     ViewComponent.renameEvents ──► UiSystem.sendAppEvent()
              └─► ButtonSystem (built in) ──► press anim + actionEvent
                    via passViewEvent (release or press trigger)
```

**Buttons**: `ButtonSystem` is a built-in pipeline system (registered by
`UiSystemImpl`) driving every `ButtonComponent` widget made by `ButtonBuilder`:
plain buttons, TabControl tabs/arrows and Scrollbar arrows.
`ButtonTrigger.release` (default) or `.press` picks when `actionEvent` fires;
`postLayout` sets normal/disabled colours from `inputEnabled` (controls only
call `Widget.setInputEnabled`). `ButtonRepeat` (press trigger) re-sends it
while held: oneShot delay, then interval timer, stopped on release/disable/hide.

**Input flags**: `Widget.handleInput` (default false) makes a widget
hittable: it takes part in pointer hit-tests and blocks click/hover-through
to widgets behind it (`WidgetBuilder.onMouse*`/`cursorCapture` set it).
`Widget.inputEnabled` (default true) is the enabled state: disabled visuals,
no mouse view events, drag or capture; a disabled hittable widget swallows
clicks. Keyboard (planned, `FocusSystem`): `KeyboardEvent`s reach the focused
widget if `inputEnabled` (disabled: no focus); `handleInput` is pointer-only.

**Cursor capture modes** (`MouseEvent.cursorCapture`, `CursorCapture` enum,
set via `WidgetBuilder.onMouseDrag(name, mode)`), applied by
`InputSystem.syncCursorCapture` while a button pressed on the widget is held:
- `none`: no capture; drag/release outside the window are lost.
- `capture`: `SDL_CaptureMouse` tracks drag/release outside the window.
- `lock`: relative mouse mode, cursor hidden; `mouseDrag` carries unbounded
  `relX/relY` deltas, coords pinned to the press point, where the cursor is
  warped back on release/removal/disable (knob controls, `knob_page.d`).

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
  ├─► 4. Screenshot (UiSystem.requestScreenshot(path) pending, root dirty):
  │     Renderer.captureFrame() (readPixels, flip) ──► Image.savePng(path)
  └─► 5. Buffer Swap: Window.swapBuffers() (at most once per frame tick)
```

**Canvas** (`Renderer.canvas()`): HTML-canvas-like API over `Path2d`.
`path_flatten` (curves, CPU transform), `path_stroker` (caps/joins/dashes),
`stencil_ops` (stencil-then-cover, exact `nonZero`/`evenOdd`; one convex
contour without clip skips the stencil) feed shared color/gradient/`Pattern`
pipelines. Stencil bit 7 = `clip()`, bits 0..6 = per-call work; Window asks
MSAA 4x + 8-bit stencil. Stencil test is on only inside Canvas calls: Renderer
`draw*` ignore Canvas clip/transform, `pushClipRect` limits both, `clearFrame`
resets Canvas state. Clips: append-only `fClips` + stored fan triangles,
`State` keeps `clipCount`; `restore()` truncates and replays (no re-flatten).
Shadows: mask of paint alpha into non-MSAA `OffscreenTarget`s (sigma clamped,
1/2 or 1/4 res if large), `BlurPipeline` H+V, tinted composite under clip bit.
**CustomDraw** (`onDraw(dg(Renderer, in Widget))`) runs after the text label
in `clipContents`, in canvas `save`/`translate(content origin)`/`restore`:
Canvas draws content-local, Renderer stays absolute (`transform()` e/f).
**Images**: `Image` (CPU RGBA8, straight alpha, top-down, no GL) ──►
`Renderer.createTexture` ──► `Texture` ──► Renderer `drawImage[Region]`
(`TexturePipeline`, tint) or `Canvas.drawImage*` (CPU-transformed triangles:
st.xf, clip bit, tint, shadow masked by texture alpha). **Offscreen**:
`createRenderTarget(logicW, logicH, msaa)`; `resizeRenderTarget` reallocs on a
pixel change. Nested `beginTarget`/`endTarget` save+restore FBO, viewport,
scissor, clip stack, Canvas state (buffers swapped with a per-depth slot,
never copied); end resolves MSAA. Separate alpha blend (ONE, 1-SRC_ALPHA)
keeps targets premultiplied (`rt.texture()` bottom-up; `rt.toImage()`
un-premultiplies). **GL state**: Renderer tracks FBO/viewport/clear color,
`ClipStack` the scissor, `ProgramTracker` program + uniform epoch: no GL
queries (debug-checked by `targetState()`); new GL code must use them.
**Text**: `TextRunCache` lays out runs at the effective scale (`fontAtScale`)
via SDL_ttf into reused `fQuads` (`layoutQuads`; outlines shifted back by
outlinePx), storing `RunGlyph` spans in a pooled buffer compacted in place;
LRU (`maxCacheEntries = 2048`), keeping `beginFrame()` strings up to 2x hard
cap. A `const(TextRun)*` is valid only until the next `runFor`. `GlyphAtlas`:
one RGBA8 page, 512 doubling to min(4096, GL max), then cleared in place; a
generation counter invalidates slots. One draw per label: white straight-alpha
coverage tinted or masking gradient/pattern paint; stroke = outline ring.

## Idiomatic Patterns
- Null Safety: Non-null references by default (tooling flags missing checks);
  constructors `assert(arg !is null)`, non-null fields via `invariant` asserts.
- Zero-CPU Idle Sleep: Controllers and `WidgetSystem`s run owner-bound timers
  (`TimerControl.startTimer`/`stopTimer`) only while animating; idle
  `TimerService` returns `-1`, so `yguilib_sdl3_wait_event()` blocks.
- ECS-Style Widgets: `Widget` is an entity with geometry (`RectF`), hierarchy,
  and a `WidgetComponents` bag (`Background`, `Border`, `Size`, `FlexContainer`,
  `MouseEvent`, custom components via `components.set!C(...)`).
- Widget Lifecycle & Release: dispose a hierarchy via `UiSystem.releaseWidget`
  (bottom-up: unregisters views, calls `onWidgetReleased`, purges input and
  pipeline caches, then `w.release()` detaches and clears components).
- guidemo Page Wiring: `registerDemoPages` passes page trackers to the view
  and, via `PageControllerParams`, to the controller (edits shared models;
  view-only models stay in views); trackers: `ModelTracker!M`/`<Page>Trackers`.
- Invalidation Scopes: Fine-grained `WidgetUpdateScope` flags (`visuals`,
  `content`, `layout`, `parentView`, `all`) prevent redundant layout passes.
- Embedded Assets: files under `assets/<package_name>/` (yguilib fonts and
  shaders, guidemo images) are `import("...")`-ed in `[internal/]assets.d`.

## Extension Recipes
### Adding a Private C Wrapper Library
`<proj>-clibs/<proj>_<libname>.[h|c]` (opaque handles, `<proj>_<libname>_`
prefix, NULL rules) + `_test.c`, both in `<proj>-clibs/meson.build`; matching
`extern(C)` in `<pkg>/clibs/<libname>.d`, linked in `meson.build`.
### Adding a Custom GUI Widget System & Component
Create `MyComponent : WidgetComponent` and `MySystem : WidgetSystem` (set
`phases`: `event`/`preLayout`/`layout`/`postLayout`/`render`, a priority, and
override phase methods); register via `app.ui.registerWidgetSystem()` and
attach with `widget.components.set(new MyComponent())`.
### Adding a Subsystem with Package Facade
`<root_pkg>/<subsystem>/` with the public API in `package.d`, helpers in
`internal/*.d` (`package(<root_pkg>):`, never `public:`); verify with
`rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d`.
