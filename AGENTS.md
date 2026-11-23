# Agent Guidelines for yvidtrim

Video trimming tool in D with private C wrappers for external C/C++ libraries.

## Build & Test
Use **Meson** and **Ninja** (`dub.json` is for IDE/LSP only, do not use `dub`).
```bash
ninja -C _build             # Build
meson test -C _build        # Run tests
meson setup _build .        # Setup (or --reconfigure)
```
- Always run unit tests through `meson test -C _build` (never ad-hoc
  `ldc2 -unittest` commands). Ensure every module with `unittest` blocks is
  covered by a Meson test target using a shared `test_main.d`, and do not add
  per-module `version (unittest) void main()` stubs that block unified test
  executables.
- Run tests with a timeout (`timeout 300 meson test -C _build`) and do not
  tee full test output into log files: an assert thrown in a `scope(exit)`
  while unwinding a failed assert can make the D test runner print the
  same error forever (100% CPU, fills `/tmp`). In GL tests, end open render
  targets (`while (r.inTarget()) r.endTarget();`) in a `scope(exit)`
  declared after the `destroy()` ones.

## Architecture & Wrapper Rules
- **No Direct C/C++ in D**: Never import external C headers or auto-bind.
- **Private C Wrappers (`yvidtrim-clibs/`, `yguilib/yguilib-clibs/`)**: Wrap
  third-party libraries in static C libraries with opaque handles and minimal
  APIs.
- **D Bindings**: Put matching `extern(C)` in
  `source/yvidtrim/clibs/<libname>.d` (for `yvidtrim`) or
  `yguilib/source/yguilib/clibs/<libname>.d` (for `yguilib`).
- **Naming**: Public symbols use `<proj>_<libname>_` prefix (files:
  `<proj>_<libname>.[c|h]`, funcs: `yvidtrim_sdl3_hello()`, types:
  `yguilib_sdl3_EventType`).
- **New Wrapper Steps**:
  1. Add header & source in `<proj>-clibs/<proj>_<libname>.[c|h]`
     (under `yguilib/` for `yguilib`).
  2. Add test `<proj>-clibs/<proj>_<libname>_test.c` in
     matching `<proj>-clibs/meson.build`.
  3. Add D binding & link in matching `meson.build`.
- **OpenGL ES**: Only call GLES in D code via `glad2.gles2` (loader and bindings
  in `subprojects/glad2gles31/` and `subprojects/glad2gles31d/`).
- **Independence**: `yguilib/` (sources and wrappers) must not depend on
  `source/yvidtrim/` or `yvidtrim-clibs/`.
- GUI changes, graphics api access is allowed only on main thread, only message passing
between threads via sendAppEvent.
- **Controller Event Delegation & Timers**: Subclasses of `DefaultController`
  that override `handleEvent(AppEvent ev)` must return `super.handleEvent(ev)`
  for unhandled events so quit and window redraw lifecycle events are not
  skipped. Phase 2 runs non-timed model-sync (`Controller.update()`,
  `WidgetSystem` `SystemPhase.update`) in Phase 2a and owner-bound due timers
  (`Controller.onTimer(id, dt)`, `WidgetSystem.onTimer(ctx, id, dt)`) in
  Phase 2b; use `TimerControl` (`startTimer` / `stopTimer`) for active
  animations and stop timers when idle so `SDL_WaitEvent` sleeps at 0% CPU.
- **View-Controller Separation**: Create `ModelTracker!M` and the `View`
  before the `Controller`, and pass `ModelTracker!M` explicitly to both
  `View(ui, tracker)` and `Controller(ui, tracker, view)`. Controllers must
  not instantiate their `View` internally or depend on `App`/`Window`; assign
  `app.withRootWidget(view.rootWidget())` in `main()` so views
  and controllers can be unit-tested headlessly with `UiSystemImpl(null)`.
- **Pointer Motion Fidelity**: Never merge or coalesce `mouseMotion` events
  into a single vector or endpoint; curved cursor sweeps within one frame must
  hit-test every waypoint in FIFO order, and hover-animated controls should
  latch sub-frame `mouseEnter` + `mouseLeave` pulses without rendering per
  motion packet.
- ARCHITECTURE.md: The system's conceptual and structural reality (module
  dependencies, invariants, topologies, and patterns, data flow).
- Keep ARCHITECTURE.md updated whenever adding new modules, altering directory
  structures, or changing core data flows.
- Keep ARCHITECTURE.md under 250 lines.


## Code Style & Workflow
Adhere to `.editorconfig` and `codestyle.md`:
- 2-space indent, LF, max 80 chars/line, opening `{` on the same line.
- Filenames lowercase only.
- D naming: modules lowercase, types `PascalCase`, funcs/vars `camelCase`.
- C naming: types `PascalCase`, defines/enums `UPPER_SNAKE_CASE`, functions/vars
  `snake_case`.
- **Verify**: Always run `ninja -C _build && meson test -C _build`.
- **Preserve**: Keep existing docstrings and comments.

## Skills & Automation
- Skill helper scripts must be written in D using the standard library.
- Launch skill scripts using `rdmd` (e.g., `rdmd .agents/skills/.../script.d`).
- Invoke skill scripts directly without wrapping them in `echo` banners or
  ad-hoc shell filters/counters (`awk`, `wc`, `sed`, `grep`). If a skill lacks
  needed output or checks, enhance the skill script instead.

## Markdown documentation
Use ascii for diagrams in `.md` files, e.g. for plans.
Keep line length 80 characters max whenever possible.

## Logs
std.logger is used with log being redirected to SDL, so to see logs when
running guidemo, yvidtrim need to set `SDL_LOGGING` env var, e.g.
```
SDL_LOGGING=app=trace ./_build/yvidtrim
```

## Planning
Write plan to `plans` directory in multiple files per phase/stage that could be
verified, where first file is an overview that references phase describing
files, e.g. `plans/scrollbars.md` -- brief overview with references, detailed
steps described in: `plans/scrollbars-ph01.md`, `plans/scrollbars-phNN.md`
depending on number of phases necessary to not overload context.  Launch new
subagents to perform the phases with clear context given each only one that file
with details for its phase.

Ask questions on missing information, confusing topics, available options.
For multiple valid options propose a recommended one. Update TODO.md by removing
the completed item if it is refered to in the prompt, if TODO.md is not mentioned,
propose to update it as part of the implementation plan.
